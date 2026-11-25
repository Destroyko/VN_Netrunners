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
	args = _without_flags(args)
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
	var cwd: String = _t.cwd()
	var node: String = _t.node_id()
	var plan: Array = _plan(remote, cwd, args, Terminal.DUMP_DIR, "")
	var readable: Array = plan.filter(func(step: Dictionary) -> bool:
		return remote.has_file(str(step["from"])) and (_t.admin() or not FsPath.requires_admin(str(step["from"]))))
	# Нечего передавать (нет файлов, закрыто правами) — ответ сразу, без полоски.
	if readable.is_empty():
		_run_plan(remote, _t.home_fs(), cwd, plan, _t.admin(), confirmed, result)
		return
	# «Заменить?» — до передачи, а не после потраченного времени.
	if not confirmed and _ask_clashes(_t.home_fs(), cwd, plan, result):
		return
	# Файлы ложатся, когда передача дошла до конца; трейс оборвал раньше — файла нет
	# (большая добыча требует подготовки, hacking-loop.md).
	_t.spend_then(_plan_minutes(remote, readable), result, func(finished: TermResult) -> void:
		if _t.node_id() != node:
			finished.add("соединение прервано: файл не успел скачаться")
			return
		var done: Array = _run_plan(remote, _t.home_fs(), cwd, plan, _t.admin(), true, finished)
		for step: Dictionary in done:
			EventBus.file_copied.emit(node, str(step["from"])))


## `put`: положить файл со своего ПК на узел (маска — все подходящие). Запись на цели оставляет
## след в логах.
func put(args: PackedStringArray, result: TermResult, confirmed: bool) -> void:
	args = _without_flags(args)
	if not _t.is_remote():
		result.add("нет подключения к узлу")
		return
	if args.is_empty():
		result.add("использование: put <файл у себя> [куда на узле]")
		return
	if _guest_on_node(result):
		return
	var home: Filesystem = _t.home_fs()
	var home_cwd: String = _t.home_cwd()
	var node: String = _t.node_id()
	var plan: Array = _plan(home, home_cwd, args, _t.cwd(), "")
	var existing: Array = plan.filter(func(step: Dictionary) -> bool: return home.has_file(str(step["from"])))
	if existing.is_empty():
		_run_plan(home, _t.fs(), home_cwd, plan, _t.admin(), confirmed, result)
		return
	if not confirmed and _ask_clashes(_t.fs(), home_cwd, plan, result):
		return
	# Права на запись у узла: берём права на узле. Следствие: файл из закрытого каталога
	# своего ПК гость на чужой не положит — крайний случай, ради него не усложняем.
	_t.spend_then(_plan_minutes(home, existing), result, func(finished: TermResult) -> void:
		if _t.node_id() != node:
			finished.add("соединение прервано: файл не успел передаться")
			return
		var done: Array = _run_plan(home, _t.fs(), home_cwd, plan, _t.admin(), true, finished)
		for step: Dictionary in done:
			var written: String = str(step["to"])
			EventBus.file_copied.emit(node, written)
			if not _in_logs(written):
				_t.note(Logbook.CATEGORY_FILE_CREATED, "записан файл %s" % FsPath.name_of(written)))


# --- Передача файлов: один путь для cp и put -------------------------------------

## Что откуда куда: [{from, to_arg, to}]. Аргумент — файл или маска (`*`, `?`) в каталоге.
## `base` — куда класть, если места назначения не указали; `local_to` — для `cp` у себя: место
## назначения как есть (каталог или новое имя), как у одиночного `cp`.
func _plan(from_fs: Filesystem, from_cwd: String, args: PackedStringArray, base: String, local_to: String) -> Array:
	var plan: Array = []
	# Папка — целиком, со всем содержимым, как `cp -r` (флаг можно и не писать).
	var folder: String = FsPath.resolve(from_cwd, args[0])
	if not FsPath.has_mask(args[0]) and not from_fs.has_file(folder) and from_fs.has_dir(folder):
		var into: String = FsPath.resolve(base, args[1]) if args.size() > 1 else base
		into = into.path_join(FsPath.name_of(folder))
		var inside: PackedStringArray = []
		for path: String in from_fs.paths():
			if path.begins_with(folder + FsPath.ROOT):
				inside.append(path)
		inside.sort()
		for path: String in inside:
			plan.append({"from": path, "to_arg": into.path_join(path.substr(folder.length() + 1))})
		return plan
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
## Спросить «заменить?», если на месте уже есть файлы. true — вопрос задан, ждём ответа.
func _ask_clashes(to_fs: Filesystem, from_cwd: String, plan: Array, result: TermResult) -> bool:
	var clashes: Array = plan.filter(func(step: Dictionary) -> bool:
		var dest: String = to_fs._destination_for(from_cwd, str(step["from"]), str(step["to_arg"]))
		return to_fs.has_file(dest) and not to_fs.is_locked(dest))
	if clashes.is_empty():
		return false
	if clashes.size() == 1 and plan.size() == 1:
		var target: String = to_fs._destination_for(from_cwd, str(clashes[0]["from"]), str(clashes[0]["to_arg"]))
		_t.ask(result, FsResult.fail(FsResult.Code.NEEDS_CONFIRM_REPLACE, target).message())
	else:
		_t.ask(result, "файлов с такими именами уже есть: %d. заменить? (y/n)" % clashes.size())
	return true


func _run_plan(
	from_fs: Filesystem, to_fs: Filesystem, from_cwd: String, plan: Array,
	is_admin: bool, confirmed: bool, result: TermResult
) -> Array:
	if plan.is_empty():
		result.add("нет таких файлов")
		return []
	# Занятый файл на месте назначения не заменяется — и вопроса о замене про него нет.
	var free: Array = []
	for step: Dictionary in plan:
		var dest: String = to_fs._destination_for(from_cwd, str(step["from"]), str(step["to_arg"]))
		if to_fs.has_file(dest) and to_fs.is_locked(dest):
			result.add(FsResult.fail(FsResult.Code.BUSY, dest).message())
		else:
			free.append(step)
	if free.is_empty():
		return []
	plan = free
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


## Флаги (`-r`, `-a`) копированию не нужны: папка и так копируется целиком.
func _without_flags(args: PackedStringArray) -> PackedStringArray:
	var kept: PackedStringArray = []
	for arg: String in args:
		if not arg.begins_with("-"):
			kept.append(arg)
	return kept


func _size_kb(data: Dictionary) -> int:
	if data.has("size_kb"):
		return int(data["size_kb"])
	return maxi(1, ceili(float(str(data.get("text", "")).length()) / 1024.0))


## `edit`: открыть текстовый файл в «Блокноте» для правки (решено 25.11.2026). Права — как у
## `mv` и `rm`: на чужом узле гость не правит. Сам файл меняет `save_edit`, когда игрок сохранил.
func edit(args: PackedStringArray, result: TermResult) -> void:
	if args.is_empty():
		result.add("использование: edit <файл>")
		return
	if _guest_on_node(result):
		return
	var path: String = FsPath.resolve(_t.cwd(), args[0])
	var fs: Filesystem = _t.fs()
	if not fs.has_file(path):
		result.add("нет такого файла: %s" % args[0])
		return
	var data: Dictionary = fs.file_data(path)
	if bool(data.get("encrypted", false)) or not data.has("text"):
		result.add("%s: это не текстовый файл" % FsPath.name_of(path))
		return
	result.request = {"type": "edit", "node": _t.node_id(), "path": path, "text": str(data["text"])}


## Сохранить правку из «Блокнота» на узел, где файл открыт (ISS-008): свой ПК — всегда, что бы
## ни делала консоль; чужой узел — только при живом соединении с ним, иначе файл не трогаем. На
## чужом узле правка пишется в его лог.
func save_edit(node: String, path: String, text: String, result: TermResult) -> void:
	var own: bool = node == Network.HOME_ID
	if not own and (not _t.is_remote() or _t.node_id() != node):
		result.add("соединение потеряно: изменения не сохранены")
		return
	if not own and _guest_on_node(result):
		return
	var fs: Filesystem = Filesystem.for_node(node)
	if not fs.has_file(path):
		result.add("файл исчез: изменения не сохранены")
		return
	var data: Dictionary = fs.file_data(path).duplicate()
	data["text"] = text
	fs.put_file(path, data)
	GameState.set_filesystem_state(node, fs.to_dict())
	result.add("сохранено: %s" % FsPath.name_of(path))
	# Правка — та же запись на диск: категория «запись», потолок заметности за взлом не растёт.
	if not own and not _in_logs(path):
		_t.note(Logbook.CATEGORY_FILE_CREATED, "изменён файл %s" % FsPath.name_of(path))
	EventBus.file_edited.emit(node, path)
	_t.spend(_t.minutes_of("terminal_command"), result)


func mv(args: PackedStringArray, result: TermResult, confirmed: bool) -> void:
	if args.size() < 2:
		result.add("использование: mv <файл> <куда>")
		return
	if _guest_on_node(result):
		return
	var moved: FsResult = _t.fs().move(_t.cwd(), args[0], args[1], _t.admin(), confirmed)
	_finish_copy(moved, result)
	if not moved.is_ok():
		return
	var from: String = str(moved.paths[0])
	# Файл ушёл со своего места — для владельца это то же, что удаление (ISS-015): след в логе,
	# а `net.sys` не на месте — узел вне сети. Перенос самих записей лога следов не оставляет,
	# как и их удаление.
	if not _in_logs(from):
		_t.note(Logbook.CATEGORY_FILE_DELETED, "удалён файл %s" % FsPath.name_of(from))
	if _t.is_remote() and from == SystemFiles.FILE_NET:
		_t.handle_events(_t.session.node_sabotaged(_t.node_id(), _t.now()), result)
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

	for busy: String in removed.skipped:
		result.add(FsResult.fail(FsResult.Code.BUSY, busy).message())
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
