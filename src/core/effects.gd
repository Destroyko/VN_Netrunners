class_name Effects
extends RefCounted
## Один язык эффектов для квестов, триггеров, диалогов и ивентов
## (словарь типов — docs/tech/quest-format.md).
##
## Эффект — словарь, где ключ это тип: {"money": 500}, {"set_flag": "story.x"}.
## Эффекты меняют только GameState; системы узнают об изменениях из EventBus.
## Подстановку параметров шаблонов ({reward} у radiant-квестов) делает вызывающий,
## сюда приходят уже готовые значения.

## Реализованные типы.
const KNOWN_TYPES: PackedStringArray = [
	"money",
	"heat",
	"set_flag",
	"clear_flag",
	"set_var",
	"rep",
]

## Типы из документации, которым нужны системы следующих этапов.
## Валидатор их пропускает, применение пока только пишет предупреждение.
const DEFERRED_TYPES: PackedStringArray = [
	"unlock_quest",   # QuestManager, M2
	"add_file",       # filesystem, M1
	"schedule_news",  # NewsManager, M2
	"send_message",   # почта и мессенджер, M2
	"add_note",       # блокнот заметок, docs/gameplay/notebook.md
]

## Репутация хранится как переменная состояния: rep.<кто>.
const VAR_REP_PREFIX: String = "rep."


## Применить один эффект. Возвращает true, если эффект действительно применён.
static func apply(effect: Dictionary) -> bool:
	var applied: bool = false
	for type: String in effect.keys():
		applied = _apply_one(type, effect[type]) or applied
	return applied


static func apply_all(effects: Array) -> void:
	for effect: Variant in effects:
		if effect is Dictionary:
			apply(effect as Dictionary)


## Для валидатора: тип либо работает, либо запланирован — но не опечатка.
static func is_known(type: String) -> bool:
	return KNOWN_TYPES.has(type) or DEFERRED_TYPES.has(type)


static func is_implemented(type: String) -> bool:
	return KNOWN_TYPES.has(type)


static func _apply_one(type: String, value: Variant) -> bool:
	match type:
		"money":
			GameState.add_money(int(value))
			return true
		"heat":
			GameState.add_heat(int(value))
			return true
		"set_flag":
			GameState.set_flag(str(value), true)
			return true
		"clear_flag":
			GameState.set_flag(str(value), false)
			return true
		"set_var":
			# Формат: {"set_var": ["ключ", значение]}
			var pair: Array = value as Array
			if pair == null or pair.size() != 2:
				push_error("Effects: set_var ожидает [ключ, значение], получено: %s" % [value])
				return false
			GameState.set_var(str(pair[0]), pair[1])
			return true
		"rep":
			# Формат: {"rep": ["персонаж_или_фракция", изменение]}
			var pair_rep: Array = value as Array
			if pair_rep == null or pair_rep.size() != 2:
				push_error("Effects: rep ожидает [кто, изменение], получено: %s" % [value])
				return false
			var key: String = VAR_REP_PREFIX + str(pair_rep[0])
			GameState.set_var(key, int(GameState.get_var_or(key, 0)) + int(pair_rep[1]))
			return true
		_:
			if DEFERRED_TYPES.has(type):
				push_warning("Effects: эффект '%s' ещё не реализован (нужна система следующего этапа)" % type)
				return false
			push_error("Effects: неизвестный тип эффекта '%s'" % type)
			return false
