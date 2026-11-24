class_name WindowButton
extends Button
## Кнопка шапки окна (свернуть, развернуть, восстановить, закрыть): значок рисуется линиями, а не
## символом шрифта — так он чёткий и одного веса во всех темах. Фон по состояниям задаёт окно.

enum Kind { MINIMIZE, MAXIMIZE, RESTORE, CLOSE }

## Размер значка внутри кнопки и толщина линии.
const GLYPH: float = 10.0
const LINE: float = 1.5

var kind: Kind = Kind.CLOSE:
	set(value):
		kind = value
		queue_redraw()
## Цвет значка в покое и под мышью (у «закрыть» под мышью — светлый на `danger`).
var glyph_color: Color = Color.WHITE
var glyph_hover_color: Color = Color.WHITE


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var color: Color = glyph_hover_color if is_hovered() or button_pressed else glyph_color
	var c: Vector2 = (size / 2.0).round()
	var h: float = GLYPH / 2.0
	match kind:
		Kind.MINIMIZE:
			draw_line(c + Vector2(-h, 0.5), c + Vector2(h, 0.5), color, LINE, true)
		Kind.MAXIMIZE:
			draw_rect(Rect2(c - Vector2(h, h), Vector2(GLYPH, GLYPH)), color, false, LINE, true)
		Kind.RESTORE:
			# Два окна друг за другом: заднее — только видимые края.
			var small: float = GLYPH - 3.0
			var front := Rect2(c + Vector2(-h, -h + 3.0), Vector2(small, small))
			draw_rect(front, color, false, LINE, true)
			var top_left: Vector2 = c + Vector2(-h + 3.0, -h)
			draw_line(top_left + Vector2(0, 3.0), top_left, color, LINE, true)
			draw_line(top_left, top_left + Vector2(small, 0), color, LINE, true)
			draw_line(top_left + Vector2(small, 0), top_left + Vector2(small, small), color, LINE, true)
			draw_line(top_left + Vector2(small, small), top_left + Vector2(small - 3.0, small), color, LINE, true)
		Kind.CLOSE:
			draw_line(c + Vector2(-h, -h), c + Vector2(h, h), color, LINE, true)
			draw_line(c + Vector2(-h, h), c + Vector2(h, -h), color, LINE, true)
