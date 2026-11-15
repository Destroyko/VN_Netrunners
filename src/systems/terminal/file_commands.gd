class_name FileCommands
extends RefCounted
## Команды файлов: pwd, ls, cd, cat, cp, put, mv, rm, mkdir (docs/tech/terminal-spec.md).
## Работают и на своём ПК, и на подключённом узле — смотрят, где сейчас терминал.
##
## Сами файловые правила — в Filesystem. Здесь то, что принадлежит терминалу: время, события,
## следы в логах цели и вопросы «заменить? / удалить?».

var _t: Terminal


func _init(terminal: Terminal) -> void:
	_t = terminal


func pwd(result: TermResult) -> void:
	result.add(_t.cwd())


func ls(args: PackedStringArray, result: TermResult) -> void:
	var files: Filesystem = _t.fs()
	var path: String = FsPath.resolve(_t.cwd(), args[0]) if not args.is_empty() else _t.cwd()

	if files.has_file(path):
		result.add(FsPath.name_of(path))
		return
	if not files.has_dir(path):
		result.add(FsResult.fail(FsResult.Code.NOT_FOUND, path).message())
		return
	if FsPath.requires_admin(path) and not _t.admin():
		result.add(FsResult.fail(FsResult.Code.NO_PERMISSION, path).message())
		return

	var entries: Array[Dictionary] = files.list(path, _t.admin())
	if entries.is_empty():
		result.add("пусто")
	for entry: Dictionary in entries:
		var line: String = str(entry["name"]) + ("/" if bool(entry["is_dir"]) else "")
		if bool(entry["system"]):
			line += "  [sys]"
		if bool(entry["locked"]):
			line += "  [закрыт]"
		result.add(line)


func cd(args: PackedStringArray, result: TermResult) -> void:
	var target: String = args[0] if not args.is_empty() else "/"
	var moved: FsResult = _t.fs().change_dir(_t.cwd(), target, _t.admin())
	if not moved.is_ok():
		result.add(moved.message())
		return
	_t.set_cwd(moved.path)


func cat(args: PackedStringArray, result: TermResult) -> void:
	if args.is_empty():
		result.add("использование: cat <файл>")
		return
	var read: FsResult = _t.fs().read(FsPath.resolve(_t.cwd(), args[0]), _t.admin())
	if not read.is_ok():
		result.add(read.message())
		return
	result.add(read.text)
	# Чтение записи в логе не оставляет: смотреть можно, трогать опасно (heat.md).
	EventBus.file_read.emit(_t.node_id(), read.path)
	_t.spend(_t.minutes_of("terminal_command"), result)


## `cp`: на узле скачивает файл на свой ПК (по умолчанию в /home/dump), дома копирует
## в пределах своей машины.
func cp(args: PackedStringArray, result: TermResult, confirmed: bool) -> void:
	if _t.is_remote():
		_download(args, result, confirmed)
		return
	if args.size() < 2:
		result.add("использование: cp <файл> <куда>")
		return
	var copied: FsResult = _t.fs().copy_to(_t.fs(), _t.cwd(), args[0], args[1], true, confirmed)
	_finish_copy(copied, result)
	if copied.is_ok():
		_t.spend(_t.minutes_of("terminal_command"), result)


func _download(args: PackedStringArray, result: TermResult, confirmed: bool) -> void:
	if args.is_empty():
		result.add("использование: cp <файл> [куда у себя]  (по умолчанию в %s)" % Terminal.DUMP_DIR)
		return
	var remote: Filesystem = _t.fs()
	var source: String = FsPath.resolve(_t.cwd(), args[0])
	var target: String = _destination(args, source, Terminal.DUMP_DIR, 1)
	var minutes: int = _transfer_minutes(remote.file_data(source))

	# Не влез в трейс — файла нет. Большая добыча требует подготовки (hacking-loop.md).
	var readable: bool = remote.has_file(source) and (_t.admin() or not FsPath.requires_admin(source))
	if readable and _cut_by_trace(minutes, result):
		return

	var copied: FsResult = remote.copy_to(_t.home_fs(), _t.cwd(), args[0], target, _t.admin(), confirmed)
	_finish_copy(copied, result)
	if copied.is_ok():
		EventBus.file_copied.emit(_t.node_id(), source)
		_t.spend(minutes, result)


## `put`: положить файл со своего ПК на узел. Запись на цели оставляет след в логах.
func put(args: PackedStringArray, result: TermResult, confirmed: bool) -> void:
	if not _t.is_remote():
		result.add("сначала подключись к узлу: connect <адрес>")
		return
	if args.is_empty():
		result.add("использование: put <файл у себя> [куда на узле]")
		return
	var source: String = FsPath.resolve(_t.home_cwd(), args[0])
	var home: Filesystem = _t.home_fs()
	var target: String = _destination(args, source, _t.cwd(), 1)
	var minutes: int = _transfer_minutes(home.file_data(source))

	if home.has_file(source) and _cut_by_trace(minutes, result):
		return

	# Права на запись у узла: берём права на узле. Следствие: файл из закрытого каталога
	# своего ПК гость на чужой не положит — крайний случай, ради него не усложняем.
	var copied: FsResult = home.copy_to(_t.fs(), _t.home_cwd(), args[0], target, _t.admin(), confirmed)
	_finish_copy(copied, result)
	if not copied.is_ok():
		return
	EventBus.file_copied.emit(_t.node_id(), copied.path)
	if not _in_logs(copied.path):
		_t.note(Logbook.CATEGORY_FILE_CREATED, "записан файл %s" % FsPath.name_of(copied.path))
	_t.spend(minutes, result)


func mv(args: PackedStringArray, result: TermResult, confirmed: bool) -> void:
	if args.size() < 2:
		result.add("использование: mv <файл> <куда>")
		return
	var moved: FsResult = _t.fs().move(_t.cwd(), args[0], args[1], _t.admin(), confirmed)
	_finish_copy(moved, result)
	if moved.is_ok():
		_t.spend(_t.minutes_of("terminal_command"), result)


func rm(args: PackedStringArray, result: TermResult, confirmed: bool) -> void:
	if args.is_empty():
		result.add("использование: rm <файл или маска>")
		return
	var removed: FsResult = _t.fs().remove(_t.cwd(), args[0], _t.admin(), confirmed)
	if removed.needs_confirm():
		_t.ask(result, removed.message())
		return
	if not removed.is_ok():
		result.add(removed.message())
		return

	result.add("удалено: %d" % removed.paths.size())
	var outside_logs: bool = false
	for path: String in removed.paths:
		EventBus.file_deleted.emit(_t.node_id(), path)
		outside_logs = outside_logs or not _in_logs(path)
	# Удаляя сами логи, следов о себе не оставляешь: чистка и есть чистка (hacking.md).
	if outside_logs:
		var what: String = "удалён файл %s" % FsPath.name_of(removed.paths[0]) \
			if removed.paths.size() == 1 else "удалены файлы: %d" % removed.paths.size()
		_t.note(Logbook.CATEGORY_FILE_DELETED, what)

	# Снёс net.sys на чужой машине — узел уходит из сети и вышвыривает игрока.
	if _t.is_remote() and removed.paths.has(SystemFiles.FILE_NET):
		_t.handle_events(_t.session.node_sabotaged(_t.node_id(), _t.now()), result)
	_t.spend(_t.minutes_of("terminal_command"), result)


func mkdir(args: PackedStringArray, result: TermResult) -> void:
	if args.is_empty():
		result.add("использование: mkdir <путь>")
		return
	var made: FsResult = _t.fs().make_dir(_t.cwd(), args[0], _t.admin())
	if not made.is_ok():
		result.add(made.message())
		return
	_t.spend(_t.minutes_of("terminal_command"), result)


# --- Общее -------------------------------------------------------------------

## Куда класть: путь из аргумента (абсолютный или от `base`), а если не указан или оканчивается
## на «/» — в каталог `base` под тем же именем. Пустой каталог ещё не существует, поэтому
## имя дописываем сами, а не надеемся, что файловая система угадает каталог.
func _destination(args: PackedStringArray, source: String, base: String, index: int) -> String:
	var name: String = FsPath.name_of(source)
	if args.size() <= index:
		return base.path_join(name)
	var raw: String = args[index]
	var resolved: String = FsPath.resolve(base, raw)
	return resolved.path_join(name) if raw.ends_with("/") else resolved


## Сколько минут качается файл: канал — ресурс, большие файлы под трейсом отдельная задача.
func _transfer_minutes(data: Dictionary) -> int:
	var per_minute: int = int((DataLoader.balance().get("channel", {}) as Dictionary).get("kb_per_minute", 500))
	return maxi(_t.minutes_of("terminal_command"), ceili(float(int(data.get("size_kb", 1))) / float(maxi(per_minute, 1))))


## Передача не уложилась в трейс: соединение оборвётся раньше, чем файл дойдёт.
## Время потрачено, файла нет.
func _cut_by_trace(minutes: int, result: TermResult) -> bool:
	if not _t.session.is_tracing() or minutes < _t.session.trace_left():
		return false
	result.add("соединение прервано: файл не успел скачаться")
	_t.spend(_t.session.trace_left(), result)
	return true


func _finish_copy(copied: FsResult, result: TermResult) -> void:
	if copied.needs_confirm():
		_t.ask(result, copied.message())
	elif not copied.is_ok():
		result.add(copied.message())
	elif copied.replaced:
		result.add("заменено: %s" % FsPath.name_of(copied.path))


func _in_logs(path: String) -> bool:
	var logs: String = str(_t.net.definition(_t.node_id()).get("logs_path", "/log"))
	return path.begins_with(logs + "/")
