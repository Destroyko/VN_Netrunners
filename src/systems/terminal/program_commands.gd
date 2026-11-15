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

	var definition: Dictionary = _t.net.service(target, service)
	var difficulty: int = _t.net.effective_difficulty(target, int(definition.get("difficulty", 1)))
	var kind: String = Programs.puzzle_of(program)
	_t.set_puzzle({"service": service, "kind": kind, "difficulty": difficulty, "node": target})
	result.request = {
		"type": "puzzle", "kind": kind, "node": target, "service": service,
		"difficulty": difficulty, "alert": _t.net.alert_level(target),
		"extra_symbols": int(GameState.get_var_or(VAR_DEEPSCAN_PREFIX + target + "." + service, 0)),
	}


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

	var key: String = VAR_DEEPSCAN_PREFIX + target + "." + service
	GameState.set_var(key, int(GameState.get_var_or(key, 0)) + 1)
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
