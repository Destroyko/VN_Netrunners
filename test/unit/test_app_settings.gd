extends GutTest
## AppSettings: настройки живут отдельно от сейва, поэтому проверяются сами по себе.
## apply() здесь не вызывается — он трогает звук и окно, это не дело юнит-теста.

const TEST_PATH: String = "user://test_settings.cfg"

var settings: AppSettings


func before_each() -> void:
	settings = AppSettings.new()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func test_defaults() -> void:
	assert_eq(settings.master_volume, AppSettings.DEFAULT_MASTER_VOLUME)
	assert_false(settings.fullscreen)
	assert_eq(settings.ui_scale, AppSettings.UI_SCALE_AUTO, "масштаб по умолчанию — авто")


# --- Масштаб интерфейса (docs/tech/resolution.md) -----------------------------

func test_suggested_scale_grows_with_screen() -> void:
	assert_eq(AppSettings.suggest_ui_scale(720), 1.0)
	assert_eq(AppSettings.suggest_ui_scale(1080), 1.0)
	assert_eq(AppSettings.suggest_ui_scale(1440), 1.25, "на 2К текст был бы мелким")
	assert_eq(AppSettings.suggest_ui_scale(2160), 2.0)


func test_auto_scale_resolves_by_screen_height() -> void:
	assert_eq(settings.resolved_ui_scale(1080), 1.0)
	assert_eq(settings.resolved_ui_scale(1440), 1.25)


func test_explicit_scale_ignores_screen() -> void:
	settings.set_ui_scale(1.5)
	assert_eq(settings.resolved_ui_scale(1080), 1.5, "выбор игрока важнее догадки")
	assert_eq(settings.resolved_ui_scale(2160), 1.5)


func test_scale_snaps_to_allowed_values() -> void:
	settings.set_ui_scale(1.3)
	assert_eq(settings.ui_scale, 1.25, "ближайшее допустимое")
	settings.set_ui_scale(99.0)
	assert_eq(settings.ui_scale, 2.0)
	settings.set_ui_scale(-1.0)
	assert_eq(settings.ui_scale, AppSettings.UI_SCALE_AUTO, "ноль и меньше — это авто")


func test_scale_survives_save_and_load() -> void:
	settings.set_ui_scale(2.0)
	assert_eq(settings.save_to(TEST_PATH), OK)
	var loaded := AppSettings.new()
	loaded.load_from(TEST_PATH)
	assert_eq(loaded.ui_scale, 2.0)


# --- Разрешения ---------------------------------------------------------------

func test_resolution_list_is_sane() -> void:
	var seen: Dictionary = {}
	var previous_width: int = 0
	for item: Dictionary in AppSettings.RESOLUTIONS:
		var size: Vector2i = item["size"] as Vector2i
		assert_false(seen.has(size), "без повторов: %s" % size)
		seen[size] = true
		assert_true(size.x >= AppSettings.MIN_WINDOW_SIZE.x, "не меньше минимума: %s" % size)
		assert_true(size.y >= AppSettings.MIN_WINDOW_SIZE.y, "не меньше минимума: %s" % size)
		assert_true(size.x >= previous_width, "список по возрастанию: %s" % size)
		previous_width = size.x
		assert_false(str(item["aspect"]).is_empty(), "у каждого подписаны пропорции")


func test_aspect_labels_match_sizes() -> void:
	# Подпись пропорции в списке должна соответствовать самому размеру, иначе игрок
	# выберет «16:9» и получит 4:3.
	# Для каждой подписи — диапазон, а не точное число: «21:9» у производителей на самом деле
	# 2.370 (2560×1080) и 2.389 (3440×1440), а не дробь 21/9 = 2.333. Подписываем как принято
	# у людей, а проверяем по тому, что это за мониторы в действительности.
	var ranges: Dictionary = {
		"4:3": [1.32, 1.34],
		"16:10": [1.59, 1.61],
		"16:9": [1.77, 1.78],
		"21:9": [2.33, 2.40],
	}
	for item: Dictionary in AppSettings.RESOLUTIONS:
		var size: Vector2i = item["size"] as Vector2i
		var label: String = str(item["aspect"])
		assert_true(ranges.has(label), "известная подпись: " + label)
		var range_values: Array = ranges[label] as Array
		assert_between(
			WindowAspect.aspect_of(size),
			float(range_values[0]),
			float(range_values[1]),
			"%s подписан как %s" % [size, label]
		)


func test_only_fitting_resolutions_are_offered() -> void:
	var for_laptop: Array[Dictionary] = AppSettings.resolutions_for_screen(Vector2i(1920, 1080))
	for item: Dictionary in for_laptop:
		var size: Vector2i = item["size"] as Vector2i
		assert_true(size.x <= 1920 and size.y <= 1080, "влезает в экран: %s" % size)
	assert_gt(for_laptop.size(), 0, "на 1080p есть из чего выбрать")

	var for_small: Array[Dictionary] = AppSettings.resolutions_for_screen(Vector2i(1280, 720))
	assert_eq(for_small.size(), 1, "на 1280x720 подходит только оно само")


func test_resolution_survives_save_and_load() -> void:
	settings.set_resolution(Vector2i(1600, 900))
	assert_eq(settings.save_to(TEST_PATH), OK)
	var loaded := AppSettings.new()
	loaded.load_from(TEST_PATH)
	assert_eq(loaded.resolution, Vector2i(1600, 900))


func test_window_resolution_means_leave_window_alone() -> void:
	settings.set_resolution(AppSettings.RESOLUTION_WINDOW)
	assert_eq(settings.resolution, AppSettings.RESOLUTION_WINDOW)


func test_resolution_is_not_smaller_than_minimum() -> void:
	settings.set_resolution(Vector2i(640, 480))
	assert_eq(settings.resolution, AppSettings.MIN_WINDOW_SIZE)


func test_min_window_size_fits_both_minimums() -> void:
	# Ограничение по каждой стороне отдельно: должны пройти и 1024x768, и 1280x720.
	assert_true(AppSettings.MIN_WINDOW_SIZE.x <= 1024, "1024 по ширине проходит")
	assert_true(AppSettings.MIN_WINDOW_SIZE.y <= 720, "720 по высоте проходит")


func test_save_and_load_round_trip() -> void:
	settings.set_master_volume(0.35)
	settings.fullscreen = true
	assert_eq(settings.save_to(TEST_PATH), OK)

	var loaded := AppSettings.new()
	loaded.load_from(TEST_PATH)
	assert_almost_eq(loaded.master_volume, 0.35, 0.001)
	assert_true(loaded.fullscreen)


func test_missing_file_keeps_defaults() -> void:
	# Первый запуск: файла нет, настройки остаются как есть, ошибки нет.
	settings.load_from("user://net_takogo_faila.cfg")
	assert_eq(settings.master_volume, AppSettings.DEFAULT_MASTER_VOLUME)
	assert_false(settings.fullscreen)


func test_volume_is_clamped() -> void:
	settings.set_master_volume(-3.0)
	assert_eq(settings.master_volume, 0.0)
	settings.set_master_volume(12.0)
	assert_eq(settings.master_volume, 1.0)


func test_broken_value_in_file_is_clamped_on_load() -> void:
	# Файл правится руками, значит в нём может оказаться что угодно.
	var config := ConfigFile.new()
	config.set_value(AppSettings.SECTION, "master_volume", 50.0)
	config.set_value(AppSettings.SECTION, "fullscreen", true)
	assert_eq(config.save(TEST_PATH), OK)

	settings.load_from(TEST_PATH)
	assert_eq(settings.master_volume, 1.0, "громкость не выше единицы")
	assert_true(settings.fullscreen)
