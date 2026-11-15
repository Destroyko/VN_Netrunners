class_name ProgramCommands
extends RefCounted
## Программы: progs, run и запуск по имени (docs/tech/terminal-spec.md, «Программы»).
## Головоломок здесь нет — они появятся в шаге 4. Терминал лишь просит интерфейс открыть
## головоломку (TermResult.request) и принимает ответ через Terminal.finish_puzzle().

const ROOTSTEP_LOG: Array[String] = [
	"обновление прав пользователя...",
	"  проверка текущей сессии          ok",
	"  запрос таблицы доступа           ok",
	"  подмена уровня доступа           ok",
]

const LOGWIPE_LOG: Array[String] = [
	"очистка журналов...",
	"  поиск каталога логов             ok",
	"  удаление записей                 ok",
]

var _t: Terminal


func _init(terminal: Terminal) -> void:
	_t = terminal


func list_installed(result: TermResult) -> void:
	var installed: PackedStringArray = Programs.installed()
	if installed.is_empty():
		result.add("установленных программ нет")
	for id: String in installed:
		result.add("%-11s %s" % [id, Programs.about(id)])


## `run <программа> [сервис]` — то же, что короткая запись `<программа> [сервис]`.
func run(args: PackedStringArray, result: TermResult) -> void:
	if args.is_empty():
		result.add("использование: run <программа> [порт]")
		return
	launch(args[0].to_lower(), args.slice(1), result)


func launch(program: String, args: PackedStringArray, result: TermResult) -> void:
	if not Programs.is_program(program) or not Programs.is_installed(program):
		result.add("программа не установлена: %s" % program)
		return
	match Programs.kind_of(program):
		Programs.KIND_CRACKER:
			_crack(program, args, result)
		Programs.KIND_RECON:
			_deepscan(program, args, result)
		_:
			match program:
				"rootstep": _rootstep(result)
				"logwipe": _logwipe(result)


# --- Взломщики ---------------------------------------------------------------

func _crack(program: String, args: PackedStringArray, result: TermResult) -> void:
	var target: String = _t.session.target_id()
	if target.is_empty():
		result.add(NetResult.fail(NetResult.Code.NO_TARGET).message())
		return
	var service: String = _pick_service(target, program, args, result)
	if service.is_empty():
		return

	var started: NetResult = _t.session.begin_cracking(service, program, _t.now(), Programs.trace_enabled())
	if not started.is_ok():
		result.add(started.message())
		return
	if started.trace_started:
		var left: int = _t.session.trace_left()
		result.add("трейс запущен: %d мин" % left)
		EventBus.trace_started.emit(target)

	result.add("%s: запущен, порт %d" % [program, _t.net.port_of(target, service)])
	_t.spend(Programs.minutes_for(program), result)
	# За время запуска трейс или конец прайм-тайма мог оборвать взлом: тогда головоломки не будет.
	if _t.session.target_id() != target:
		return

	_open_puzzle(target, service, program, result)


## Собрать головоломку и попросить интерфейс её открыть. Ступень задаёт сложность сервиса
## (PuzzleLevels); сид — по узлу, сервису, осторожности цели и номеру
## попытки, так что после загрузки сейва игрок получает ту же головоломку.
func _open_puzzle(target: String, service: String, program: String, result: TermResult) -> void:
	var now: int = _t.now()
	var progress: PuzzleProgress = PuzzleProgress.for_game()
	var level: int = _puzzle_level(target, service)
	var attempt: int = progress.attempts(target, service, now)
	var alert: int = _t.net.alert_level(target)
	var seed_value: int = PuzzleProgress.seed_for(Rng.get_seed(), target, service, alert, attempt)
	var kind: String = Programs.puzzle_of(program)

	var puzzle: RefCounted
	var layers_total: int = 1
	var layers_done: int = 0
	if kind == "password":
		puzzle = PasswordPuzzle.generate(level, seed_value, 0)
	elif kind == "dump":
		puzzle = DumpPuzzle.generate(level, seed_value)
	else:
		layers_total = int(PuzzleLevels.matrix(level)["sequences"])
		layers_done = mini(progress.layers(target, service, now), layers_total - 1)
		# Слой = раунд с одной целью. Вскрытые слои остаются: играть надо только оставшиеся.
		puzzle = MatrixPuzzle.generate_round(level, seed_value, 0)

	# Слово, которое откроется, когда хэш собран: по сиду партии, так что после загрузки — то же.
	var password: String = pick_password(seed_value) if kind == "dump" or kind == "password" else ""
	if kind == "password":
		password = (puzzle as PasswordPuzzle).word
	_t.set_puzzle({
		"node": target, "service": service, "kind": kind, "level": level,
		"layers_total": layers_total, "puzzle": puzzle, "password": password,
	})
	result.request = {
		"type": "puzzle", "kind": kind, "node": target, "service": service,
		"port": _t.net.port_of(target, service), "address": str(_t.net.definition(target).get("address", "")),
		"difficulty": level, "alert": alert, "attempt": attempt,
		"layers_done": layers_done, "layers_total": layers_total, "puzzle": puzzle,
		"rounds": layers_total - layers_done, "seed": seed_value, "password": password,
	}


## Пароль сервиса — слово из словаря «пароля» (частые и обычные слова): его игрок увидит и введёт.
static func pick_password(seed_value: int) -> String:
	var words: PackedStringArray = Words.answers(5, ["common", "regular"])
	if words.is_empty():
		return "admin"
	return words[Rng.fixed(("pass:%d" % seed_value).hash()).randi_range(0, words.size() - 1)]


## Какая ступень сыграется против этого сервиса: по его сложности с учётом осторожности цели.
func _puzzle_level(target: String, service: String) -> int:
	var base: int = int(_t.net.service(target, service).get("difficulty", 1))
	return PuzzleLevels.level_for_service(_t.net.effective_difficulty(target, base))


## Какой сервис брать. Игрок называет порт (`passhound 22`); не назвал — единственный
## подходящий невскрытый. Возвращает внутренний id сервиса или пусто, если выбрать не из чего.
func _pick_service(target: String, program: String, args: PackedStringArray, result: TermResult) -> String:
	if not args.is_empty():
		if not args[0].is_valid_int():
			result.add("порт — это число: %s" % args[0])
			return ""
		var by_port: String = _t.net.service_at_port(target, int(args[0]))
		if by_port.is_empty():
			result.add("порт %s: нет сервиса" % args[0])
		return by_port
	var fitting: Array[String] = []
	var ports: PackedStringArray = []
	for service: Dictionary in _t.net.describe(target, _t.now())["services"] as Array:
		if str(service["program"]) == program and not bool(service["cracked"]):
			fitting.append(str(service["id"]))
			ports.append(str(service["port"]))
	if fitting.size() == 1:
		return fitting[0]
	if fitting.is_empty():
		result.add("%s не работает против этой защиты" % program)
	else:
		result.add("не указан порт (подходят: %s)" % ", ".join(ports))
	return ""


## `deepscan`: дольше `scan`, но видит всю сеть за роутером или сервером, а не только соседей.
## Работает только изнутри роутера или сервера: у обычного ПК нет таблиц маршрутов (решено
## 15.11.2026). Трейс не запускает, но время идёт.
func _deepscan(program: String, _args: PackedStringArray, result: TermResult) -> void:
	if not _t.session.has_connection():
		result.add("нет подключения к узлу")
		return
	var here: String = _t.node_id()
	if not Network.DEEPSCAN_DEVICES.has(_t.net.device_of(here)):
		result.add("%s: на этом устройстве нет таблиц маршрутов" % program)
		return
	result.add("%s: обход сети от %s .........." % [program, _t.net.definition(here).get("address", here)])
	var found: Array[Dictionary] = _t.net.deep_scan(here)
	if found.is_empty():
		result.add("других узлов не найдено")
	for entry: Dictionary in found:
		result.add("  %s  через %d" % [NetCommands.book_line(entry), int(entry["depth"])])
	_t.spend(Programs.minutes_for(program), result)


# --- Автоматические программы ------------------------------------------------

func _rootstep(result: TermResult) -> void:
	if not _t.is_remote():
		result.add("нет подключения к узлу")
		return
	if _t.session.has_admin():
		result.add("права уже повышены")
		return
	result.add_all(PackedStringArray(ROOTSTEP_LOG))
	result.request = {"type": "progress", "title": "rootstep"}
	var node: String = _t.node_id()
	_t.spend(Programs.minutes_for("rootstep"), result)
	# Трейс мог оборвать соединение раньше, чем права поднялись.
	if not _t.session.has_connection():
		return
	_t.session.grant_admin()
	_t.note(Logbook.CATEGORY_ROOT, "смена уровня доступа", "root")
	result.add("права администратора получены на %s" % node)


func _logwipe(result: TermResult) -> void:
	if not _t.is_remote():
		result.add("нет подключения к узлу")
		return
	result.add_all(PackedStringArray(LOGWIPE_LOG))
	result.request = {"type": "progress", "title": "logwipe"}
	var node: String = _t.node_id()
	_t.spend(Programs.minutes_for("logwipe"), result)
	if not _t.session.has_connection():
		return
	var removed: int = Logbook.for_node(node).clear()
	result.add("очищено записей: %d" % removed)
