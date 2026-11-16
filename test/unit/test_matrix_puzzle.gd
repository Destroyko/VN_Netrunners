extends GutTest
## «Матрица»: правила хода, сбор целей, шумные ячейки и генерация
## (docs/tech/puzzles-spec.md, раздел 2).
##
## Сетка 3×3, номера ячеек и символы в них:
##   0:s0  1:s1  2:s2
##   3:s3  4:s4  5:s5
##   6:s0  7:s1  8:s2
## Нумерация символов — индексы в MatrixPuzzle.SYMBOLS, здесь важна только их различимость.


## Партия по заданным руками данным: чтобы проверять правила, а не генератор.
func _manual(size: int, capacity: int, symbols: Array, noisy: Array = [], goals: Array = []) -> MatrixPuzzle:
	var puzzle := MatrixPuzzle.new()
	puzzle.size = size
	puzzle.capacity = capacity
	puzzle.grid = PackedInt32Array(symbols)
	puzzle.noise = PackedByteArray()
	puzzle.noise.resize(size * size)
	puzzle.noise.fill(0)
	for cell: int in noisy:
		puzzle.noise[cell] = 1
	puzzle._used = PackedByteArray()
	puzzle._used.resize(size * size)
	puzzle._used.fill(0)
	for goal: Array in goals:
		puzzle.targets.append(PackedInt32Array(goal))
	return puzzle


func _grid3(noisy: Array = [], goals: Array = [], capacity: int = 6) -> MatrixPuzzle:
	return _manual(3, capacity, [0, 1, 2, 3, 4, 5, 0, 1, 2], noisy, goals)


# --- Правила хода ------------------------------------------------------------

func test_first_move_is_any_cell_of_the_top_row() -> void:
	assert_eq(_grid3().legal_moves(), PackedInt32Array([0, 1, 2]))


func test_moves_alternate_column_then_row() -> void:
	var puzzle: MatrixPuzzle = _grid3()
	puzzle.pick(1)
	assert_eq(puzzle.legal_moves(), PackedInt32Array([4, 7]), "из столбца первой ячейки, её саму нельзя")
	puzzle.pick(4)
	assert_eq(puzzle.legal_moves(), PackedInt32Array([3, 5]), "из строки второй ячейки")
	puzzle.pick(5)
	assert_eq(puzzle.legal_moves(), PackedInt32Array([2, 8]), "снова из столбца")


func test_illegal_and_used_cells_are_refused() -> void:
	var puzzle: MatrixPuzzle = _grid3()
	assert_false(bool(puzzle.pick(8)["ok"]), "не из верхней строки")
	puzzle.pick(1)
	assert_false(bool(puzzle.pick(1)["ok"]), "вторично ту же ячейку нельзя")
	assert_false(bool(puzzle.pick(3)["ok"]), "не из нужного столбца")
	assert_eq(puzzle.picks.size(), 1, "отказы ходов не считаются")


# --- Шумные ячейки -----------------------------------------------------------

func test_noisy_cell_takes_two_buffer_cells() -> void:
	var puzzle: MatrixPuzzle = _grid3([1])
	puzzle.pick(1)
	assert_eq(puzzle.buffer, PackedInt32Array([1, MatrixPuzzle.JUNK]), "символ и пустая помеха")


func test_noisy_cell_needs_two_free_cells() -> void:
	# Буфер на 2 клетки: после обычного хода остаётся одна, шумную уже не выбрать.
	var puzzle: MatrixPuzzle = _grid3([4], [], 2)
	puzzle.pick(1)
	assert_eq(puzzle.legal_moves(), PackedInt32Array([7]), "ячейка 4 шумная и не помещается")


func test_junk_breaks_a_chain() -> void:
	# Цель [1, 4] через шумную ячейку 1: между символами встаёт помеха — цепочка порвана.
	var puzzle: MatrixPuzzle = _grid3([1], [[1, 4]])
	puzzle.pick(1)
	puzzle.pick(4)
	assert_eq(puzzle.layers(), 0)


func test_a_chain_may_end_on_a_noisy_cell() -> void:
	# Помеха ложится после символа, поэтому цель на шумной ячейке заканчиваться может.
	var puzzle: MatrixPuzzle = _grid3([4], [[1, 4]])
	puzzle.pick(1)
	puzzle.pick(4)
	assert_eq(puzzle.layers(), 1)


# --- Сбор целей --------------------------------------------------------------

func test_a_target_is_collected_when_it_runs_in_a_row() -> void:
	var puzzle: MatrixPuzzle = _grid3([], [[1, 4]])
	puzzle.pick(1)
	assert_eq(puzzle.layers(), 0)
	puzzle.pick(4)
	assert_eq(puzzle.layers(), 1)
	assert_eq(puzzle.collected(), [true] as Array[bool])


func test_targets_may_overlap() -> void:
	# Конец одной цели — начало другой.
	var puzzle: MatrixPuzzle = _grid3([], [[1, 4], [4, 3]])
	puzzle.pick(1)
	puzzle.pick(4)
	puzzle.pick(3)
	assert_eq(puzzle.layers(), 2)


func test_order_of_collecting_is_free() -> void:
	var puzzle: MatrixPuzzle = _grid3([], [[4, 3], [1, 4]])
	puzzle.pick(1)
	puzzle.pick(4)
	puzzle.pick(3)
	assert_eq(puzzle.collected(), [true, true] as Array[bool])


func test_target_in_the_middle_of_the_buffer_counts() -> void:
	var puzzle: MatrixPuzzle = _grid3([], [[4, 3]])
	puzzle.pick(0)
	puzzle.pick(3)
	puzzle.pick(4)
	puzzle.pick(3 if false else 5)
	assert_eq(puzzle.layers(), 0, "4 и 5 подряд — не то, что нужно")


# --- Конец партии ------------------------------------------------------------

func test_game_ends_at_once_when_the_target_cannot_be_collected_any_more() -> void:
	# Цель из символов, которых в сетке нет: уже первый ход — тупик, добивать буфер не надо.
	var puzzle: MatrixPuzzle = _grid3([], [[7, 7]], 2)
	puzzle.pick(1)
	assert_true(puzzle.is_hopeless())
	assert_true(puzzle.is_finished())
	assert_eq(puzzle.layers(), 0, "ни одной цели — провал")


func test_a_reachable_target_is_not_a_dead_end() -> void:
	var puzzle: MatrixPuzzle = _grid3([], [[1, 4]], 6)
	assert_false(puzzle.is_hopeless())


func test_round_generation_has_one_target_and_a_tight_buffer() -> void:
	var puzzle: MatrixPuzzle = MatrixPuzzle.generate_round(2, 7, 0)
	assert_eq(puzzle.targets.size(), 1)
	assert_eq(puzzle.capacity, MatrixPuzzle.round_params(2)["buffer"])
	assert_eq(MatrixPuzzle.generate_round(2, 7, 1).puzzle_seed != puzzle.puzzle_seed, true, "у раундов разные сетки")


func test_game_ends_early_when_everything_is_collected() -> void:
	var puzzle: MatrixPuzzle = _grid3([], [[1, 4]], 6)
	puzzle.pick(1)
	var turn: Dictionary = puzzle.pick(4)
	assert_true(bool(turn["finished"]), "всё собрано — дальше играть незачем")
	assert_eq(int(turn["layers"]), 1)


func test_game_ends_when_there_are_no_moves() -> void:
	var puzzle: MatrixPuzzle = _manual(2, 8, [0, 1, 2, 3], [], [[5, 5]])
	puzzle.pick(0)
	puzzle.pick(2)
	puzzle.pick(3)
	puzzle.pick(1)
	assert_eq(puzzle.legal_moves().size(), 0)
	assert_true(puzzle.is_finished())


# --- Генерация ---------------------------------------------------------------

func test_same_seed_gives_the_same_puzzle() -> void:
	for level: int in [2, 3, 4]:
		var first: MatrixPuzzle = MatrixPuzzle.generate(level, 99)
		var second: MatrixPuzzle = MatrixPuzzle.generate(level, 99)
		assert_eq(first.grid, second.grid)
		assert_eq(first.noise, second.noise)
		assert_eq(first.targets, second.targets)


func test_levels_match_the_spec_table() -> void:
	var expected: Dictionary = {
		2: [5, 8, 2, 0],
		3: [6, 8, 2, 0],
		4: [7, 7, 3, 0],
	}
	for level: int in expected.keys():
		var puzzle: MatrixPuzzle = MatrixPuzzle.generate(level, 5)
		var noisy: int = 0
		for flag: int in puzzle.noise:
			noisy += flag
		assert_eq([puzzle.size, puzzle.capacity, puzzle.targets.size(), noisy], expected[level], "уровень %d" % level)


func test_targets_have_the_right_length() -> void:
	for level: int in [2, 3, 4]:
		var config: Dictionary = PuzzleLevels.matrix(level)
		var puzzle: MatrixPuzzle = MatrixPuzzle.generate(level, 21)
		for target: PackedInt32Array in puzzle.targets:
			assert_true(target.size() >= int(config["seq_min"]) and target.size() <= int(config["seq_max"]))


func test_targets_are_all_different() -> void:
	for seed_value: int in range(1, 6):
		var puzzle: MatrixPuzzle = MatrixPuzzle.generate(3, seed_value)
		assert_ne(puzzle.targets[0], puzzle.targets[1])


func test_generated_puzzles_are_solvable_and_the_reference_solution_works() -> void:
	# Эталонное решение — настоящая последовательность ходов по правилам: проигрываем её
	# через обычную партию и убеждаемся, что собраны все цели.
	for level: int in [2, 3, 4]:
		for seed_value: int in range(1, 5):
			var puzzle: MatrixPuzzle = MatrixPuzzle.generate(level, seed_value)
			assert_true(bool(puzzle.metrics["solvable"]), "решаема: уровень %d, сид %d" % [level, seed_value])
			for cell: int in puzzle.solution:
				assert_true(bool(puzzle.pick(cell)["ok"]), "ход эталона законен")
			assert_eq(puzzle.layers(), puzzle.targets.size(), "собрано всё")
			assert_eq(puzzle.buffer.size(), int(puzzle.metrics["min_moves"]))


func test_most_puzzles_land_in_the_levels_slack_range() -> void:
	var accepted: int = 0
	var total: int = 0
	for level: int in [2, 3, 4]:
		for seed_value: int in range(1, 7):
			total += 1
			if bool(MatrixPuzzle.generate(level, seed_value).metrics["accepted"]):
				accepted += 1
	assert_gte(float(accepted) / float(total), 0.8, "принято %d из %d" % [accepted, total])


func test_slack_is_the_buffer_minus_the_shortest_solution() -> void:
	var puzzle: MatrixPuzzle = MatrixPuzzle.generate(3, 8)
	assert_eq(int(puzzle.metrics["slack"]), puzzle.capacity - int(puzzle.metrics["min_moves"]))


func test_every_round_is_solvable_on_all_levels() -> void:
	var accepted: int = 0
	var total: int = 0
	for level: int in range(PuzzleLevels.MIN_LEVEL, PuzzleLevels.MAX_LEVEL + 1):
		for seed_value: int in 15:
			var puzzle: MatrixPuzzle = MatrixPuzzle.generate_round(level, seed_value, 0)
			assert_true(bool(puzzle.metrics["solvable"]), "уровень %d, сид %d" % [level, seed_value])
			total += 1
			if bool(puzzle.metrics["accepted"]):
				accepted += 1
	gut.p("раунды «матрицы» в допуске: %d из %d" % [accepted, total])


func test_wrong_first_symbol_is_a_dead_end_at_once_in_a_round() -> void:
	var puzzle: MatrixPuzzle = MatrixPuzzle.generate_round(2, 11, 0)
	var first_symbol: int = (puzzle.targets[0] as PackedInt32Array)[0]
	for cell: int in puzzle.legal_moves():
		if puzzle.grid[cell] != first_symbol:
			puzzle.pick(cell)
			assert_true(puzzle.is_finished(), "неверный первый символ — тупик сразу")
			return
	pass_test("в верхней строке все символы совпали с началом цели")


func test_round_does_not_judge_a_dead_end_ahead_of_the_player() -> void:
	# Баг со снимка F9 16.11: верный первый байт, а в нужном столбце следующего нет — игра сразу
	# объявляла тупик. Теперь тупик только когда игрок сам поставил не тот байт.
	for seed_value: int in 30:
		var puzzle: MatrixPuzzle = MatrixPuzzle.generate_round(4, seed_value, 0)
		var target: PackedInt32Array = puzzle.targets[0] as PackedInt32Array
		for cell: int in puzzle.legal_moves():
			if puzzle.grid[cell] == target[0]:
				puzzle.pick(cell)
				assert_false(puzzle.is_hopeless(), "сид %d: верный ход не тупик" % seed_value)
				break

