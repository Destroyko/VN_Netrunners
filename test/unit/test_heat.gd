extends "res://test/unit/terminal_fixture.gd"
## Заметность: цены источников, ворота `gate.pressure`, спад за тихие сутки, этапы
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


# --- Спад: за каждые полные сутки без нового начисления ----------------------

const DAY: int = 24 * 60


## Заметность «только что начислена»: отсчёт тихих суток идёт с этой минуты.
func _heat(value: int) -> void:
	GameState.set_heat(value)
	GameState.set_var(Heat.VAR_QUIET_SINCE, Clock.total_minutes())


func test_a_quiet_day_lowers_heat_by_five() -> void:
	_heat(12)
	Clock.advance(DAY)
	assert_eq(GameState.heat, 7)


func test_less_than_a_day_does_nothing() -> void:
	_heat(12)
	Clock.advance(DAY - 1)
	assert_eq(GameState.heat, 12)


func test_quiet_days_add_up_and_stop_at_zero() -> void:
	_heat(12)
	Clock.advance(5 * DAY)
	assert_eq(GameState.heat, 0)


func test_decay_is_counted_by_the_minute_not_by_midnight() -> void:
	Clock.set_time(1, 23 * 60)
	_heat(20)
	Clock.advance(120)
	assert_eq(GameState.heat, 20, "полночь сама по себе заметность не снижает")


func test_new_gain_restarts_the_quiet_day() -> void:
	open_gate()
	_heat(20)
	Clock.advance(DAY - 60)
	EventBus.trace_finished.emit("node_x")
	assert_eq(GameState.heat, 40)
	Clock.advance(DAY - 1)
	assert_eq(GameState.heat, 40, "сутки считаются от последнего начисления")
	Clock.advance(1)
	assert_eq(GameState.heat, 35)


func test_even_a_clean_hack_restarts_the_quiet_day() -> void:
	open_gate()
	_heat(10)
	Clock.advance(DAY - 10)
	assert_eq(Heat.gain(1), 1)
	Clock.advance(10)
	assert_eq(GameState.heat, 11)


func test_gain_behind_closed_gate_does_not_restart() -> void:
	_heat(10)
	Clock.advance(DAY - 10)
	assert_eq(Heat.gain(5), 0)
	Clock.advance(10)
	assert_eq(GameState.heat, 5)


func test_decay_works_even_with_a_closed_gate() -> void:
	_heat(10)
	assert_eq(Heat.decay(1), 5)
	assert_eq(GameState.heat, 5)


func test_sleep_does_not_lower_heat_by_itself() -> void:
	Clock.set_time(1, 22 * 60)
	_heat(30)
	Rest.sleep_until(8 * 60)
	assert_eq(GameState.heat, 30, "сон не снимает заметность, только тихие сутки")


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


func test_quest_effect_and_console_restart_the_quiet_day() -> void:
	_heat(0)
	Clock.advance(DAY - 10)
	Effects.apply({"heat": 10})
	Clock.advance(10)
	assert_eq(GameState.heat, 10, "эффект квеста — тоже начисление")
	Clock.advance(DAY - 20)
	DebugCommands.run("heat +5")
	Clock.advance(10)
	assert_eq(GameState.heat, 15, "консоль F1 тоже")



## Повторный визит платит только за свои следы (ISS-014): прошлые оплачены при прошлом отключении.
func test_second_visit_pays_only_for_new_traces() -> void:
	open_gate()
	var book: Logbook = logbook("node_training_pc")
	book.append(Logbook.CATEGORY_SESSION, "вход", 1, 600, false, "login")
	book.append(Logbook.CATEGORY_FILE_DELETED, "удалён a", 1, 601, false, "a")
	EventBus.node_disconnected.emit("node_training_pc")
	assert_eq(GameState.heat, 4, "первый визит: сеанс 1 + удаление 3")
	logbook("node_training_pc").append(Logbook.CATEGORY_SESSION, "вход", 2, 600, false, "login")
	EventBus.node_disconnected.emit("node_training_pc")
	assert_eq(GameState.heat, 5, "второй визит: только его запись сеанса")
	assert_eq(Heat.traces_cost("node_training_pc"), 4, "в логе по-прежнему лежит всё — чистить есть что")
