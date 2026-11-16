class_name MatrixPuzzle
extends RefCounted
## «Матрица»: собрать последовательности (docs/tech/puzzles-spec.md, раздел 2).
## Идея — «протокол взлома» из Cyberpunk 2077, но правила и реализация свои.
##
## Правила:
## - сетка N×N символов из шести; буфер на `capacity` клеток;
## - нужно собрать S целевых последовательностей: цель считается собранной, если идёт в
##   буфере **подряд**; собирать можно в любом порядке и внахлёст;
## - первый ход — любая ячейка верхней строки; дальше ходы чередуются: из столбца предыдущей
##   ячейки, затем из её строки, снова из столбца… Выбранная ячейка недоступна;
## - **шумная** ячейка (наш твист) кладёт в буфер символ **и пустую помеху**. Помеха ничему
##   не соответствует и рвёт цепочку: цель может закончиться на шумной ячейке, но не пройти
##   через неё. Занимает две клетки буфера, поэтому при одной свободной клетке её не выбрать;
## - ходы кончились (буфер полон, собрано всё или некуда идти) — головоломка закончена:
##   каждая собранная цель — один вскрытый слой, все — вскрыт весь сервис, ни одной — провал.
##
## Решаемость гарантирует генерация: цели нарезаются из настоящего пути по правилам, а затем
## солвер меряет запас. Чистая логика без сцен; один сид — одна и та же головоломка.

const SYMBOLS: PackedStringArray = ["1C", "55", "7A", "BD", "E9", "FF"]
## Помеха от шумной ячейки в буфере: не совпадает ни с одним символом.
const JUNK: int = -1

var level: int = 2
var puzzle_seed: int = 0
var size: int = 5
var capacity: int = 8
## Символы по ячейкам (строка за строкой), индексы в SYMBOLS.
var grid: PackedInt32Array = PackedInt32Array()
## 1 — шумная ячейка.
var noise: PackedByteArray = PackedByteArray()
## Цели: массивы индексов символов.
var targets: Array = []
var metrics: Dictionary = {}
## Эталонное решение (ячейки по порядку): для отладки и отчёта, игроку не показывается.
var solution: PackedInt32Array = PackedInt32Array()

# Состояние партии.
var buffer: PackedInt32Array = PackedInt32Array()
var picks: PackedInt32Array = PackedInt32Array()
var _used: PackedByteArray = PackedByteArray()


# --- Партия ------------------------------------------------------------------

func cell_of(row: int, col: int) -> int:
	return row * size + col


func symbol_name(cell: int) -> String:
	return SYMBOLS[grid[cell]]


func is_noisy(cell: int) -> bool:
	return noise[cell] == 1


func is_used(cell: int) -> bool:
	return _used[cell] == 1


func legal_moves() -> PackedInt32Array:
	var last: int = picks[picks.size() - 1] if not picks.is_empty() else -1
	return legal_cells(size, picks.size(), last, _used, noise, capacity - buffer.size())


## Выбрать ячейку. Возвращает {"ok": принят ли ход, "finished": партия закончена, "layers": сколько целей собрано}.
func pick(cell: int) -> Dictionary:
	var allowed: PackedInt32Array = legal_moves()
	if not allowed.has(cell):
		return {"ok": false, "finished": is_finished(), "layers": layers()}
	_used[cell] = 1
	picks.append(cell)
	buffer.append(grid[cell])
	if is_noisy(cell):
		buffer.append(JUNK)
	return {"ok": true, "finished": is_finished(), "layers": layers()}


## Какие цели уже собраны в буфере.
func collected() -> Array[bool]:
	var result: Array[bool] = []
	for target: Variant in targets:
		result.append(contains_run(buffer, target as PackedInt32Array))
	return result


func layers() -> int:
	var count: int = 0
	for done: bool in collected():
		if done:
			count += 1
	return count


func is_finished() -> bool:
	return buffer.size() >= capacity or layers() == targets.size() or legal_moves().is_empty() or is_hopeless()


## Тупик: ни одна цепочка ходов из этого положения не соберёт больше целей, чем собрано.
## Партия кончается сразу, а не после того, как игрок дозаполнит буфер зря.
func is_hopeless() -> bool:
	var goal: int = layers()
	if goal >= targets.size():
		return false
	# Раунд (одна цель, буфер ровно под неё): тупик — только когда игрок сам поставил не тот байт.
	# Заглядывать вперёд нельзя: «нужного байта нет в следующем ряду» игрок должен увидеть сам и
	# ошибиться, а не получить поражение до хода (разработчик, 16.11.2026).
	if targets.size() == 1 and capacity == (targets[0] as PackedInt32Array).size():
		var target: PackedInt32Array = targets[0] as PackedInt32Array
		for index: int in buffer.size():
			if buffer[index] != target[index]:
				return true
		return false
	return not _can_collect_more(buffer, _used, picks.size(), picks[picks.size() - 1] if not picks.is_empty() else -1, goal)


func _collected_in(sequence: PackedInt32Array) -> int:
	var count: int = 0
	for target: Variant in targets:
		if contains_run(sequence, target as PackedInt32Array):
			count += 1
	return count


## Перебор оставшихся ходов; глубина ограничена свободными клетками буфера, поэтому он быстрый.
func _can_collect_more(
	sequence: PackedInt32Array, used: PackedByteArray, made: int, last: int, goal: int
) -> bool:
	var left: int = capacity - sequence.size()
	for cell: int in legal_cells(size, made, last, used, noise, left):
		var next: PackedInt32Array = sequence.duplicate()
		next.append(grid[cell])
		if noise[cell] == 1:
			next.append(JUNK)
		if _collected_in(next) > goal:
			return true
		var next_used: PackedByteArray = used.duplicate()
		next_used[cell] = 1
		if _can_collect_more(next, next_used, made + 1, cell, goal):
			return true
	return false


# --- Правила: общие для партии и солвера --------------------------------------

## Ячейки, которые можно выбрать следующим ходом. `picks` — сколько ходов уже сделано,
## `last` — последняя выбранная ячейка (-1, если ходов не было), `slots_left` — свободных клеток буфера.
static func legal_cells(
	size: int, picks: int, last: int, used: PackedByteArray, noise: PackedByteArray, slots_left: int
) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	if slots_left <= 0:
		return result

	var line: PackedInt32Array = PackedInt32Array()
	if picks == 0:
		for col: int in size:
			line.append(col)
	elif picks % 2 == 1:
		var column: int = last % size
		for row: int in size:
			line.append(row * size + column)
	else:
		var row_start: int = (last / size) * size
		for col: int in size:
			line.append(row_start + col)

	for cell: int in line:
		if used[cell] == 1:
			continue
		# Шумной ячейке нужны две свободные клетки: символ и помеха.
		if noise[cell] == 1 and slots_left < 2:
			continue
		result.append(cell)
	return result


## Заканчивается ли буфер этой целью — так цель замечается в момент последнего символа.
static func tail_matches(buffer: PackedInt32Array, target: PackedInt32Array) -> bool:
	var length: int = target.size()
	if buffer.size() < length:
		return false
	var offset: int = buffer.size() - length
	for index: int in length:
		if buffer[offset + index] != target[index]:
			return false
	return true


## Есть ли цель в буфере подряд, где угодно.
static func contains_run(buffer: PackedInt32Array, target: PackedInt32Array) -> bool:
	var length: int = target.size()
	for start: int in range(0, buffer.size() - length + 1):
		var fits: bool = true
		for index: int in length:
			if buffer[start + index] != target[index]:
				fits = false
				break
		if fits:
			return true
	return false


# --- Генерация ---------------------------------------------------------------

## Параметры одного раунда: одна цель и буфер ровно по её длине, без запаса. Так цепочка обязана
## идти по цели с первого хода, и неверный ход — тупик сразу (docs/tech/puzzles-spec.md).
## Сложность даёт длина цели, размер сетки и шумные ячейки (обход помех — часть задачи).
static func round_params(game_level: int) -> Dictionary:
	var params: Dictionary = PuzzleLevels.matrix(game_level)
	var length: int = int(params["seq_max"])
	params["sequences"] = 1
	params["seq_min"] = length
	params["seq_max"] = length
	params["buffer"] = length
	params["slack"] = [0, 0]
	return params


static func generate_round(game_level: int, seed_value: int, index: int) -> MatrixPuzzle:
	return generate(game_level, ("round:%d:%d" % [seed_value, index]).hash(), round_params(game_level))


## Головоломка по уровню и сиду. `params` — параметры вместо тех, что в balance.json.
## Если за отведённые попытки подходящей не нашлось, отдаёт наименее плохую с пометкой.
static func generate(game_level: int, seed_value: int, params: Dictionary = {}) -> MatrixPuzzle:
	var config: Dictionary = params if not params.is_empty() else PuzzleLevels.matrix(game_level)
	var tries: int = maxi(1, int(config.get("max_tries", 60)))
	var best: MatrixPuzzle = null
	var best_gap: float = INF

	for attempt: int in tries:
		var sub_seed: int = ("%d:%d" % [seed_value, attempt]).hash()
		var puzzle: MatrixPuzzle = _roll(game_level, seed_value, sub_seed, config)
		if puzzle == null:
			continue
		var gap: float = puzzle._measure(config)
		if gap == 0.0:
			puzzle.metrics["accepted"] = true
			puzzle.metrics["tries"] = attempt + 1
			return puzzle
		if gap < best_gap:
			best = puzzle
			best_gap = gap

	if best == null:
		# Совсем не вышло собрать путь (так бывает при безумных параметрах): последняя
		# попытка без отбора, чтобы вызывающий всё равно получил рабочую головоломку.
		best = _roll(game_level, seed_value, seed_value, config)
		if best != null:
			best._measure(config)
	best.metrics["accepted"] = false
	best.metrics["tries"] = tries
	return best


static func _roll(
	game_level: int, seed_value: int, sub_seed: int, config: Dictionary
) -> MatrixPuzzle:
	var rng: RandomNumberGenerator = Rng.fixed(sub_seed)
	var puzzle := MatrixPuzzle.new()
	puzzle.level = game_level
	puzzle.puzzle_seed = seed_value
	puzzle.size = int(config["size"])
	puzzle.capacity = int(config["buffer"])
	var cells: int = puzzle.size * puzzle.size

	puzzle.grid.resize(cells)
	for cell: int in cells:
		puzzle.grid[cell] = rng.randi_range(0, SYMBOLS.size() - 1)
	puzzle.noise.resize(cells)
	puzzle.noise.fill(0)
	puzzle._used.resize(cells)
	puzzle._used.fill(0)

	# Шумные ячейки: случайные, без повторов.
	var order: Array = range(cells)
	_shuffle(order, rng)
	for index: int in mini(int(config["noise"]), cells):
		puzzle.noise[int(order[index])] = 1

	# Путь-решение по настоящим правилам, до заполнения буфера.
	var path: PackedInt32Array = puzzle._random_path(rng)

	# Цели нарезаем из той части пути, которая укладывается в «нужный запас»: запас задаёт
	# сложность, и мы целимся в него, а солвер потом проверяет, что вышло.
	var slack_range: Array = config.get("slack", [0, 0]) as Array
	var wanted_slack: int = rng.randi_range(int(slack_range[0]), int(slack_range[1]))
	if not puzzle._cut_targets(path, puzzle.capacity - wanted_slack, config, rng):
		return null
	return puzzle


## Случайный путь по правилам хода, пока не заполнится буфер или не кончатся ходы.
func _random_path(rng: RandomNumberGenerator) -> PackedInt32Array:
	var path: PackedInt32Array = PackedInt32Array()
	var used: PackedByteArray = PackedByteArray()
	used.resize(size * size)
	used.fill(0)
	var slots: int = 0
	var last: int = -1
	while slots < capacity:
		var options: PackedInt32Array = legal_cells(size, path.size(), last, used, noise, capacity - slots)
		if options.is_empty():
			break
		var cell: int = options[rng.randi_range(0, options.size() - 1)]
		path.append(cell)
		used[cell] = 1
		slots += 2 if noise[cell] == 1 else 1
		last = cell
	return path


## Нарезать цели из пути. `span_slots` — сколько клеток буфера должны занять цели вместе:
## первая цель начинается с начала пути, последняя заканчивается там, где кончается эта длина.
## Цель не может идти через шумную ячейку (помеха рвёт цепочку), только заканчиваться на ней.
func _cut_targets(
	path: PackedInt32Array, span_slots: int, config: Dictionary, rng: RandomNumberGenerator
) -> bool:
	# Сколько ходов пути умещается в span_slots.
	var usable: int = 0
	var slots: int = 0
	for cell: int in path:
		var cost: int = 2 if noise[cell] == 1 else 1
		if slots + cost > span_slots:
			break
		slots += cost
		usable += 1

	var count: int = int(config["sequences"])
	var seq_min: int = int(config["seq_min"])
	var seq_max: int = int(config["seq_max"])
	if usable < seq_min:
		return false

	targets.clear()
	var seen: Dictionary = {}
	for index: int in count:
		var placed: bool = false
		for _try: int in 40:
			var length: int = rng.randi_range(seq_min, mini(seq_max, usable))
			# Первая цель — с начала пути, последняя — до конца: так занято всё нужное место.
			var start: int = rng.randi_range(0, usable - length)
			if index == 0:
				start = 0
			elif index == count - 1:
				start = usable - length
			if _crosses_noise(path, start, length):
				continue
			var target: PackedInt32Array = PackedInt32Array()
			var key: String = ""
			for step: int in length:
				var symbol: int = grid[path[start + step]]
				target.append(symbol)
				key += str(symbol) + ","
			if seen.has(key):
				continue
			seen[key] = true
			targets.append(target)
			placed = true
			break
		if not placed:
			return false
	return true


## Идёт ли цель через шумную ячейку: помеха стоит после символа и разорвала бы цепочку.
## Шумной может быть только последняя ячейка цели.
func _crosses_noise(path: PackedInt32Array, start: int, length: int) -> bool:
	for step: int in length - 1:
		if noise[path[start + step]] == 1:
			return true
	return false


## Считает метрики солвером и возвращает «расстояние до допустимого»: 0 — подходит.
func _measure(config: Dictionary) -> float:
	var result: Dictionary = MatrixSolver.analyze(
		self, int(config.get("solutions_cap", 200)), int(config.get("nodes_cap", 20000))
	)
	solution = result["path"] as PackedInt32Array
	metrics = {
		"solvable": result["solvable"],
		"min_moves": result["min_moves"],
		"slack": result["slack"],
		"solutions_count": result["solutions_count"],
		"nodes_explored": result["nodes_explored"],
		"truncated": result["truncated"],
	}
	if not bool(result["solvable"]):
		metrics["score"] = 0.0
		return 1000.0

	var solutions: int = maxi(int(result["solutions_count"]), 1)
	metrics["score"] = -float(result["slack"]) + log(float(result["nodes_explored"])) - log(float(solutions))

	var bounds: Array = config.get("slack", [0, 100]) as Array
	var slack: int = int(result["slack"])
	var gap: float = 0.0
	if slack < int(bounds[0]):
		gap += float(int(bounds[0]) - slack)
	if slack > int(bounds[1]):
		gap += float(slack - int(bounds[1]))
	return gap


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(items.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var swap: Variant = items[index]
		items[index] = items[other]
		items[other] = swap
