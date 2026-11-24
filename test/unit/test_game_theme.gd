extends GutTest
## Общая тема интерфейса (src/ui/theme/game_theme.gd) и список загрузки (src/ui/boot/boot_screen.gd).


func test_theme_styles_the_basic_controls() -> void:
	var theme: Theme = GameTheme.build()
	assert_true(theme.has_stylebox("normal", "Button"))
	assert_true(theme.has_stylebox("panel", "PanelContainer"))
	assert_true(theme.has_stylebox("normal", "LineEdit"))
	assert_true(theme.has_stylebox("background", "ProgressBar"))
	assert_true(theme.has_stylebox("panel", "TooltipPanel"))
	assert_eq(theme.get_color("font_color", "Label"), GameTheme.color("text"))


func test_colors_come_from_data_roles() -> void:
	assert_eq(GameTheme.color("accent"), Color("#E87B2E"), "роль accent — тёплый оранжевый лампы")
	assert_eq(GameTheme.color("no_such_role"), Color.WHITE, "нет роли — белый, ошибка видна")


func test_boot_lists_backgrounds_and_masks_but_not_menu_art() -> void:
	var paths: PackedStringArray = BootScreen.assets_to_preload()
	assert_gt(paths.size(), 0, "фоны и маски комнаты есть")
	for path: String in paths:
		assert_false(path.get_file().begins_with("bg_menu"), "картинки меню не грузим заранее: " + path)
	assert_true(paths.has("res://assets/backgrounds/bg_room_main_day_pc_on.png"))
	assert_true(paths.has("res://assets/masks/loc_room_bed.png"))


func test_pc_theme_follows_os_and_player_swap() -> void:
	GameState.reset()
	GameState.set_var("pc.os", "normal")
	assert_eq(GameTheme.pc_theme_id(), "standard", "обычная ОС — стандартная тема")
	GameState.set_var("pc.os", "hacker")
	assert_eq(GameTheme.pc_theme_id(), "hacker")
	GameState.set_var(GameTheme.VAR_PC_THEME, "standard")
	assert_eq(GameTheme.pc_theme_id(), "standard", "игрок подменил тему файлом: побеждает подмена")
	GameState.set_var(GameTheme.VAR_PC_THEME, "no_such_theme")
	assert_eq(GameTheme.pc_theme_id(), "hacker", "несуществующую тему не берём")


func test_themes_differ_and_have_icons() -> void:
	assert_ne(GameTheme.color("background", "standard"), GameTheme.color("background", "hacker"))
	assert_gt(GameTheme.color("background", "standard").get_luminance(), 0.5, "стандартная — светлая основа")
	assert_lt(GameTheme.color("background", "hacker").get_luminance(), 0.2, "хакерская — тёмная")
	for theme_id: String in ["standard", "hacker"]:
		assert_not_null(GameTheme.icon("terminal", theme_id), "значок терминала в теме " + theme_id)
	assert_not_null(GameTheme.icon("mail", "phone"), "у телефона значки на плашках")

