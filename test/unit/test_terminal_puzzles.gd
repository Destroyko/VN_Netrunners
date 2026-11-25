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

func test_passhound_request_carries_a_live_dump() -> void:
	# passhound ломает вход по паролю «перехватом в дампе» (решено 15.11.2026).
	_start_training()
	run("passhound")
	var request: Dictionary = last.request
	assert_eq(request["kind"], "dump")
	assert_eq(request["difficulty"], 2, "сервис 1 — лёгкая ступень")
	assert_eq(request["layers_total"], 1)
	var puzzle: DumpPuzzle = request["puzzle"] as DumpPuzzle
	assert_not_null(puzzle)
	assert_eq(puzzle.targets.size(), int(PuzzleLevels.dump(2)["pieces"]))
	assert_same(t.current_puzzle(), puzzle, "терминал держит ту же партию, что отдал интерфейсу")


func test_catching_the_hash_opens_the_service() -> void:
	_start_training()
	run("passhound")
	var puzzle: DumpPuzzle = last.request["puzzle"] as DumpPuzzle
	assert_eq(catch_all(puzzle)["result"], DumpPuzzle.PICK_DONE)
	var word: String = str(last.request["password"])
	var text: String = t.finish_puzzle(1).text()
	assert_string_contains(text, "доступ получен")
	assert_string_contains(text, "пароль: " + word.to_upper(), "пароль показан игроку")
	assert_string_contains(run(word), "вход выполнен", "игрок вводит его сам")
	assert_true(t.session.has_connection())


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
	var first: Array = (last.request["puzzle"] as DumpPuzzle).targets
	run("passhound")
	assert_eq((last.request["puzzle"] as DumpPuzzle).targets, first)


func test_cautious_target_plays_harder() -> void:
	_start_training()
	run("passhound")
	assert_eq(last.request["difficulty"], 2)
	Network.for_game().raise_alert("node_training_pc")
	run("passhound")
	assert_eq(last.request["difficulty"], 3, "доведённый трейс: +1 к сложности сервиса")
	assert_eq(last.request["alert"], 1)


# --- Слои «матрицы» ----------------------------------------------------------

func test_partial_success_keeps_the_layers() -> void:
	_start_husband()
	run("gridrunner")
	assert_string_contains(t.finish_puzzle(1).text(), "слой вскрыт: 1 из 2")
	assert_signal_emitted(EventBus, "puzzle_solved")
	assert_string_contains(run("connect 92.44.18.3"), "вход отклонён", "один слой — ещё не сервис")


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
	var text: String = t.finish_puzzle(1).text()
	assert_string_contains(text, "доступ получен")
	assert_true(t.session.has_connection(), "вскрыто всё нужное — вошли без лишнего connect")


func test_solving_every_layer_at_once_opens_the_service() -> void:
	_start_husband()
	run("gridrunner")
	assert_string_contains(solve_puzzle().text(), "доступ получен")


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
	t.spend(trace_of("node_husband_pc"), TermResult.new())
	assert_eq(PuzzleProgress.for_game().layers("node_husband_pc", "svc_firewall", t.now()), 0, "цель перенастроила защиту")


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
	var first_seed: int = (last.request["puzzle"] as DumpPuzzle).puzzle_seed
	t.finish_puzzle(0)
	run("passhound")
	assert_ne((last.request["puzzle"] as DumpPuzzle).puzzle_seed, first_seed, "новая попытка — новый сид")
	assert_eq(last.request["attempt"], 1)


func test_failure_report_names_node_and_service() -> void:
	_start_training()
	run("passhound")
	t.finish_puzzle(0)
	var params: Array = get_signal_parameters(EventBus, "puzzle_failed")
	assert_eq(params[2], "node_training_pc")
	assert_eq(params[3], "svc_login")
