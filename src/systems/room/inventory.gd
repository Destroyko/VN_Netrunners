class_name Inventory
extends RefCounted
## Инвентарь героя: какие предметы у него есть (docs/gameplay/hacking.md, «Комната»).
##
## Описания — в `data/items.json`, а факт владения — флаг `item.<имя>` в GameState (имя — id
## без префикса `item_`). Отдельного поля в сейве нет, поэтому миграция не нужна.
## Предметы выдаёт сюжет эффектом `give_item`; в M1 — консоль: `effect {"give_item": "item_flash_backup"}`.

const FLAG_PREFIX: String = "item."
const ID_PREFIX: String = "item_"

const KIND_RESTORE: String = "restore"  # резервный носитель
const KINDS: PackedStringArray = [KIND_RESTORE]


static func definitions() -> Dictionary:
	var result: Dictionary = {}
	var data: Dictionary = DataLoader.items()
	for id: String in data.keys():
		if not id.begins_with("_") and data[id] is Dictionary:
			result[id] = data[id]
	return result


static func is_item(id: String) -> bool:
	return definitions().has(id)


static func flag_for(id: String) -> String:
	return FLAG_PREFIX + id.trim_prefix(ID_PREFIX)


static func has(id: String) -> bool:
	return is_item(id) and GameState.has_flag(flag_for(id))


static func give(id: String) -> bool:
	if not is_item(id):
		push_error("Inventory: неизвестный предмет '%s'" % id)
		return false
	GameState.set_flag(flag_for(id))
	return true


static func take(id: String) -> bool:
	if not has(id):
		return false
	GameState.clear_flag(flag_for(id))
	return true


## Предметы героя в стабильном порядке.
static func items() -> PackedStringArray:
	var result: PackedStringArray = []
	for id: String in definitions().keys():
		if has(id):
			result.append(id)
	result.sort()
	return result


static func name_of(id: String) -> String:
	return str((definitions().get(id, {}) as Dictionary).get("name", id))


static func about(id: String) -> String:
	return str((definitions().get(id, {}) as Dictionary).get("about", ""))


static func kind_of(id: String) -> String:
	return str((definitions().get(id, {}) as Dictionary).get("kind", ""))
