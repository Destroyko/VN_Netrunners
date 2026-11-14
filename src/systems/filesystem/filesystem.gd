class_name Filesystem
extends RefCounted
## Виртуальная файловая система одного узла: свой ПК или чужая машина.
##
## Данные плоские: путь → описание файла (docs/tech/terminal-spec.md). Каталоги не хранятся,
## они выводятся из путей файлов — кроме пустых, созданных игроком через mkdir: их держим
## отдельным списком, иначе каталог без файлов исчезал бы сразу после создания.
##
## Чистая логика без сцен и без обращений к Clock и EventBus: время тратит и события шлёт
## вызывающий (терминал). Так файловую систему можно проверить тестами целиком.
##
## Состояние живёт в словаре, который передаётся снаружи — в игре это словарь из GameState,
## чтобы удаления и копии попадали в сейв. В тестах — обычный словарь.

var node_id: String = ""

## path → Dictionary: text, size_kb, system, log, tag, file_id (см. формат узла).
var _files: Dictionary = {}
## Пустые каталоги, созданные игроком.
var _dirs: Dictionary = {}


func _init(for_node: String = "", files: Dictionary = {}, dirs: Dictionary = {}) -> void:
	node_id = for_node
	_files = files
	_dirs = dirs


## Собрать из описания узла. Данные копируем: правки игрока не должны менять содержимое
## data/nodes на диске (DataLoader кэширует разобранный JSON).
static func from_node(node: Dictionary) -> Filesystem:
	var files: Dictionary = (node.get("files", {}) as Dictionary).duplicate(true)
	return Filesystem.new(str(node.get("id", "")), files, {})


## Файловая система узла в игре: берётся из состояния, а при первом обращении
## собирается из data/nodes и туда же кладётся. Так удаления и копии попадают в сейв.
static func for_node(node_id: String) -> Filesystem:
	if GameState.has_filesystem(node_id):
		return Filesystem.from_dict(node_id, GameState.filesystem_state(node_id))

	var nodes: Dictionary = DataLoader.nodes()
	if not nodes.has(node_id):
		push_error("Filesystem: нет такого узла в данных: %s" % node_id)
		return Filesystem.new(node_id, {}, {})

	var filesystem: Filesystem = from_node(nodes[node_id] as Dictionary)
	GameState.set_filesystem_state(node_id, filesystem.to_dict())
	return filesystem


# --- Чтение ------------------------------------------------------------------

func has_file(path: String) -> bool:
	return _files.has(FsPath.normalize(path))


func has_dir(path: String) -> bool:
	var normalized: String = FsPath.normalize(path)
	if normalized == FsPath.ROOT or FsPath.ROOTS.has(normalized):
		return true
	if _dirs.has(normalized):
		return true
	# Каталог существует, если внутри него что-то лежит.
	for file_path: String in _files.keys():
		if file_path.begins_with(normalized + FsPath.ROOT):
			return true
	return false


func file_data(path: String) -> Dictionary:
	return _files.get(FsPath.normalize(path), {}) as Dictionary


## Все пути файлов — для квестовых проверок и для сейва.
func paths() -> PackedStringArray:
	var result: PackedStringArray = []
	for path: String in _files.keys():
		result.append(path)
	result.sort()
	return result


## Есть ли на этой машине файл с таким file_id, где бы он ни лежал.
## Основа условия has_file из формата квестов: игрок мог переименовать файл и спрятать.
func has_file_id(file_id: String) -> bool:
	for path: String in _files.keys():
		if str((_files[path] as Dictionary).get("file_id", "")) == file_id:
			return true
	return false


## Содержимое каталога: каталоги и файлы, лежащие прямо в нём.
## Закрытые по правам показываются, но помечаются — игрок должен видеть, что там что-то есть.
func list(path: String, is_admin: bool = false) -> Array[Dictionary]:
	var directory: String = FsPath.normalize(path)
	var entries: Array[Dictionary] = []

	if directory == FsPath.ROOT:
		for root: String in FsPath.ROOTS:
			entries.append({
				"name": FsPath.name_of(root),
				"path": root,
				"is_dir": true,
				"locked": FsPath.requires_admin(root) and not is_admin,
				"system": root == "/sys",
				"log": root == "/log",
			})
		return entries

	var seen_dirs: Dictionary = {}
	for file_path: String in _files.keys():
		if not file_path.begins_with(directory + FsPath.ROOT):
			continue
		if FsPath.is_direct_child(file_path, directory):
			var data: Dictionary = _files[file_path] as Dictionary
			entries.append({
				"name": FsPath.name_of(file_path),
				"path": file_path,
				"is_dir": false,
				"locked": FsPath.requires_admin(file_path) and not is_admin,
				"system": bool(data.get("system", false)),
				"log": bool(data.get("log", false)),
			})
		else:
			# Файл лежит глубже: значит между ним и нами есть подкаталог.
			var rest: String = file_path.substr(directory.length() + 1)
			var child: String = rest.split(FsPath.ROOT)[0]
			seen_dirs[child] = true

	for child: String in _dirs.keys():
		if FsPath.is_direct_child(child, directory):
			seen_dirs[FsPath.name_of(child)] = true

	for child: String in seen_dirs.keys():
		var child_path: String = directory.path_join(child)
		entries.append({
			"name": child,
			"path": child_path,
			"is_dir": true,
			"locked": FsPath.requires_admin(child_path) and not is_admin,
			"system": false,
			"log": false,
		})

	entries.sort_custom(_compare_entries)
	return entries


## Каталоги сверху, дальше по алфавиту — так список читается глазами.
static func _compare_entries(a: Dictionary, b: Dictionary) -> bool:
	if bool(a["is_dir"]) != bool(b["is_dir"]):
		return bool(a["is_dir"])
	return str(a["name"]) < str(b["name"])


func read(path: String, is_admin: bool = false) -> FsResult:
	var target: String = FsPath.normalize(path)
	if not FsPath.is_valid(target):
		return FsResult.fail(FsResult.Code.BAD_PATH, target)
	if not _files.has(target):
		if has_dir(target):
			return FsResult.fail(FsResult.Code.IS_A_DIR, target)
		return FsResult.fail(FsResult.Code.NOT_FOUND, target)
	if FsPath.requires_admin(target) and not is_admin:
		return FsResult.fail(FsResult.Code.NO_PERMISSION, target)

	var data: Dictionary = _files[target] as Dictionary
	if data.has("text"):
		return FsResult.ok(target, str(data["text"]))
	# Не текст: картинка, база, архив. Читать нечего, но это не ошибка — игрок видит, что это.
	return FsResult.ok(target, "[двоичный файл, %d КБ]" % int(data.get("size_kb", 0)))


func change_dir(cwd: String, arg: String, is_admin: bool = false) -> FsResult:
	var target: String = FsPath.resolve(cwd, arg)
	if not FsPath.is_valid(target):
		return FsResult.fail(FsResult.Code.BAD_PATH, target)
	if _files.has(target):
		return FsResult.fail(FsResult.Code.NOT_A_DIR, target)
	if not has_dir(target):
		return FsResult.fail(FsResult.Code.NOT_FOUND, target)
	if FsPath.requires_admin(target) and not is_admin:
		return FsResult.fail(FsResult.Code.NO_PERMISSION, target)
	return FsResult.ok(target)


# --- Изменение ---------------------------------------------------------------

## Удалить файл или всё по маске: `rm *` в каталоге логов.
## Предупреждений нет даже для системных файлов — это обещанная свобода (hacking.md).
func remove(cwd: String, arg: String, is_admin: bool = false) -> FsResult:
	if FsPath.has_mask(arg):
		return _remove_by_mask(cwd, arg, is_admin)

	var target: String = FsPath.resolve(cwd, arg)
	if not _files.has(target):
		if has_dir(target):
			return FsResult.fail(FsResult.Code.IS_A_DIR, target)
		return FsResult.fail(FsResult.Code.NOT_FOUND, target)
	if FsPath.requires_admin(target) and not is_admin:
		return FsResult.fail(FsResult.Code.NO_PERMISSION, target)
	_files.erase(target)
	return FsResult.ok(target)


func _remove_by_mask(cwd: String, arg: String, is_admin: bool) -> FsResult:
	var directory: String = FsPath.normalize(cwd if not arg.contains(FsPath.ROOT) else FsPath.parent(FsPath.resolve(cwd, arg)))
	var mask: String = FsPath.name_of(arg) if arg.contains(FsPath.ROOT) else arg
	if FsPath.requires_admin(directory) and not is_admin:
		return FsResult.fail(FsResult.Code.NO_PERMISSION, directory)

	var removed: PackedStringArray = []
	for file_path: String in paths():
		if not FsPath.is_direct_child(file_path, directory):
			continue
		if not FsPath.matches_mask(FsPath.name_of(file_path), mask):
			continue
		if FsPath.requires_admin(file_path) and not is_admin:
			continue
		_files.erase(file_path)
		removed.append(file_path)
	if removed.is_empty():
		return FsResult.fail(FsResult.Code.NOT_FOUND, directory.path_join(mask))
	return FsResult.ok_many(removed)


## Переместить или переименовать в пределах этой машины.
func move(cwd: String, from_arg: String, to_arg: String, is_admin: bool = false) -> FsResult:
	var from: String = FsPath.resolve(cwd, from_arg)
	var to: String = _destination_for(cwd, from, to_arg)

	if not _files.has(from):
		return FsResult.fail(FsResult.Code.NOT_FOUND, from)
	if not FsPath.is_valid(to):
		return FsResult.fail(FsResult.Code.BAD_PATH, to)
	if (FsPath.requires_admin(from) or FsPath.requires_admin(to)) and not is_admin:
		return FsResult.fail(FsResult.Code.NO_PERMISSION, to)

	# Перезапись разрешена, как в настоящем шелле: предупреждений мы не делаем (hacking.md).
	var was_there: bool = _files.has(to)
	_files[to] = _files[from]
	_files.erase(from)
	var result := FsResult.ok(to)
	result.paths = [from, to]
	result.replaced = was_there
	return result


## Скопировать файл на эту же или на другую машину: `cp` с узла к себе.
## file_id переезжает вместе с копией — по нему квесты ищут файл (docs/tech/quest-format.md).
func copy_to(target_fs: Filesystem, cwd: String, from_arg: String, to_arg: String, is_admin: bool = false) -> FsResult:
	var from: String = FsPath.resolve(cwd, from_arg)
	if not _files.has(from):
		return FsResult.fail(FsResult.Code.NOT_FOUND, from)
	if FsPath.requires_admin(from) and not is_admin:
		return FsResult.fail(FsResult.Code.NO_PERMISSION, from)

	var to: String = target_fs._destination_for(cwd, from, to_arg)
	if not FsPath.is_valid(to):
		return FsResult.fail(FsResult.Code.BAD_PATH, to)
	# Писать в системные каталоги чужой машины тоже нужны права.
	if FsPath.requires_admin(to) and not is_admin:
		return FsResult.fail(FsResult.Code.NO_PERMISSION, to)

	# Перезапись разрешена: иначе сменить тему было бы нельзя без предварительного rm,
	# а в шелле cp просто заменяет файл.
	var was_there: bool = target_fs._files.has(to)
	target_fs._files[to] = (_files[from] as Dictionary).duplicate(true)
	var result := FsResult.ok(to)
	result.paths = [from, to]
	result.replaced = was_there
	return result


## Положить файл напрямую, минуя команды игрока: восстановление с флешки, эффект `add_file`
## из данных, выдача файла квестом. Прав не спрашивает — это не действие игрока, а игра.
func put_file(path: String, data: Dictionary) -> void:
	_files[FsPath.normalize(path)] = data.duplicate(true)


## Создать каталог. Только в /home: игрок раскладывает свою добычу, а не чинит чужую систему.
func make_dir(cwd: String, arg: String, is_admin: bool = false) -> FsResult:
	var target: String = FsPath.resolve(cwd, arg)
	if not FsPath.is_valid(target) or target == FsPath.ROOT:
		return FsResult.fail(FsResult.Code.BAD_PATH, target)
	if FsPath.root_of(target) != "/home":
		return FsResult.fail(FsResult.Code.NOT_WRITABLE, target)
	if _files.has(target):
		return FsResult.fail(FsResult.Code.ALREADY_EXISTS, target)
	if has_dir(target):
		return FsResult.fail(FsResult.Code.ALREADY_EXISTS, target)
	_dirs[target] = true
	return FsResult.ok(target)


# --- Сейв --------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"files": _files, "dirs": _dirs}


static func from_dict(for_node: String, data: Dictionary) -> Filesystem:
	return Filesystem.new(
		for_node,
		data.get("files", {}) as Dictionary,
		data.get("dirs", {}) as Dictionary
	)


# --- Внутреннее --------------------------------------------------------------

## Куда именно кладём файл: если указан существующий каталог — внутрь него,
## сохранив имя. Иначе аргумент считается полным именем назначения.
func _destination_for(cwd: String, from: String, to_arg: String) -> String:
	var to: String = FsPath.resolve(cwd, to_arg)
	if has_dir(to) and not _files.has(to):
		return to.path_join(FsPath.name_of(from))
	return to
