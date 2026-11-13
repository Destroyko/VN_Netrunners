class_name DataLoader
extends RefCounted
## Загрузка и кэш JSON из data/. Один файл читается с диска один раз.
##
## Почему static: это не система и не узел сцены — просто доступ к данным,
## нужен и в тестах, и в инструментах без запуска игры.
##
## ВНИМАНИЕ (на этап экспорта, M4): Godot не импортирует .json как ресурс,
## поэтому в настройках экспорта нужно добавить фильтр "*.json", иначе в собранной
## игре файлов не будет.

const DATA_ROOT: String = "res://data"
const BALANCE_PATH: String = "res://data/balance.json"

static var _cache: Dictionary = {}


## Прочитать один файл. Ошибка чтения или разбора → null и сообщение в консоль
## (молча падать нельзя: данные правит человек, он должен видеть, что не так).
static func load_json(path: String) -> Variant:
	if _cache.has(path):
		return _cache[path]
	if not FileAccess.file_exists(path):
		push_error("DataLoader: файл не найден: %s" % path)
		return null
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("DataLoader: файл пустой или не читается: %s" % path)
		return null
	var json := JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		push_error("DataLoader: ошибка JSON в %s, строка %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	_cache[path] = json.data
	return json.data


## Все *.json из папки, сложенные по полю "id" (или по имени файла, если id нет).
static func load_dir(dir_path: String) -> Dictionary:
	var result: Dictionary = {}
	if not DirAccess.dir_exists_absolute(dir_path):
		return result
	for file_name: String in DirAccess.get_files_at(dir_path):
		# В собранной игре к имени может прилипнуть .remap — учитываем.
		var clean: String = file_name.trim_suffix(".remap")
		if not clean.ends_with(".json"):
			continue
		var data: Variant = load_json(dir_path.path_join(clean))
		if data is Dictionary:
			var dict: Dictionary = data as Dictionary
			var id: String = dict.get("id", clean.get_basename()) as String
			if result.has(id):
				push_error("DataLoader: повторяющийся id '%s' в %s" % [id, dir_path])
			result[id] = dict
	return result


## Числа баланса. Пустой словарь, если файла нет — системы работают на заглушках.
static func balance() -> Dictionary:
	var data: Variant = load_json(BALANCE_PATH) if FileAccess.file_exists(BALANCE_PATH) else null
	return (data as Dictionary) if data is Dictionary else {}


static func quests() -> Dictionary:
	var all: Dictionary = {}
	for sub: String in ["main", "side", "radiant"]:
		all.merge(load_dir(DATA_ROOT.path_join("quests").path_join(sub)))
	return all


static func nodes() -> Dictionary:
	return load_dir(DATA_ROOT.path_join("nodes"))


static func news() -> Dictionary:
	return load_dir(DATA_ROOT.path_join("news"))


static func triggers() -> Dictionary:
	return load_dir(DATA_ROOT.path_join("triggers"))


## Сбросить кэш: после правки JSON в отладке и между тестами.
static func clear_cache() -> void:
	_cache.clear()
