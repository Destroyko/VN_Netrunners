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
	assert_eq(last.request["kind"], "dump")
	assert_eq(last.request["service"], "svc_login")
	assert_eq(last.request["node"], "node_training_pc")
	assert_eq(minute(), before + 3, "программа стоит hack_step из balance.json")


func test_run_form_is_the_same_as_the_short_one() -> void:
	learn_programs()
	reach_training_pc()
	run("connect 10.0.0.7")
	run("run passhound 22")
	assert_eq(last.request["service"], "svc_login")


func _password_after_cracking_the_training_pc() -> String:
	learn_programs()
	reach_training_pc()
	run("connect 10.0.0.7")
	run("passhound")
	var word: String = str(last.request["password"])
	solve_puzzle()
	return word


func test_cracked_password_is_shown_and_the_server_asks_for_it() -> void:
	learn_programs()
	reach_training_pc()
	run("connect 10.0.0.7")
	run("passhound")
	var word: String = str(last.request["password"])
	assert_false(word.is_empty(), "взломщик знает, какое слово достанет")
	var result: TermResult = solve_puzzle()
	assert_string_contains(result.text(), "порт 22: доступ получен (1 из 1)")
	assert_string_contains(result.text(), "пароль: " + word.to_upper())
	assert_string_contains(result.text(), "соединение с 10.0.0.7 установлено")
	assert_eq(result.request.get("type"), "remote", "интерфейс открывает трансляцию с экраном блокировки")
	assert_signal_emitted(EventBus, "puzzle_solved")
	assert_false(t.session.has_connection(), "пароль ещё не введён")
	assert_eq(t.prompt(), "пароль: ")


func test_typing_the_password_lets_in() -> void:
	var word: String = _password_after_cracking_the_training_pc()
	assert_string_contains(run("неверно"), "доступ запрещён")
	assert_eq(t.prompt(), "пароль: ", "сервер спрашивает снова")
	assert_string_contains(run(word.to_upper()), "подключено", "регистр не важен")
	assert_true(t.session.has_connection())
	assert_false(t.history().has(word.to_upper()), "пароль не попадает в историю команд")


func test_entered_password_is_not_asked_again() -> void:
	var word: String = _password_after_cracking_the_training_pc()
	run(word)
	run("dc")
	assert_string_contains(run("connect 10.0.0.7"), "подключено", "пароль уже вводили")


func test_empty_line_cancels_the_login() -> void:
	_password_after_cracking_the_training_pc()
	assert_string_contains(run(""), "вход отменён")
	assert_ne(t.prompt(), "пароль: ")
	assert_eq(run("connect 10.0.0.7").contains("установлено"), true, "спросит снова при следующем connect")
	assert_eq(t.prompt(), "пароль: ")


func test_reset_service_needs_a_new_password() -> void:
	var word: String = _password_after_cracking_the_training_pc()
	run(word)
	run("dc")
	Network.for_game().reset_services("node_training_pc")
	assert_eq(Network.for_game().password_of("node_training_pc", "svc_login"), "", "старый пароль забыт")
	assert_false(run("connect 10.0.0.7").contains("подключено"), "сервис снова закрыт")


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
	Network.for_game().reset_services("node_training_pc")
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


# --- Трейс в реальном времени -------------------------------------------------

func _start_trace() -> void:
	learn_programs()
	GameState.set_flag(Programs.GATE_PRESSURE)
	reveal("node_office_server")
	run("connect 77.61.204.12")
	run("passhound")  # трейс 60, программа отъела 3 → 57


func test_trace_ticks_with_the_clock_without_commands() -> void:
	_start_trace()
	watch_signals(t)
	Clock.advance(10)  # часы пошли сами: игрок думает над головоломкой
	assert_eq(t.session.trace_left(), 47)
	assert_signal_emitted(t, "ticked", "окну сказали сдвинуть полоску")


func test_trace_can_end_while_the_player_does_nothing() -> void:
	_start_trace()
	Clock.advance(57)
	assert_signal_emitted(EventBus, "trace_finished")
	assert_null(t.current_puzzle(), "открытая головоломка сгорела вместе с сеансом")
	assert_eq(t.prompt(), "home:/home$ ")


func test_own_command_does_not_count_the_trace_twice() -> void:
	_start_trace()
	t.spend(1, TermResult.new())  # команда тратит минуту сама
	assert_eq(t.session.trace_left(), 56)


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
	Network.for_game().mark_cracked("node_office_server", "svc_vpn", t.now())
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


# --- Баги второго прогона (снимки F9, 16.11.2026) ------------------------------------

func test_scan_at_the_door_does_not_run_on_your_own_pc() -> void:
	# У двери закрытого узла scan молча сканировал свою домашнюю сеть.
	learn_programs()
	reveal("node_office_server")
	Clock.set_time(1, 10 * 60)
	run("connect 77.61.204.12")
	assert_eq(t.prompt(), "77.61.204.12> ")
	for line: String in ["scan", "ls", "cd /home", "cat readme.txt"]:
		assert_eq(run(line), "вход не выполнен", line)
	assert_string_contains(run("probe"), "сканирование 77.61.204.12", "разведка цели работает")
	assert_false(run("passhound 8080").contains("вход не выполнен"), "взломщики работают")


func test_cracker_with_nothing_left_to_open_says_so() -> void:
	learn_programs()
	enter("node_office_server")
	assert_eq(run("gridrunner"), "gridrunner: закрытых целей нет")


func test_ls_ignores_flags() -> void:
	assert_false(run("ls -la").contains("нет такого"))

