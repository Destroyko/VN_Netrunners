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
	# Флаги (`ls -la`) понимаем как привычку из настоящих консолей и просто пропускаем.
	var paths: PackedStringArray = []
	for arg: String in args:
		if not arg.begins_with("-"):
			paths.append(arg)
	args = paths
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
	var path: String = FsPath.resolve(_t.cwd(), args[0])
	if _t.fs().has_file(path) and bool(_t.fs().file_data(path).get("encrypted", false)):
		var kb: int = int(_t.fs().file_data(path).get("size_kb", 0))
		result.add("[файл зашифрован, %d КБ] расшифровать: decrypt <файл> -auto" % kb)
		_t.spend(_t.minutes_of("terminal_command"), result)
		return
	var read: FsResult = _t.fs().read(path, _t.admin())
	if not read.is_ok():
		result.add(read.message())
		return
	result.add(read.text)
	# Чтение записи в логе не оставляет: смотреть можно, трогать опасно (heat.md).
	EventBus.file_read.emit(_t.node_id(), read.path)
	_t.spend(_t.minutes_of("terminal_command"), result)


## `cp`: на узле скачивает файл на свой ПК (по умолчанию в /home/dump), дома копирует
## в пределах своей машины. Маска (`*.txt`) — все подходящие файлы каталога.
func cp(args: PackedStringArray, result: TermResult, confirmed: bool) -> void:
	if _t.is_remote():
		_download(args, result, confirmed)
		return
	if args.size() < 2:
		result.add("использование: cp <файл> <куда>")
		return
	var plan: Array = _plan(_t.fs(), _t.cwd(), args, _t.cwd(), args[1])
	if _run_plan(_t.fs(), _t.fs(), _t.cwd(), plan, true, confirmed, result).size() > 0:
		_t.spend(_t.minutes_of("terminal_command"), result)


func _download(args: PackedStringArray, result: TermResult, confirmed: bool) -> void:
	if args.is_empty():
		result.add("использование: cp <файл> [куда у себя]  (по умолчанию в %s)" % Terminal.DUMP_DIR)
		return
	# Фаервол узла режет исходящее: смотреть можно, вынести нельзя (hacking.md, «Стены»).
	if _t.net.firewall_up(_t.node_id(), _t.now()):
		result.add("передача заблокирована: фаервол узла")
		return
	var remote: Filesystem = _t.fs()
	var plan: Array = _plan(remote, _t.cwd(), args, Terminal.DUMP_DIR, "")

	# Не влез в трейс — файла нет. Большая добыча требует подготовки (hacking-loop.md).
	var readable: Array = plan.filter(func(step: Dictionary) -> bool:
		return remote.has_file(str(step["from"])) and (_t.admin() or not FsPath.requires_admin(str(step["from"]))))
	var minutes: int = _plan_minutes(remote, readable)
	if not readable.is_empty() and _cut_by_trace(minutes, result):
		return

	var done: Array = _run_plan(remote, _t.home_fs(), _t.cwd(), plan, _t.admin(), confirmed, result)
	for step: Dictionary in done:
		EventBus.file_copied.emit(_t.node_id(), str(step["from"]))
	if not done.is_empty():
		_t.spend(minutes, result)


## `put`: положить файл со своего ПК на узел (маска — все подходящие). Запись на цели оставляет
## след в логах.
func put(args: PackedStringArray, result: TermResult, confirmed: bool) -> void:
	if not _t.is_remote():
		result.add("нет подключения к узлу")
		return
	if args.is_empty():
		result.add("использование: put <файл у себя> [куда на узле]")
		return
	if _guest_on_node(result):
		return
	var home: Filesystem = _t.home_fs()
	var plan: Array = _plan(home, _t.home_cwd(), args, _t.cwd(), "")
	var existing: Array = plan.filter(func(step: Dictionary) -> bool: return home.has_file(str(step["from"])))
	var minutes: int = _plan_minutes(home, existing)
	if not existing.is_empty() and _cut_by_trace(minutes, result):
		return

	# Права на запись у узла: берём права на узле. Следствие: файл из закрытого каталога
	# своего ПК гость на чужой не положит — крайний случай, ради него не усложняем.
	var done: Array = _run_plan(home, _t.fs(), _t.home_cwd(), plan, _t.admin(), confirmed, result)
	for step: Dictionary in done:
		var written: String = str(step["to"])
		EventBus.file_copied.emit(_t.node_id(), written)
		if not _in_logs(written):
			_t.note(Logbook.CATEGORY_FILE_CREATED, "записан файл %s" % FsPath.name_of(written))
	if not done.is_empty():
		_t.spend(minutes, result)


# --- Передача файлов: один путь для cp и put -------------------------------------

## Что откуда куда: [{from, to_arg, to}]. Аргумент — файл или маска (`*`, `?`) в каталоге.
## `base` — куда класть, если места назначения не указали; `local_to` — для `cp` у себя: место
## назначения как есть (каталог или новое имя), как у одиночного `cp`.
func _plan(from_fs: Filesystem, from_cwd: String, args: PackedStringArray, base: String, local_to: String) -> Array:
	var plan: Array = []
	var mask: bool = FsPath.has_mask(args[0])
	for source: String in _sources(from_fs, from_cwd, args[0]):
		var to_arg: String
		if mask:
			# Пачка файлов всегда ложится в каталог: иначе все они затёрли бы одно имя.
			var dir: String = FsPath.resolve(base, args[1]) if args.size() > 1 else base
			to_arg = dir.path_join(FsPath.name_of(source))
		elif not local_to.is_empty():
			to_arg = local_to
		else:
			to_arg = _destination(args, source, base, 1)
		plan.append({"from": source, "to_arg": to_arg})
	return plan


## Файлы по аргументу: маска — подходящие файлы каталога (по алфавиту), иначе один путь.
func _sources(fs: Filesystem, cwd: String, arg: String) -> PackedStringArray:
	if not FsPath.has_mask(arg):
		return PackedStringArray([FsPath.resolve(cwd, arg)])
	var with_dir: bool = arg.contains(FsPath.ROOT)
	var dir: String = FsPath.parent(FsPath.resolve(cwd, arg)) if with_dir else FsPath.normalize(cwd)
	var mask: String = FsPath.name_of(arg) if with_dir else arg
	var found: PackedStringArray = []
	for path: String in fs.paths():
		if FsPath.is_direct_child(path, dir) and FsPath.matches_mask(FsPath.name_of(path), mask):
			found.append(path)
	found.sort()
	return found


## Сколько минут займёт передача всего плана: по суммарному объёму, не меньше команды.
func _plan_minutes(fs: Filesystem, plan: Array) -> int:
	var kb: int = 0
	for step: Dictionary in plan:
		kb += _size_kb(fs.file_data(str(step["from"])))
	return _transfer_minutes({"size_kb": kb})


## Выполнить план. Замена — один вопрос на всю пачку (на повтор с «y» заменяет всё). Каждый
## переданный файл — строкой отчёта, как у настоящей утилиты копирования; ошибки — своей строкой.
## Возвращает переданные шаги [{from, to}].
func _run_plan(
	from_fs: Filesystem, to_fs: Filesystem, from_cwd: String, plan: Array,
	is_admin: bool, confirmed: bool, result: TermResult
) -> Array:
	if plan.is_empty():
		result.add("нет таких файлов")
		return []
	if not confirmed:
		var clashes: Array = plan.filter(func(step: Dictionary) -> bool:
			return to_fs.has_file(to_fs._destination_for(from_cwd, str(step["from"]), str(step["to_arg"]))))
		if clashes.size() == 1 and plan.size() == 1:
			var target: String = to_fs._destination_for(from_cwd, str(clashes[0]["from"]), str(clashes[0]["to_arg"]))
			_t.ask(result, FsResult.fail(FsResult.Code.NEEDS_CONFIRM_REPLACE, target).message())
			return []
		if not clashes.is_empty():
			_t.ask(result, "файлов с такими именами уже есть: %d. заменить? (y/n)" % clashes.size())
			return []
	var done: Array = []
	for step: Dictionary in plan:
		var copied: FsResult = from_fs.copy_to(to_fs, from_cwd, str(step["from"]), str(step["to_arg"]), is_admin, confirmed)
		if not copied.is_ok():
			result.add(copied.message())
			continue
		var kb: int = _size_kb(from_fs.file_data(str(step["from"])))
		var line: String = "%s  %d КБ  100%%" % [FsPath.name_of(copied.path), kb]
		result.add(("заменено: " + line) if copied.replaced else line)
		done.append({"from": str(step["from"]), "to": copied.path})
	if plan.size() > 1:
		result.add("передано файлов: %d из %d" % [done.size(), plan.size()])
	return done


func _size_kb(data: Dictionary) -> int:
	if data.has("size_kb"):
		return int(data["size_kb"])
	return maxi(1, ceili(float(str(data.get("text", "")).length()) / 1024.0))


func mv(args: PackedStringArray, result: TermResult, confirmed: bool) -> void:
	if args.size() < 2:
		result.add("использование: mv <файл> <куда>")
		return
	if _guest_on_node(result):
		return
	var moved: FsResult = _t.fs().move(_t.cwd(), args[0], args[1], _t.admin(), confirmed)
	_finish_copy(moved, result)
	if moved.is_ok():
		_t.spend(_t.minutes_of("terminal_command"), result)


func rm(args: PackedStringArray, result: TermResult, confirmed: bool) -> void:
	if args.is_empty():
		result.add("использование: rm <файл или маска>")
		return
	if _guest_on_node(result):
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
	if _guest_on_node(result):
		return
	var made: FsResult = _t.fs().make_dir(_t.cwd(), args[0], _t.admin())
	if not made.is_ok():
		result.add(made.message())
		return
	_t.spend(_t.minutes_of("terminal_command"), result)


# --- Общее -------------------------------------------------------------------

## Права на чужом узле как в Unix (решено 15.11.2026): гость — «остальные» в правах вида 664,
## ему только читать и скачивать. Удалять, перемещать, переименовывать, записывать — с правами
## администратора (`rootstep`). На своём ПК игрок хозяин и делает что хочет.
func _guest_on_node(result: TermResult) -> bool:
	if _t.is_remote() and not _t.admin():
		result.add("недостаточно прав. нужен доступ администратора")
		return true
	return false


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
