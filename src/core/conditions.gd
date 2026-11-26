class_name Conditions
extends RefCounted
## Один язык условий для квестов, триггеров, новостей и диалогов
## (словарь типов — docs/tech/quest-format.md).
##
## Условие — словарь, где ключ это тип проверки: {"flag": "story.debt_revealed"}.
## Если ключей несколько, они должны выполниться все (И).
## Код знает только КАК проверить условие; что проверять — решают данные.

## Реализованные типы. Новый тип добавляется здесь один раз и работает везде.
const KNOWN_TYPES: PackedStringArray = [
	"flag",
	"not_flag",
	"money_at_least",
	"heat_at_most",
	"time_of_day",
	"day_at_least",
	"rank_at_least",
	"episode_at_least",
	"skill_at_least",
	"has_item",
	"has_file",
	"heat_at_least",
	"at_location",
	"weekday",
	"time_between",
	"var_at_least",
]

## Типы из документации, которым нужны системы следующих этапов.
## Валидатор их пропускает, проверка пока возвращает false с предупреждением.
const DEFERRED_TYPES: PackedStringArray = [
]

## Где в GameState лежат ранг и эпизод: обычные числовые переменные состояния.
const VAR_RANK: String = "progress.rank"
const VAR_EPISODE: String = "progress.episode"

## Навыки: skill.hacking и далее (docs/gameplay/skills.md).
const VAR_SKILL_PREFIX: String = "skill."


## Проверить одно условие.
static func check(condition: Dictionary) -> bool:
	for type: String in condition.keys():
		if not _check_one(type, condition[type]):
			return false
	return true


## Все условия из списка (И). Пустой список — истина: «нет требований».
static func check_all(conditions: Array) -> bool:
	for condition: Variant in conditions:
		if condition is Dictionary and not check(condition as Dictionary):
			return false
	return true


## Хотя бы одно условие из списка (ИЛИ). Пустой список — ложь.
static func check_any(conditions: Array) -> bool:
	for condition: Variant in conditions:
		if condition is Dictionary and check(condition as Dictionary):
			return true
	return false


## Для валидатора данных: тип либо работает, либо запланирован — но не опечатка.
static func is_known(type: String) -> bool:
	return KNOWN_TYPES.has(type) or DEFERRED_TYPES.has(type)


static func is_implemented(type: String) -> bool:
	return KNOWN_TYPES.has(type)


static func _check_one(type: String, value: Variant) -> bool:
	match type:
		"flag":
			return GameState.has_flag(str(value))
		"not_flag":
			return not GameState.has_flag(str(value))
		"money_at_least":
			return GameState.money >= int(value)
		"heat_at_most":
			return GameState.heat <= int(value)
		"time_of_day":
			return Clock.time_of_day() == str(value)
		"day_at_least":
			return GameState.day >= int(value)
		"rank_at_least":
			return int(GameState.get_var_or(VAR_RANK, 0)) >= int(value)
		"episode_at_least":
			return int(GameState.get_var_or(VAR_EPISODE, 0)) >= int(value)
		"skill_at_least":
			# Формат: {"skill_at_least": ["hacking", 4]}
			var pair: Array = value as Array
			if pair == null or pair.size() != 2:
				push_error("Conditions: skill_at_least ожидает [навык, значение], получено: %s" % [value])
				return false
			return int(GameState.get_var_or(VAR_SKILL_PREFIX + str(pair[0]), 0)) >= int(pair[1])
		"has_item":
			return Inventory.has(str(value))
		"has_file":
			# По file_id, где бы файл ни лежал на ПК героя (quest-format.md).
			return Filesystem.for_node(Network.HOME_ID).has_file_id(str(value))
		"heat_at_least":
			return GameState.heat >= int(value)
		"at_location":
			# Формат: {"at_location": "loc_park"} — герой сейчас в этой локации.
			return str(GameState.get_var_or(Locations.VAR_LOCATION, "")) == str(value)
		"weekday":
			# Формат: {"weekday": "сб"} или {"weekday": ["сб", "вс"]} — как в дате у игрока.
			var today: String = Clock.WEEKDAYS[int(Clock.date_of(GameState.day)["weekday"])]
			return (value as Array).has(today) if value is Array else today == str(value)
		"time_between":
			# Формат: {"time_between": ["12:00", "16:00"]} — с 12:00 включительно до 16:00.
			var span: Array = value as Array
			if span == null or span.size() != 2:
				push_error("Conditions: time_between ожидает [\"чч:мм\", \"чч:мм\"], получено: %s" % [value])
				return false
			var from: int = Rest.parse_clock(str(span[0]))
			var to: int = Rest.parse_clock(str(span[1]))
			var now: int = GameState.minute
			return now >= from and now < to if from <= to else (now >= from or now < to)
		"var_at_least":
			# Формат: {"var_at_least": ["stats.jogs", 4]} — числовая переменная состояния (счётчик).
			var pair2: Array = value as Array
			if pair2 == null or pair2.size() != 2:
				push_error("Conditions: var_at_least ожидает [переменная, значение], получено: %s" % [value])
				return false
			return float(GameState.get_var_or(str(pair2[0]), 0)) >= float(pair2[1])
		_:
			if DEFERRED_TYPES.has(type):
				push_warning("Conditions: условие '%s' ещё не реализовано (нужна система следующего этапа)" % type)
				return false
			push_error("Conditions: неизвестный тип условия '%s'" % type)
			return false
