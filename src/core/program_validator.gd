class_name ProgramValidator
extends RefCounted
## Проверка описаний программ (`data/programs.json`, docs/tech/terminal-spec.md).
## Вынесено из Validator отдельным файлом: один файл — одна ответственность.

## Автоматические программы, у которых есть обработчик в терминале. Новая `auto`-программа без
## обработчика ничего не сделает, поэтому валидатор об этом предупреждает.
const AUTO_HANDLERS: PackedStringArray = ["rootstep", "logwipe"]

var errors: PackedStringArray = []
var warnings: PackedStringArray = []


func validate(programs: Dictionary, balance: Dictionary) -> void:
	errors.clear()
	warnings.clear()
	var costs: Dictionary = balance.get("action_minutes", {}) as Dictionary

	var found: int = 0
	for id: String in programs.keys():
		if id.begins_with("_"):
			continue
		found += 1
		_check_program(id, programs[id] as Dictionary, costs)
	if found == 0:
		errors.append("data/programs.json не найден или пустой: герою нечего запускать")


func _check_program(id: String, program: Dictionary, costs: Dictionary) -> void:
	var where: String = "программа " + id
	var kind: String = str(program.get("kind", ""))
	if not Programs.KINDS.has(kind):
		errors.append("%s: неизвестный kind '%s' (есть: %s)" % [where, kind, ", ".join(Programs.KINDS)])

	if kind == Programs.KIND_CRACKER:
		var puzzle: String = str(program.get("puzzle", ""))
		if not NodeValidator.PUZZLE_TYPES.has(puzzle):
			errors.append("%s: у взломщика нет известного типа головоломки (puzzle = '%s')" % [where, puzzle])
	if kind == Programs.KIND_AUTO and not AUTO_HANDLERS.has(id):
		warnings.append("%s: автоматическая программа без обработчика в терминале — запуск ничего не сделает" % where)

	var minutes: String = str(program.get("minutes", ""))
	if minutes.is_empty() or not costs.has(minutes):
		errors.append("%s: нет ключа времени '%s' в balance.json, action_minutes" % [where, minutes])
	if str(program.get("about", "")).is_empty():
		warnings.append("%s: нет строки about для help и progs" % where)

	if not program.has("requires"):
		warnings.append("%s: нет поля requires (пустой список, если требований нет)" % where)
		return
	if not (program["requires"] is Array):
		errors.append("%s: requires должен быть списком условий" % where)
		return
	for condition: Variant in program["requires"] as Array:
		if not (condition is Dictionary):
			errors.append("%s: условие в requires должно быть объектом" % where)
			continue
		for type: String in (condition as Dictionary).keys():
			if not Conditions.is_known(type):
				errors.append("%s: неизвестный тип условия '%s' в requires" % [where, type])
