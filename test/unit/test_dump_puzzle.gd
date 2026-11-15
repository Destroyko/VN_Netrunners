extends GutTest
## «Перехват в дампе»: поток строк по сиду, клик по цели и мимо, ловушки, конец партии.


func _find(puzzle: DumpPuzzle, piece: PackedInt32Array) -> Vector2i:
	# Ищет кусок в видимых строках: (строка, столбец начала) или (-1, -1).
	for row: int in puzzle.visible_rows():
		var symbols: PackedInt32Array = puzzle.row_symbols(row)
		for at: int in puzzle.width - piece.size() + 1:
			if symbols.slice(at, at + piece.size()) == piece:
				return Vector2i(row, at)
	return Vector2i(-1, -1)


## Прокручивать, пока текущая цель не покажется на экране.
func _scroll_until_target(puzzle: DumpPuzzle) -> Vector2i:
	for _i: int in 40:
		var spot: Vector2i = _find(puzzle, puzzle.current_target())
		if spot.x >= 0:
			return spot
		puzzle.scroll()
	return Vector2i(-1, -1)


func test_same_seed_gives_the_same_stream() -> void:
	var a: DumpPuzzle = DumpPuzzle.generate(2, 7)
	var b: DumpPuzzle = DumpPuzzle.generate(2, 7)
	assert_eq(a.targets, b.targets)
	for row: int in 12:
		assert_eq(a.row_symbols(row), b.row_symbols(row))


func test_target_shows_up_on_screen_soon() -> void:
	for seed_value: int in 20:
		var puzzle: DumpPuzzle = DumpPuzzle.generate(3, seed_value)
		assert_true(_scroll_until_target(puzzle).x >= 0, "сид %d: цель так и не пришла" % seed_value)


func test_clicking_the_target_catches_a_piece() -> void:
	var puzzle: DumpPuzzle = DumpPuzzle.generate(2, 3)
	var spot: Vector2i = _scroll_until_target(puzzle)
	var result: Dictionary = puzzle.pick(spot.x, spot.y + 1)
	assert_eq(result["result"], DumpPuzzle.PICK_HIT, "клик по любой клетке куска засчитывается")
	assert_eq(puzzle.stage, 1)
	assert_eq((result["cells"] as Array).size(), puzzle.targets[0].size())


func test_miss_resets_what_was_collected() -> void:
	var puzzle: DumpPuzzle = DumpPuzzle.generate(3, 5)
	var spot: Vector2i = _scroll_until_target(puzzle)
	puzzle.pick(spot.x, spot.y)
	assert_eq(puzzle.stage, 1)
	# Клик туда, где второго куска точно нет: строка выше экрана.
	var result: Dictionary = puzzle.pick(puzzle.top - 1, 0)
	assert_eq(result["result"], DumpPuzzle.PICK_MISS)
	assert_eq(puzzle.stage, 0, "ошибка стоит всего набора")
	assert_eq(puzzle.misses, 1)


func test_collecting_every_piece_solves_the_puzzle() -> void:
	var puzzle: DumpPuzzle = DumpPuzzle.generate(3, 11)
	var last: Dictionary = {}
	for _piece: int in puzzle.targets.size():
		var spot: Vector2i = _scroll_until_target(puzzle)
		assert_true(spot.x >= 0)
		last = puzzle.pick(spot.x, spot.y)
	assert_eq(last["result"], DumpPuzzle.PICK_DONE)
	assert_true(puzzle.is_solved())


func test_decoy_differs_from_the_target_in_one_symbol() -> void:
	# Ловушки — почти совпадения: клик по ним — промах.
	var puzzle: DumpPuzzle = DumpPuzzle.generate(4, 2, {
		"width": 8, "rows": 8, "length": 4, "pieces": 1, "match_every": 50, "decoy_chance": 1.0,
	})
	var target: PackedInt32Array = puzzle.current_target()
	var found_decoy: bool = false
	for row: int in puzzle.visible_rows():
		var symbols: PackedInt32Array = puzzle.row_symbols(row)
		for at: int in puzzle.width - target.size() + 1:
			var diff: int = 0
			for offset: int in target.size():
				if symbols[at + offset] != target[offset]:
					diff += 1
			if diff == 1:
				found_decoy = true
				assert_eq(puzzle.pick(row, at)["result"], DumpPuzzle.PICK_MISS)
				return
	assert_true(found_decoy, "при decoy_chance = 1 ловушка есть в каждой строке")


func test_scrolling_moves_the_screen_by_one_row() -> void:
	var puzzle: DumpPuzzle = DumpPuzzle.generate(2, 1)
	var second: PackedInt32Array = puzzle.row_symbols(1)
	puzzle.scroll()
	assert_eq(puzzle.visible_rows()[0], 1)
	assert_eq(puzzle.row_symbols(puzzle.visible_rows()[0]), second)
	assert_eq(puzzle.visible_rows().size(), puzzle.rows_visible)
