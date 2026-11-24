extends GutTest
## Кнопка по маске (src/ui/location/mask_button.gd): клик и подсветка только над силуэтом.


## Маска 4×4: левая половина непрозрачная, правая прозрачная.
func _button() -> MaskButton:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	for y: int in range(4):
		for x: int in range(4):
			image.set_pixel(x, y, Color(1, 1, 1, 1.0 if x < 2 else 0.0))
	var button := MaskButton.new()
	button.setup(ImageTexture.create_from_image(image))
	add_child_autofree(button)
	# в игре кнопка растянута якорями на весь экран; в тесте размер задаём руками
	button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	button.size = Vector2(100, 100)
	return button


func test_click_only_inside_silhouette() -> void:
	var button: MaskButton = _button()
	assert_true(button._has_point(Vector2(10, 50)), "левая половина — предмет")
	assert_false(button._has_point(Vector2(90, 50)), "правая — пусто, клик пройдёт дальше")
	assert_false(button._has_point(Vector2(-5, 50)), "за краем кнопки")


func test_mask_scales_with_button_size() -> void:
	var button: MaskButton = _button()
	button.size = Vector2(400, 200)
	assert_true(button._has_point(Vector2(150, 150)))
	assert_false(button._has_point(Vector2(250, 150)))


func test_glow_only_while_hovered() -> void:
	var button: MaskButton = _button()
	assert_eq(button.glow_alpha(), 0.0, "без курсора подсветки нет")
	button.mouse_entered.emit()
	assert_gt(button.glow_alpha(), 0.0, "курсор над предметом — силуэт светлее")
	button.mouse_exited.emit()
	assert_eq(button.glow_alpha(), 0.0)


func test_pointing_hand_cursor() -> void:
	assert_eq(_button().mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND, "видно, что нажимается")
