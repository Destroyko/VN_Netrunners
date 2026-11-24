class_name PhoneNavButton
extends Button
## Кнопка навигационной панели телефона внизу экрана, как у старых смартфонов: «назад» (треугольник),
## «домой» (кружок), «свернуть» (крестик). Значок рисуется фигурой, а не шрифтом: так он одинаков на любой
## машине и красится ролями цвета темы. Правил здесь нет: что кнопка делает, решает телефон.

enum Kind { BACK, HOME, HIDE }

var kind: Kind = Kind.HOME


func _init(button_kind: Kind = Kind.HOME) -> void:
	kind = button_kind
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(72, 40)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _draw() -> void:
	var colour: Color = GameTheme.color("text") if not disabled else GameTheme.color("text_dim")
	if is_hovered():
		colour = GameTheme.color("accent")
	var c: Vector2 = size / 2.0
	var r: float = 9.0
	match kind:
		Kind.BACK:
			# треугольник вершиной влево: «назад»
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r, 0), c + Vector2(r * 0.7, -r), c + Vector2(r * 0.7, r)]), colour)
		Kind.HOME:
			draw_arc(c, r, 0.0, TAU, 32, colour, 2.5, true)
		Kind.HIDE:
			draw_line(c + Vector2(-r, -r), c + Vector2(r, r), colour, 2.5, true)
			draw_line(c + Vector2(-r, r), c + Vector2(r, -r), colour, 2.5, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		queue_redraw()
