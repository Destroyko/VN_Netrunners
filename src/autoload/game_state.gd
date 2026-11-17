extends Node
## Единственный источник правды о состоянии игры.
## Здесь нет правил игры — только хранение, чтение и уведомление об изменениях.
## Всё, что должно уцелеть после загрузки сейва, лежит здесь (см. docs/tech/architecture.md).

## Версия формата сейва. Меняешь структуру — поднимай версию и пиши миграцию.
## v2 (M3, 17.11.2026): предметы — экземпляры в контейнерах (раздел `inventory`), а не флаги.
const SAVE_VERSION: int = 2

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
## Файловые системы узлов: node_id → {files, dirs}. Лежат здесь, а не в системе, потому что
## удаления и скопированные файлы обязаны попасть в сейв — иначе после загрузки мир
## «забудет», что игрок там был (docs/tech/architecture.md).
var _filesystems: Dictionary = {}
## Сеть: адресная книга, вскрытые сервисы, осторожность целей и идущий взлом. Это состояние
## мира, а не сессии: после загрузки узел должен помнить, что его уже вскрывали, и сколько
## осталось до конца трейса (docs/gameplay/network.md).
var _network: Dictionary = {}
## Прогресс головоломок: вскрытые слои и счётчик попыток по сервисам. Состояние мира, а не
## сессии: после загрузки сейва сервис должен помнить, что он наполовину вскрыт
## (docs/tech/puzzles-spec.md).
var _puzzles: Dictionary = {}
## Экономика: счета к оплате и история операций банка (docs/gameplay/economy.md). Состояние
## мира: после загрузки долг за аренду и пеня должны остаться.
var _economy: Dictionary = {}
## Почта: доставленные письма, прочитано ли, что ответил (docs/tech/quest-format.md). Ответ —
## выбор игрока, после загрузки он должен остаться сделанным.
var _mail: Dictionary = {}
## Инвентарь и хранилища (docs/gameplay/inventory.md): {containers: {id: [предметы]}, next: n}.
## Предмет — экземпляр со своим uid: флешку можно переименовать, квестовую — не выбросить.
var _inventory: Dictionary = {}


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
	_filesystems.clear()
	_network.clear()
	_puzzles.clear()
	_economy.clear()
	_mail.clear()
	_inventory.clear()


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


## Запись квеста целиком (этап, выполненные цели, день начала, исход) — для QuestManager.
## Изменяемая: правила квестов пишут в неё прямо, сигналы шлют сами.
func quest_entry(quest_id: String) -> Dictionary:
	if not _quests.has(quest_id):
		_quests[quest_id] = {}
	return _quests[quest_id]


func quest_ids() -> Array:
	return _quests.keys()


func is_quest_completed(quest_id: String) -> bool:
	var entry: Dictionary = _quests.get(quest_id, {}) as Dictionary
	return entry.get("completed", false) as bool


# --- Файловые системы узлов --------------------------------------------------
# Хранение, а не правила: операции с файлами — в src/systems/filesystem.

func has_filesystem(node_id: String) -> bool:
	return _filesystems.has(node_id)


## Возвращается сам словарь, а не копия: система файлов меняет его на месте,
## и изменения сразу оказываются в состоянии игры.
func filesystem_state(node_id: String) -> Dictionary:
	return _filesystems.get(node_id, {}) as Dictionary


func set_filesystem_state(node_id: String, state: Dictionary) -> void:
	_filesystems[node_id] = state


## Сеть одна на игру. Отдаётся сам словарь, как и у файлов: Network меняет его на месте.
func network_state() -> Dictionary:
	return _network


func set_network_state(state: Dictionary) -> void:
	_network = state


## Как и с сетью: отдаётся сам словарь, PuzzleProgress меняет его на месте.
func puzzle_state() -> Dictionary:
	return _puzzles


func economy_state() -> Dictionary:
	return _economy


func set_economy_state(state: Dictionary) -> void:
	_economy = state


func mail_state() -> Dictionary:
	return _mail


## Отдаётся сам словарь: Inventory меняет его на месте.
func inventory_state() -> Dictionary:
	return _inventory


func set_puzzle_state(state: Dictionary) -> void:
	_puzzles = state


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
		"filesystems": _filesystems.duplicate(true),
		"network": _network.duplicate(true),
		"puzzles": _puzzles.duplicate(true),
		"economy": _economy.duplicate(true),
		"mail": _mail.duplicate(true),
		"inventory": _inventory.duplicate(true),
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
	_filesystems = (data.get("filesystems", {}) as Dictionary).duplicate(true)
	_network = (data.get("network", {}) as Dictionary).duplicate(true)
	_puzzles = (data.get("puzzles", {}) as Dictionary).duplicate(true)
	# Нет ключа (сейв до M2) — пустая экономика: счетов нет, история пустая. Миграция не нужна.
	_economy = (data.get("economy", {}) as Dictionary).duplicate(true)
	_mail = (data.get("mail", {}) as Dictionary).duplicate(true)
	_inventory = (data.get("inventory", {}) as Dictionary).duplicate(true)


# --- Внутреннее --------------------------------------------------------------

## Шлём событие через EventBus, если он уже есть (в юнит-тестах его может не быть).
func _notify(signal_name: String, args: Array) -> void:
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null and bus.has_signal(signal_name):
		bus.emit_signal(signal_name, args[0], args[1])
