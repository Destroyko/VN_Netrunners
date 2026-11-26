extends "res://test/unit/terminal_fixture.gd"
## Terminal: сетевые команды — scan, probe, nodes, connect, dc, программы, автодополнение,
## команды у двери закрытого узла (docs/tech/terminal-spec.md, docs/gameplay/network.md).

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
	assert_string_contains(text, "мониторинг подключений: нет")
	assert_string_contains(run("nodes"), "Роутер (дом)")


func test_probe_shows_services_without_game_internals() -> void:
	reach_training_pc()
	var text: String = run("probe 10.0.0.7")
	assert_string_contains(text, "ПОРТ")
	var port: int = Array(last.lines).find_custom(func(l: String) -> bool: return l.begins_with("22 "))
	assert_eq(last.role_at(port), "lock", "закрытый порт — красный [Х]")
	assert_false(text.contains("требуется сервисов"), "сколько сервисов для входа — не пишем (вычитка 25.11.2026)")
	assert_false(text.contains("passhound"), "какой программой ломать — знание игрока, не сканера")
	assert_false(text.contains("сложность"))
	assert_false(text.contains("вскрыто"))
	assert_false(text.contains("подсказка"), "консоль не подсказывает: подсказки — в блокноте")


func test_probe_reports_monitoring_but_not_the_schedule() -> void:
	reveal("node_office_server")
	var text: String = run("probe 77.61.204.12")
	assert_string_contains(text, "мониторинг подключений: да")
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
	assert_string_contains(run("connect 10.0.0.1"), "вход выполнен")
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
	assert_string_contains(text, "Вход по паролю")
	assert_string_contains(text, "сканирование узла 10.0.0.7")


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
	assert_eq(run("dc"), "соединение разорвано")
	assert_eq(t.prompt(), "home:/home$ ")
	assert_signal_emitted(EventBus, "node_disconnected")


func test_dc_before_connecting_drops_the_target() -> void:
	reach_training_pc()
	var before: int = get_signal_emit_count(EventBus, "node_disconnected")
	run("connect 10.0.0.7")
	assert_eq(run("dc"), "соединение разорвано")
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
	assert_string_contains(run("run"), "help run")


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
	assert_string_contains(run("probe"), "сканирование узла 77.61.204.12", "разведка цели работает")
	assert_false(run("passhound 8080").contains("вход не выполнен"), "взломщики работают")


func test_cracker_with_nothing_left_to_open_says_so() -> void:
	learn_programs()
	enter("node_office_server")
	assert_eq(run("gridrunner"), "gridrunner: закрытых целей нет")


func test_ls_ignores_flags() -> void:
	assert_false(run("ls -la").contains("нет такого"))
