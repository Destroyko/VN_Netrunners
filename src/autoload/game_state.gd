extends Node
## Единственный источник правды о состоянии игры.
## Здесь нет правил игры — только хранение, чтение и уведомление об изменениях.
## Всё, что должно уцелеть после загрузки сейва, лежит здесь (см. docs/tech/architecture.md).

## Версия формата сейва. Меняешь структуру — поднимай версию и пиши миграцию.
const SAVE_VERSION: int = 1

## Уровни сложности, docs/gameplay/difficulty.md. Фиксируется при старте игры.
enum Difficulty { STORY = 1, EASY = 2, NORMAL = 3, NETRUNNER = 4 }

const HEAT_MIN: int = 0
const HEAT_MAX: int = 100

var money: int = 0
var heat: int = 0
var difficulty: Difficulty = Difficulty.NORMAL

## Игровое время. Двигает его только Clock, хранится здесь — иначе сейв забудет время.
var day: int = 1
var minute: int = 0

# Приватные словари: только через методы ниже, чтобы изменения не проходили молча.
var _flags: Dictionary = {}
var _vars: Dictionary = {}
var _quests: Dictionary = {}


## Новая игра. Сложность задаётся здесь, потому что менять её потом нельзя.
func reset(new_difficulty: Difficulty = Difficulty.NORMAL) -> void:
	money = 0
	heat = 0
	difficulty = new_difficulty
	day = 1
	minute = 0
	_flags.clear()
	_vars.clear()
	_quests.clear()


# --- Флаги -------------------------------------------------------------------
# Имена с пространством имён: story.debt_revealed, world.police_raid_done.

func set_flag(flag: String, value: bool = true) -> void:
	var was: bool = has_flag(flag)
	if value:
		_flags[flag] = true
	else:
		_flags.erase(flag)
	if was != value:
		_notify("flag_changed", [flag, value])


func has_flag(flag: String) -> bool:
	return _flags.has(flag)


func clear_flag(flag: String) -> void:
	set_flag(flag, false)


## Копия, а не сам словарь: чтобы снаружи нельзя было поменять состояние мимо set_flag.
func get_flags() -> Dictionary:
	return _flags.duplicate()


# --- Переменные --------------------------------------------------------------
# Для чисел и строк, которым не хватает флага: счётчики, выбранные варианты.

func set_var(key: String, value: Variant) -> void:
	var old: Variant = _vars.get(key)
	_vars[key] = value
	if old != value:
		_notify("var_changed", [key, value])


func get_var_or(key: String, default_value: Variant = null) -> Variant:
	return _vars.get(key, default_value)


func has_var(key: String) -> bool:
	return _vars.has(key)


# --- Деньги ------------------------------------------------------------------

func add_money(delta: int) -> void:
	if delta == 0:
		return
	money += delta
	_notify("money_changed", [money, delta])


func set_money(value: int) -> void:
	add_money(value - money)


func can_afford(amount: int) -> bool:
	return money >= amount


# --- Заметность (heat) -------------------------------------------------------

func add_heat(delta: int) -> void:
	var before: int = heat
	heat = clampi(heat + delta, HEAT_MIN, HEAT_MAX)
	if heat != before:
		_notify("heat_changed", [heat, heat - before])


func set_heat(value: int) -> void:
	add_heat(value - heat)


# --- Прогресс квестов --------------------------------------------------------
# Этапы и цели ведёт QuestManager (M2), здесь только хранение.

func set_quest_stage(quest_id: String, stage_id: String) -> void:
	var entry: Dictionary = _quests.get(quest_id, {}) as Dictionary
	entry["stage"] = stage_id
	_quests[quest_id] = entry
	_notify("quest_stage_changed", [quest_id, stage_id])


func get_quest_stage(quest_id: String) -> String:
	var entry: Dictionary = _quests.get(quest_id, {}) as Dictionary
	return entry.get("stage", "") as String


func is_quest_started(quest_id: String) -> bool:
	return _quests.has(quest_id)


func set_quest_completed(quest_id: String, outcome: String = "done") -> void:
	var entry: Dictionary = _quests.get(quest_id, {}) as Dictionary
	entry["completed"] = true
	entry["outcome"] = outcome
	_quests[quest_id] = entry
	_notify("quest_completed", [quest_id, outcome])


func is_quest_completed(quest_id: String) -> bool:
	var entry: Dictionary = _quests.get(quest_id, {}) as Dictionary
	return entry.get("completed", false) as bool


# --- Сейв --------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"money": money,
		"heat": heat,
		"difficulty": int(difficulty),
		"day": day,
		"minute": minute,
		"flags": _flags.duplicate(true),
		"vars": _vars.duplicate(true),
		"quests": _quests.duplicate(true),
	}


## Загрузка без уведомлений: мир после загрузки не «происходит», он просто такой.
func from_dict(data: Dictionary) -> void:
	money = int(data.get("money", 0))
	heat = int(data.get("heat", 0))
	difficulty = int(data.get("difficulty", Difficulty.NORMAL)) as Difficulty
	day = int(data.get("day", 1))
	minute = int(data.get("minute", 0))
	_flags = (data.get("flags", {}) as Dictionary).duplicate(true)
	_vars = (data.get("vars", {}) as Dictionary).duplicate(true)
	_quests = (data.get("quests", {}) as Dictionary).duplicate(true)


# --- Внутреннее --------------------------------------------------------------

## Шлём событие через EventBus, если он уже есть (в юнит-тестах его может не быть).
func _notify(signal_name: String, args: Array) -> void:
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null and bus.has_signal(signal_name):
		bus.emit_signal(signal_name, args[0], args[1])
