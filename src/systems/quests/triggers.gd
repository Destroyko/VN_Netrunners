class_name Triggers
extends RefCounted
## Сюжетные и мировые триггеры (docs/tech/architecture.md, «Сюжетные триггеры»): «при событии X,
## если условия Y → эффекты Z». Данные — `data/triggers/`, один файл на триггер.
##
## Чистые правила. События приносит двигатель сюжета (`StoryEngine` → `StoryQueue`,
## docs/tech/story-engine.md): `fire({"event": имя, аргументы…})`. `"match"` триггера сверяет
## аргументы события (`{"path": "/log/…"}`), `requires` — состояние мира.
##
## Перехват действия: триггер с `"on": "attempt.<действие>"` и `"block": "текст"` запрещает
## действие, пока выполнены его `requires` (`check_attempt`); текст — мысль героя.

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
static func fire(event: Variant, list: Dictionary = {}) -> PackedStringArray:
	var fired: PackedStringArray = []
	var args: Dictionary = event as Dictionary if event is Dictionary else {"event": str(event)}
	var name: String = str(args.get("event", ""))
	if list.is_empty():
		list = all()
	# Порядок по id — одинаковый при каждом запуске: баг воспроизводится.
	var ids: Array = list.keys()
	ids.sort()
	for id: String in ids:
		var t: Dictionary = list[id]
		if str(t.get("on", "")) != name or t.has("block"):
			continue
		if not _matches(t.get("match", {}) as Dictionary, args):
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


## Аргументы события совпадают с `match` триггера (все указанные поля равны).
static func _matches(wanted: Dictionary, args: Dictionary) -> bool:
	for key: String in wanted.keys():
		if str(args.get(key, "")) != str(wanted[key]):
			return false
	return true


## Можно ли действие `action` («attempt.pc_power_on»): первый подходящий триггер с `block` —
## {ok: false, text}; иначе {ok: true}.
static func check_attempt(action: String, list: Dictionary = {}) -> Dictionary:
	if list.is_empty():
		list = all()
	var ids: Array = list.keys()
	ids.sort()
	for id: String in ids:
		var t: Dictionary = list[id]
		if str(t.get("on", "")) != action or not t.has("block"):
			continue
		if Conditions.check_all(t.get("requires", []) as Array):
			return {"ok": false, "text": str(t["block"])}
	return {"ok": true, "text": ""}


static func has_fired(id: String) -> bool:
	return bool(GameState.get_var_or(VAR_FIRED_PREFIX + id, false))
