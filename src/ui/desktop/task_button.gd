class_name TaskButton
extends Button
## Кнопка окна на панели задач: значок и название, сверху полоска состояния окна. В фокусе — яркая
## полоса акцента во всю кнопку, открыто без фокуса — короткая серая, свёрнуто — едва заметная.
## Смена состояния плавная (Tween), в тестах и вне дерева — сразу (`DesktopWindow.animate`).

enum State { FOCUSED, OPEN, MINIMIZED }

const STRIP_HEIGHT: float = 3.0
## Ширина короткой полоски у окна без фокуса и время перехода.
const SHORT_WIDTH: float = 16.0
const FADE_TIME: float = 0.15

var state: State = State.OPEN
## Цвета полоски по состояниям (задаёт панель задач из темы).
var focused_color: Color = Color.WHITE
var open_color: Color = Color.GRAY

## Текущий вид полоски: цвет и доля ширины кнопки (0 — короткая, 1 — во всю кнопку).
var strip_color: Color = Color.GRAY:
	set(value):
		strip_color = value
		queue_redraw()
var strip_span: float = 0.0:
	set(value):
		strip_span = value
		queue_redraw()

var _tween: Tween


func set_state(value: State) -> void:
	var changed: bool = value != state
	state = value
	var color: Color = focused_color if value == State.FOCUSED else open_color
	if value == State.MINIMIZED:
		color = Color(open_color, 0.25)
	var span: float = 1.0 if value == State.FOCUSED else 0.0
	if _tween != null:
		_tween.kill()
	if not changed or not DesktopWindow.animate or not is_inside_tree():
		strip_color = color
		strip_span = span
		return
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "strip_color", color, FADE_TIME)
	_tween.tween_property(self, "strip_span", span, FADE_TIME)


func _draw() -> void:
	var inset: float = 6.0
	var full: float = size.x - inset * 2.0
	var width: float = lerpf(SHORT_WIDTH, full, strip_span)
	var rect := Rect2((size.x - width) / 2.0, 0.0, width, STRIP_HEIGHT)
	draw_rect(rect, strip_color)
