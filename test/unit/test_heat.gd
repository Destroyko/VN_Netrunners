extends "res://test/unit/terminal_fixture.gd"
## Заметность: цены источников, ворота `gate.pressure`, спад ото сна, этапы
## (docs/gameplay/heat.md). Слушатель HeatManager проверяем настоящими событиями шины.


func open_gate() -> void:
	GameState.set_flag(Programs.GATE_PRESSURE)


# --- Цены ---------------------------------------------------------------------

func test_failed_puzzle_costs_grow_with_the_attempt() -> void:
	assert_eq(Heat.puzzle_failed_cost(1), 5)
	assert_eq(Heat.puzzle_failed_cost(2), 7)
	assert_eq(Heat.puzzle_failed_cost(3), 9)


func test_trace_finished_is_the_costliest_mistake() -> void:
	assert_eq(Heat.trace_finished_cost(), 20)


func test_traces_cost_is_the_sum_of_remaining_categories() -> void:
	var book: Logbook = logbook("node_training_pc")
	assert_eq(Heat.traces_cost("node_training_pc"), 0)
	book.append(Logbook.CATEGORY_SESSION, "вход", 1, 600, false, "login")
	book.append(Logbook.CATEGORY_FILE_DELETED, "удалён a", 1, 601, false, "a")
	book.append(Logbook.CATEGORY_FILE_DELETED, "удалён b", 1, 602, false, "b")
	assert_eq(Heat.traces_cost("node_training_pc"), 4, "сеанс 1 + удаление 3, а не за каждый файл")


# --- Ворота -------------------------------------------------------------------

func test_nothing_grows_while_the_gate_is_closed() -> void:
	EventBus.puzzle_failed.emit("password", 2, "node_x", "svc_x", 1)
	EventBus.trace_finished.emit("node_x")
	assert_eq(GameState.heat, 0)
	assert_eq(Heat.gain(10), 0)


func test_gate_opens_the_pressure() -> void:
	open_gate()
	EventBus.puzzle_failed.emit("password", 2, "node_x", "svc_x", 1)
	assert_eq(GameState.heat, 5)


# --- События шины -------------------------------------------------------------

func test_retries_on_the_same_service_cost_more() -> void:
	open_gate()
	EventBus.puzzle_failed.emit("password", 2, "node_x", "svc_x", 1)
	EventBus.puzzle_failed.emit("password", 2, "node_x", "svc_x", 2)
	assert_eq(GameState.heat, 5 + 7)


func test_trace_finished_adds_twenty() -> void:
	open_gate()
	EventBus.trace_finished.emit("node_x")
	assert_eq(GameState.heat, 20)


func test_a_clean_hack_costs_exactly_one() -> void:
	open_gate()
	enter("node_training_pc")
	run("dc")
	assert_eq(GameState.heat, 1, "запись о выходе неустранима")


func test_a_messy_hack_costs_more() -> void:
	open_gate()
	enter("node_training_pc")
	logbook("node_training_pc").append(Logbook.CATEGORY_ROOT, "права", 1, 600, false, "root")
	run("dc")
	assert_eq(GameState.heat, 1 + 4)


func test_heat_is_capped_at_the_maximum() -> void:
	open_gate()
	GameState.set_heat(95)
	EventBus.trace_finished.emit("node_x")
	assert_eq(GameState.heat, 100)


# --- Спад ---------------------------------------------------------------------

func test_a_night_of_sleep_lowers_heat_by_five() -> void:
	GameState.set_heat(12)
	EventBus.slept.emit(1)
	assert_eq(GameState.heat, 7)


func test_nights_add_up_and_stop_at_zero() -> void:
	GameState.set_heat(12)
	EventBus.slept.emit(5)
	assert_eq(GameState.heat, 0)


func test_decay_works_even_with_a_closed_gate() -> void:
	GameState.set_heat(10)
	assert_eq(Heat.rest(1), 5)
	assert_eq(GameState.heat, 5)


func test_no_decay_without_sleep() -> void:
	GameState.set_heat(30)
	Clock.advance(3 * 24 * 60)
	assert_eq(GameState.heat, 30, "время идёт само, спад только ото сна")


func test_rest_with_no_nights_does_nothing() -> void:
	GameState.set_heat(30)
	assert_eq(Heat.rest(0), 0)
	assert_eq(GameState.heat, 30)


# --- Как это видно ------------------------------------------------------------

func test_stages_are_twenty_wide() -> void:
	assert_eq(Heat.stage_of(0), 1)
	assert_eq(Heat.stage_of(19), 1)
	assert_eq(Heat.stage_of(20), 2)
	assert_eq(Heat.stage_of(59), 3)
	assert_eq(Heat.stage_of(60), 4)
	assert_eq(Heat.stage_of(80), 5)
	assert_eq(Heat.stage_of(100), 5)


func test_bar_has_ten_cells() -> void:
	assert_eq(Heat.bar_cells(0), 0)
	assert_eq(Heat.bar_cells(9), 0)
	assert_eq(Heat.bar_cells(10), 1)
	assert_eq(Heat.bar_cells(100), 10)


# --- Консоль ------------------------------------------------------------------

func test_sleep_command_lowers_heat() -> void:
	GameState.set_heat(20)
	assert_string_contains(DebugCommands.run("sleep 2"), "10")
	assert_eq(GameState.heat, 10)


func test_sleep_command_defaults_to_one_night() -> void:
	GameState.set_heat(20)
	DebugCommands.run("sleep")
	assert_eq(GameState.heat, 15)


func test_sleep_command_rejects_garbage() -> void:
	assert_string_contains(DebugCommands.run("sleep many"), "sleep:")
