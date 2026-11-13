extends GutTest
## WindowAspect: рамка пропорций окна (docs/tech/resolution.md).

const MIN: Vector2i = AppSettings.MIN_WINDOW_SIZE


func test_minimum_itself_is_inside_the_frame() -> void:
	# На этом держится весь расчёт: если минимум вне рамки, подгонка по пропорциям
	# и подгонка по минимуму начнут спорить друг с другом.
	assert_true(WindowAspect.is_in_frame(MIN), "минимум %s в рамке" % MIN)


func test_standard_resolutions_are_inside_the_frame() -> void:
	for item: Dictionary in AppSettings.RESOLUTIONS:
		var size: Vector2i = item["size"] as Vector2i
		assert_true(WindowAspect.is_in_frame(size), "%s в рамке" % size)


func test_usual_sizes_are_left_alone() -> void:
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1024, 768), Vector2i(1680, 1050)]:
		assert_eq(WindowAspect.clamp_size(size, MIN), size, "не трогаем нормальное: %s" % size)


func test_too_wide_is_narrowed() -> void:
	# Игрок растянул окно в полоску 5000x720.
	var result: Vector2i = WindowAspect.clamp_size(Vector2i(5000, 720), MIN)
	assert_eq(result.y, 720, "высоту не меняем — окно не должно вылезти за экран")
	assert_true(result.x < 5000, "ширину урезали")
	assert_true(WindowAspect.is_in_frame(result), "результат в рамке: %s" % result)


func test_too_tall_is_shortened() -> void:
	var result: Vector2i = WindowAspect.clamp_size(Vector2i(1024, 3000), MIN)
	assert_eq(result.x, 1024, "ширину не меняем")
	assert_true(result.y < 3000, "высоту урезали")
	assert_true(WindowAspect.is_in_frame(result))


func test_below_minimum_grows_to_minimum() -> void:
	var result: Vector2i = WindowAspect.clamp_size(Vector2i(300, 200), MIN)
	assert_true(result.x >= MIN.x and result.y >= MIN.y, "не меньше минимума: %s" % result)
	assert_true(WindowAspect.is_in_frame(result))


func test_result_is_never_smaller_than_minimum() -> void:
	for size: Vector2i in [Vector2i(5000, 720), Vector2i(1024, 4000), Vector2i(1, 1), Vector2i(2000, 1000)]:
		var result: Vector2i = WindowAspect.clamp_size(size, MIN)
		assert_true(result.x >= MIN.x, "ширина не меньше минимума: %s → %s" % [size, result])
		assert_true(result.y >= MIN.y, "высота не меньше минимума: %s → %s" % [size, result])


func test_clamping_twice_changes_nothing() -> void:
	# Иначе сторож окна зацикливался бы: поправил размер, снова получил событие, снова поправил.
	for size: Vector2i in [Vector2i(5000, 720), Vector2i(1024, 3000), Vector2i(300, 200)]:
		var once: Vector2i = WindowAspect.clamp_size(size, MIN)
		var twice: Vector2i = WindowAspect.clamp_size(once, MIN)
		assert_eq(twice, once, "повторный зажим ничего не меняет: %s" % size)


func test_ultrawide_edge_is_allowed() -> void:
	# 21:9 внутри рамки, а не за ней.
	assert_true(WindowAspect.is_in_frame(Vector2i(2560, 1080)), "2560x1080 это 21:9")
	assert_eq(WindowAspect.clamp_size(Vector2i(2560, 1080), MIN), Vector2i(2560, 1080))
