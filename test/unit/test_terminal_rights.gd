extends "res://test/unit/terminal_fixture.gd"
## Terminal: следы в логах, права гостя и администратора, стены после входа, ранняя игра
## (docs/gameplay/hacking.md, «Права», «Стены», «Логи и заметность»).

# --- Следы в логах цели ------------------------------------------------------

func test_connect_leaves_a_session_trace() -> void:
	enter("node_training_pc")
	var log_book: Logbook = logbook("node_training_pc")
	assert_eq(log_book.categories(), PackedStringArray([Logbook.CATEGORY_SESSION]))
	assert_eq(log_book.heat_weight(), 1)


func test_reading_leaves_no_trace() -> void:
	enter("node_training_pc")
	run("cat zametka.txt")
	assert_eq(logbook("node_training_pc").count(), 1, "только вход")


func test_deleting_on_the_target_leaves_a_trace() -> void:
	enter_as_admin("node_training_pc")
	run("rm spisok_pokupok.txt")
	assert_true(logbook("node_training_pc").categories().has(Logbook.CATEGORY_FILE_DELETED))


func test_many_deletions_cost_the_same_as_one() -> void:
	enter("node_training_pc")
	run("rm spisok_pokupok.txt")
	var one: int = logbook("node_training_pc").heat_weight()
	run("rm zametka.txt")
	run("rm privet.txt")
	assert_eq(logbook("node_training_pc").heat_weight(), one, "категория одна")


func test_cleaning_logs_leaves_no_new_trace_but_exit_stays() -> void:
	enter_as_admin("node_training_pc")
	run("rm spisok_pokupok.txt")
	run("cd /log/access")
	run("rm *")
	run("cd /log/auth")
	run("rm *")
	assert_eq(logbook("node_training_pc").heat_weight(), 0, "почистил — не платишь")
	run("dc")
	assert_eq(logbook("node_training_pc").heat_weight(), 1, "запись о выходе остаётся всегда")
	assert_eq(logbook("node_training_pc").count(), 1, "и это единственная запись")


func test_logs_are_real_files_the_player_can_read() -> void:
	enter("node_training_pc")
	run("cd /log/auth")
	var text: String = run("ls")
	assert_string_contains(text, "login", "свой вход виден в списке")


func test_own_pc_writes_nothing_to_its_logs() -> void:
	run("rm readme.txt")
	run("mkdir novaya")
	run("cp mail/archive.txt kopiya.txt")
	assert_eq(logbook(Network.HOME_ID).count(), 0)


# --- Права на чужом узле -----------------------------------------------------

func test_guest_cannot_open_sys() -> void:
	enter("node_training_pc")
	assert_string_contains(run("cd /sys"), "недостаточно прав")
	assert_string_contains(run("ls /"), "[закрыт]")
	assert_eq(t.prompt(), "10.0.0.7:/home$ ", "гость: доллар")


func test_rootstep_needs_a_connection() -> void:
	learn_programs()
	assert_string_contains(run("rootstep"), "нет подключения")


func test_rootstep_raises_rights_and_leaves_a_trace() -> void:
	learn_programs()
	enter("node_training_pc")
	var before: int = minute()
	var text: String = run("rootstep")
	assert_string_contains(text, "подмена уровня доступа")
	assert_string_contains(text, "права администратора получены")
	assert_false(text.contains("работает…"), "без заглушки прогресса после результата")
	assert_eq(minute(), before + 3)
	assert_eq(t.prompt(), "10.0.0.7:/home# ", "решётка вместо доллара")
	assert_true(logbook("node_training_pc").categories().has(Logbook.CATEGORY_ROOT))
	assert_eq(logbook("node_training_pc").heat_weight(), 5, "сеанс 1 + права 4")


func test_rootstep_opens_sys() -> void:
	learn_programs()
	enter("node_training_pc")
	run("rootstep")
	assert_eq(run("cd /sys"), "")
	assert_string_contains(run("ls"), "x-server.sys")


func test_rootstep_twice() -> void:
	learn_programs()
	enter("node_training_pc")
	run("rootstep")
	assert_eq(run("rootstep"), "права уже повышены")


func test_rights_survive_reconnect_until_the_target_resets() -> void:
	# Баг со снимка F9 16.11: после dc права пропадали, /sys и /prog снова закрыты.
	learn_programs()
	enter("node_training_pc")
	run("rootstep")
	run("dc")
	run("connect 10.0.0.7")
	assert_true(t.admin(), "права держатся на узле")
	assert_eq(run("cd /sys"), "")
	run("dc")
	Network.for_game().access.reset_services("node_training_pc")
	enter("node_training_pc")
	assert_false(t.admin(), "цель перенастроила защиту — прав больше нет")


func test_logwipe_needs_admin_rights() -> void:
	# Баг со снимка F9 16.11: logwipe чистил логи гостю, хотя rm ему отказывал.
	learn_programs()
	enter("node_training_pc")
	assert_string_contains(run("logwipe"), "недостаточно прав")
	assert_gt(logbook("node_training_pc").count(), 0, "логи на месте")


func test_logwipe_keeps_the_log_folders() -> void:
	learn_programs()
	enter_as_admin("node_training_pc")
	run("cd /log/auth")
	run("logwipe")
	assert_eq(run("ls"), "пусто", "каталог остался, просто пустой")


func test_logwipe_clears_the_whole_log_folder() -> void:
	learn_programs()
	enter_as_admin("node_training_pc")
	run("rm spisok_pokupok.txt")
	var text: String = run("logwipe")
	assert_string_contains(text, "очищено записей")
	assert_eq(logbook("node_training_pc").count(), 0)
	run("dc")
	assert_eq(logbook("node_training_pc").heat_weight(), 1, "после logwipe остаётся только запись о выходе")


func test_logwipe_needs_a_connection() -> void:
	learn_programs()
	assert_string_contains(run("logwipe"), "нет подключения")


func test_deepscan_needs_a_router_or_a_server() -> void:
	learn_programs()
	reach_training_pc()
	assert_string_contains(run("deepscan"), "нет подключения", "со своего ПК — нельзя")
	run("connect 10.0.0.7")
	assert_string_contains(run("deepscan"), "нет подключения", "у двери закрытого узла — тоже")


func test_deepscan_on_a_plain_pc_has_no_routes() -> void:
	learn_programs()
	enter("node_training_pc")
	assert_string_contains(run("deepscan"), "нет таблиц маршрутов")


func test_deepscan_on_the_router_lists_the_network_with_depth() -> void:
	learn_programs()
	enter("node_home_router")
	var before: int = minute()
	var text: String = run("deepscan")
	assert_string_contains(text, "10.0.0.7")
	assert_string_contains(text, "через 1")
	assert_true(Network.for_game().is_known("node_training_pc"), "найденное — в адресной книге")
	assert_eq(minute(), before + Programs.minutes_for("deepscan"), "работает дольше scan")
	assert_false(t.session.is_tracing(), "разведка трейс не запускает")


func _enter_husband() -> void:
	Clock.set_time(1, 19 * 60)
	enter("node_husband_pc")


func test_cp_on_a_node_downloads_to_dump_by_default() -> void:
	_enter_husband()
	run("cd photos")
	var before: int = minute()
	run("cp hotel.jpg")
	assert_true(t.home_fs().has_file("/home/dump/hotel.jpg"))
	assert_eq(minute(), before + 5, "2400 КБ по 500 КБ в минуту")
	assert_signal_emitted(EventBus, "file_copied")


func test_downloaded_copy_keeps_its_file_id() -> void:
	# По file_id квесты находят файл, куда бы игрок его ни спрятал (quest-format.md).
	_enter_husband()
	run("cp photos/hotel.jpg")
	assert_true(t.home_fs().has_file_id("file_evidence_hotel"))


func test_download_to_a_chosen_folder() -> void:
	_enter_husband()
	run("cp photos/semya.jpg komprot/")
	assert_true(t.home_fs().has_file("/home/dump/komprot/semya.jpg"))


func test_second_download_asks_before_replacing() -> void:
	_enter_husband()
	run("cp photos/hotel.jpg")
	assert_string_contains(run("cp photos/hotel.jpg"), "заменить? (y/n)")
	assert_string_contains(run("y"), "заменено")


func test_download_is_not_logged_as_a_write() -> void:
	_enter_husband()
	run("cp photos/hotel.jpg")
	assert_eq(logbook("node_husband_pc").categories(), PackedStringArray([Logbook.CATEGORY_SESSION]))


func test_guest_cannot_download_from_sys() -> void:
	enter("node_office_server")
	assert_string_contains(run("cp /sys/backup/klienty.db"), "недостаточно прав")


func test_download_that_does_not_fit_the_trace_is_cut() -> void:
	# Не влез в трейс — файла нет, время потрачено (hacking-loop.md).
	learn_programs()
	GameState.set_flag(Programs.GATE_PRESSURE)
	reveal("node_husband_pc")
	Clock.set_time(1, 19 * 60)
	run("connect 92.44.18.3")
	run("gridrunner")
	solve_puzzle()
	run("connect 92.44.18.3")
	t.spend(t.session.trace_left() - 3, TermResult.new())

	var text: String = run("cp photos/hotel.jpg")
	assert_string_contains(text, "файл не успел скачаться")
	assert_string_contains(text, "трейс дошёл до конца")
	assert_false(t.home_fs().has_file("/home/dump/hotel.jpg"))
	assert_eq(t.prompt(), "home:/home$ ")


func test_small_download_fits_the_trace() -> void:
	learn_programs()
	GameState.set_flag(Programs.GATE_PRESSURE)
	reveal("node_husband_pc")
	Clock.set_time(1, 19 * 60)
	run("connect 92.44.18.3")
	run("gridrunner")
	solve_puzzle()
	run("connect 92.44.18.3")
	run("cp photos/hotel.jpg")
	assert_true(t.home_fs().has_file("/home/dump/hotel.jpg"), "5 минут при 41 остававшихся — укладывается")


func test_put_uploads_a_file_and_leaves_a_trace() -> void:
	enter_as_admin("node_training_pc")
	assert_eq(run("put readme.txt"), "", "успешная загрузка молчит")
	assert_true(Filesystem.for_node("node_training_pc").has_file("/home/readme.txt"))
	assert_true(logbook("node_training_pc").categories().has(Logbook.CATEGORY_FILE_CREATED))
	assert_eq(logbook("node_training_pc").heat_weight(), 4, "сеанс 1 + запись 3")


func test_put_takes_the_source_from_your_own_pc() -> void:
	enter_as_admin("node_training_pc")
	run("put mail/archive.txt")
	assert_true(Filesystem.for_node("node_training_pc").has_file("/home/archive.txt"))


func test_put_to_a_chosen_folder_on_the_node() -> void:
	enter_as_admin("node_training_pc")
	run("put readme.txt podarok/")
	assert_true(Filesystem.for_node("node_training_pc").has_file("/home/podarok/readme.txt"))


func test_put_needs_a_connection() -> void:
	assert_string_contains(run("put readme.txt"), "нет подключения")


func test_put_over_existing_file_asks() -> void:
	enter_as_admin("node_training_pc")
	run("put readme.txt")
	assert_string_contains(run("put readme.txt"), "заменить? (y/n)")


func test_guest_cannot_put_into_sys() -> void:
	enter("node_training_pc")
	assert_string_contains(run("put readme.txt /sys/"), "недостаточно прав")


func test_deleting_net_sys_on_a_node_is_sabotage() -> void:
	learn_programs()
	enter("node_office_server")
	run("rootstep")
	assert_string_contains(run("rm /sys/net.sys"), "системный файл net.sys")
	run("y")
	assert_eq(t.prompt(), "home:/home$ ", "выкинуло из узла")
	assert_signal_emitted(EventBus, "node_disconnected")
	assert_string_contains(run("connect 77.61.204.12"), "узел не в сети")
	assert_true(Network.for_game().alert_level("node_office_server") >= 1, "цель насторожилась")
	# Не навсегда: через три дня владелец чинит (защита от софтлока).
	Clock.advance(3 * 1440)
	assert_true(Network.for_game().is_online("node_office_server", t.now()))
	assert_false(Filesystem.for_node("node_office_server").has_file(SystemFiles.FILE_NET), "пока никто не смотрел")
	run("pwd")
	assert_true(Filesystem.for_node("node_office_server").has_file(SystemFiles.FILE_NET), "владелец вернул net.sys")
	assert_eq(Network.for_game().due_repairs(t.now()).size(), 0, "починенный второй раз не чинят")


# --- Стены: защита, которая мешает и после входа ---------------------------------

func _inside_office_past_the_login_only() -> void:
	# Клиент дал логин в панель администратора — этого хватает, чтобы войти (нужен один сервис),
	# но фаервол периметра (1194) остаётся.
	learn_programs()
	reveal("node_office_server", ["svc_admin_login"])
	Clock.set_time(1, 10 * 60)
	run("connect 77.61.204.12")


func test_firewall_blocks_downloads_after_entry() -> void:
	_inside_office_past_the_login_only()
	assert_true(t.session.has_connection(), "внутрь пустили")
	var before: int = minute()
	assert_string_contains(run("cp /home/users/list.txt"), "заблокирована: фаервол")
	assert_eq(minute(), before, "за отказ время не берём")
	assert_false(t.home_fs().has_file(Terminal.DUMP_DIR + "/list.txt"))
	assert_string_contains(run("cat /home/users/list.txt"), "Сотрудники", "смотреть можно")


func test_cracked_firewall_lets_files_out() -> void:
	_inside_office_past_the_login_only()
	Network.for_game().access.mark_cracked("node_office_server", "svc_vpn", t.now())
	assert_false(run("cp /home/users/list.txt").contains("заблокирована"))
	assert_true(t.home_fs().has_file(Terminal.DUMP_DIR + "/list.txt"))


func test_probe_shows_action_analysis() -> void:
	reveal("node_office_server")
	assert_string_contains(run("probe 77.61.204.12"), "обнаружен анализ действий: да")
	reach_training_pc()
	assert_string_contains(run("probe 10.0.0.7"), "обнаружен анализ действий: нет")


func test_action_analysis_makes_loud_actions_eat_the_trace() -> void:
	_inside_office_past_the_login_only()
	GameState.set_flag(Programs.GATE_PRESSURE)
	run("gridrunner 1194")  # первый взломщик — трейс пошёл
	t.finish_puzzle(0)
	t.session.grant_admin()  # удалять гостю нельзя
	var quiet_before: int = t.session.trace_left()
	run("cat /home/users/list.txt")  # тихое: в журнал не пишется
	var quiet_cost: int = quiet_before - t.session.trace_left()
	var loud_before: int = t.session.trace_left()
	run("rm /home/users/list.txt")  # громкое: удаление пишется в журнал
	var loud_cost: int = loud_before - t.session.trace_left()
	var extra: int = int((DataLoader.balance()["nodes"] as Dictionary)["ids_trace_minutes"])
	assert_eq(loud_cost, quiet_cost + extra, "громкое действие стоит лишних минут трейса")


# --- Права гостя ------------------------------------------------------------------

func test_guest_on_a_node_only_reads() -> void:
	enter("node_training_pc")
	assert_false(t.admin())
	for line: String in ["rm spisok_pokupok.txt", "mv spisok_pokupok.txt drugoe.txt", "mkdir novaya", "put readme.txt"]:
		assert_string_contains(run(line), "недостаточно прав", line)
	assert_true(Filesystem.for_node("node_training_pc").has_file("/home/spisok_pokupok.txt"), "ничего не тронуто")
	assert_false(run("cat spisok_pokupok.txt").contains("недостаточно прав"), "читать можно")


func test_admin_can_change_files() -> void:
	enter_as_admin("node_training_pc")
	assert_false(run("mv spisok_pokupok.txt drugoe.txt").contains("недостаточно прав"))
	assert_true(Filesystem.for_node("node_training_pc").has_file("/home/drugoe.txt"))


func test_own_pc_needs_no_rights() -> void:
	assert_false(run("mkdir proekty").contains("недостаточно прав"), "на своём ПК игрок хозяин")


# --- Ранняя игра: логин администратора и подчищенные следы --------------------------

func test_client_admin_login_gives_rights_on_entry() -> void:
	# Заказ подработки: адрес и логин администратора — удалить и положить можно сразу, без rootstep.
	Effects.apply({"reveal_node": {"node": "node_training_pc", "open": ["svc_login"], "admin": true}})
	run("connect 10.0.0.7")
	assert_true(t.admin(), "логин администратора")
	assert_false(run("rm spisok_pokupok.txt").contains("недостаточно прав"))


func test_plain_client_login_is_a_guest() -> void:
	Effects.apply({"reveal_node": {"node": "node_training_pc", "open": ["svc_login"]}})
	run("connect 10.0.0.7")
	assert_false(t.admin())


func test_covered_session_leaves_no_traces() -> void:
	# Ворота gate.cover: за игроком подчищают — ни удаления, ни входа, ни выхода в логах узла.
	GameState.set_flag(Terminal.GATE_COVER)
	Effects.apply({"reveal_node": {"node": "node_training_pc", "open": ["svc_login"], "admin": true}})
	var before: int = logbook("node_training_pc").count()
	run("connect 10.0.0.7")
	run("rm spisok_pokupok.txt")
	run("dc")
	assert_eq(logbook("node_training_pc").count(), before, "журнал узла не изменился")


func test_without_cover_the_session_is_logged() -> void:
	Effects.apply({"reveal_node": {"node": "node_training_pc", "open": ["svc_login"], "admin": true}})
	var before: int = logbook("node_training_pc").count()
	run("connect 10.0.0.7")
	run("rm spisok_pokupok.txt")
	run("dc")
	assert_gt(logbook("node_training_pc").count(), before)


# --- Расшифровка архива (шаг 10, docs/gameplay/hacking-loop.md) --------------------

func test_cat_shows_encrypted_marker() -> void:
	t.home_fs().put_file("/home/dump/arhiv.enc", {"encrypted": true, "size_kb": 500,
		"locked": {"text": "секрет"}})
	assert_string_contains(run("cat /home/dump/arhiv.enc"), "зашифрован")
	assert_false(run("cat /home/dump/arhiv.enc").contains("секрет"), "содержимое скрыто")


func test_decrypt_auto_starts_bruteforce() -> void:
	t.home_fs().put_file("/home/dump/arhiv.enc", {"encrypted": true, "size_kb": 500,
		"locked": {"text": "секрет"}})
	assert_string_contains(run("decrypt /home/dump/arhiv.enc"), "недоступна", "без -auto — заглушка")
	assert_string_contains(run("decrypt /home/dump/arhiv.enc -auto"), "подбор")
	assert_true(BackgroundTasks.is_running("/home/dump/arhiv.enc"))


func test_reboot_reports_stopped_tasks() -> void:
	t.home_fs().put_file("/home/dump/arhiv.enc", {"encrypted": true,
		"locked": {"text": "x"}})
	run("decrypt /home/dump/arhiv.enc -auto")
	assert_string_contains(run("reboot"), "прервано")
