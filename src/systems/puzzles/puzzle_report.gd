class_name PuzzleReport
extends RefCounted
## Отчёт и песочница по головоломкам (docs/tech/puzzles-spec.md, «Инструменты»).
##
## - `run()` — сгенерировать N головоломок на уровень и собрать распределение метрик: доля принятых,
##   число попыток отбора, время генерации. По этим цифрам калибруются диапазоны в balance.json.
##   Запуск из командной строки: `godot --headless -s tools/puzzle_report.gd -- count=1000`;
## - `describe()` — показать одну головоломку вместе с метриками и эталонным решением. Это то, что
##   отвечает консоль разработчика на `puzzle <тип> <уровень> <сид>`.
##
## Всё чистая логика: в отчёте нет сцен, а случайность — только через сид.

const LEVELS: Array[int] = [2, 3, 4]
const PASSWORD_COLUMNS: PackedStringArray = [
	"candidates_after_hints", "solver_attempts_avg", "solver_attempts_worst", "word_rarity", "score",
]
const MATRIX_COLUMNS: PackedStringArray = [
	"min_moves", "slack", "solutions_count", "nodes_explored", "score",
]


## Прогнать `count` сидов на каждый уровень. Возвращает {"csv": текст, "summary": строки}.
static func run(count: int, first_seed: int = 1) -> Dictionary:
	var csv: PackedStringArray = ["kind,level,seed,accepted,tries,ms,%s" % ",".join(_all_columns())]
	var summary: PackedStringArray = []

	for kind: String in ["password", "matrix"]:
		for level: int in LEVELS:
			var rows: Array[Dictionary] = []
			for index: int in count:
				rows.append(_one(kind, level, first_seed + index))
			for row: Dictionary in rows:
				csv.append(_csv_row(kind, level, row))
			summary.append_array(_summarise(kind, level, rows))

	return {"csv": "\n".join(csv) + "\n", "summary": summary}


static func _one(kind: String, level: int, seed_value: int) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var puzzle: RefCounted
	if kind == "password":
		puzzle = PasswordPuzzle.generate(level, seed_value)
	else:
		puzzle = MatrixPuzzle.generate(level, seed_value)
	var metrics: Dictionary = (puzzle.get("metrics") as Dictionary).duplicate()
	metrics["seed"] = seed_value
	metrics["ms"] = float(Time.get_ticks_usec() - started) / 1000.0
	return metrics


static func _all_columns() -> PackedStringArray:
	var columns: PackedStringArray = []
	for name: String in PASSWORD_COLUMNS:
		columns.append("pw_" + name)
	for name: String in MATRIX_COLUMNS:
		columns.append("mx_" + name)
	return columns


static func _csv_row(kind: String, level: int, row: Dictionary) -> String:
	var cells: PackedStringArray = [
		kind, str(level), str(row["seed"]), str(bool(row.get("accepted", false))),
		str(row.get("tries", 0)), "%.1f" % float(row["ms"]),
	]
	var own: PackedStringArray = PASSWORD_COLUMNS if kind == "password" else MATRIX_COLUMNS
	for name: String in PASSWORD_COLUMNS:
		cells.append(_cell(row, name) if own == PASSWORD_COLUMNS else "")
	for name: String in MATRIX_COLUMNS:
		cells.append(_cell(row, name) if own == MATRIX_COLUMNS else "")
	return ",".join(cells)


static func _cell(row: Dictionary, name: String) -> String:
	var value: Variant = row.get(name, "")
	return "%.3f" % float(value) if value is float else str(value)


static func _summarise(kind: String, level: int, rows: Array[Dictionary]) -> PackedStringArray:
	var accepted: int = 0
	var tries_sum: int = 0
	var ms_sum: float = 0.0
	var ms_max: float = 0.0
	for row: Dictionary in rows:
		accepted += 1 if bool(row.get("accepted", false)) else 0
		tries_sum += int(row.get("tries", 0))
		ms_sum += float(row["ms"])
		ms_max = maxf(ms_max, float(row["ms"]))

	var total: int = maxi(rows.size(), 1)
	var lines: PackedStringArray = [
		"%s, уровень %d: принято %d из %d (%.0f%%), попыток отбора в среднем %.1f, генерация в среднем %.1f мс, максимум %.1f мс" % [
			kind, level, accepted, rows.size(), 100.0 * float(accepted) / float(total),
			float(tries_sum) / float(total), ms_sum / float(total), ms_max,
		]
	]
	for name: String in (PASSWORD_COLUMNS if kind == "password" else MATRIX_COLUMNS):
		lines.append("    %-24s %s" % [name, _distribution(rows, name)])
	return lines


## «мин / среднее / медиана / макс» по одной метрике.
static func _distribution(rows: Array[Dictionary], name: String) -> String:
	var values: Array[float] = []
	for row: Dictionary in rows:
		if row.has(name):
			values.append(float(row[name]))
	if values.is_empty():
		return "нет данных"
	values.sort()
	var sum: float = 0.0
	for value: float in values:
		sum += value
	return "мин %.2f / среднее %.2f / медиана %.2f / макс %.2f" % [
		values[0], sum / float(values.size()), values[values.size() / 2], values[values.size() - 1]
	]


# --- Песочница ---------------------------------------------------------------

## Сгенерировать одну головоломку и описать её: для консоли разработчика.
static func describe(kind: String, level: int, seed_value: int) -> String:
	if kind == "password":
		return _describe_password(PasswordPuzzle.generate(level, seed_value))
	return _describe_matrix(MatrixPuzzle.generate(level, seed_value))


static func _describe_password(puzzle: PasswordPuzzle) -> String:
	var lines: PackedStringArray = [
		"«пароль», уровень %d, сид %d" % [puzzle.level, puzzle.puzzle_seed],
		"длина %d, попыток %d, открыто: %s" % [puzzle.length, puzzle.max_attempts, puzzle.pattern()],
		"загадано: %s" % puzzle.word,
		"лучший первый ход солвера: %s" % str(puzzle.metrics["first_guess"]),
	]
	lines.append_array(_metric_lines(puzzle.metrics))
	return "\n".join(lines)


static func _describe_matrix(puzzle: MatrixPuzzle) -> String:
	var lines: PackedStringArray = [
		"«матрица», уровень %d, сид %d" % [puzzle.level, puzzle.puzzle_seed],
		"сетка %d×%d, буфер %d, шумные ячейки помечены звёздочкой" % [puzzle.size, puzzle.size, puzzle.capacity],
	]
	for row: int in puzzle.size:
		var cells: PackedStringArray = []
		for col: int in puzzle.size:
			var cell: int = puzzle.cell_of(row, col)
			cells.append(puzzle.symbol_name(cell) + ("*" if puzzle.is_noisy(cell) else " "))
		lines.append("  " + " ".join(cells))

	var goals: PackedStringArray = []
	for target: PackedInt32Array in puzzle.targets:
		var names: PackedStringArray = []
		for symbol: int in target:
			names.append(MatrixPuzzle.SYMBOLS[symbol])
		goals.append(" ".join(names))
	lines.append("цели: " + "  |  ".join(goals))

	var path: PackedStringArray = []
	for cell: int in puzzle.solution:
		path.append("(%d,%d)" % [cell / puzzle.size + 1, cell % puzzle.size + 1])
	lines.append("эталонное решение (строка,столбец): " + " ".join(path))
	lines.append_array(_metric_lines(puzzle.metrics))
	return "\n".join(lines)


static func _metric_lines(metrics: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	for name: String in metrics.keys():
		if name == "first_guess":
			continue
		var value: Variant = metrics[name]
		lines.append("  %-24s %s" % [name, ("%.3f" % float(value)) if value is float else str(value)])
	return lines
