class_name Rest
extends RefCounted
## Сон и ожидание (docs/gameplay/needs.md, «Сон и будильник»; docs/gameplay/time.md, «Ждать и
## спать»): время проматывается до будильника или до события, которое будит.
##
## Чистые правила без сцен. Кровать в комнате и консоль F1 только вызывают их. Время двигает
## `Clock.advance` по минуте: так все, кто слушает ход часов (трейс, потребности), видят сон как
## обычное течение времени, а будящее событие может остановить промотку на своей минуте.

const MODE_SLEEP: String = "sleep"
const MODE_WAIT: String = "wait"

## Герой спит прямо сейчас: потребности (шаг 3 M2) по нему решают, тратить энергию или копить.
const VAR_ASLEEP: String = "rest.asleep"

const DEFAULT_ALARM: int = 480


## Будильник по умолчанию в окне кровати (минуты от начала суток).
static func default_alarm() -> int:
	return int(_cfg().get("alarm_default", DEFAULT_ALARM))


## Сколько минут до ближайшего `alarm` (минуты от начала суток). Будильник на текущую минуту —
## это через сутки, как у настоящего будильника.
static func minutes_until(alarm: int) -> int:
	var per_day: int = Clock.minutes_per_day
	var target: int = posmod(alarm, per_day)
	var left: int = posmod(target - GameState.minute, per_day)
	return per_day if left == 0 else left


static func sleep_until(alarm: int) -> Dictionary:
	return pass_time(minutes_until(alarm), MODE_SLEEP)


static func wait_until(alarm: int) -> Dictionary:
	return pass_time(minutes_until(alarm), MODE_WAIT)


## Вырубился: сон без будильника, пока энергия не станет полной (не дольше `rest.pass_out_max_minutes`
## на случай, если голод почти не даёт восстановиться). Будящие события прерывают и его.
static func sleep_until_rested() -> Dictionary:
	var cap: int = int(_cfg().get("pass_out_max_minutes", 1440))
	return _run(MODE_SLEEP, func(passed: int) -> bool: return passed < cap and Needs.energy() < Needs.energy_max())


static func is_asleep() -> bool:
	return bool(GameState.get_var_or(VAR_ASLEEP, false))


## Промотать `minutes` сна или ожидания. Возвращает {minutes, interrupted}: сколько прошло и
## что разбудило ("" — будильник). Заметность ото сна не зависит: она спадает за тихие сутки (Heat).
static func pass_time(minutes: int, mode: String) -> Dictionary:
	return _run(mode, func(passed: int) -> bool: return passed < minutes)


## Общий ход сна и ожидания: по минуте, пока `go_on(прошло)` и никто не разбудил.
static func _run(mode: String, go_on: Callable) -> Dictionary:
	# Словарь, а не локальная строка: лямбда захватывает локальные значения копией.
	var woke: Dictionary = {"reason": ""}
	var on_wake := func(reason: String) -> void:
		if str(woke["reason"]).is_empty():
			woke["reason"] = reason if not reason.is_empty() else "?"
	EventBus.wake_requested.connect(on_wake)
	if mode == MODE_SLEEP:
		GameState.set_var(VAR_ASLEEP, true)
	var passed: int = 0
	while go_on.call(passed) and str(woke["reason"]).is_empty():
		Clock.advance(1)
		passed += 1
	EventBus.wake_requested.disconnect(on_wake)
	GameState.set_var(VAR_ASLEEP, false)

	EventBus.rested.emit(mode, passed, str(woke["reason"]))
	return {"minutes": passed, "interrupted": str(woke["reason"])}


## «08:00» → 480; не время — -1.
static func parse_clock(text: String) -> int:
	var parts: PackedStringArray = text.strip_edges().split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1
	var h: int = int(parts[0])
	var m: int = int(parts[1])
	if h < 0 or h > 23 or m < 0 or m > 59:
		return -1
	return h * 60 + m


static func _cfg() -> Dictionary:
	return DataLoader.balance().get("rest", {}) as Dictionary
