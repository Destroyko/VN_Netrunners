class_name Terminal
extends RefCounted
## Терминал: разбор строки, таблица команд, время, события, подтверждения, автодополнение
## (docs/tech/terminal-spec.md). Это чистая логика без сцен: строка на входе, TermResult на
## выходе. Что рисовать и как анимировать полоску, решает интерфейс (шаг 7).
##
## Терминал единственный, кто соединяет файловую систему и сеть с часами, шиной событий и
## журналами: сами они про Clock и EventBus не знают (CLAUDE.md).
##   - время: после команды сдвигаем `Clock`, затем сообщаем сеансу — он решает, не вышел ли
##     трейс или прайм-тайм (`HackSession.advance`);
##   - события: `EventBus.node_connected`, `file_deleted` и остальные из terminal-spec.md;
##   - следы: записи в логи цели пишутся здесь, на чужом узле (на своём ПК их нет).
##
## Состояние игры — в `GameState`, не здесь. Здесь только то, что относится к сеансу
## ввода: история, текущий каталог и вопрос «y/n», на который ждём ответ. Network и
## HackSession создаются заново на каждую команду: это тонкие обёртки над состоянием игры,
## так что после загрузки сейва терминал не держит устаревшие словари.

const HISTORY_LIMIT: int = 50
const HOME_DIR: String = "/home"
## Куда `cp` кладёт файл с узла, если не сказано иначе (terminal-spec.md, «Добыча»).
## Куда `cp` с узла кладёт файл по умолчанию — «Загрузки» (до 25.11.2026 — `/home/dump`, сейв v3).
const DUMP_DIR: String = "/home/downloads"
## Рабочий стол героя — обычная папка: файлы на столе и ярлыки приложений (`.lnk`).
const DESKTOP_DIR: String = "/home/desktop"

const ANSWERS_YES: PackedStringArray = ["y", "yes", "д", "да"]
const ANSWERS_NO: PackedStringArray = ["n", "no", "н", "нет"]
## Команду вызвали неверно (нет аргумента): синтаксис и куда смотреть (вычитка 25.11.2026).
static func usage(result: TermResult, syntax: String) -> void:
	result.add("команда указана неверно: %s. Подробнее: help %s" % [syntax, syntax.get_slice(" ", 0)])


## Ответ, пока идёт программа: консоль одна, вторая команда ждать не станет (ISS-006).
const BUSY_TEXT: String = "терминал занят"

## Уровень ОС героя: от него зависит автодополнение (terminal-spec.md). Переменная состояния
## `pc.os`: old / normal / hacker. Пока нет флешки соседки (шаг 6), по умолчанию normal.
const VAR_OS: String = "pc.os"
const OS_OLD: String = "old"
const OS_NORMAL: String = "normal"

## Время прошло само (часы идут в реальном времени), и с сеансом что-то случилось: трейс
## перевалил за половину, дошёл до конца, узел ушёл из сети. Окно печатает строки и
## перечитывает состояние; игрок при этом мог ничего не набирать.
signal ticked(result: TermResult)
## Программа доработала (или прервана): её итог, напечатать как обычный ответ команды.
signal job_finished(result: TermResult)

var net: Network
var session: HackSession

var _history: PackedStringArray = []
var _cwd_home: String = HOME_DIR
var _cwd_remote: String = HOME_DIR
## Команда идёт на своём ПК при открытом сеансе (`execute_local`).
var _local: bool = false
## Файл, открытый в «Блокноте»: {node, path}. «Блокнот» один, файл в нём занят (ISS-008).
var _editing: Dictionary = {}
## Программа, чьи минуты сейчас идут под полоской: {then} — что сделать, когда дойдёт до конца.
var _job: Dictionary = {}
## Вопрос, на который ждём ответ: {"line": исходная команда}.
var _pending: Dictionary = {}
## Вопрос окна «Файлы» (`execute_local`): отдельно от вопроса консоли.
var _local_pending: Dictionary = {}
## Головоломка, которую открыли программой: {"service", "kind", "difficulty", "node"}.
var _puzzle: Dictionary = {}
var _line: String = ""
## Сервер спросил пароль (как ssh): {"node", "service", "address"}; пусто — не спрашивает.
var _login: Dictionary = {}
## Лишние минуты трейса за «громкие» действия на узле с анализом действий; списываются в spend.
var _ids_extra: int = 0

var _files: FileCommands
var _network: NetCommands
var _programs: ProgramCommands


func _init() -> void:
	_files = FileCommands.new(self)
	_network = NetCommands.new(self)
	_programs = ProgramCommands.new(self)
	_sync()
	EventBus.session_advanced.connect(_on_session_advanced)


## Что можно у двери закрытого узла: разведка цели, вход и выход, взломщики (они — программы)
## и служебные команды самого терминала.
const AT_DOOR_COMMANDS: PackedStringArray = ["probe", "connect", "dc", "nodes", "progs", "run", "help", "clear", "history"]


## Итог команды, которая сейчас тратит минуты: события сеанса от хода часов дописываются в него.
## Вне команды (часы идут сами) они уходят в окно сигналом `ticked`.
var _collect: TermResult


## Сеанс взлома тикнул от хода часов (HackManager): последствия для мира уже применены,
## здесь — что сказать игроку и что забыть самому терминалу.
func _on_session_advanced(events: Array) -> void:
	_sync_wrappers()
	var result: TermResult = _collect if _collect != null else TermResult.new()
	var typed: Array[Dictionary] = []
	for event: Variant in events:
		typed.append(event as Dictionary)
	_describe(typed, result)
	if _collect == null:
		ticked.emit(result)


## Свежие обёртки над состоянием игры. Зовём в начале каждой публичной операции.
func _sync() -> void:
	_sync_wrappers()
	_apply_repairs()


## Только обёртки, без починки узлов: починка ленивая, по команде игрока, а не по ходу часов.
func _sync_wrappers() -> void:
	net = Network.for_game()
	session = HackSession.new(net)


## Владелец починил узел, с которого игрок снёс net.sys: переустановил ОС (ISS-015) —
## системные файлы из данных узла на месте, логи пусты.
## Делаем лениво, когда кто-то смотрит: часы идут не только в терминале (сон, ожидание),
## а подписки на смену дня у сети нет — и не нужна, пока нужный файл виден лишь отсюда.
func _apply_repairs() -> void:
	for node_id: String in net.due_repairs(now()):
		var restored: Filesystem = Filesystem.for_node(node_id)
		var original: Dictionary = (DataLoader.nodes().get(node_id, {}) as Dictionary).get("files", {}) as Dictionary
		for path: String in original.keys():
			if bool((original[path] as Dictionary).get("system", false)) and not restored.has_file(path):
				restored.put_file(path, original[path] as Dictionary)
		if not restored.has_file(SystemFiles.FILE_NET):
			restored.put_file(SystemFiles.FILE_NET, {"system": true})
		Logbook.for_node(node_id).clear()
		net.mark_repaired(node_id)


# --- Где мы ------------------------------------------------------------------

func node_id() -> String:
	return Network.HOME_ID if _local else session.current_id()


func is_remote() -> bool:
	return not _local and session.has_connection()


## Выполнить команду на своём ПК, даже если открыт сеанс с чужим узлом: окно «Файлы» своего ПК
## работает теми же командами (права, логи), но не должно трогать чужую машину. Вопрос y/n у окна
## свой (`local_question`, `answer_local`): вопрос консоли он не закрывает и в консоли на него не
## ответить (ISS-004, ISS-007).
func execute_local(line: String) -> TermResult:
	var console_question: Dictionary = _pending
	_pending = {}
	var was: bool = _local
	_local = true
	var result: TermResult = execute(line)
	_local = was
	_local_pending = _pending
	_pending = console_question
	return result


## Вопрос y/n, который ждёт ответа в окне «Файлы»; пусто — вопроса нет.
func local_question() -> String:
	return str(_local_pending.get("question", ""))


## Ответ окна «Файлы» на свой вопрос: «да» повторяет команду с подтверждением на своём ПК.
func answer_local(yes: bool) -> TermResult:
	var result := TermResult.new()
	if _local_pending.is_empty():
		return result
	var saved: String = str(_local_pending["line"])
	_local_pending = {}
	if not yes:
		result.add("отменено")
		return result
	_sync()
	if has_job():
		result.add(BUSY_TEXT)
		return result
	var was: bool = _local
	_local = true
	_dispatch(saved, true, result)
	_local = was
	return result


func fs() -> Filesystem:
	return _with_locks(Filesystem.for_node(node_id()))


func home_fs() -> Filesystem:
	return _with_locks(Filesystem.for_node(Network.HOME_ID))


## «Блокнот» открыл файл (стол вызывает, когда показал окно); закрыл — `end_edit`.
func begin_edit(node: String, path: String) -> void:
	_editing = {"node": node, "path": path}


func end_edit() -> void:
	_editing = {}


func editing() -> Dictionary:
	return _editing


## Файлы узла, занятые программами: архив под фоновым подбором (ISS-018), файл в «Блокноте».
func busy_paths(node: String) -> PackedStringArray:
	var paths: PackedStringArray = []
	if str(_editing.get("node", "")) == node:
		paths.append(str(_editing["path"]))
	if node == Network.HOME_ID:
		for task: Dictionary in BackgroundTasks.tasks():
			paths.append(str(task["path"]))
	return paths


func _with_locks(filesystem: Filesystem) -> Filesystem:
	filesystem.locked = busy_paths(filesystem.node_id)
	return filesystem


## На своём ПК у героя полные права всегда (примеры в terminal-spec.md: `home:/sys$ rm`),
## на чужом — гость, пока `rootstep` не поднял права.
func admin() -> bool:
	return not is_remote() or session.has_admin()


func cwd() -> String:
	return _cwd_remote if is_remote() else _cwd_home


func set_cwd(path: String) -> void:
	if is_remote():
		_cwd_remote = path
	else:
		_cwd_home = path


func home_cwd() -> String:
	return _cwd_home


func now() -> int:
	return net.abs_minute(GameState.day, GameState.minute)


## Приглашение: `home:/home$`, `10.0.0.7:/home$` (гость), `10.0.0.7:/sys#` (администратор).
func prompt() -> String:
	_sync()
	if not _login.is_empty():
		return "пароль: "
	var where: String = "home"
	if is_remote():
		where = str(net.definition(node_id()).get("address", node_id()))
	elif not session.target_id().is_empty():
		# Соединение есть, входа нет: адрес без каталога — файлы узла ещё недоступны.
		return "%s> " % session.target_address()
	return "%s:%s%s " % [where, cwd(), "#" if is_remote() and admin() else "$"]


## Заставка при открытии окна: версия ОС и ядра, как у настоящего терминала. Текст — в
## data/terminal.json по уровню ОС (`pc.os`), правил здесь нет.
func banner() -> PackedStringArray:
	var os_level: String = str(GameState.get_var_or(VAR_OS, OS_NORMAL))
	var all: Dictionary = DataLoader.terminal().get("banner", {}) as Dictionary
	var lines: PackedStringArray = []
	for line: Variant in all.get(os_level, all.get(OS_NORMAL, [])) as Array:
		lines.append(str(line))
	return lines


func history() -> PackedStringArray:
	return _history.duplicate()


## Текст вопроса «y/n», который ждёт ответа (для окна подтверждения); пусто — вопроса нет.
func last_question() -> String:
	return str(_pending.get("question", ""))


func has_question() -> bool:
	return not _pending.is_empty()


# --- Ввод --------------------------------------------------------------------

func execute(line: String) -> TermResult:
	_sync()
	var result := TermResult.new()
	var text: String = line.strip_edges()
	# Идёт программа: любая новая команда (с клавиатуры, мышью из окон) — отказ, игрок сам
	# планирует работу (решено 25.11.2026). Прервать — Ctrl+C (`cancel_job`).
	if has_job():
		result.add(BUSY_TEXT)
		return result
	# Сервер ждёт пароль: строка — это пароль, а не команда, и в историю она не идёт.
	if not _login.is_empty():
		return _attempt_login(text, result)
	if text.is_empty():
		return result

	# Ждали ответа на вопрос: «y» повторяет команду с подтверждением, «n» отменяет,
	# всё остальное закрывает вопрос и выполняется как обычная команда.
	if not _pending.is_empty():
		var saved: String = str(_pending["line"])
		_pending = {}
		var answer: String = text.to_lower()
		if ANSWERS_YES.has(answer):
			return _dispatch(saved, true, result)
		if ANSWERS_NO.has(answer):
			result.add("отменено")
			return result

	_remember(text)
	return _dispatch(text, false, result)


## Игрок сохранил правку в «Блокноте» (`edit`): записать файл на узле, где он открывался.
func save_edit(node: String, path: String, text: String) -> TermResult:
	_sync()
	var result := TermResult.new()
	# Минуты сохранения не лезут в минуты идущей программы: «Блокнот» ждёт, правка цела.
	if has_job():
		result.add(BUSY_TEXT)
		return result
	_files.save_edit(node, path, text, result)
	return result


# --- Вход по паролю ------------------------------------------------------------

func begin_login(node: String, service: String) -> void:
	_login = {"node": node, "service": service, "address": str(net.definition(node).get("address", ""))}


func login_pending() -> bool:
	return not _login.is_empty()


## Ответ на «пароль:». Пустая строка (или dc) — отказ от входа. Верное слово — вход, как после
## connect. Неверное — «доступ запрещён», сервер спрашивает снова.
func _attempt_login(text: String, result: TermResult) -> TermResult:
	var node: String = str(_login["node"])
	if text.is_empty() or text.to_lower() == "dc" or session.target_id() != node:
		_login = {}
		result.add("вход отменён")
		if text.to_lower() == "dc":
			return _dispatch("dc", false, result)
		return result
	var service: String = str(_login["service"])
	var word: String = net.access.password_of(node, service)
	if word.is_empty() or text.to_lower().replace("ё", "е") != word:
		result.add("доступ запрещён")
		spend(minutes_of("terminal_command"), result)
		return result
	net.access.enter_password(node, service)
	var address: String = str(_login["address"])
	_login = {}
	_network.connect_to(PackedStringArray([address]), result)
	return result


func _remember(text: String) -> void:
	_history.append(text)
	while _history.size() > HISTORY_LIMIT:
		_history.remove_at(0)


func _dispatch(text: String, confirmed: bool, result: TermResult) -> TermResult:
	_line = text
	var words: PackedStringArray = CommandLine.parse(text)
	var command: String = words[0].to_lower()
	var args: PackedStringArray = words.slice(1)

	# У двери (соединение есть, входа нет) работают только команды к цели и служебные: иначе
	# `scan` или `ls` молча выполнились бы на своём ПК, хотя приглашение показывает чужой адрес.
	if not session.target_id().is_empty() and not session.has_connection() \
			and not AT_DOOR_COMMANDS.has(command) and not Programs.is_program(command):
		result.add("вход не выполнен")
		return result

	match command:
		"pwd": _files.pwd(result)
		"ls": _files.ls(args, result)
		"cd": _files.cd(args, result)
		"cat": _files.cat(args, result)
		"cp": _files.cp(args, result, confirmed)
		"put": _files.put(args, result, confirmed)
		"mv": _files.mv(args, result, confirmed)
		"edit": _files.edit(args, result)
		"rm": _files.rm(args, result, confirmed)
		"mkdir": _files.mkdir(args, result)
		"scan": _network.scan(result)
		"probe": _network.probe(args, result)
		"connect": _network.connect_to(args, result)
		"dc": _network.disconnect_now(result)
		"nodes": _network.nodes(result)
		"progs": _programs.list_installed(result)
		"run": _programs.run(args, result)
		"help": TerminalHelp.show(args, result)
		"clear": result.clear_screen = true
		"history": _show_history(result)
		"reboot": _reboot(result)
		"decrypt":
			if Gates.is_open(Gates.AUTOCRACK):
				_decrypt(args, result)
			else:
				result.add("команда не найдена: %s" % words[0])
		_:
			if Programs.is_program(command):
				_programs.launch(command, args, result)
			else:
				result.add("команда не найдена: %s" % words[0])
	return result


## Задать вопрос «y/n». Команда запомнится и повторится с подтверждением, если ответят «y».
func ask(result: TermResult, question: String) -> void:
	result.question = question
	result.add(question)
	_pending = {"line": _line, "question": question}


# --- Время и последствия -----------------------------------------------------

func minutes_of(key: String, fallback: int = 1) -> int:
	var costs: Dictionary = DataLoader.balance().get("action_minutes", {}) as Dictionary
	return int(costs.get(key, fallback))


## Потратить минуты программы и только потом получить её итог (`then`). В игре минуты идут
## ускоренно под полоской, итог — когда полоска дошла до конца; `Ctrl+C` (`cancel_job`) его
## отменяет, обрыв соединения — тоже: программа «не успела». Когда часы стоят (тесты), всё сразу;
## трейс, кончающийся раньше программы, отнимает ровно оставшиеся минуты.
## `bar` — полоска и для короткого шага (слой `probe`).
func spend_then(minutes: int, result: TermResult, then: Callable, bar: bool = false) -> void:
	if Clock.will_fast_forward(minutes, bar):
		_job = {"then": then}
		if not Clock.fast_forward_finished.is_connected(_on_job_done):
			Clock.fast_forward_finished.connect(_on_job_done)
		# Отрезок бросили снаружи (выключение ПК): программа доигрывает итог «не успела».
		if not Clock.fast_forward_dropped.is_connected(_on_job_done):
			Clock.fast_forward_dropped.connect(_on_job_done)
		spend(minutes, result, bar)
		return
	var spent: int = minutes
	if session.is_tracing() and minutes >= session.trace_left():
		spent = session.trace_left()
	spend(spent, result)
	then.call(result)


func has_job() -> bool:
	return not _job.is_empty()


## Ctrl+C: бросить программу. Потраченное время не возвращается, итога нет.
func cancel_job() -> TermResult:
	var result := TermResult.new()
	if _job.is_empty():
		return result
	_job = {}
	Clock.cancel_fast_forward()
	result.add("^C")
	result.add("прервано")
	return result


func _on_job_done() -> void:
	_finish_job()


func _finish_job() -> void:
	if _job.is_empty():
		return
	var then: Callable = _job["then"] as Callable
	_job = {}
	var result := TermResult.new()
	then.call(result)
	job_finished.emit(result)


## Потратить игровые минуты: сдвинуть часы и спросить у сеанса, что случилось за это время.
func spend(minutes: int, result: TermResult, bar: bool = false) -> void:
	if minutes <= 0:
		return
	# Штраф анализа действий: трейс идёт быстрее часов, часы — как обычно.
	var extra: int = _ids_extra
	_ids_extra = 0
	if extra > 0:
		handle_events(session.advance(extra, now()), result)
	# Ход часов двигает трейс через HackManager; что случилось, дописывается в этот итог.
	# В игре минуты программы идут ускоренно под полоску (Clock.fast_forward): тогда события
	# трейса придут позже, отдельным итогом через `ticked`.
	_collect = result
	Clock.fast_forward(minutes, bar)
	_collect = null
	result.minutes += minutes


## События сеанса от действия игрока (саботаж, штраф анализа действий): применить последствия
## для мира и сказать игроку.
func handle_events(events: Array[Dictionary], result: TermResult) -> void:
	HackConsequences.apply(events)
	_describe(events, result)


## Что напечатать по событиям сеанса и что забыть самому терминалу, если сеанс закрылся.
func _describe(events: Array[Dictionary], result: TermResult) -> void:
	for event: Dictionary in events:
		match str(event["type"]):
			"trace_half":
				result.add("трейс: осталась половина (%d мин)" % int(event["left"]))
			"trace_last_quarter":
				result.add("трейс: осталась последняя четверть (%d мин)" % int(event["left"]))
			"connection_lost":
				result.add("соединение потеряно: узел ушёл из сети")
				_forget_session()
			"trace_finished":
				result.add("трейс дошёл до конца: соединение оборвано")
				_forget_session()


## Сеанс закрыт — у терминала больше нет ни головоломки, ни вопроса пароля, ни чужого каталога.
func _forget_session() -> void:
	if not _puzzle.is_empty():
		var dropped: Dictionary = _puzzle
		_puzzle = {}
		PuzzleOutcome.new(self).abandon(dropped)
	_login = {}
	_cwd_remote = HOME_DIR
	# Соединение оборвалось посреди программы: остальные минуты не идут, программа «не успела».
	if not _job.is_empty():
		Clock.cancel_fast_forward()
		_finish_job.call_deferred()


## Игрок сам закрыл сеанс (`dc`, переход на другой узел): забыть своё и записать выход.
func hung_up(node: String, was_connected: bool) -> void:
	_forget_session()
	HackConsequences.session_closed(node, was_connected)


## Записать след на чужом узле. На своём ПК следов нет: терминал не пишет туда то,
## что игрок делает сам (решено 15.11.2026).
func note(category: String, text: String, slug: String = "") -> void:
	if not is_remote() or traces_covered():
		return
	Logbook.for_node(node_id()).append(category, text, GameState.day, GameState.minute, false, slug)
	# Записано в журнал — значит, действие «громкое»: анализ действий узла его заметил.
	if net.has_ids(node_id()) and session.is_tracing():
		_ids_extra += int((DataLoader.balance().get("nodes", {}) as Dictionary).get("ids_trace_minutes", 3))


## Ворота «следы подчищают» — правило в HackConsequences; имя оставлено для читаемости.
const GATE_COVER: String = HackConsequences.GATE_COVER


static func traces_covered() -> bool:
	return HackConsequences.traces_covered()


func has_network() -> bool:
	return SystemFiles.has_network(home_fs())


# --- Головоломка -------------------------------------------------------------

## Живая головоломка, которую просил терминал (PasswordPuzzle или MatrixPuzzle), или null.
## Интерфейс играет прямо в ней: `guess()` у пароля, `pick()` у матрицы.
func current_puzzle() -> RefCounted:
	return _puzzle.get("puzzle") as RefCounted


func set_puzzle(data: Dictionary) -> void:
	_puzzle = data


## Интерфейс закончил головоломку. `gained` — сколько слоёв вскрыто за эту попытку: у «пароля»
## 1 или 0, у «матрицы» столько целей собрано. Время на головоломку потрачено при запуске
## программы; пока она открыта, часы идут, как везде, кроме диалогов и меню (time.md, ISS-019).
func finish_puzzle(gained: int) -> TermResult:
	_sync()
	var result := TermResult.new()
	if _puzzle.is_empty():
		result.add("сейчас нет открытой головоломки")
		return result

	var data: Dictionary = _puzzle
	_puzzle = {}
	PuzzleOutcome.new(self).apply(data, gained, result)
	return result


## Вскрыто всё нужное после головоломки — войти на узел-цель (как `connect`).
func connect_target(result: TermResult) -> void:
	_network.connect_to(PackedStringArray([session.target_address()]), result)


# --- Остальные команды -------------------------------------------------------

func _show_history(result: TermResult) -> void:
	if _history.is_empty():
		result.add("история пуста")
	for index: int in _history.size():
		result.add("%3d  %s" % [index + 1, _history[index]])


## Перезагрузка своего ПК: применяет тему, пересобирает рабочий стол, обрывает всё запущенное.
## Чужую машину перезагружать нельзя: это было бы то же, что `dc`, но с лишним шумом.
## Расшифровать архив на своём ПК. `-auto` — поставить подбор на фон (идёт, пока игрок живёт).
## Без ключа ручная расшифровка (мини-игра) пока не готова — см. docs/open-questions.md.
func _decrypt(args: PackedStringArray, result: TermResult) -> void:
	if is_remote():
		result.add("архивы расшифровываются только на своём ПК")
		return
	if args.is_empty():
		var running: Array = BackgroundTasks.tasks()
		if running.is_empty():
			Terminal.usage(result, "decrypt <файл> -auto")
		else:
			for t: Dictionary in running:
				result.add("подбор идёт: %s" % str(t["path"]))
		return
	var path: String = FsPath.resolve(home_cwd(), args[0])
	var auto: bool = args.has("-auto")
	if not auto:
		result.add("ручная расшифровка пока недоступна. Запусти подбор: decrypt %s -auto" % args[0])
		return
	var report: Dictionary = BackgroundTasks.start_decrypt(path)
	if not bool(report["ok"]):
		result.add("decrypt: %s" % str(report["reason"]))
		return
	result.add("подбор пароля запущен, займёт около %d мин. Можно заняться другими делами." % int(report["minutes"]))


func _reboot(result: TermResult) -> void:
	if is_remote():
		result.add("перезагрузка недоступна на удалённом узле")
		return
	# Одно правило на все кнопки питания (PcPower): сеанс оборван как `dc`, подбор прерван,
	# тема применена. Стол, увидев загрузку, соберётся заново.
	result.add("перезагрузка...")
	var report: Dictionary = PcPower.reboot()
	_forget_session()
	if int(report.get("stopped", 0)) > 0:
		result.add("прервано фоновых задач: %d" % int(report["stopped"]))
	if bool(report.get("theme_changed", false)):
		result.add("применена тема: %s" % str(report["theme"]))
	for error: String in report.get("errors", PackedStringArray()) as PackedStringArray:
		result.add(error)


# --- Автодополнение ----------------------------------------------------------

## Дополнить слово под курсором (в конце строки). Возвращает {"line": новая строка,
## "options": варианты}. На старой ОС автодополнения нет: игрок печатает руками (hacking.md).
func complete(line: String) -> Dictionary:
	_sync()
	if str(GameState.get_var_or(VAR_OS, OS_NORMAL)) == OS_OLD:
		return {"line": line, "options": PackedStringArray()}
	return Autocomplete.complete(line, self)
