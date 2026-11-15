class_name NodeValidator
extends RefCounted
## Проверка узлов сети (data/nodes/*.json).
## Формат описан в docs/tech/terminal-spec.md, раздел «Формат узла».
##
## Вынесено из Validator отдельным файлом: один файл — одна ответственность.
## Validator вызывает validate_all() и подмешивает ошибки к своим.

## Типы головоломок, docs/tech/puzzles-spec.md. MVP — две.
const PUZZLE_TYPES: PackedStringArray = ["password", "matrix"]

## Тип устройства, который показывает scan (docs/tech/terminal-spec.md). Нет поля — «pc».
const DEVICE_TYPES: PackedStringArray = ["pc", "router", "server", "phone"]

const MIN_DIFFICULTY: int = 1
const MAX_DIFFICULTY: int = 4

## Корневые каталоги узла, docs/tech/terminal-spec.md. Других не бывает:
## /home и /log доступны гостю, /sys и /prog — только администратору.
const FILE_ROOTS: PackedStringArray = ["/home/", "/log/", "/sys/", "/prog/"]

var errors: PackedStringArray = []
var warnings: PackedStringArray = []

# Адреса узлов должны быть уникальны: иначе connect приведёт не туда.
var _addresses: Dictionary = {}

# Все узлы: нужны, чтобы проверить связи links на существующие id.
var _nodes: Dictionary = {}

# file_id содержательных файлов: по ним квесты ищут файл у игрока, поэтому они уникальны.
var _file_ids: Dictionary = {}


## `revealed` — узлы, которые открывают заказы и эффекты (Effects.collect_revealed): у них
## есть вход не через scan, и недостижимыми они не считаются.
func validate_all(nodes: Dictionary, revealed: Dictionary = {}) -> void:
	errors.clear()
	warnings.clear()
	_addresses.clear()
	_file_ids.clear()
	_nodes = nodes
	for id: String in nodes.keys():
		_validate_node(id, nodes[id] as Dictionary)
	_check_reachability(nodes, revealed)


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
	if node.has("device") and not DEVICE_TYPES.has(str(node["device"])):
		errors.append(
			"%s: неизвестный тип устройства '%s' (допустимо: %s)"
			% [where, node["device"], ", ".join(DEVICE_TYPES)]
		)
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
	_validate_links(id, where, node)
	_validate_online(where, node)
	_validate_effects(where + ", on_hacked", node.get("on_hacked", []) as Array)


## Достижимость: в игру узел попадает тремя путями — известен с начала, открыт заказом
## (reveal_node) или найден через scan по цепочке links от одного из них. Узел вне всех трёх
## игрок не увидит никогда. Предупреждение, а не ошибка: сюжетные узлы следующих этапов могут
## ждать своего заказа, но дыру в двадцати JSON-файлах глазами не найти.
## Без точек входа мерить не от чего — проверка молчит (так бывает в тестах).
func _check_reachability(nodes: Dictionary, revealed: Dictionary) -> void:
	var reached: Dictionary = {}
	var queue: Array[String] = []
	for id: String in nodes.keys():
		var entry: bool = bool((nodes[id] as Dictionary).get("known_from_start", false)) or revealed.has(id)
		if entry:
			reached[id] = true
			queue.append(id)
	if queue.is_empty():
		return

	while not queue.is_empty():
		var current: String = queue.pop_back()
		for link: Variant in (nodes[current] as Dictionary).get("links", []) as Array:
			var other: String = str(link)
			if nodes.has(other) and not reached.has(other):
				reached[other] = true
				queue.append(other)

	var lost: Array = nodes.keys()
	lost.sort()
	for id: String in lost:
		if not reached.has(id):
			warnings.append(
				"узел %s недостижим: он не известен с начала, его не открывает ни один заказ (reveal_node), и scan не ведёт к нему"
				% id
			)


## Связи между узлами: их показывает scan (docs/gameplay/network.md).
## Связь обязана быть двусторонней, иначе scan с одной стороны видит узел, а с другой нет.
func _validate_links(node_id: String, where: String, node: Dictionary) -> void:
	var links: Array = node.get("links", []) as Array
	if links == null:
		return
	var seen: Dictionary = {}
	for link_variant: Variant in links:
		var other: String = str(link_variant)
		if other == node_id:
			errors.append("%s: узел связан сам с собой" % where)
			continue
		if seen.has(other):
			errors.append("%s: связь с '%s' указана дважды" % [where, other])
			continue
		seen[other] = true
		if not _nodes.has(other):
			errors.append("%s: связь с несуществующим узлом '%s'" % [where, other])
			continue
		var back: Array = (_nodes[other] as Dictionary).get("links", []) as Array
		if back == null or not back.has(node_id):
			errors.append(
				"%s: связь с '%s' односторонняя — добавь '%s' в его links"
				% [where, other, node_id]
			)


## Окно доступности («прайм-тайм»): время в формате чч:мм.
func _validate_online(where: String, node: Dictionary) -> void:
	if not node.has("online"):
		return
	var online: Dictionary = node["online"] as Dictionary
	if online == null:
		errors.append("%s: online должен быть объектом {from, to}" % where)
		return
	for key: String in ["from", "to"]:
		if not online.has(key):
			errors.append("%s: в online нет '%s'" % [where, key])
			continue
		if _parse_time(str(online[key])) < 0:
			errors.append("%s: online.%s должно быть чч:мм, получено '%s'" % [where, key, online[key]])


## Минуты от начала суток или -1, если формат неверный.
func _parse_time(value: String) -> int:
	var parts: PackedStringArray = value.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1
	var hours: int = int(parts[0])
	var minutes: int = int(parts[1])
	if hours < 0 or hours > 23 or minutes < 0 or minutes > 59:
		return -1
	return hours * 60 + minutes


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
		if not _has_known_root(path):
			errors.append(
				"%s: путь '%s' вне корневых каталогов (%s)"
				% [where, path, ", ".join(FILE_ROOTS)]
			)
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
		# file_id должен быть уникален во всех данных: по нему квест ищет файл у игрока,
		# где бы тот его ни спрятал (docs/tech/quest-format.md).
		if file.has("file_id"):
			var file_id: String = str(file["file_id"])
			if file_id.is_empty():
				errors.append("%s: пустой file_id у файла '%s'" % [where, path])
			elif _file_ids.has(file_id):
				errors.append(
					"%s: file_id '%s' уже занят (%s)" % [where, file_id, _file_ids[file_id]]
				)
			else:
				_file_ids[file_id] = "%s %s" % [where, path]


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


func _has_known_root(path: String) -> bool:
	for root: String in FILE_ROOTS:
		if path.begins_with(root):
			return true
	return false


## Эффект reveal_node ссылается на существующий узел и существующие сервисы. Общая для
## обоих валидаторов: эффект встречается и в квестах, и в on_hacked узлов.
## Подстановка шаблона radiant-квеста ({phone}) проверяется после подстановки, не здесь.
static func check_reveal(where: String, value: Variant, nodes: Dictionary) -> PackedStringArray:
	var problems: PackedStringArray = []
	var node_id: String = Effects.reveal_target(value)
	if node_id.begins_with("{"):
		return problems
	if not nodes.has(node_id):
		problems.append("%s: reveal_node ссылается на несуществующий узел '%s'" % [where, node_id])
		return problems
	var known_services: Array[String] = []
	for service_variant: Variant in (nodes[node_id] as Dictionary).get("services", []) as Array:
		known_services.append(str((service_variant as Dictionary).get("id", "")))
	for service_id: Variant in Effects.reveal_open(value):
		if not known_services.has(str(service_id)):
			problems.append(
				"%s: reveal_node открывает несуществующий сервис '%s' узла %s" % [where, service_id, node_id]
			)
	return problems


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
			elif type == "reveal_node":
				errors.append_array(check_reveal(where, effect[type], _nodes))
