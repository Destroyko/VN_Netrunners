class_name MatrixSolver
extends RefCounted
## Солвер «матрицы» (docs/tech/puzzles-spec.md, «Метрики солвера»): полный перебор ходов
## с отсечением. Глубина ограничена буфером, ветвление — стороной сетки.
##
## Считает два прохода:
##   1. `min_moves` — самый короткий (по клеткам буфера) способ собрать все последовательности.
##      Идёт с отсечением по лучшему найденному, поэтому быстрый;
##   2. `solutions_count` и `nodes_explored` — сколько всего полных решений и сколько вариантов
##      пришлось перебрать. Ограничены потолками: «200 и больше решений» — уже очень легко,
##      точное число не нужно, а полный перебор сетки 7×7 был бы заметной паузой.
##
## Решение — последовательность выбранных ячеек, при которой в буфере собраны все цели.
## Решения не продолжаются после сбора последней цели: лишние ходы — не новое решение.

var _size: int
var _capacity: int
var _grid: PackedInt32Array
var _noise: PackedByteArray
var _targets: Array

var _used: PackedByteArray = PackedByteArray()
var _buffer: PackedInt32Array = PackedInt32Array()
var _picks: PackedInt32Array = PackedInt32Array()
var _full_mask: int = 0

var _best: int = 0
var _best_path: PackedInt32Array = PackedInt32Array()
var _solutions: int = 0
var _nodes: int = 0
var _solutions_cap: int = 0
var _nodes_cap: int = 0
var truncated: bool = false


## Результат: {"solvable", "min_moves", "slack", "solutions_count", "nodes_explored",
## "truncated", "path"}.
static func analyze(puzzle: MatrixPuzzle, solutions_cap: int = 200, nodes_cap: int = 20000) -> Dictionary:
	var solver := MatrixSolver.new()
	return solver._run(puzzle, solutions_cap, nodes_cap)


func _run(puzzle: MatrixPuzzle, solutions_cap: int, nodes_cap: int) -> Dictionary:
	_size = puzzle.size
	_capacity = puzzle.capacity
	_grid = puzzle.grid
	_noise = puzzle.noise
	_targets = puzzle.targets
	_solutions_cap = solutions_cap
	_nodes_cap = nodes_cap
	_full_mask = (1 << _targets.size()) - 1
	_used.resize(_size * _size)

	# Проход 1: минимум клеток буфера. Верхняя граница — вся ёмкость буфера плюс один.
	_best = _capacity + 1
	_find_min(0, -1, 0)

	# Проход 2: сколько решений и сколько вариантов. Начинаем с чистого состояния.
	_used.fill(0)
	_buffer.clear()
	_picks.clear()
	_count(0, -1, 0)

	var solvable: bool = _best <= _capacity
	return {
		"solvable": solvable,
		"min_moves": _best if solvable else -1,
		"slack": (_capacity - _best) if solvable else -1,
		"solutions_count": _solutions,
		"nodes_explored": _nodes,
		"truncated": truncated,
		"path": _best_path,
	}


func _find_min(picks: int, last: int, mask: int) -> void:
	if mask == _full_mask:
		if _buffer.size() < _best:
			_best = _buffer.size()
			_best_path = _picks.duplicate()
		return
	# Любой следующий ход добавит минимум одну клетку: хуже найденного уже не будет.
	if _buffer.size() + 1 >= _best:
		return
	for cell: int in _legal(picks, last):
		var new_mask: int = _apply(cell, mask)
		_find_min(picks + 1, cell, new_mask)
		_undo(cell)


func _count(picks: int, last: int, mask: int) -> void:
	if truncated:
		return
	_nodes += 1
	if mask == _full_mask:
		_solutions += 1
		if _solutions >= _solutions_cap:
			truncated = true
		return
	if _nodes >= _nodes_cap:
		truncated = true
		return
	for cell: int in _legal(picks, last):
		var new_mask: int = _apply(cell, mask)
		_count(picks + 1, cell, new_mask)
		_undo(cell)


func _legal(picks: int, last: int) -> PackedInt32Array:
	return MatrixPuzzle.legal_cells(_size, picks, last, _used, _noise, _capacity - _buffer.size())


## Выбрать ячейку: символ в буфер, затем (у шумной) пустая помеха. Цели проверяем до помехи:
## последовательность может закончиться на шумной ячейке, но не пройти через неё.
func _apply(cell: int, mask: int) -> int:
	_used[cell] = 1
	_picks.append(cell)
	_buffer.append(_grid[cell])
	var result: int = mask
	for index: int in _targets.size():
		if (result & (1 << index)) == 0 and MatrixPuzzle.tail_matches(_buffer, _targets[index] as PackedInt32Array):
			result |= 1 << index
	if _noise[cell] == 1:
		_buffer.append(MatrixPuzzle.JUNK)
	return result


func _undo(cell: int) -> void:
	if _noise[cell] == 1:
		_buffer.resize(_buffer.size() - 1)
	_buffer.resize(_buffer.size() - 1)
	_picks.resize(_picks.size() - 1)
	_used[cell] = 0
