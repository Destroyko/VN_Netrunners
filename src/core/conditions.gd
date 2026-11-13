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
]

## Где в GameState лежат ранг и эпизод: обычные числовые переменные состояния.
const VAR_RANK: String = "progress.rank"
const VAR_EPISODE: String = "progress.episode"


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


## Для валидатора данных: известен ли такой тип условия.
static func is_known(type: String) -> bool:
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
		_:
			push_error("Conditions: неизвестный тип условия '%s'" % type)
			return false
