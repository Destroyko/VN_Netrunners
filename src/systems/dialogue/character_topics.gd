class_name CharacterTopics
extends RefCounted
## Темы разговора с персонажем (docs/tech/dialogue-format.md, «Взаимодействие с персонажами»):
## клик по персонажу — меню тем, которые доступны сейчас. Тема — диалог + условия, когда она видна,
## + `once` (одноразовая). Квест открывает нужную тему флагом; цель `talk` закрывается, когда
## диалог темы кончился.
##
## Данные — `data/characters.json`, у персонажа поле `topics`:
##   [{"id": "run", "title": "О совместной пробежке", "dialogue": "dlg_x",
##     "requires": [{"flag": "quest.x.ask_run"}], "once": true}]
## Заготовка (26.11.2026): формат и правила; настоящие темы пишутся вместе с диалогами.

## Использованная одноразовая тема: `topic_used.<персонаж>.<тема>` (сейв помнит).
const VAR_USED_PREFIX: String = "topic_used."


static func all(character: String) -> Array:
	return (DataLoader.characters().get(character, {}) as Dictionary).get("topics", []) as Array


## Темы, которые видны сейчас: условия выполнены, одноразовая ещё не использована.
static func available(character: String) -> Array:
	var shown: Array = []
	for topic: Dictionary in all(character):
		if bool(topic.get("once", false)) and is_used(character, str(topic["id"])):
			continue
		if not Conditions.check_all(topic.get("requires", []) as Array):
			continue
		shown.append(topic)
	return shown


static func is_used(character: String, topic_id: String) -> bool:
	return bool(GameState.get_var_or("%s%s.%s" % [VAR_USED_PREFIX, character, topic_id], false))


## Выбрать тему: начать её диалог, одноразовую — отметить. Темы нет или она сейчас не видна — false.
static func choose(character: String, topic_id: String) -> bool:
	for topic: Dictionary in available(character):
		if str(topic["id"]) != topic_id:
			continue
		if bool(topic.get("once", false)):
			GameState.set_var("%s%s.%s" % [VAR_USED_PREFIX, character, topic_id], true)
		Effects.apply({"start_dialogue": str(topic["dialogue"])})
		return true
	return false
