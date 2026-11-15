class_name DumpPuzzle
extends RefCounted
## «Перехват в дампе» (docs/tech/puzzles-spec.md, раздел 3): по экрану ползёт дамп памяти,
## игрок ловит в нём кусок хэша — цель, которая всегда на виду. Собрал все куски — хэш готов.
##
## Чистые правила без сцен: поток строк по сиду, проверка клика, ловушки. Время (как часто
## ползёт дамп) задаёт окно, здесь — только «экран сдвинулся на строку» (`scroll`).
##
## Ловушки — почти совпадения: цель с одним другим символом. Клик мимо цели сбрасывает
## собранное (так решил разработчик: ошибка стоит набора, а не попытки).

## Алфавит дампа: шестнадцать байтов. Шире, чем у «матрицы», чтобы случайные совпадения
## были редкостью и цель встречалась там, где её положил генератор.
const SYMBOLS: PackedStringArray = [
	"00", "1C", "2F", "3B", "4E", "55", "6D", "7A", "8C", "9F", "A3", "BD", "C4", "D8", "E9", "FF",
]

const PICK_HIT: String = "hit"
const PICK_MISS: String = "miss"
const PICK_DONE: String = "done"

## Состояния клеток под «лупой» (наведение мыши): подходит, не подходит, просто рядом.
const LENS_MATCH: String = "match"
const LENS_WRONG: String = "wrong"
const LENS_NEAR: String = "near"

var level: int = 2
var puzzle_seed: int = 0
## Ширина строки и сколько строк видно разом.
var width: int = 8
var rows_visible: int = 8
## Куски хэша, которые надо поймать по порядку.
var targets: Array[PackedInt32Array] = []
## Сколько кусков уже поймано (индекс текущей цели).
var stage: int = 0
var misses: int = 0

## Первая видимая строка потока; строки нумеруются с нуля и не повторяются.
var top: int = 0

var _match_every: int = 5
var _decoy_chance: float = 0.3
var _rows: Dictionary = {}
var _next_match: int = 0
var _rng: RandomNumberGenerator


## Головоломка по уровню и сиду. `params` — вместо значений из balance.json.
static func generate(game_level: int, seed_value: int, params: Dictionary = {}) -> DumpPuzzle:
	var config: Dictionary = params if not params.is_empty() else PuzzleLevels.dump(game_level)
	var puzzle := DumpPuzzle.new()
	puzzle.level = game_level
	puzzle.puzzle_seed = seed_value
	puzzle.width = int(config.get("width", 8))
	puzzle.rows_visible = int(config.get("rows", 8))
	puzzle._match_every = maxi(2, int(config.get("match_every", 5)))
	puzzle._decoy_chance = clampf(float(config.get("decoy_chance", 0.3)), 0.0, 1.0)
	puzzle._rng = Rng.fixed(seed_value)
	var length: int = clampi(int(config.get("length", 3)), 2, puzzle.width)
	for _i: int in maxi(1, int(config.get("pieces", 3))):
		var piece := PackedInt32Array()
		for _j: int in length:
			piece.append(puzzle._rng.randi_range(0, SYMBOLS.size() - 1))
		puzzle.targets.append(piece)
	# Первое совпадение — в нижней половине экрана: его видно сразу, но не в первой строке.
	puzzle._next_match = puzzle.rows_visible / 2 + puzzle._rng.randi_range(0, 2)
	for row: int in puzzle.rows_visible:
		puzzle._ensure(row)
	return puzzle


# --- Поток ---------------------------------------------------------------------

## Символы строки `row` (номер в потоке). Строки рождаются по мере прокрутки и запоминаются:
## уехавшая строка больше не нужна, но вернуть её одинаковой — дешевле, чем помнить, что её нет.
func row_symbols(row: int) -> PackedInt32Array:
	_ensure(row)
	return _rows[row] as PackedInt32Array


func visible_rows() -> Array[int]:
	var result: Array[int] = []
	for offset: int in rows_visible:
		result.append(top + offset)
	return result


## Экран сдвинулся на строку: верхняя уехала, снизу пришла новая.
func scroll() -> void:
	top += 1
	_ensure(top + rows_visible - 1)


func symbol_name(value: int) -> String:
	return SYMBOLS[value]


func current_target() -> PackedInt32Array:
	return targets[stage] if stage < targets.size() else PackedInt32Array()


func is_solved() -> bool:
	return stage >= targets.size()


## Новая строка: случайный шум, иногда ловушка, по расписанию — текущая цель. Цель кладётся
## та, что нужна игроку в момент рождения строки: поймал кусок — дальше по экрану идёт следующий.
func _ensure(row: int) -> void:
	while not _rows.has(row):
		var index: int = _rows.size()
		var symbols := PackedInt32Array()
		for _i: int in width:
			symbols.append(_rng.randi_range(0, SYMBOLS.size() - 1))
		var target: PackedInt32Array = current_target()
		var taken: int = -1
		if not target.is_empty() and index >= _next_match:
			taken = _rng.randi_range(0, width - target.size())
			_put(symbols, taken, target)
			_next_match = index + _match_every + _rng.randi_range(-1, 1)
		if not target.is_empty() and _rng.randf() < _decoy_chance:
			_put_decoy(symbols, target, taken)
		_rows[index] = symbols


func _put(symbols: PackedInt32Array, at: int, piece: PackedInt32Array) -> void:
	for offset: int in piece.size():
		symbols[at + offset] = piece[offset]


## Ловушка: цель с одним изменённым символом, не поверх настоящей цели этой строки.
func _put_decoy(symbols: PackedInt32Array, target: PackedInt32Array, taken: int) -> void:
	var length: int = target.size()
	var places: Array[int] = []
	for at: int in width - length + 1:
		if taken < 0 or at + length <= taken or at >= taken + length:
			places.append(at)
	if places.is_empty():
		return
	var decoy: PackedInt32Array = target.duplicate()
	var spot: int = _rng.randi_range(0, length - 1)
	decoy[spot] = (decoy[spot] + 1 + _rng.randi_range(0, SYMBOLS.size() - 2)) % SYMBOLS.size()
	_put(symbols, places[_rng.randi_range(0, places.size() - 1)], decoy)


# --- Лупа ----------------------------------------------------------------------

## Подсказка при наведении на клетку (решено 15.11.2026, на пробу): сама клетка и её соседи
## слева и справа. Клетка с байтом из текущего куска — «подходит», иначе «не подходит». Если
## подходит, соседи сверяются с тем, что в куске стоит рядом с этим байтом: совпал — «подходит»,
## нет — «не подходит»; сосед за краем куска — просто «рядом». Байт встречается в куске дважды —
## берём место, где сходится больше соседей. Возвращает {столбец: состояние}.
func lens(row: int, col: int) -> Dictionary:
	var result: Dictionary = {}
	var symbols: PackedInt32Array = row_symbols(row)
	var target: PackedInt32Array = current_target()
	var best: int = -1
	var best_score: int = -1
	for index: int in target.size():
		if target[index] != symbols[col]:
			continue
		var score: int = 0
		if index > 0 and col > 0 and target[index - 1] == symbols[col - 1]:
			score += 1
		if index < target.size() - 1 and col < width - 1 and target[index + 1] == symbols[col + 1]:
			score += 1
		if score > best_score:
			best = index
			best_score = score
	result[col] = LENS_WRONG if best < 0 else LENS_MATCH
	for side: int in [-1, 1]:
		var neighbour: int = col + side
		if neighbour < 0 or neighbour >= width:
			continue
		var expected: int = best + side
		if best < 0 or expected < 0 or expected >= target.size():
			result[neighbour] = LENS_NEAR
		else:
			result[neighbour] = LENS_MATCH if target[expected] == symbols[neighbour] else LENS_WRONG
	return result


# --- Клик ----------------------------------------------------------------------

## Игрок кликнул по ячейке. Попал внутрь текущей цели (в видимой строке) — кусок пойман.
## Иначе — промах: собранное сбрасывается, ловить начинаем с первого куска.
## Возвращает {"result": hit / miss / done, "stage": сколько поймано, "cells": клетки цели при попадании}.
func pick(row: int, col: int) -> Dictionary:
	if is_solved():
		return {"result": PICK_DONE, "stage": stage, "cells": []}
	# +1: при плавной прокрутке снизу уже въезжает следующая строка, её тоже видно.
	if row < top or row > top + rows_visible or col < 0 or col >= width:
		return _miss()
	var at: int = _occurrence_at(row_symbols(row), current_target(), col)
	if at < 0:
		return _miss()
	var cells: Array[int] = []
	for offset: int in current_target().size():
		cells.append(at + offset)
	stage += 1
	return {"result": PICK_DONE if is_solved() else PICK_HIT, "stage": stage, "cells": cells}


func _miss() -> Dictionary:
	misses += 1
	stage = 0
	# После сброса цель снова первая: следующее её появление — скоро, а не через полэкрана.
	_next_match = mini(_next_match, _rows.size() + 1)
	return {"result": PICK_MISS, "stage": stage, "cells": []}


## Начало вхождения цели в строке, покрывающего столбец `col`; -1 — такого нет.
static func _occurrence_at(symbols: PackedInt32Array, target: PackedInt32Array, col: int) -> int:
	var length: int = target.size()
	for at: int in range(maxi(0, col - length + 1), mini(col, symbols.size() - length) + 1):
		var same: bool = true
		for offset: int in length:
			if symbols[at + offset] != target[offset]:
				same = false
				break
		if same:
			return at
	return -1
