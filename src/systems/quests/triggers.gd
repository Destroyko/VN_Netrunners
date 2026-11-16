class_name Triggers
extends RefCounted
## Сюжетные и мировые триггеры (docs/tech/architecture.md, «Сюжетные триггеры»): «при событии X,
## если условия Y → эффекты Z». Данные — `data/triggers/`, один файл на триггер.
##
## Чистые правила. Подписку на сигналы шины делает автозагрузка `TriggerManager`: она зовёт
## `fire(имя события)`. Аргументы сигнала триггер не читает — что проверить, решают `requires`.

## Сработавший триггер с `"once": true` больше не срабатывает (переменная состояния — сейв помнит).
const VAR_FIRED_PREFIX: String = "trigger_fired."


static func all() -> Dictionary:
	return DataLoader.triggers()


## Имена событий, на которые есть хоть один триггер.
static func events() -> PackedStringArray:
	var names: PackedStringArray = []
	for t: Dictionary in all().values():
		var on: String = str(t.get("on", ""))
		if not on.is_empty() and not names.has(on):
			names.append(on)
	return names


## Случилось событие `event`: сработать всем подходящим триггерам. Возвращает id сработавших.
## `list` — триггеры; по умолчанию все из данных (тесты передают свои).
static func fire(event: String, list: Dictionary = {}) -> PackedStringArray:
	var fired: PackedStringArray = []
	if list.is_empty():
		list = all()
	for id: String in list.keys():
		var t: Dictionary = list[id]
		if str(t.get("on", "")) != event:
			continue
		if bool(t.get("once", false)) and has_fired(id):
			continue
		if not Conditions.check_all(t.get("requires", []) as Array):
			continue
		if bool(t.get("once", false)):
			GameState.set_var(VAR_FIRED_PREFIX + id, true)
		Effects.apply_all(t.get("effects", []) as Array)
		fired.append(id)
	return fired


static func has_fired(id: String) -> bool:
	return bool(GameState.get_var_or(VAR_FIRED_PREFIX + id, false))
