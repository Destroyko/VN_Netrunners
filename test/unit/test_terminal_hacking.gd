extends "res://test/unit/terminal_fixture.gd"
## Terminal: взломщики, пароль после взлома, трейс — в командах, от хода часов и на узле
## (docs/gameplay/hacking.md, «Трейс», «Пароль после перехвата»).

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
	assert_string_contains(run(word.to_upper()), "вход выполнен", "регистр не важен")
	assert_true(t.session.has_connection())
	assert_false(t.history().has(word.to_upper()), "пароль не попадает в историю команд")


func test_entered_password_is_not_asked_again() -> void:
	var word: String = _password_after_cracking_the_training_pc()
	run(word)
	run("dc")
	assert_string_contains(run("connect 10.0.0.7"), "вход выполнен", "пароль уже вводили")


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
	Network.for_game().access.reset_services("node_training_pc")
	assert_eq(Network.for_game().access.password_of("node_training_pc", "svc_login"), "", "старый пароль забыт")
	assert_false(run("connect 10.0.0.7").contains("вход выполнен"), "сервис снова закрыт")


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
	var total: int = trace_of("node_office_server")
	assert_string_contains(run("passhound"), "трейс запущен: %d мин" % total)
	assert_signal_emitted(EventBus, "trace_started")
	assert_eq(t.session.trace_left(), total - 3, "программа уже отъела три минуты")


func test_trace_warns_and_then_breaks_the_connection() -> void:
	learn_programs()
	GameState.set_flag(Programs.GATE_PRESSURE)
	reveal("node_office_server")
	run("connect 77.61.204.12")
	run("passhound")  # трейс стартует, программа отъедает 3 минуты
	var total: int = trace_of("node_office_server")

	var half := TermResult.new()
	t.spend(total / 2 - 3, half)
	assert_string_contains(half.text(), "осталась половина")

	var end := TermResult.new()
	t.spend(total, end)
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
	t.spend(trace_of("node_office_server"), TermResult.new())
	var net: Network = Network.for_game()
	assert_eq(net.access.cracked_count("node_office_server", t.now()), 0)
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


# --- Трейс в реальном времени -------------------------------------------------

func _start_trace() -> void:
	learn_programs()
	GameState.set_flag(Programs.GATE_PRESSURE)
	reveal("node_office_server")
	run("connect 77.61.204.12")
	run("passhound")  # трейс пошёл, программа отъела 3 минуты


func test_trace_ticks_with_the_clock_without_commands() -> void:
	_start_trace()
	watch_signals(t)
	var before: int = t.session.trace_left()
	Clock.advance(10)  # часы пошли сами: игрок думает над головоломкой
	assert_eq(t.session.trace_left(), before - 10)
	assert_signal_emitted(t, "ticked", "окну сказали сдвинуть полоску")


func test_trace_can_end_while_the_player_does_nothing() -> void:
	_start_trace()
	Clock.advance(t.session.trace_left())
	assert_signal_emitted(EventBus, "trace_finished")
	assert_null(t.current_puzzle(), "открытая головоломка сгорела вместе с сеансом")
	assert_eq(t.prompt(), "home:/home$ ")


func test_own_command_does_not_count_the_trace_twice() -> void:
	_start_trace()
	var before: int = t.session.trace_left()
	t.spend(1, TermResult.new())  # команда тратит минуту сама
	assert_eq(t.session.trace_left(), before - 1)


# --- Трейс на узле, а не в сеансе (второй прогон гейта, 16.11.2026) --------------------

func _office_under_trace() -> void:
	# Вошли в сервер фирмы по логину в панель, запустили взломщик против фаервола — трейс пошёл.
	learn_programs()
	GameState.set_flag(Programs.GATE_PRESSURE)
	reveal("node_office_server", ["svc_admin_login"])
	Clock.set_time(1, 10 * 60)
	run("connect 77.61.204.12")
	run("gridrunner 1194")


func test_reconnect_does_not_shake_off_the_trace() -> void:
	# Абуз: вскрыл, вышел, зашёл — трейса нет. Теперь отсчёт у узла один на всё вторжение.
	_office_under_trace()
	solve_puzzle()
	var at_dc: int = t.session.trace_left()
	run("dc")
	assert_false(t.session.is_tracing(), "вне узла трейс не идёт")
	Clock.advance(30)
	var text: String = run("connect 77.61.204.12")
	assert_true(t.session.is_tracing(), "вернулся — трейс тот же")
	assert_string_contains(text, "трейс: ")
	assert_lte(t.session.trace_left(), at_dc, "пока был снаружи, отсчёт стоял, но назад не откатился")
	assert_gt(t.session.trace_left(), at_dc - 30, "30 минут снаружи не съели трейс")


func test_cracked_service_eases_the_trace() -> void:
	_office_under_trace()
	var before: int = t.session.trace_left()
	var total: int = t.session.trace_total()
	var text: String = solve_puzzle().text()
	var ease: int = total * int((DataLoader.balance()["nodes"] as Dictionary)["trace_ease_percent"]) / 100
	assert_string_contains(text, "трейс: +")
	assert_eq(t.session.trace_left(), mini(total, before + ease))


func test_trace_is_gone_after_the_target_resets() -> void:
	_office_under_trace()
	run("dc")
	Network.for_game().access.reset_services("node_office_server")
	reveal("node_office_server", ["svc_admin_login"])
	run("connect 77.61.204.12")
	assert_false(t.session.is_tracing(), "защита перенастроена — тревоги нет, нужен новый взлом")


func test_two_terminals_do_not_count_the_trace_twice() -> void:
	# Трейс двигает одна автозагрузка (HackManager), а не каждый терминал: окно и аварийная
	# консоль могут жить одновременно (технический разбор 16.11.2026).
	_office_under_trace()
	var second := Terminal.new()
	var ticks: Array = []
	second.ticked.connect(func(_r: TermResult) -> void: ticks.append(1))
	var before: int = t.session.trace_left()
	Clock.advance(10)
	assert_eq(t.session.trace_left(), before - 10, "ровно 10 минут, а не 20")
	assert_eq(ticks.size(), 1, "второй терминал тоже узнал о тике")
