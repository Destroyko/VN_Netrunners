extends GutTest
## Rng: воспроизводимость. Без неё нельзя повторить баг и проверить головоломку.


func after_each() -> void:
	Rng.randomize_seed()


func _take(count: int) -> Array:
	var out: Array = []
	for _i: int in count:
		out.append(Rng.randi_range(0, 1_000_000))
	return out


func test_same_seed_gives_same_sequence() -> void:
	Rng.set_seed(42)
	var first: Array = _take(10)
	Rng.set_seed(42)
	var second: Array = _take(10)
	assert_eq(first, second, "один сид — одна последовательность")


func test_different_seed_gives_different_sequence() -> void:
	Rng.set_seed(1)
	var first: Array = _take(10)
	Rng.set_seed(2)
	var second: Array = _take(10)
	assert_ne(first, second, "разные сиды — разные последовательности")


func test_seed_is_stored() -> void:
	Rng.set_seed(12345)
	assert_eq(Rng.get_seed(), 12345)


func test_stream_is_deterministic() -> void:
	Rng.set_seed(7)
	var first: int = Rng.stream("puzzles").randi()
	Rng.set_seed(7)
	var second: int = Rng.stream("puzzles").randi()
	assert_eq(first, second, "поток выводится из общего сида")


func test_streams_are_independent() -> void:
	Rng.set_seed(7)
	var expected: int = Rng.stream("puzzles").randi()

	Rng.set_seed(7)
	# Расходуем случайность в другом месте — на поток головоломок это влиять не должно.
	Rng.randi_range(0, 100)
	Rng.stream("news").randi()
	var actual: int = Rng.stream("puzzles").randi()
	assert_eq(actual, expected, "чужой расход не сдвигает поток")


func test_different_streams_differ() -> void:
	Rng.set_seed(7)
	assert_ne(Rng.stream("puzzles").randi(), Rng.stream("news").randi())


func test_fixed_generator_depends_only_on_its_seed() -> void:
	Rng.set_seed(1)
	var a: int = Rng.fixed(999).randi()
	Rng.set_seed(2)
	var b: int = Rng.fixed(999).randi()
	assert_eq(a, b, "головоломка по сиду не зависит от сида игры")


func test_pick_and_shuffle_are_reproducible() -> void:
	var items: Array = [1, 2, 3, 4, 5, 6, 7, 8]
	Rng.set_seed(5)
	var picked_first: Variant = Rng.pick(items)
	var shuffled_first: Array = items.duplicate()
	Rng.shuffle(shuffled_first)

	Rng.set_seed(5)
	var picked_second: Variant = Rng.pick(items)
	var shuffled_second: Array = items.duplicate()
	Rng.shuffle(shuffled_second)

	assert_eq(picked_first, picked_second)
	assert_eq(shuffled_first, shuffled_second)
	assert_eq(shuffled_first.size(), items.size(), "ничего не потеряли")


func test_pick_on_empty_array_returns_null() -> void:
	assert_null(Rng.pick([]))
