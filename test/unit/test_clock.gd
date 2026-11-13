extends GutTest
## Clock: движение времени и переход через полночь.

const TEST_DAY: int = 100  # короткий день, чтобы переходы было видно в тесте


func before_each() -> void:
	GameState.reset()
	Clock.configure({
		"minutes_per_day": TEST_DAY,
		"time_of_day_bounds": {"morning": 25, "day": 45, "evening": 70, "night": 90},
	})


func after_each() -> void:
	# Возвращаем настройки из balance.json, чтобы не влиять на другие тесты.
	Clock.reload_config()


func test_advance_moves_minutes() -> void:
	Clock.advance(30)
	assert_eq(GameState.minute, 30)
	assert_eq(GameState.day, 1, "день не сменился")


func test_advance_zero_or_negative_does_nothing() -> void:
	Clock.advance(0)
	Clock.advance(-10)
	assert_eq(GameState.minute, 0)


func test_midnight_starts_new_day() -> void:
	watch_signals(EventBus)
	Clock.advance(TEST_DAY + 20)
	assert_eq(GameState.day, 2)
	assert_eq(GameState.minute, 20)
	assert_signal_emitted_with_parameters(EventBus, "day_started", [2])


func test_long_action_can_cross_several_days() -> void:
	watch_signals(EventBus)
	Clock.advance(TEST_DAY * 3 + 5)
	assert_eq(GameState.day, 4, "брутфорс на несколько дней")
	assert_eq(GameState.minute, 5)
	assert_signal_emit_count(EventBus, "day_started", 3, "событие на каждый день")


func test_time_advanced_reports_spent_minutes() -> void:
	watch_signals(EventBus)
	Clock.advance(15)
	assert_signal_emitted_with_parameters(EventBus, "time_advanced", [15, 15])


func test_set_time_does_not_send_events() -> void:
	watch_signals(EventBus)
	Clock.set_time(5, 50)
	assert_eq(GameState.day, 5)
	assert_eq(GameState.minute, 50)
	assert_signal_not_emitted(EventBus, "day_started", "перевод времени — не событие игры")


func test_set_time_clamps_values() -> void:
	Clock.set_time(0, TEST_DAY + 500)
	assert_eq(GameState.day, 1, "день меньше первого невозможен")
	assert_eq(GameState.minute, TEST_DAY - 1)


func test_minutes_until_next_day() -> void:
	Clock.advance(40)
	assert_eq(Clock.minutes_until_next_day(), TEST_DAY - 40)


func test_time_of_day_segments() -> void:
	Clock.set_time(1, 10)
	assert_eq(Clock.time_of_day(), "night")
	Clock.set_time(1, 30)
	assert_eq(Clock.time_of_day(), "morning")
	Clock.set_time(1, 50)
	assert_eq(Clock.time_of_day(), "day")
	Clock.set_time(1, 75)
	assert_eq(Clock.time_of_day(), "evening")
	Clock.set_time(1, 95)
	assert_eq(Clock.time_of_day(), "night")


func test_hours_and_format_use_real_day_length() -> void:
	Clock.reload_config()  # 1440 минут в сутках
	Clock.set_time(3, 14 * 60 + 30)
	assert_eq(Clock.hour(), 14)
	assert_eq(Clock.minute_of_hour(), 30)
	assert_eq(Clock.format_time(), "День 3, 14:30")
