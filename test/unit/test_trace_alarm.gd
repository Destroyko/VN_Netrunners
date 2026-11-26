extends GutTest
## Тревога трейса в реальных секундах (решено 25.11.2026): рамка вспыхивает раз в 10 с с 60 до
## 30, раз в 5 с с 30 до 15, последние 15 с горит с таймером.

const CFG: Dictionary = {"slow_from": 60, "slow_period": 10, "fast_from": 30, "fast_period": 5, "solid_from": 15}


func test_stages_by_real_seconds() -> void:
	assert_eq(TraceAlarm.stage(90.0, CFG), TraceAlarm.NONE)
	assert_eq(TraceAlarm.stage(60.0, CFG), TraceAlarm.SLOW)
	assert_eq(TraceAlarm.stage(29.0, CFG), TraceAlarm.FAST)
	assert_eq(TraceAlarm.stage(15.0, CFG), TraceAlarm.SOLID)
	assert_eq(TraceAlarm.stage(0.0, CFG), TraceAlarm.SOLID)


func test_frame_flashes_once_per_period() -> void:
	# Считаем вспышки — включения рамки — на отрезках 60…30 и 30…15.
	var slow_flashes: int = 0
	var fast_flashes: int = 0
	var was_on: bool = false
	for i: int in 451:
		var seconds: float = 60.0 - i * 0.1 - 0.05
		var on: bool = TraceAlarm.frame_on(seconds, CFG)
		if on and not was_on:
			if seconds > 30.0:
				slow_flashes += 1
			elif seconds > 15.0:
				fast_flashes += 1
		was_on = on
	assert_eq(slow_flashes, 3, "60…30: раз в 10 секунд")
	assert_eq(fast_flashes, 3, "30…15: раз в 5 секунд")
	assert_true(TraceAlarm.frame_on(10.0, CFG), "последние секунды — горит")
	assert_false(TraceAlarm.frame_on(120.0, CFG), "до минуты — рамки нет")


func test_real_seconds_follow_the_clock() -> void:
	assert_eq(TraceAlarm.real_seconds(10, 4.0, 1.0, 0.0), 40.0, "10 минут по 4 секунды")
	assert_eq(TraceAlarm.real_seconds(10, 4.0, 1.0, 1.5), 38.5, "полторы секунды текущей минуты прошли")
	assert_almost_eq(TraceAlarm.real_seconds(9, 4.0, 3.0, 0.0), 12.0, 0.001, "под полоской программы — втрое быстрее")


func test_timer_shows_milliseconds() -> void:
	assert_eq(TraceAlarm.timer_text(14.372), "14.372")
	assert_eq(TraceAlarm.timer_text(3.5), "03.500")
