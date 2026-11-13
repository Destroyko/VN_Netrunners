class_name NodeValidator
extends RefCounted
## Проверка узлов сети (data/nodes/*.json).
## Формат описан в docs/tech/terminal-spec.md, раздел «Формат узла».
##
## Вынесено из Validator отдельным файлом: один файл — одна ответственность.
## Validator вызывает validate_all() и подмешивает ошибки к своим.

## Типы головоломок, docs/tech/puzzles-spec.md. MVP — две.
const PUZZLE_TYPES: PackedStringArray = ["password", "matrix"]

const MIN_DIFFICULTY: int = 1
const MAX_DIFFICULTY: int = 4

var errors: PackedStringArray = []
var warnings: PackedStringArray = []

# Адреса узлов должны быть уникальны: иначе connect приведёт не туда.
var _addresses: Dictionary = {}


func validate_all(nodes: Dictionary) -> void:
	errors.clear()
	warnings.clear()
	_addresses.clear()
	for id: String in nodes.keys():
		_validate_node(id, nodes[id] as Dictionary)


## Формат узла описан в docs/tech/terminal-spec.md, раздел «Формат узла».
func _validate_node(id: String, node: Dictionary) -> void:
	var where: String = "узел " + id
	_require_fields(where, node, ["id", "title", "address", "services", "files"])
	if node.has("id") and str(node["id"]) != id:
		errors.append("%s: поле id не совпадает с ключом ('%s')" % [where, node["id"]])

	var address: String = str(node.get("address", ""))
	if not address.is_empty():
		if _addresses.has(address):
			errors.append("%s: адрес '%s' уже занят узлом %s" % [where, address, _addresses[address]])
		else:
			_addresses[address] = id

	_check_difficulty(where, node)
	if int(node.get("trace_minutes", 0)) < 0:
		errors.append("%s: trace_minutes не может быть отрицательным" % where)

	var services: Array = node.get("services", []) as Array
	_validate_services(where, services)

	var required: int = int(node.get("required_services", 0))
	if required > services.size():
		errors.append(
			"%s: required_services = %d, а сервисов всего %d — узел нельзя взломать"
			% [where, required, services.size()]
		)

	var files: Dictionary = node.get("files", {}) as Dictionary
	_validate_files(where, files)
	_validate_logs_path(where, node, files)
	_validate_effects(where + ", on_hacked", node.get("on_hacked", []) as Array)


func _validate_services(where: String, services: Array) -> void:
	var seen: Dictionary = {}
	for service_variant: Variant in services:
		var service: Dictionary = service_variant as Dictionary
		if service == null:
			errors.append("%s: сервис должен быть объектом" % where)
			continue

		var service_id: String = str(service.get("id", ""))
		var service_where: String = "%s, сервис %s" % [where, service_id if not service_id.is_empty() else "?"]
		_require_fields(service_where, service, ["id", "name", "puzzle", "program"])

		if service_id.is_empty():
			continue
		if seen.has(service_id):
			errors.append("%s: повторяющийся id сервиса '%s'" % [where, service_id])
		seen[service_id] = true

		var puzzle: String = str(service.get("puzzle", ""))
		if not puzzle.is_empty() and not PUZZLE_TYPES.has(puzzle):
			errors.append("%s: неизвестный тип головоломки '%s'" % [service_where, puzzle])
		_check_difficulty(service_where, service)


func _validate_files(where: String, files: Dictionary) -> void:
	for path: String in files.keys():
		if not path.begins_with("/"):
			errors.append("%s: путь файла должен начинаться со слеша: '%s'" % [where, path])
		var file: Dictionary = files[path] as Dictionary
		if file == null:
			errors.append("%s: файл '%s' должен быть объектом" % [where, path])
			continue
		# Пустое описание файла — скорее забытое поле, чем задумка.
		var has_content: bool = (
			file.has("text") or file.has("size_kb") or file.has("system") or file.has("log")
		)
		if not has_content:
			warnings.append(
				"%s: у файла '%s' нет ни text, ни size_kb, ни пометки system/log" % [where, path]
			)


func _validate_logs_path(where: String, node: Dictionary, files: Dictionary) -> void:
	var logs_path: String = str(node.get("logs_path", ""))
	if logs_path.is_empty():
		return
	for path: String in files.keys():
		if path.begins_with(logs_path):
			return
	errors.append(
		"%s: logs_path = '%s', но ни одного файла в этом каталоге нет — чистить логи будет нечего"
		% [where, logs_path]
	)


func _check_difficulty(where: String, data: Dictionary) -> void:
	if not data.has("difficulty"):
		return
	var value: int = int(data["difficulty"])
	if value < MIN_DIFFICULTY or value > MAX_DIFFICULTY:
		errors.append("%s: difficulty = %d, допустимо %d-%d" % [where, value, MIN_DIFFICULTY, MAX_DIFFICULTY])

func _require_fields(where: String, data: Dictionary, fields: Array) -> void:
	for field: String in fields:
		if not data.has(field):
			errors.append("%s: нет обязательного поля '%s'" % [where, field])


func _validate_effects(where: String, effects: Array) -> void:
	for effect_variant: Variant in effects:
		var effect: Dictionary = effect_variant as Dictionary
		if effect == null:
			errors.append("%s: эффект должен быть объектом" % where)
			continue
		for type: String in effect.keys():
			if not Effects.is_known(type):
				errors.append("%s: неизвестный тип эффекта '%s'" % [where, type])
