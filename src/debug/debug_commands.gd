class_name DebugCommands
extends RefCounted
## Разбор и выполнение команд отладочной консоли.
##
## Чистая логика без сцен: команду можно проверить тестом, не запуская игру.
## Интерфейс консоли (src/debug/debug_console.gd) только передаёт строку сюда
## и показывает ответ.

## Список команд: имя → краткая справка. Используется и в help, и в автодополнении.
const HELP: Dictionary = {
	"help": "help — список команд",
	"state": "state — текущее состояние: деньги, заметность, время, сложность, сид",
	"flags": "flags [часть_имени] — поставленные флаги",
	"set_flag": "set_flag <имя> [0|1] — поставить или снять флаг",
	"money": "money <±сколько> | money =<значение> — изменить или задать деньги",
	"heat": "heat <±сколько> | heat =<значение> — изменить или задать заметность",
	"sleep": "sleep [ночей] — выспать ночи: заметность спадает (по умолчанию одна)",
	"time": "time | time +<минут> | time <день> <чч:мм> — показать, продвинуть или перевести время",
	"seed": "seed [значение] — показать или задать сид случайности",
	"effect": "effect <json> — применить эффект, например: effect {\"money\": 500}",
	"cond": "cond <json> — проверить условие, например: cond {\"flag\": \"story.x\"}",
	"quest": "quest <id> <этап> — перевести квест на этап",
	"play": "play <password|matrix|dump> [уровень 2-4] [сид] — открыть головоломку окном без взлома (на рабочем столе)",
	"puzzle": "puzzle <password|matrix> <уровень 2-4> <сид> — сгенерировать головоломку: метрики и эталонное решение",
}


## Выполнить строку команды. Возвращает текст для вывода в консоль.
static func run(line: String) -> String:
	var text: String = line.strip_edges()
	if text.is_empty():
		return ""

	var parts: PackedStringArray = text.split(" ", false)
	var command: String = parts[0].to_lower()
	# Аргументы как одна строка: нужно для JSON, внутри которого есть пробелы.
	var rest: String = text.substr(parts[0].length()).strip_edges()
	var args: PackedStringArray = parts.slice(1)

	match command:
		"help":
			return _help()
		"state":
			return _state()
		"flags":
			return _flags(rest)
		"set_flag":
			return _set_flag(args)
		"money":
			return _change_number(args, "money")
		"heat":
			return _change_number(args, "heat")
		"sleep":
			return _sleep(args)
		"time":
			return _time(args)
		"seed":
			return _seed(args)
		"effect":
			return _effect(rest)
		"cond":
			return _cond(rest)
		"quest":
			return _quest(args)
		"puzzle":
			return _puzzle(args)
		"play":
			return "play работает только на рабочем столе (консоль F1 в окне стола)"
		_:
			return "неизвестная команда '%s'. help — список команд" % command


## Для автодополнения в консоли.
static func names() -> PackedStringArray:
	var result: PackedStringArray = []
	for name: String in HELP.keys():
		result.append(name)
	result.sort()
	return result


# --- Команды -----------------------------------------------------------------

static func _help() -> String:
	var lines: PackedStringArray = []
	for name: String in names():
		lines.append("  " + str(HELP[name]))
	return "Команды:\n" + "\n".join(lines)


static func _state() -> String:
	return "\n".join([
		"%s (%s)" % [Clock.format_time(), Clock.time_of_day()],
		"деньги: %d" % GameState.money,
		"заметность: %d" % GameState.heat,
		"сложность: %d" % int(GameState.difficulty),
		"сид: %d" % Rng.get_seed(),
		"флагов поставлено: %d" % GameState.get_flags().size(),
	])


static func _flags(filter: String) -> String:
	var names_found: PackedStringArray = []
	for flag: String in GameState.get_flags().keys():
		if filter.is_empty() or flag.contains(filter):
			names_found.append(flag)
	if names_found.is_empty():
		return "флагов нет"
	names_found.sort()
	return "\n".join(names_found)


static func _set_flag(args: PackedStringArray) -> String:
	if args.is_empty():
		return "нужно имя флага: " + str(HELP["set_flag"])
	var flag: String = args[0]
	var value: bool = true
	if args.size() > 1:
		value = args[1] != "0" and args[1].to_lower() != "false"
	GameState.set_flag(flag, value)
	return "%s = %s" % [flag, value]


## money и heat: "+50" / "-50" меняют, "=50" задаёт.
static func _change_number(args: PackedStringArray, what: String) -> String:
	if args.is_empty():
		var current: int = GameState.money if what == "money" else GameState.heat
		return "%s: %d" % [what, current]

	var arg: String = args[0]
	var absolute: bool = arg.begins_with("=")
	var raw: String = arg.trim_prefix("=")
	if not raw.lstrip("+-").is_valid_int():
		return "нужно число, получено '%s'" % arg
	var value: int = int(raw)

	if what == "money":
		if absolute:
			GameState.set_money(value)
		else:
			GameState.add_money(value)
		return "деньги: %d" % GameState.money

	if absolute:
		GameState.set_heat(value)
	else:
		GameState.add_heat(value)
	return "заметность: %d" % GameState.heat


static func _time(args: PackedStringArray) -> String:
	if args.is_empty():
		return "%s (%s)" % [Clock.format_time(), Clock.time_of_day()]

	# time +90 — именно продвинуть время: сработают события дня и триггеры.
	if args[0].begins_with("+"):
		var minutes: String = args[0].trim_prefix("+")
		if not minutes.is_valid_int():
			return "нужно число минут, получено '%s'" % args[0]
		Clock.advance(int(minutes))
		return "прошло %s минут → %s" % [minutes, Clock.format_time()]

	# time 5 14:30 — перевести стрелки, событий не будет.
	if args.size() < 2 or not args[0].is_valid_int():
		return str(HELP["time"])
	var clock_parts: PackedStringArray = args[1].split(":")
	if clock_parts.size() != 2 or not clock_parts[0].is_valid_int() or not clock_parts[1].is_valid_int():
		return "время задаётся как чч:мм, получено '%s'" % args[1]
	Clock.set_time(int(args[0]), int(clock_parts[0]) * 60 + int(clock_parts[1]))
	return "время переведено: " + Clock.format_time()


static func _seed(args: PackedStringArray) -> String:
	if args.is_empty():
		return "сид: %d" % Rng.get_seed()
	if not args[0].lstrip("-").is_valid_int():
		return "нужно число, получено '%s'" % args[0]
	Rng.set_seed(int(args[0]))
	return "сид: %d" % Rng.get_seed()


static func _effect(json_text: String) -> String:
	# JSON.new().parse(), а не parse_string(): второй шлёт ошибку в движок,
	# и тесты падают на заведомо битом вводе. Плюс здесь видно, что именно не так.
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return "не разобрал JSON: %s. Пример: effect {\"money\": 500}" % json.get_error_message()
	if json.data is not Dictionary:
		return "нужен объект JSON, например: effect {\"money\": 500}"
	var effect: Dictionary = json.data as Dictionary
	for type: String in effect.keys():
		if not Effects.is_known(type):
			return "неизвестный эффект '%s'" % type
		if not Effects.is_implemented(type):
			return "эффект '%s' ещё не реализован" % type
	Effects.apply(effect)
	return "применено: " + json_text


static func _cond(json_text: String) -> String:
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return "не разобрал JSON: %s. Пример: cond {\"flag\": \"story.x\"}" % json.get_error_message()
	if json.data is not Dictionary:
		return "нужен объект JSON, например: cond {\"flag\": \"story.x\"}"
	var condition: Dictionary = json.data as Dictionary
	for type: String in condition.keys():
		if not Conditions.is_known(type):
			return "неизвестное условие '%s'" % type
	return "%s → %s" % [json_text, Conditions.check(condition)]


static func _quest(args: PackedStringArray) -> String:
	if args.size() < 2:
		return str(HELP["quest"])
	GameState.set_quest_stage(args[0], args[1])
	return "%s: этап %s" % [args[0], args[1]]


## Песочница головоломок (docs/tech/puzzles-spec.md): тип, уровень, сид → описание, метрики и
## эталонное решение. Играть в неё тут нельзя, зато видно, что получилось и почему.
static func _puzzle(args: PackedStringArray) -> String:
	if args.size() < 3:
		return "нужно: " + str(HELP["puzzle"])
	var kind: String = args[0].to_lower()
	if kind != "password" and kind != "matrix":
		return "тип — password или matrix, получено '%s'" % args[0]
	if not args[1].is_valid_int() or not args[2].is_valid_int():
		return "уровень и сид — числа: " + str(HELP["puzzle"])
	var level: int = int(args[1])
	if level < PuzzleLevels.MIN_LEVEL or level > PuzzleLevels.MAX_LEVEL:
		return "уровень от %d до %d (первый — сюжетный, там головоломок нет)" % [PuzzleLevels.MIN_LEVEL, PuzzleLevels.MAX_LEVEL]
	return PuzzleReport.describe(kind, level, int(args[2]))


## Выспать ночи. Системы сна пока нет, поэтому это единственный способ спада заметности руками.
static func _sleep(args: PackedStringArray) -> String:
	var nights: int = 1
	if args.size() > 0:
		if not args[0].is_valid_int() or int(args[0]) < 1:
			return "sleep: нужно целое число ночей от 1"
		nights = int(args[0])
	var before: int = GameState.heat
	EventBus.slept.emit(nights)
	return "заметность: %d (было %d)" % [GameState.heat, before]
