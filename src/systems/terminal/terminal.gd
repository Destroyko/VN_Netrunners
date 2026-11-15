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
const DUMP_DIR: String = "/home/dump"

const ANSWERS_YES: PackedStringArray = ["y", "yes", "д", "да"]
const ANSWERS_NO: PackedStringArray = ["n", "no", "н", "нет"]

## Уровень ОС героя: от него зависит автодополнение (terminal-spec.md). Переменная состояния
## `pc.os`: old / normal / hacker. Пока нет флешки соседки (шаг 6), по умолчанию normal.
const VAR_OS: String = "pc.os"
const OS_OLD: String = "old"
const OS_NORMAL: String = "normal"

var net: Network
var session: HackSession

var _history: PackedStringArray = []
var _cwd_home: String = HOME_DIR
var _cwd_remote: String = HOME_DIR
## Вопрос, на который ждём ответ: {"line": исходная команда}.
var _pending: Dictionary = {}
## Головоломка, которую открыли программой: {"service", "kind", "difficulty", "node"}.
var _puzzle: Dictionary = {}
var _line: String = ""

var _files: FileCommands
var _network: NetCommands
var _programs: ProgramCommands


func _init() -> void:
	_files = FileCommands.new(self)
	_network = NetCommands.new(self)
	_programs = ProgramCommands.new(self)
	_sync()


## Свежие обёртки над состоянием игры. Зовём в начале каждой публичной операции.
func _sync() -> void:
	net = Network.for_game()
	session = HackSession.new(net)
	_apply_repairs()


## Владелец починил узел, с которого игрок снёс net.sys: возвращаем файл на место.
## Делаем лениво, когда кто-то смотрит: часы идут не только в терминале (сон, ожидание),
## а подписки на смену дня у сети нет — и не нужна, пока нужный файл виден лишь отсюда.
func _apply_repairs() -> void:
	for node_id: String in net.due_repairs(now()):
		Filesystem.for_node(node_id).put_file(SystemFiles.FILE_NET, {"system": true})
		net.mark_repaired(node_id)


# --- Где мы ------------------------------------------------------------------

func node_id() -> String:
	return session.current_id()


func is_remote() -> bool:
	return session.has_connection()


func fs() -> Filesystem:
	return Filesystem.for_node(node_id())


func home_fs() -> Filesystem:
	return Filesystem.for_node(Network.HOME_ID)


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
	var where: String = "home"
	if is_remote():
		where = str(net.definition(node_id()).get("address", node_id()))
	elif not session.target_id().is_empty():
		# Соединение есть, входа нет: адрес без каталога — файлы узла ещё недоступны.
		return "%s> " % session.target_address()
	return "%s:%s%s " % [where, cwd(), "#" if is_remote() and admin() else "$"]


func history() -> PackedStringArray:
	return _history.duplicate()


func has_question() -> bool:
	return not _pending.is_empty()


# --- Ввод --------------------------------------------------------------------

func execute(line: String) -> TermResult:
	_sync()
	var result := TermResult.new()
	var text: String = line.strip_edges()
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


func _remember(text: String) -> void:
	_history.append(text)
	while _history.size() > HISTORY_LIMIT:
		_history.remove_at(0)


func _dispatch(text: String, confirmed: bool, result: TermResult) -> TermResult:
	_line = text
	var words: PackedStringArray = CommandLine.parse(text)
	var command: String = words[0].to_lower()
	var args: PackedStringArray = words.slice(1)

	match command:
		"pwd": _files.pwd(result)
		"ls": _files.ls(args, result)
		"cd": _files.cd(args, result)
		"cat": _files.cat(args, result)
		"cp": _files.cp(args, result, confirmed)
		"put": _files.put(args, result, confirmed)
		"mv": _files.mv(args, result, confirmed)
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
	_pending = {"line": _line}


# --- Время и последствия -----------------------------------------------------

func minutes_of(key: String, fallback: int = 1) -> int:
	var costs: Dictionary = DataLoader.balance().get("action_minutes", {}) as Dictionary
	return int(costs.get(key, fallback))


## Потратить игровые минуты: сдвинуть часы и спросить у сеанса, что случилось за это время.
func spend(minutes: int, result: TermResult) -> void:
	if minutes <= 0:
		return
	Clock.advance(minutes)
	result.minutes += minutes
	handle_events(session.advance(minutes, now()), result)


## Сообщить игроку о том, что произошло с сеансом, и закрыть его последствия.
func handle_events(events: Array[Dictionary], result: TermResult) -> void:
	for event: Dictionary in events:
		var node: String = str(event.get("node", ""))
		match str(event["type"]):
			"trace_half":
				result.add("трейс: осталась половина (%d мин)" % int(event["left"]))
			"trace_last_quarter":
				result.add("трейс: осталась последняя четверть (%d мин)" % int(event["left"]))
			"connection_lost":
				result.add("соединение потеряно: узел ушёл из сети")
				hung_up(node, bool(event["was_connected"]))
			"trace_finished":
				result.add("трейс дошёл до конца: соединение оборвано")
				_forget_progress(node)
				EventBus.trace_finished.emit(node)
				hung_up(node, bool(event["was_connected"]))


## Цель перенастроила защиту: частичные слои и счётчики попыток узла обнуляются, а символы,
## открытые `deepscan`, были про старое слово и теряются вместе с ним.
func _forget_progress(node: String) -> void:
	PuzzleProgress.for_game().reset_node(node)
	for service: Variant in net.definition(node).get("services", []) as Array:
		var key: String = ProgramCommands.VAR_DEEPSCAN_PREFIX + node + "." + str((service as Dictionary).get("id", ""))
		GameState.set_var(key, 0)


## Сеанс с узлом закончился — по `dc`, обрыву или трейсу. Запись о выходе пишется всегда и
## после любой чистки: бесследно уйти нельзя (hacking.md).
func hung_up(node: String, was_connected: bool) -> void:
	_puzzle = {}
	_cwd_remote = HOME_DIR
	if not was_connected:
		return
	Logbook.for_node(node).append(
		Logbook.CATEGORY_SESSION, "сеанс закрыт", GameState.day, GameState.minute, false, "logout"
	)
	EventBus.node_disconnected.emit(node)


## Записать след на чужом узле. На своём ПК следов нет: терминал не пишет туда то,
## что игрок делает сам (решено 15.11.2026).
func note(category: String, text: String, slug: String = "") -> void:
	if not is_remote():
		return
	Logbook.for_node(node_id()).append(category, text, GameState.day, GameState.minute, false, slug)


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
## 1 или 0, у «матрицы» столько целей собрано. Время на головоломку уже потрачено при запуске
## программы: пока она открыта, игровое время стоит (time.md).
func finish_puzzle(gained: int) -> TermResult:
	_sync()
	var result := TermResult.new()
	if _puzzle.is_empty():
		result.add("сейчас нет открытой головоломки")
		return result

	var data: Dictionary = _puzzle
	_puzzle = {}
	apply_outcome(
		str(data["node"]), str(data["service"]), str(data["kind"]), int(data["level"]),
		gained, result, int(data["layers_total"])
	)
	return result


## Итог попытки: слои в прогресс, сервис вскрыт целиком, частичный успех или провал.
func apply_outcome(
	node: String, service: String, kind: String, level: int, gained: int, result: TermResult,
	layers_total: int = 1
) -> void:
	var now_minute: int = now()
	var progress: PuzzleProgress = PuzzleProgress.for_game()
	var layers_gained: int = gained
	var attempt: int = progress.attempts(node, service, now_minute) + 1
	progress.record(node, service, now_minute, layers_gained)
	var layers_now: int = progress.layers(node, service, now_minute)

	if layers_now >= layers_total:
		var done: NetResult = session.crack(service, now_minute)
		progress.clear_service(node, service)
		GameState.set_var(ProgramCommands.VAR_DEEPSCAN_PREFIX + node + "." + service, 0)
		EventBus.puzzle_solved.emit(kind, level, node, service)
		result.add("сервис вскрыт: %s (%d из %d)" % [service, done.cracked, done.required])
		# Вскрыто всё нужное — вход происходит сам: игрок входит без лишнего connect.
		if done.cracked >= done.required and not session.has_connection():
			_network.connect_to(PackedStringArray([session.target_address()]), result)
	elif layers_gained > 0:
		# Частичный успех: слои остались, добить можно позже (даже после `dc`).
		EventBus.puzzle_solved.emit(kind, level, node, service)
		result.add("слой вскрыт: %d из %d. сервис %s ещё держится" % [layers_now, layers_total, service])
	else:
		EventBus.puzzle_failed.emit(kind, level, node, service, attempt)
		result.add("провал: сервис %s не поддался" % service)


# --- Остальные команды -------------------------------------------------------

func _show_history(result: TermResult) -> void:
	if _history.is_empty():
		result.add("история пуста")
	for index: int in _history.size():
		result.add("%3d  %s" % [index + 1, _history[index]])


## Перезагрузка своего ПК: применяет тему, пересобирает рабочий стол, обрывает всё запущенное.
## Чужую машину перезагружать нельзя: это было бы то же, что `dc`, но с лишним шумом.
func _reboot(result: TermResult) -> void:
	if is_remote():
		result.add("перезагрузка недоступна на удалённом узле")
		return
	session.disconnect_now()
	result.add("перезагрузка...")
	var report: Dictionary = SystemFiles.reboot(home_fs())
	if bool(report["theme_changed"]):
		result.add("применена тема: %s" % str(report["theme"]))
	for error: String in report["errors"] as PackedStringArray:
		result.add(error)
	spend(int((DataLoader.balance().get("nodes", {}) as Dictionary).get("action_minutes_reboot", 5)), result)


# --- Автодополнение ----------------------------------------------------------

## Дополнить слово под курсором (в конце строки). Возвращает {"line": новая строка,
## "options": варианты}. На старой ОС автодополнения нет: игрок печатает руками (hacking.md).
func complete(line: String) -> Dictionary:
	_sync()
	if str(GameState.get_var_or(VAR_OS, OS_NORMAL)) == OS_OLD:
		return {"line": line, "options": PackedStringArray()}
	return Autocomplete.complete(line, self)
