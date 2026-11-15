class_name ItemValidator
extends RefCounted
## Проверка предметов (`data/items.json`, docs/gameplay/hacking.md). Отдельным файлом:
## один файл — одна ответственность.

var errors: PackedStringArray = []
var warnings: PackedStringArray = []


func validate(items: Dictionary) -> void:
	errors.clear()
	warnings.clear()
	var found: int = 0
	for id: String in items.keys():
		if id.begins_with("_"):
			continue
		found += 1
		if not id.begins_with(Inventory.ID_PREFIX):
			errors.append("предмет %s: id должен начинаться с '%s'" % [id, Inventory.ID_PREFIX])
		var item: Dictionary = items[id] as Dictionary
		var kind: String = str(item.get("kind", ""))
		if not Inventory.KINDS.has(kind):
			errors.append("предмет %s: неизвестный kind '%s' (есть: %s)" % [id, kind, ", ".join(Inventory.KINDS)])
		if str(item.get("name", "")).is_empty():
			errors.append("предмет %s: нет name" % id)
		if str(item.get("about", "")).is_empty():
			warnings.append("предмет %s: нет about" % id)
	if found == 0:
		errors.append("data/items.json не найден или пустой: у героя не может быть предметов")
