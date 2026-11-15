extends GutTest
## MatrixSolver: полный перебор с отсечением (docs/tech/puzzles-spec.md, «Метрики солвера»).
## Сетка та же, что в test_matrix_puzzle.gd: символы 0 1 2 / 3 4 5 / 0 1 2.


func _manual(capacity: int, noisy: Array, goals: Array) -> MatrixPuzzle:
	var puzzle := MatrixPuzzle.new()
	puzzle.size = 3
	puzzle.capacity = capacity
	puzzle.grid = PackedInt32Array([0, 1, 2, 3, 4, 5, 0, 1, 2])
	puzzle.noise = PackedByteArray()
	puzzle.noise.resize(9)
	puzzle.noise.fill(0)
	for cell: int in noisy:
		puzzle.noise[cell] = 1
	for goal: Array in goals:
		puzzle.targets.append(PackedInt32Array(goal))
	return puzzle


func test_finds_the_shortest_solution() -> void:
	var result: Dictionary = MatrixSolver.analyze(_manual(6, [], [[1, 4]]))
	assert_true(bool(result["solvable"]))
	assert_eq(result["min_moves"], 2)
	assert_eq(result["slack"], 4)
	assert_eq(result["path"], PackedInt32Array([1, 4]), "символ 1 в верхней строке только в ячейке 1")


func test_unsolvable_target() -> void:
	# Трёх символов подряд в буфере на две клетки не собрать.
	var result: Dictionary = MatrixSolver.analyze(_manual(2, [], [[5, 5, 5]]))
	assert_false(bool(result["solvable"]))
	assert_eq(result["min_moves"], -1)


func test_noise_can_make_a_target_unreachable() -> void:
	# Символ 3 есть только в ячейке 3, а за ним 4 — только в ячейке 4. Если 3 шумная, между
	# ними встаёт помеха и цепочку не собрать никаким путём.
	var result: Dictionary = MatrixSolver.analyze(_manual(6, [3], [[3, 4]]))
	assert_false(bool(result["solvable"]))
	assert_true(bool(MatrixSolver.analyze(_manual(6, [], [[3, 4]]))["solvable"]), "без шума решаема")


func test_noisy_last_cell_still_solves_and_costs_two_cells() -> void:
	var result: Dictionary = MatrixSolver.analyze(_manual(6, [4], [[1, 4]]))
	assert_true(bool(result["solvable"]))
	assert_eq(result["min_moves"], 3, "символ, символ и помеха от шумной ячейки")


func test_counts_solutions_and_nodes() -> void:
	var result: Dictionary = MatrixSolver.analyze(_manual(6, [], [[1, 4]]))
	assert_gte(int(result["solutions_count"]), 1)
	assert_gte(int(result["nodes_explored"]), int(result["solutions_count"]))
	assert_false(bool(result["truncated"]))


func test_overlapping_targets_need_fewer_cells_than_the_sum() -> void:
	var result: Dictionary = MatrixSolver.analyze(_manual(6, [], [[1, 4], [4, 3]]))
	assert_eq(result["min_moves"], 3, "1-4-3 собирает обе цели подряд")


func test_solution_cap_truncates_the_count() -> void:
	var result: Dictionary = MatrixSolver.analyze(_manual(8, [], [[1]]), 1, 100000)
	assert_true(bool(result["truncated"]))
	assert_eq(result["solutions_count"], 1)


func test_solver_does_not_change_the_puzzle() -> void:
	var puzzle: MatrixPuzzle = _manual(6, [], [[1, 4]])
	MatrixSolver.analyze(puzzle)
	assert_eq(puzzle.buffer.size(), 0)
	assert_eq(puzzle.picks.size(), 0)
