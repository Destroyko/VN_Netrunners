extends "res://test/unit/terminal_fixture.gd"
## Terminal: сеть, программы, трейс, следы в логах, права и скачивание
## (docs/tech/terminal-spec.md, docs/gameplay/hacking.md, docs/gameplay/network.md).


# --- scan, probe, nodes ------------------------------------------------------

func test_scan_from_home_shows_the_router() -> void:
	var text: String = run("scan")
	assert_string_contains(text, "10.0.0.1")
	assert_string_contains(text, "router")
	assert_false(text.contains("Роутер"), "имя узла — только после probe")


func test_scan_costs_a_minute() -> void:
	var before: int = minute()
	run("scan")
	assert_eq(minute(), before + 1)


func test_scan_adds_to_address_book() -> void:
	run("scan")
	assert_string_contains(run("nodes"), "10.0.0.1")


func test_nodes_is_free_and_lists_own_pc() -> void:
	var before: int = minute()
	assert_string_contains(run("nodes"), "localhost")
	assert_eq(minute(), before)


func test_probe_describes_the_node_and_reveals_its_name() -> void:
	run("scan")
	var text: String = run("probe 10.0.0.1")
	assert_string_contains(text, "Роутер (дом)")
	assert_string_contains(text, "обнаружен мониторинг подключений: нет")
	assert_string_contains(run("nodes"), "Роутер (дом)")


func test_probe_shows_services_without_game_internals() -> void:
	reach_training_pc()
	var text: String = run("probe 10.0.0.7")
	assert_string_contains(text, "порт 22")
	assert_string_contains(text, "закрыт")
	assert_string_contains(text, "для входа требуется сервисов: 1")
	assert_false(text.contains("passhound"), "какой программой ломать — знание игрока, не сканера")
	assert_false(text.contains("сложность"))
	assert_false(text.contains("вскрыто"))
	assert_false(text.contains("подсказка"), "консоль не подсказывает: подсказки — в блокноте")


func test_probe_reports_monitoring_but_not_the_schedule() -> void:
	reveal("node_office_server")
	var text: String = run("probe 77.61.204.12")
	assert_string_contains(text, "обнаружен мониторинг подключений: да")
	assert_false(text.contains("08:00"), "расписание узнаётся отдельной механикой, не сканером")


func test_probe_of_unknown_address_is_refused() -> void:
	# Адрес из письма — подсказка, а не способ попасть (network.md).
	assert_string_contains(run("probe 77.61.204.12"), "неизвестный адрес")


func test_probe_does_not_start_the_trace() -> void:
	GameState.set_flag(Programs.GATE_PRESSURE)
	reveal("node_office_server")
	run("probe 77.61.204.12")
	assert_false(t.session.is_tracing())


func test_network_commands_need_net_sys() -> void:
	run("rm /sys/net.sys")
	run("y")
	assert_eq(run("scan"), NetCommands.NO_NETWORK)
	assert_eq(run("probe 10.0.0.1"), NetCommands.NO_NETWORK)
	assert_eq(run("connect 10.0.0.1"), NetCommands.NO_NETWORK)
	assert_eq(run("nodes").contains("localhost"), true, "адресная книга — локальные данные")


# --- connect, dc -------------------------------------------------------------

func test_connect_to_unknown_address() -> void:
	assert_string_contains(run("connect 1.2.3.4"), "неизвестный адрес")


func test_connect_to_own_pc_is_refused() -> void:
	assert_eq(run("connect localhost"), "локальный адрес")


func test_connect_router_changes_the_prompt() -> void:
	run("scan")
	assert_string_contains(run("connect 10.0.0.1"), "подключено")
	assert_eq(t.prompt(), "10.0.0.1:/home$ ")
	assert_signal_emitted(EventBus, "node_connected")


func test_connect_costs_a_minute() -> void:
	run("scan")
	var before: int = minute()
	run("connect 10.0.0.1")
	assert_eq(minute(), before + 1)


func test_connected_terminal_works_on_the_remote_machine() -> void:
	run("scan")
	run("connect 10.0.0.1")
	assert_string_contains(run("cat devices.txt"), "Список устройств")
	assert_eq(run("cat readme.txt").contains("Старая ОС"), false, "это уже не свой ПК")


func test_scan_on_a_remote_node_shows_its_neighbours() -> void:
	run("scan")
	run("connect 10.0.0.1")
	var text: String = run("scan")
	assert_string_contains(text, "10.0.0.7")
	assert_string_contains(text, "localhost")


func test_denied_connect_keeps_the_target_and_marks_it_closed() -> void:
	reach_training_pc()
	var text: String = run("connect 10.0.0.7")
	assert_string_contains(text, "соединение с 10.0.0.7 установлено")
	assert_string_contains(text, "вход отклонён")
	assert_false(text.contains("svc_login"), "защиту показывает probe, а не connect")
	assert_false(text.contains("двер"), "метафор в консоли нет")
	assert_eq(t.prompt(), "10.0.0.7> ")


func test_probe_without_an_address_examines_the_target() -> void:
	reach_training_pc()
	run("connect 10.0.0.7")
	var text: String = run("probe")
	assert_string_contains(text, "порт 22")
	assert_string_contains(text, "сканирование 10.0.0.7")


func test_connect_outside_prime_time() -> void:
	reveal("node_office_server", service_ids("node_office_server"))
	Clock.set_time(1, 22 * 60)
	assert_string_contains(run("connect 77.61.204.12"), "узел не в сети")


func test_first_connect_marks_the_hack_and_applies_effects() -> void:
	reach_training_pc()  # по дороге вскрыт и роутер: у него защиты нет, но заход первый
	var before: int = get_signal_emit_count(EventBus, "hack_completed")
	reveal("node_training_pc", ["svc_login"])
	run("connect 10.0.0.7")
	assert_signal_emit_count(EventBus, "hack_completed", before + 1)
	assert_true(GameState.has_flag("node.training_pc.hacked"), "on_hacked из данных узла")
	run("dc")
	run("connect 10.0.0.7")
	assert_signal_emit_count(EventBus, "hack_completed", before + 1, "повторный заход — не первый взлом")


func test_dc_without_connection() -> void:
	assert_eq(run("dc"), "нет соединения")


func test_dc_disconnects_and_emits() -> void:
	enter("node_training_pc")
	assert_eq(run("dc"), "отключено")
	assert_eq(t.prompt(), "home:/home$ ")
	assert_signal_emitted(EventBus, "node_disconnected")


func test_dc_before_connecting_drops_the_target() -> void:
	reach_training_pc()
	var before: int = get_signal_emit_count(EventBus, "node_disconnected")
	run("connect 10.0.0.7")
	assert_eq(run("dc"), "цель сброшена")
	assert_signal_emit_count(EventBus, "node_disconnected", before, "подключения не было")


func test_hop_to_another_node_closes_the_previous_session() -> void:
	run("scan")
	run("connect 10.0.0.1")
	reveal("node_training_pc", ["svc_login"])
	run("connect 10.0.0.7")
	assert_signal_emit_count(EventBus, "node_disconnected", 1)
	var router_log: Logbook = logbook("node_home_router")
	assert_eq(router_log.categories(), PackedStringArray([Logbook.CATEGORY_SESSION]), "вход и выход с роутера записаны")
	assert_eq(router_log.count(), 2)


func test_cwd_resets_between_nodes() -> void:
	enter("node_training_pc")
	run("cd /log")
	run("dc")
	enter("node_training_pc")
	assert_eq(run("pwd"), "/home")


# --- Программы: на старте их нет ---------------------------------------------

func test_no_programs_at_the_start() -> void:
	# Решено 15.11.2026: у героя обычная ОС, первые задания — прямой доступ без взлома.
	assert_eq(run("progs"), "установленных программ нет")
	assert_eq(Programs.installed().size(), 0)


func test_program_is_not_installed_without_the_flag() -> void:
	assert_eq(run("passhound"), "программа не установлена: passhound")
	assert_eq(run("run rootstep"), "программа не установлена: rootstep")


func test_installed_programs_are_listed() -> void:
	GameState.set_flag(Programs.flag_for("passhound"))
	var text: String = run("progs")
	assert_string_contains(text, "passhound")
	assert_false(text.contains("gridrunner"))


func test_run_without_a_program_name() -> void:
	assert_string_contains(run("run"), "использование: run")


# --- Взломщики и трейс -------------------------------------------------------

func test_cracker_needs_a_target() -> void:
	learn_programs()
	assert_string_contains(run("passhound"), "цель не выбрана")


func test_passhound_asks_the_interface_for_a_puzzle() -> void:
	learn_programs()
	reach_training_pc()
	run("connect 10.0.0.7")
	var before: int = minute()
	run("passhound")
	assert_eq(last.request["type"], "puzzle")
	assert_eq(last.request["kind"], "password")
	assert_eq(last.request["service"], "svc_login")
	assert_eq(last.request["node"], "node_training_pc")
	assert_eq(minute(), before + 3, "программа стоит hack_step из balance.json")


func test_run_form_is_the_same_as_the_short_one() -> void:
	learn_programs()
	reach_training_pc()
	run("connect 10.0.0.7")
	run("run passhound 22")
	assert_eq(last.request["service"], "svc_login")


func test_solved_puzzle_opens_the_service_and_lets_in_by_itself() -> void:
	learn_programs()
	reach_training_pc()
	run("connect 10.0.0.7")
	run("passhound")
	var text: String = solve_puzzle().text()
	assert_string_contains(text, "порт 22: доступ получен (1 из 1)")
	assert_string_contains(text, "подключено")
	assert_signal_emitted(EventBus, "puzzle_solved")
	assert_true(t.session.has_connection())
	assert_eq(t.prompt().ends_with("$ ") or t.prompt().ends_with("# "), true)


func test_failed_puzzle_keeps_the_service_closed_and_can_be_retried() -> void:
	learn_programs()
	reach_training_pc()
	run("connect 10.0.0.7")
	run("passhound")
	assert_string_contains(t.finish_puzzle(0).text(), "провал")
	assert_signal_emitted(EventBus, "puzzle_failed")
	assert_string_contains(run("connect 10.0.0.7"), "вход отклонён")
	run("passhound")
	assert_eq(last.request["type"], "puzzle", "повторить можно")


func test_finish_puzzle_without_one_open() -> void:
	assert_string_contains(t.finish_puzzle(1).text(), "нет открытой головоломки")


func test_wrong_program_for_the_defence() -> void:
	learn_programs()
	reveal("node_office_server")
	run("connect 77.61.204.12")
	assert_eq(run("passhound 1194"), "passhound не работает против этой защиты")


func test_cracker_picks_the_only_fitting_service() -> void:
	learn_programs()
	reveal("node_office_server")
	run("connect 77.61.204.12")
	run("gridrunner")
	assert_eq(last.request["service"], "svc_vpn", "под gridrunner подходит один сервис")


func test_unknown_service_is_refused() -> void:
	learn_programs()
	reach_training_pc()
	run("connect 10.0.0.7")
	assert_string_contains(run("passhound 9999"), "порт 9999: нет сервиса")


func test_no_trace_before_the_group_era() -> void:
	learn_programs()
	reveal("node_office_server")
	run("connect 77.61.204.12")
	assert_false(run("passhound").contains("трейс запущен"))
	assert_false(t.session.is_tracing())


func test_first_cracker_starts_the_trace_in_the_group_era() -> void:
	learn_programs()
	GameState.set_flag(Programs.GATE_PRESSURE)
	reveal("node_office_server")
	run("connect 77.61.204.12")
	assert_string_contains(run("passhound"), "трейс запущен: 60 мин")
	assert_signal_emitted(EventBus, "trace_started")
	assert_eq(t.session.trace_left(), 57, "программа уже отъела три минуты")


func test_trace_warns_and_then_breaks_the_connection() -> void:
	learn_programs()
	GameState.set_flag(Programs.GATE_PRESSURE)
	reveal("node_office_server")
	run("connect 77.61.204.12")
	run("passhound")  # трейс стартует: 60, программа отъедает 3 → 57

	var half := TermResult.new()
	t.spend(27, half)
	assert_string_contains(half.text(), "осталась половина")

	var end := TermResult.new()
	t.spend(40, end)
	assert_string_contains(end.text(), "трейс дошёл до конца")
	assert_signal_emitted(EventBus, "trace_finished")
	assert_eq(t.prompt(), "home:/home$ ", "обрыв: терминал снова дома")


func test_finished_trace_resets_services_and_makes_target_wary() -> void:
	learn_programs()
	GameState.set_flag(Programs.GATE_PRESSURE)
	reveal("node_office_server")
	run("connect 77.61.204.12")
	run("passhound")
	solve_puzzle()
	t.spend(60, TermResult.new())
	var net: Network = Network.for_game()
	assert_eq(net.cracked_count("node_office_server", t.now()), 0)
	assert_eq(net.alert_level("node_office_server"), 1)


func test_prime_time_ending_cuts_the_session() -> void:
	reveal("node_husband_pc", ["svc_firewall"])
	Clock.set_time(1, 23 * 60)
	run("connect 92.44.18.3")
	assert_eq(t.prompt(), "92.44.18.3:/home$ ")
	var cut: TermResult = TermResult.new()
	t.spend(45, cut)
	assert_string_contains(cut.text(), "соединение потеряно")
	assert_eq(t.prompt(), "home:/home$ ")
	assert_signal_emitted(EventBus, "node_disconnected")


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
	enter("node_training_pc")
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
	enter("node_training_pc")
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
	assert_eq(last.request["type"], "progress")
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


func test_rights_do_not_survive_the_session() -> void:
	learn_programs()
	enter("node_training_pc")
	run("rootstep")
	run("dc")
	enter("node_training_pc")
	assert_string_contains(run("cd /sys"), "недостаточно прав")


func test_logwipe_clears_the_whole_log_folder() -> void:
	learn_programs()
	enter("node_training_pc")
	run("rm spisok_pokupok.txt")
	var text: String = run("logwipe")
	assert_string_contains(text, "очищено записей")
	assert_eq(logbook("node_training_pc").count(), 0)
	run("dc")
	assert_eq(logbook("node_training_pc").heat_weight(), 1, "после logwipe остаётся только запись о выходе")


func test_logwipe_needs_a_connection() -> void:
	learn_programs()
	assert_string_contains(run("logwipe"), "нет подключения")


func test_deepscan_opens_one_more_symbol() -> void:
	# Узел фирмы: пароль сложности 3 → «нетраннер», открытых букв нет, есть куда открывать.
	learn_programs()
	reveal("node_office_server")
	run("connect 77.61.204.12")
	var before: int = minute()
	assert_string_contains(run("deepscan 8080"), "ещё один символ")
	assert_eq(int(GameState.get_var_or("deepscan.node_office_server.svc_admin_login", 0)), 1)
	run("deepscan 8080")
	assert_eq(int(GameState.get_var_or("deepscan.node_office_server.svc_admin_login", 0)), 2)
	assert_eq(minute(), before + 10, "две пятиминутки")
	assert_false(t.session.is_tracing(), "разведка трейс не запускает")


func test_deepscan_refuses_when_nothing_more_can_be_opened() -> void:
	# На лёгком уровне открыто уже всё, что можно: три буквы остаются неизвестными.
	learn_programs()
	reach_training_pc()
	run("connect 10.0.0.7")
	var before: int = minute()
	assert_string_contains(run("deepscan"), "больше символов здесь не открыть")
	assert_eq(minute(), before, "за несуществующий символ время не берём")
	assert_eq(int(GameState.get_var_or("deepscan.node_training_pc.svc_login", 0)), 0)


func test_deepscan_works_only_against_a_password() -> void:
	learn_programs()
	reveal("node_husband_pc")
	Clock.set_time(1, 19 * 60)
	run("connect 92.44.18.3")
	assert_string_contains(run("deepscan 443"), "только против пароля")


# --- Скачивание и загрузка ---------------------------------------------------

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
	enter("node_training_pc")
	assert_eq(run("put readme.txt"), "", "успешная загрузка молчит")
	assert_true(Filesystem.for_node("node_training_pc").has_file("/home/readme.txt"))
	assert_true(logbook("node_training_pc").categories().has(Logbook.CATEGORY_FILE_CREATED))
	assert_eq(logbook("node_training_pc").heat_weight(), 4, "сеанс 1 + запись 3")


func test_put_takes_the_source_from_your_own_pc() -> void:
	enter("node_training_pc")
	run("put mail/archive.txt")
	assert_true(Filesystem.for_node("node_training_pc").has_file("/home/archive.txt"))


func test_put_to_a_chosen_folder_on_the_node() -> void:
	enter("node_training_pc")
	run("put readme.txt podarok/")
	assert_true(Filesystem.for_node("node_training_pc").has_file("/home/podarok/readme.txt"))


func test_put_needs_a_connection() -> void:
	assert_string_contains(run("put readme.txt"), "нет подключения")


func test_put_over_existing_file_asks() -> void:
	enter("node_training_pc")
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


# --- Автодополнение ----------------------------------------------------------

func test_complete_command_name() -> void:
	assert_eq(t.complete("cat")["line"], "cat ")
	assert_eq((t.complete("pw")["options"] as PackedStringArray).size(), 1)


func test_complete_several_options_keeps_the_line() -> void:
	var result: Dictionary = t.complete("c")
	assert_true((result["options"] as PackedStringArray).size() > 1)
	assert_eq(result["line"], "c", "общего продолжения нет")


func test_complete_common_prefix() -> void:
	# mkdir и mv расходятся сразу после «m», зато история и help — «h» с общим «h».
	var result: Dictionary = t.complete("hi")
	assert_eq(result["line"], "history ")


func test_complete_path_directory_gets_a_slash() -> void:
	assert_eq(t.complete("cd ma")["line"], "cd mail/")


func test_complete_absolute_path() -> void:
	assert_eq(t.complete("ls /ho")["line"], "ls /home/")


func test_complete_file_name() -> void:
	assert_eq(t.complete("cat read")["line"], "cat readme.txt ")


func test_complete_nothing_found() -> void:
	var result: Dictionary = t.complete("cat zzz")
	assert_eq(result["line"], "cat zzz")
	assert_eq((result["options"] as PackedStringArray).size(), 0)


func test_complete_only_known_addresses() -> void:
	assert_eq((t.complete("connect 10.")["options"] as PackedStringArray).size(), 0, "ничего не нашёл — ничего не подсказываем")
	run("scan")
	assert_eq(t.complete("connect 10.")["line"], "connect 10.0.0.1 ")


func test_complete_installed_programs_only() -> void:
	assert_eq(t.complete("pass")["line"], "pass")
	GameState.set_flag(Programs.flag_for("passhound"))
	assert_eq(t.complete("pass")["line"], "passhound ")


func test_complete_service_of_the_target() -> void:
	learn_programs()
	reach_training_pc()
	run("connect 10.0.0.7")
	assert_eq(t.complete("passhound 2")["line"], "passhound 22 ")


func test_complete_put_takes_files_from_own_pc() -> void:
	enter("node_training_pc")
	assert_eq(t.complete("put read")["line"], "put readme.txt ")


func test_old_os_has_no_autocomplete() -> void:
	# Старая ОС: только история по стрелкам (terminal-spec.md).
	GameState.set_var(Terminal.VAR_OS, Terminal.OS_OLD)
	assert_eq(t.complete("cat read")["line"], "cat read")


func test_complete_quotes_a_path_with_spaces() -> void:
	t.home_fs().put_file("/home/мои файлы/заметка.txt", {"text": "секрет"})
	assert_eq(t.complete("cd мо")["line"], "cd \"мои файлы/\"")


func test_program_takes_a_port_number_not_a_service_name() -> void:
	learn_programs()
	reach_training_pc()
	run("connect 10.0.0.7")
	assert_string_contains(run("passhound svc_login"), "порт — это число")
	run("passhound 22")
	assert_eq(last.request["port"], 22)
	assert_eq(last.request["service"], "svc_login", "внутри игра по-прежнему знает сервис по id")

