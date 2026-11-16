extends GutTest
## Rest: сон и ожидание до будильника, будящие события
## (docs/gameplay/needs.md, «Сон и будильник»).

func before_each() -> void:
	GameState.reset()
	Clock.reload_config()


func _at(hour: int, minute: int = 0) -> void:
	Clock.set_time(GameState.day, hour * 60 + minute)


func test_minutes_until_wraps_past_midnight() -> void:
	_at(22)
	assert_eq(Rest.minutes_until(8 * 60), 600, "с 22:00 до 08:00 — 10 часов")
	assert_eq(Rest.minutes_until(23 * 60), 60)


func test_alarm_on_current_minute_means_next_day() -> void:
	_at(8)
	assert_eq(Rest.minutes_until(8 * 60), 1440)


func test_sleep_wakes_on_alarm_next_day() -> void:
	_at(22)
	var report: Dictionary = Rest.sleep_until(12 * 60)
	assert_eq(GameState.day, 2)
	assert_eq(GameState.minute, 12 * 60, "проснулся по будильнику, а не когда выспался")
	assert_eq(int(report["minutes"]), 14 * 60)
	assert_eq(str(report["interrupted"]), "")


func test_waiting_passes_time_but_is_not_sleep() -> void:
	_at(22)
	var report: Dictionary = Rest.wait_until(8 * 60)
	assert_eq(GameState.minute, 8 * 60)


func test_asleep_only_while_sleeping() -> void:
	var seen: Dictionary = {"asleep": false}
	var spy := func(_m: int, _p: int) -> void:
		if Rest.is_asleep():
			seen["asleep"] = true
	EventBus.time_advanced.connect(spy)
	_at(22)
	Rest.sleep_until(23 * 60)
	EventBus.time_advanced.disconnect(spy)
	assert_true(bool(seen["asleep"]), "пока идёт сон, слушатели часов видят, что герой спит")
	assert_false(Rest.is_asleep(), "проснулся")


func test_wake_event_interrupts_sleep() -> void:
	var knock := func(minute: int, _p: int) -> void:
		if minute == 2 * 60:
			EventBus.wake_requested.emit("стук в дверь")
	EventBus.time_advanced.connect(knock)
	_at(23)
	var report: Dictionary = Rest.sleep_until(8 * 60)
	EventBus.time_advanced.disconnect(knock)
	assert_eq(GameState.minute, 2 * 60, "проснулся на минуте события")
	assert_eq(str(report["interrupted"]), "стук в дверь")


func test_wake_request_outside_sleep_is_ignored() -> void:
	EventBus.wake_requested.emit("звонок")
	_at(22)
	assert_eq(str(Rest.sleep_until(23 * 60)["interrupted"]), "")


func test_sleep_moves_trace_like_any_time() -> void:
	# Сон — обычное течение времени: всё, что слушает часы, видит каждую минуту.
	var count: Dictionary = {"n": 0}
	var spy := func(_m: int, passed: int) -> void: count["n"] += passed
	EventBus.time_advanced.connect(spy)
	_at(22)
	Rest.wait_until(23 * 60)
	EventBus.time_advanced.disconnect(spy)
	assert_eq(int(count["n"]), 60)


func test_parse_clock() -> void:
	assert_eq(Rest.parse_clock("08:00"), 480)
	assert_eq(Rest.parse_clock("23:59"), 1439)
	assert_eq(Rest.parse_clock("24:00"), -1)
	assert_eq(Rest.parse_clock("8"), -1)


func test_bed_console_command() -> void:
	_at(22)
	var text: String = DebugCommands.run("bed sleep 07:00")
	assert_string_contains(text, "прошло 540 мин")
	assert_eq(GameState.minute, 7 * 60)
	assert_string_contains(DebugCommands.run("bed nap 07:00"), "bed:")
	assert_string_contains(DebugCommands.run("bed wait 7"), "чч:мм")
