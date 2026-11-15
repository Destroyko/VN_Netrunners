extends "res://test/unit/terminal_fixture.gd"
## Терминал и головоломки: запуск, слои, провал, сюжетный автовзлом
## (docs/tech/terminal-spec.md, docs/tech/puzzles-spec.md).


func _start_husband() -> void:
	# Узел мужа: «матрица» (фаервол), сложность сервиса 2 — средняя ступень.
	learn_programs()
	reveal("node_husband_pc")
	Clock.set_time(1, 19 * 60)
	run("connect 92.44.18.3")


func _start_training() -> void:
	learn_programs()
	reach_training_pc()
	run("connect 10.0.0.7")


# --- Запрос головоломки ------------------------------------------------------

func test_password_request_carries_a_live_puzzle() -> void:
	_start_training()
	run("passhound")
	var request: Dictionary = last.request
	assert_eq(request["difficulty"], 2, "сервис 1 — лёгкая ступень")
	assert_eq(request["layers_total"], 1)
	var puzzle: PasswordPuzzle = request["puzzle"] as PasswordPuzzle
	assert_not_null(puzzle)
	assert_eq(puzzle.length, 5)
	assert_same(t.current_puzzle(), puzzle, "терминал держит ту же партию, что отдал интерфейсу")


func test_solving_the_password_opens_the_service() -> void:
	_start_training()
	run("passhound")
	var puzzle: PasswordPuzzle = last.request["puzzle"] as PasswordPuzzle
	assert_true(bool(puzzle.guess(puzzle.word)["solved"]))
	assert_string_contains(t.finish_puzzle(1).text(), "сервис вскрыт")
	assert_string_contains(run("connect 10.0.0.7"), "подключено")


func test_matrix_request_is_a_matrix() -> void:
	_start_husband()
	run("gridrunner")
	assert_eq(last.request["kind"], "matrix")
	assert_eq(last.request["difficulty"], 3)
	assert_eq(last.request["layers_total"], 2)
	assert_true(last.request["puzzle"] is MatrixPuzzle)


func test_same_attempt_gives_the_same_puzzle() -> void:
	# После загрузки сейва игрок получает ту же головоломку, а не новую.
	_start_training()
	run("passhound")
	var first: String = (last.request["puzzle"] as PasswordPuzzle).word
	run("passhound")
	assert_eq((last.request["puzzle"] as PasswordPuzzle).word, first)


func test_cautious_target_plays_harder() -> void:
	_start_training()
	run("passhound")
	assert_eq(last.request["difficulty"], 2)
	Network.for_game().raise_alert("node_training_pc")
	run("passhound")
	assert_eq(last.request["difficulty"], 3, "доведённый трейс: +1 к сложности сервиса")
	assert_eq(last.request["alert"], 1)


func test_deepscan_opens_an_extra_letter_in_the_next_puzzle() -> void:
	# Узел фирмы: сервис с паролем сложности 3 → уровень «нетраннер», открытых букв нет.
	learn_programs()
	reveal("node_office_server")
	run("connect 77.61.204.12")
	run("passhound")
	assert_eq((last.request["puzzle"] as PasswordPuzzle).known.size(), 0)
	run("deepscan svc_admin_login")
	run("passhound")
	assert_eq((last.request["puzzle"] as PasswordPuzzle).known.size(), 1, "deepscan открыл ещё один символ")


func test_deepscan_can_fill_up_to_the_rule_and_no_further() -> void:
	# Минимум три буквы остаются неизвестными: на «нетраннере» открыть можно четыре из семи.
	learn_programs()
	reveal("node_office_server")
	run("connect 77.61.204.12")
	for _step: int in 4:
		assert_string_contains(run("deepscan svc_admin_login"), "ещё один символ")
	assert_string_contains(run("deepscan svc_admin_login"), "больше символов здесь не открыть")
	run("passhound")
	var puzzle: PasswordPuzzle = last.request["puzzle"] as PasswordPuzzle
	assert_eq(puzzle.length - puzzle.known.size(), 3)


# --- Слои «матрицы» ----------------------------------------------------------

func test_partial_success_keeps_the_layers() -> void:
	_start_husband()
	run("gridrunner")
	assert_string_contains(t.finish_puzzle(1).text(), "слой вскрыт: 1 из 2")
	assert_signal_emitted(EventBus, "puzzle_solved")
	assert_string_contains(run("connect 92.44.18.3"), "вскрыто 0 из 1", "один слой — ещё не сервис")


func test_layers_survive_a_voluntary_disconnect() -> void:
	# Добровольный dc прогресс сохраняет: взлом можно растянуть на несколько дней.
	_start_husband()
	run("gridrunner")
	t.finish_puzzle(1)
	run("dc")
	run("connect 92.44.18.3")
	run("gridrunner")
	assert_eq(last.request["layers_done"], 1)
	assert_eq((last.request["puzzle"] as MatrixPuzzle).targets.size(), 1, "осталось собрать одну цель")


func test_finishing_the_remaining_layers_opens_the_service() -> void:
	_start_husband()
	run("gridrunner")
	t.finish_puzzle(1)
	run("gridrunner")
	assert_string_contains(t.finish_puzzle(1).text(), "сервис вскрыт")
	assert_string_contains(run("connect 92.44.18.3"), "подключено")


func test_solving_every_layer_at_once_opens_the_service() -> void:
	_start_husband()
	run("gridrunner")
	assert_string_contains(solve_puzzle().text(), "сервис вскрыт")


func test_opened_service_forgets_its_progress() -> void:
	_start_husband()
	run("gridrunner")
	solve_puzzle()
	assert_eq(PuzzleProgress.for_game().attempts("node_husband_pc", "svc_firewall", t.now()), 0)


func test_layers_melt_after_two_days() -> void:
	_start_husband()
	run("gridrunner")
	t.finish_puzzle(1)
	Clock.advance(2 * 1440)
	run("gridrunner")
	assert_eq(last.request["layers_done"], 0, "слои растаяли")


func test_finished_trace_resets_the_layers() -> void:
	GameState.set_flag(Programs.GATE_PRESSURE)
	_start_husband()
	run("gridrunner")
	t.finish_puzzle(1)
	t.spend(60, TermResult.new())
	assert_eq(PuzzleProgress.for_game().layers("node_husband_pc", "svc_firewall", t.now()), 0, "цель перенастроила защиту")


func test_finished_trace_drops_the_deepscan_symbols() -> void:
	# Они были про старое слово: после трейса пароль новый.
	GameState.set_flag(Programs.GATE_PRESSURE)
	learn_programs()
	reveal("node_office_server")
	run("connect 77.61.204.12")
	run("deepscan svc_admin_login")
	run("passhound")
	t.spend(60, TermResult.new())
	assert_eq(int(GameState.get_var_or("deepscan.node_office_server.svc_admin_login", 0)), 0)


# --- Провал ------------------------------------------------------------------

func test_failure_counts_the_attempt_and_reports_it() -> void:
	_start_training()
	run("passhound")
	assert_string_contains(t.finish_puzzle(0).text(), "провал")
	assert_signal_emitted(EventBus, "puzzle_failed")
	assert_eq(get_signal_parameters(EventBus, "puzzle_failed")[4], 1, "первая неудача")
	run("passhound")
	t.finish_puzzle(0)
	assert_eq(get_signal_parameters(EventBus, "puzzle_failed")[4], 2, "вторая: цена растёт")


func test_retry_after_failure_is_a_new_puzzle() -> void:
	_start_training()
	run("passhound")
	var first_seed: int = (last.request["puzzle"] as PasswordPuzzle).puzzle_seed
	t.finish_puzzle(0)
	run("passhound")
	assert_ne((last.request["puzzle"] as PasswordPuzzle).puzzle_seed, first_seed, "новая попытка — новый сид")
	assert_eq(last.request["attempt"], 1)


func test_failure_report_names_node_and_service() -> void:
	_start_training()
	run("passhound")
	t.finish_puzzle(0)
	var params: Array = get_signal_parameters(EventBus, "puzzle_failed")
	assert_eq(params[2], "node_training_pc")
	assert_eq(params[3], "svc_login")
