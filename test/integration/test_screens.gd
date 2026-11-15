extends GutTest
## Экраны M0.5 собираются и находят свои узлы.
##
## Зачем интеграционный тест на такую мелочь: сцены написаны руками, а скрипты обращаются
## к узлам по путям (`$Rows/NewGame`). Опечатка в пути не ломает ни парсинг, ни валидатор —
## она падает только при запуске. Этот тест ловит её headless.


func _open(path: String) -> Node:
	var scene: PackedScene = load(path) as PackedScene
	assert_not_null(scene, "сцена загружается: " + path)
	var node: Node = scene.instantiate()
	add_child_autofree(node)
	return node


func test_main_menu_has_all_buttons() -> void:
	var menu: Node = _open(Screens.MAIN_MENU)
	for button_name: String in ["NewGame", "Continue", "Settings", "About", "Quit"]:
		var button: Button = menu.get_node_or_null("Rows/" + button_name) as Button
		assert_not_null(button, "кнопка на месте: " + button_name)


func test_continue_is_disabled_until_saves_exist() -> void:
	var menu: Node = _open(Screens.MAIN_MENU)
	var button: Button = menu.get_node("Rows/Continue") as Button
	assert_true(button.disabled, "сохранения появятся в M4")


func test_new_game_lists_four_difficulties() -> void:
	var screen: Node = _open(Screens.NEW_GAME)
	var levels: VBoxContainer = screen.get_node("Rows/Levels") as VBoxContainer
	assert_eq(levels.get_child_count(), 4, "четыре уровня из docs/gameplay/difficulty.md")


func test_new_game_selects_normal_by_default() -> void:
	var screen: Node = _open(Screens.NEW_GAME)
	var levels: VBoxContainer = screen.get_node("Rows/Levels") as VBoxContainer
	var pressed: Array = []
	for child: Node in levels.get_children():
		var button: Button = child as Button
		if button != null and button.button_pressed:
			pressed.append(int(button.get_meta(&"difficulty")))
	assert_eq(pressed, [int(GameState.Difficulty.NORMAL)], "по умолчанию средний, и только он")


func test_new_game_hint_is_filled() -> void:
	var screen: Node = _open(Screens.NEW_GAME)
	var hint: Label = screen.get_node("Rows/Hint") as Label
	assert_false(hint.text.is_empty(), "пояснение к выбранному уровню показано")


func test_settings_screen_shows_current_values() -> void:
	var screen: Node = _open(Screens.SETTINGS)
	var volume: HSlider = screen.get_node("Rows/VolumeRow/Volume") as HSlider
	assert_not_null(volume)
	assert_between(volume.value, 0.0, 1.0)
	var value_label: Label = screen.get_node("Rows/VolumeRow/Value") as Label
	assert_true(value_label.text.ends_with("%"), "громкость подписана процентами")
	assert_not_null(screen.get_node_or_null("Rows/Fullscreen") as CheckButton)

	var scale: OptionButton = screen.get_node("Rows/ScaleRow/Scale") as OptionButton
	assert_not_null(scale)
	assert_eq(scale.item_count, AppSettings.UI_SCALES.size() + 1, "авто плюс фиксированные")
	assert_eq(scale.get_item_text(0), "Авто")
	assert_gt(scale.selected, -1, "что-то выбрано")

	var resolution: OptionButton = screen.get_node("Rows/ResolutionRow/Resolution") as OptionButton
	assert_not_null(resolution)
	assert_gt(resolution.item_count, 1, "«по размеру окна» плюс хотя бы одно разрешение")
	assert_gt(resolution.selected, -1, "что-то выбрано")
	assert_string_contains(resolution.get_item_text(1), "×", "размер подписан как ширина×высота")


func test_about_shows_version() -> void:
	var screen: Node = _open(Screens.ABOUT)
	var text: Label = screen.get_node("Rows/Text") as Label
	assert_string_contains(text.text, "Версия")
	assert_string_contains(text.text, str(ProjectSettings.get_setting("application/config/version")))


func test_every_screen_has_a_way_back() -> void:
	# Экран без выхода — тупик, из которого игрок уходит только Alt+F4.
	for path: String in [Screens.NEW_GAME, Screens.SETTINGS, Screens.ABOUT]:
		var screen: Node = _open(path)
		assert_not_null(screen.get_node_or_null("Rows/Back") as Button, "есть «Назад»: " + path)


func test_desktop_opens() -> void:
	var desktop: Node = _open(Screens.DESKTOP)
	assert_true(desktop is Desktop)


func test_room_has_its_objects() -> void:
	var room: Node = _open(Screens.ROOM)
	for node_name: String in ["Monitor", "SystemBlock", "Inventory", "Output", "Menu"]:
		assert_not_null(room.get_node_or_null("Rows/" + node_name), "на месте: " + node_name)


func test_room_lists_inventory_items_as_buttons() -> void:
	GameState.reset()
	Inventory.give("item_flash_backup")
	var room: Node = _open(Screens.ROOM)
	assert_eq(room.get_node("Rows/Inventory").get_child_count(), 1)
