class_name LocationValidator
extends RefCounted
## Проверка локаций (docs/gameplay/locations.md): id с префиксом, известные типы объектов,
## прямоугольник в долях экрана, двери ведут в существующие локации, диалоги существуют.
## Условия объектов проверяет общий `Validator`.

var errors: PackedStringArray = []
var warnings: PackedStringArray = []


func validate(locations: Dictionary, dialogues: Dictionary) -> void:
	errors.clear()
	warnings.clear()
	for id: String in locations.keys():
		_validate_one(id, locations[id] as Dictionary, locations, dialogues)


func _validate_one(id: String, loc: Dictionary, locations: Dictionary, dialogues: Dictionary) -> void:
	var where: String = "локация " + id
	if not id.begins_with("loc_"):
		errors.append("%s: id должен начинаться с 'loc_'" % where)
	if str(loc.get("title", "")).is_empty():
		errors.append("%s: нет title" % where)
	var seen: Dictionary = {}
	for object_variant: Variant in loc.get("objects", []) as Array:
		var object: Dictionary = object_variant as Dictionary
		if object == null:
			errors.append("%s: объект должен быть словарём" % where)
			continue
		var object_id: String = str(object.get("id", ""))
		var at: String = "%s, объект '%s'" % [where, object_id]
		if object_id.is_empty():
			errors.append("%s: у объекта нет id" % where)
		elif seen.has(object_id):
			errors.append("%s: повторяющийся id" % at)
		seen[object_id] = true
		var kind: String = str(object.get("kind", ""))
		if not Locations.KINDS.has(kind):
			errors.append("%s: неизвестный kind '%s'" % [at, kind])
		_check_rect(at, object.get("rect", null))
		match kind:
			"door", "turn":
				var to: String = str(object.get("to", ""))
				if not locations.has(to):
					errors.append("%s: дверь ведёт в несуществующую локацию '%s'" % [at, to])
				elif to == id:
					errors.append("%s: дверь ведёт в ту же локацию" % at)
			"container":
				var container: String = str(object.get("container", ""))
				if not [Inventory.STORAGE, Inventory.FRIDGE].has(container):
					errors.append("%s: неизвестный контейнер '%s' (есть: room_storage, fridge)" % [at, container])
			"look":
				if str(object.get("text", "")).is_empty():
					errors.append("%s: у look нет text" % at)
			"dialogue":
				if not dialogues.has(str(object.get("dialogue", ""))):
					errors.append("%s: нет диалога '%s'" % [at, object.get("dialogue", "")])
	if seen.is_empty():
		warnings.append("%s: нет объектов" % where)


## rect — [x, y, ширина, высота] в долях экрана: сцена тянется под любое окно.
func _check_rect(at: String, rect_variant: Variant) -> void:
	var rect: Array = rect_variant as Array if rect_variant is Array else []
	if rect.size() != 4:
		errors.append("%s: rect — четыре числа [x, y, w, h]" % at)
		return
	for value: Variant in rect:
		if not (value is float or value is int):
			errors.append("%s: rect — числа" % at)
			return
	var x: float = float(rect[0])
	var y: float = float(rect[1])
	var w: float = float(rect[2])
	var h: float = float(rect[3])
	if x < 0.0 or y < 0.0 or w <= 0.0 or h <= 0.0 or x + w > 1.0 or y + h > 1.0:
		errors.append("%s: rect выходит за экран (доли 0..1)" % at)
