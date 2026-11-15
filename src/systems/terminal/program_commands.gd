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

## Счётчик «открытых символов» у сервиса: deepscan +1 за запуск. Головоломка «пароль»
## читает его при генерации и не открывает больше, чем позволяет правило (puzzles-spec.md).
const VAR_DEEPSCAN_PREFIX: String = "deepscan."

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
		result.add("использование: run <программа> [сервис]")
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

	result.add("%s: запущен против %s" % [program, service])
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
		var extra: int = int(GameState.get_var_or(VAR_DEEPSCAN_PREFIX + target + "." + service, 0))
		puzzle = PasswordPuzzle.generate(level, seed_value, extra)
	else:
		var params: Dictionary = PuzzleLevels.matrix(level)
		layers_total = int(params["sequences"])
		layers_done = mini(progress.layers(target, service, now), layers_total - 1)
		# Вскрытые слои остаются: собирать надо только оставшиеся цели.
		params["sequences"] = layers_total - layers_done
		puzzle = MatrixPuzzle.generate(level, seed_value, params)

	_t.set_puzzle({
		"node": target, "service": service, "kind": kind, "level": level,
		"layers_total": layers_total, "puzzle": puzzle,
	})
	result.request = {
		"type": "puzzle", "kind": kind, "node": target, "service": service,
		"difficulty": level, "alert": alert, "attempt": attempt,
		"layers_done": layers_done, "layers_total": layers_total, "puzzle": puzzle,
	}


## Какая ступень сыграется против этого сервиса: по его сложности с учётом осторожности цели.
func _puzzle_level(target: String, service: String) -> int:
	var base: int = int(_t.net.service(target, service).get("difficulty", 1))
	return PuzzleLevels.level_for_service(_t.net.effective_difficulty(target, base))


## Какой сервис брать, если игрок не указал: единственный подходящий невскрытый.
func _pick_service(target: String, program: String, args: PackedStringArray, result: TermResult) -> String:
	if not args.is_empty():
		return args[0]
	var fitting: PackedStringArray = []
	for service: Dictionary in _t.net.describe(target, _t.now())["services"] as Array:
		if str(service["program"]) == program and not bool(service["cracked"]):
			fitting.append(str(service["id"]))
	if fitting.size() == 1:
		return fitting[0]
	if fitting.is_empty():
		result.add("%s не работает против этой защиты" % program)
	else:
		result.add("укажи сервис: %s" % ", ".join(fitting))
	return ""


func _deepscan(program: String, args: PackedStringArray, result: TermResult) -> void:
	var target: String = _t.session.target_id()
	if target.is_empty():
		result.add(NetResult.fail(NetResult.Code.NO_TARGET).message())
		return
	var service: String = _pick_service(target, "passhound", args, result)
	if service.is_empty():
		return
	if str(_t.net.service(target, service).get("puzzle", "")) != "password":
		result.add("%s работает только против пароля" % program)
		return

	# Три буквы остаются неизвестными всегда (puzzles-spec.md). Если открыто всё, что можно,
	# честно говорим об этом и не тратим время: иначе игрок платил бы за символ, которого нет.
	var key: String = VAR_DEEPSCAN_PREFIX + target + "." + service
	var opened: int = int(GameState.get_var_or(key, 0))
	var config: Dictionary = PuzzleLevels.password(_puzzle_level(target, service))
	var most: int = int(config["length"]) - int(config.get("min_unknown", 3))
	if int(config["known"]) + opened >= most:
		result.add("%s: больше символов здесь не открыть, три останутся неизвестными" % program)
		return

	GameState.set_var(key, opened + 1)
	result.add("%s: открыт ещё один символ пароля (сервис %s)" % [program, service])
	# Разведка трейс не запускает, но время идёт, а если трейс уже идёт — он тикает.
	_t.spend(Programs.minutes_for(program), result)


# --- Автоматические программы ------------------------------------------------

func _rootstep(result: TermResult) -> void:
	if not _t.is_remote():
		result.add("права повышают на узле: сначала connect <адрес>")
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
		result.add("логи чистят на узле: сначала connect <адрес>")
		return
	result.add_all(PackedStringArray(LOGWIPE_LOG))
	result.request = {"type": "progress", "title": "logwipe"}
	var node: String = _t.node_id()
	_t.spend(Programs.minutes_for("logwipe"), result)
	if not _t.session.has_connection():
		return
	var removed: int = Logbook.for_node(node).clear()
	result.add("очищено записей: %d" % removed)
