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


# --- Лупа ----------------------------------------------------------------------

func _puzzle_with_row(symbols: Array, target: Array) -> DumpPuzzle:
	# Головоломка с заданной первой строкой и целью — чтобы проверять лупу по известным байтам.
	var puzzle: DumpPuzzle = DumpPuzzle.generate(2, 1, {"width": 8, "rows": 8, "length": target.size(), "pieces": 1})
	puzzle.targets[0] = PackedInt32Array(target)
	puzzle._rows[0] = PackedInt32Array(symbols)
	return puzzle


func test_lens_covers_the_whole_piece_aligned_by_the_hovered_byte() -> void:
	# Цель: 14 5 1 (C4 55 1C). Строка: … 15(FF) 14(C4) 2(2F) 0(00) …
	var puzzle: DumpPuzzle = _puzzle_with_row([0, 0, 0, 15, 14, 2, 0, 0], [14, 5, 1])
	var lens: Dictionary = puzzle.lens(0, 4)
	assert_eq(lens.keys().size(), 3, "лупа длиной с кусок")
	assert_eq(lens[4], DumpPuzzle.LENS_MATCH, "C4 есть в куске")
	assert_eq(lens[5], DumpPuzzle.LENS_WRONG, "после C4 должно быть 55")
	assert_eq(lens[6], DumpPuzzle.LENS_WRONG, "дальше должно быть 1C")
	assert_false(lens.has(3), "перед C4 в куске ничего нет — клетка не накрыта")


func test_lens_grows_with_a_longer_piece() -> void:
	var puzzle: DumpPuzzle = _puzzle_with_row([0, 7, 14, 2, 1, 0, 0, 0], [7, 14, 2, 1])
	var lens: Dictionary = puzzle.lens(0, 3)
	assert_eq(lens.keys().size(), 4)
	for col: int in [1, 2, 3, 4]:
		assert_eq(lens[col], DumpPuzzle.LENS_MATCH)


func test_lens_on_the_right_spot_is_all_green() -> void:
	var puzzle: DumpPuzzle = _puzzle_with_row([0, 14, 5, 1, 0, 0, 0, 0], [14, 5, 1])
	var lens: Dictionary = puzzle.lens(0, 2)
	assert_eq([lens[1], lens[2], lens[3]], [DumpPuzzle.LENS_MATCH, DumpPuzzle.LENS_MATCH, DumpPuzzle.LENS_MATCH])


func test_lens_on_a_foreign_byte_is_red_with_plain_neighbours() -> void:
	var puzzle: DumpPuzzle = _puzzle_with_row([0, 3, 7, 9, 0, 0, 0, 0], [14, 5, 1])
	var lens: Dictionary = puzzle.lens(0, 2)
	assert_eq(lens[2], DumpPuzzle.LENS_WRONG)
	assert_eq(lens[1], DumpPuzzle.LENS_NEAR)
	assert_eq(lens[3], DumpPuzzle.LENS_NEAR)


func test_lens_is_cut_at_the_edge_of_the_row() -> void:
	# Наводимся на 1C в первой клетке: начало куска осталось бы за левым краем.
	var puzzle: DumpPuzzle = _puzzle_with_row([1, 5, 0, 0, 0, 0, 0, 0], [14, 5, 1])
	assert_eq(puzzle.lens(0, 0).keys(), [0])

