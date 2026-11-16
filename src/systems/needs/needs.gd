class_name Needs
extends RefCounted
## Энергия и сытость (docs/gameplay/needs.md): как они тают и копятся с ходом времени, когда
## герой предупреждает и когда вырубается.
##
## Чистые правила без сцен. Слушает часы автозагрузка `NeedsManager`, а считает и меняет
## состояние этот класс. На взлом шкалы не влияют (решено 16.11.2026): ни головоломки, ни
## таймеры, ни команды их не читают.
##
## Значения — дробные, в переменных `GameState` (сейв их помнит). Числа — `balance.json`, `needs`.

const VAR_ENERGY: String = "needs.energy"
const VAR_SATIETY: String = "needs.satiety"
## Объём шкалы энергии. Растёт с прокачкой (M4); пока равен стартовому.
const VAR_ENERGY_MAX: String = "needs.energy_max"
## Реплика «скоро пора отдыхать» уже прозвучала: повторяется только после отдыха.
const VAR_WARNED_ENERGY: String = "needs.warned_energy"
## День, когда герой уже сказал, что голоден: одна реплика на сутки (time.md).
const VAR_WARNED_HUNGER_DAY: String = "needs.warned_hunger_day"

const EVENT_ENERGY_LOW: String = "energy_low"
const EVENT_HUNGRY: String = "hungry"
const EVENT_PASSED_OUT: String = "passed_out"

## Сытость: сытый — энергия тает медленнее и копится быстрее, голодный — наоборот.
const BAND_FED: String = "fed"
const BAND_NORMAL: String = "normal"
const BAND_HUNGRY: String = "hungry"


# --- Чтение ---------------------------------------------------------------------

static func energy() -> float:
	return float(GameState.get_var_or(VAR_ENERGY, _num("energy_start", 80.0)))


static func satiety() -> float:
	return float(GameState.get_var_or(VAR_SATIETY, _num("satiety_start", 70.0)))


static func energy_max() -> float:
	return float(GameState.get_var_or(VAR_ENERGY_MAX, _num("energy_max", 100.0)))


static func satiety_max() -> float:
	return _num("satiety_max", 100.0)


static func band() -> String:
	var s: float = satiety()
	if s <= _num("hungry_threshold", 20.0):
		return BAND_HUNGRY
	if s >= _num("fed_threshold", 60.0):
		return BAND_FED
	return BAND_NORMAL


## Сколько энергии уходит за час бодрствования сейчас (с поправкой на сытость).
static func drain_per_hour() -> float:
	return _num("energy_per_hour_awake", 2.0) * _band_mult("drain")


static func restore_per_hour() -> float:
	return _num("energy_restored_per_hour_sleep", 12.0) * _band_mult("restore")


## На сколько игровых часов бодрствования хватит энергии при нынешней сытости.
static func hours_left() -> float:
	var drain: float = drain_per_hour()
	return INF if drain <= 0.0 else energy() / drain


# --- Изменение ------------------------------------------------------------------

static func set_energy(value: float) -> void:
	GameState.set_var(VAR_ENERGY, clampf(value, 0.0, energy_max()))


static func set_satiety(value: float) -> void:
	GameState.set_var(VAR_SATIETY, clampf(value, 0.0, satiety_max()))


## Поесть: сытость растёт (не выше максимума). Что и почём — доставка (шаг 5 M2).
static func eat(amount: float) -> void:
	set_satiety(satiety() + amount)
	EventBus.needs_changed.emit()


## Прошло `minutes` игровых минут. Считаем по минуте: сытость за это время может перейти порог,
## а энергия — дойти до нуля посередине. Возвращает события по порядку: `energy_low`, `hungry`,
## `passed_out`.
static func pass_minutes(minutes: int, asleep: bool) -> Array[String]:
	var events: Array[String] = []
	for i: int in minutes:
		set_satiety(satiety() - _num("satiety_per_hour", 3.0) / 60.0)
		if asleep:
			set_energy(energy() + restore_per_hour() / 60.0)
		elif energy() > 0.0:
			set_energy(energy() - drain_per_hour() / 60.0)
			if energy() <= 0.0:
				events.append(EVENT_PASSED_OUT)
		_check_warnings(asleep, events)
	return events


## Реплика об усталости — когда энергии осталось на `warn_hours` бодрствования; снова — только
## после отдыха. О голоде — на пороге голода, раз в сутки.
static func _check_warnings(asleep: bool, events: Array[String]) -> void:
	var warn_hours: float = _num("warn_hours", 2.0)
	var warned: bool = bool(GameState.get_var_or(VAR_WARNED_ENERGY, false))
	if hours_left() > warn_hours:
		if warned:
			GameState.set_var(VAR_WARNED_ENERGY, false)
	elif not asleep and not warned and energy() > 0.0:
		GameState.set_var(VAR_WARNED_ENERGY, true)
		events.append(EVENT_ENERGY_LOW)
	if band() == BAND_HUNGRY and not asleep \
			and int(GameState.get_var_or(VAR_WARNED_HUNGER_DAY, 0)) != GameState.day:
		GameState.set_var(VAR_WARNED_HUNGER_DAY, GameState.day)
		events.append(EVENT_HUNGRY)


static func _band_mult(kind: String) -> float:
	match band():
		BAND_FED:
			return _num("fed_%s_mult" % kind, 1.0)
		BAND_HUNGRY:
			return _num("hungry_%s_mult" % kind, 1.0)
	return 1.0


static func _num(key: String, fallback: float) -> float:
	var section: Dictionary = DataLoader.balance().get("needs", {}) as Dictionary
	return float(section.get(key, fallback))
