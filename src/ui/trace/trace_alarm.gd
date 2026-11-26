class_name TraceAlarm
extends RefCounted
## Когда и как тревожит трейс (решено разработчиком 25.11.2026, шаг 7, часть 7): считается в
## **реальных** секундах до конца — сколько осталось игроку на часах, а не в игре. Числа —
## `balance.json`, раздел `trace_alarm`:
## - от `slow_from` (60) до `fast_from` (30) — рамка экрана вспыхивает раз в `slow_period` (10) с;
## - от `fast_from` до `solid_from` (15) — раз в `fast_period` (5) с;
## - последние `solid_from` секунд — рамка горит и виден таймер с миллисекундами.
##
## Чистые расчёты: оверлей (`TraceOverlay`) спрашивает их каждый кадр.

const NONE: String = "none"
const SLOW: String = "slow"
const FAST: String = "fast"
const SOLID: String = "solid"
## Сколько длится вспышка рамки.
const FLASH_SECONDS: float = 0.5


static func config() -> Dictionary:
	return DataLoader.balance().get("trace_alarm", {}) as Dictionary


## Стадия тревоги по реальным секундам до конца трейса.
static func stage(seconds_left: float, cfg: Dictionary = {}) -> String:
	var c: Dictionary = cfg if not cfg.is_empty() else config()
	if seconds_left <= float(c.get("solid_from", 15)):
		return SOLID
	if seconds_left <= float(c.get("fast_from", 30)):
		return FAST
	if seconds_left <= float(c.get("slow_from", 60)):
		return SLOW
	return NONE


## Видна ли рамка сейчас: вспышка в начале каждого периода, в последней стадии — всегда.
static func frame_on(seconds_left: float, cfg: Dictionary = {}) -> bool:
	var c: Dictionary = cfg if not cfg.is_empty() else config()
	var now: String = stage(seconds_left, c)
	if now == NONE:
		return false
	if now == SOLID:
		return true
	var period: float = float(c.get("slow_period" if now == SLOW else "fast_period", 10 if now == SLOW else 5))
	return fmod(seconds_left, period) > period - FLASH_SECONDS


## Реальные секунды до конца трейса: игровые минуты переводятся по ходу часов (под полоской
## программы — быстрее). `into_minute` — сколько реальных секунд уже прошло от текущей минуты.
static func real_seconds(minutes_left: int, seconds_per_minute: float, speedup: float, into_minute: float) -> float:
	return maxf(0.0, (float(minutes_left) * seconds_per_minute - into_minute) / maxf(1.0, speedup))


## Таймер последней стадии: «14.372».
static func timer_text(seconds_left: float) -> String:
	return "%06.3f" % maxf(0.0, seconds_left)
