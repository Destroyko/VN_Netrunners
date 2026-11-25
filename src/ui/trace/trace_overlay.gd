extends CanvasLayer
## Заметный трейс на экране игрока (решено разработчиком 25.11.2026, шаг 7, часть 7): пока на
## узле идёт трейс — где бы ни был герой — вверху экрана полоска «ТРЕЙС», как панель задач. За
## минуту реального времени до конца вспыхивает рамка экрана, чаще к концу; последние секунды
## рамка горит и тикает таймер с миллисекундами (`TraceAlarm`).
##
## Только показ: сколько осталось — сеанс (`HackSession`), как переводить в секунды — часы.

const STRIP_HEIGHT: float = 22.0
const FRAME_WIDTH: int = 6

var _strip: PanelContainer
var _bar: ProgressBar
var _minutes: Label
var _frame: Panel
var _timer: Label
var _seconds_left: float = -1.0


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_hide_all()


func _process(_delta: float) -> void:
	if not PhoneOverlay.in_game():
		_seconds_left = -1.0
		_hide_all()
		return
	var session := HackSession.new(Network.for_game())
	if not session.is_tracing():
		_seconds_left = -1.0
		_hide_all()
		return
	var left: int = session.trace_left()
	var total: int = maxi(1, session.trace_total())
	var speed: float = Clock.program_speedup if Clock.is_fast_forwarding() else 1.0
	_seconds_left = TraceAlarm.real_seconds(left, Clock.real_seconds_per_minute, speed, Clock.seconds_into_minute() if not Clock.is_paused() else 0.0)
	_strip.visible = true
	_bar.value = float(left) / float(total)
	_minutes.text = "%d мин" % left
	_frame.visible = TraceAlarm.frame_on(_seconds_left)
	_timer.visible = TraceAlarm.stage(_seconds_left) == TraceAlarm.SOLID
	_timer.text = TraceAlarm.timer_text(_seconds_left)


## Для тестов и отладки: реальные секунды до конца, -1 — трейса нет.
func seconds_left() -> float:
	return _seconds_left


func is_shown() -> bool:
	return _strip.visible


func _hide_all() -> void:
	_strip.visible = false
	_frame.visible = false
	_timer.visible = false


func _build() -> void:
	var danger: Color = GameTheme.color("danger", GameTheme.current_id)
	var warn: Color = GameTheme.color("warn", GameTheme.current_id)
	var mono: Font = GameTheme.font("mono")

	_frame = Panel.new()
	_frame.name = "Frame"
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := StyleBoxFlat.new()
	border.draw_center = false
	border.border_color = danger
	border.set_border_width_all(FRAME_WIDTH)
	_frame.add_theme_stylebox_override("panel", border)
	add_child(_frame)

	_strip = PanelContainer.new()
	_strip.name = "TraceStrip"
	_strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE)
	_strip.custom_minimum_size = Vector2(0, STRIP_HEIGHT)
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.05, 0.06, 0.92)
	back.set_content_margin_all(3)
	back.content_margin_left = 10
	back.content_margin_right = 10
	_strip.add_theme_stylebox_override("panel", back)
	add_child(_strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(row)
	var title := Label.new()
	title.text = "ТРЕЙС"
	title.add_theme_font_override("font", mono)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", warn)
	row.add_child(title)
	_bar = ProgressBar.new()
	_bar.name = "Bar"
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.custom_minimum_size = Vector2(0, 6)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = warn
	var empty := StyleBoxFlat.new()
	empty.bg_color = Color(warn, 0.18)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", empty)
	row.add_child(_bar)
	_minutes = Label.new()
	_minutes.name = "Minutes"
	_minutes.add_theme_font_override("font", mono)
	_minutes.add_theme_font_size_override("font_size", 12)
	_minutes.add_theme_color_override("font_color", warn)
	row.add_child(_minutes)

	_timer = Label.new()
	_timer.name = "Timer"
	_timer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 0)
	_timer.position.y = STRIP_HEIGHT + 8
	_timer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.add_theme_font_override("font", mono)
	_timer.add_theme_font_size_override("font_size", 28)
	_timer.add_theme_color_override("font_color", danger)
	_timer.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_timer.add_theme_constant_override("outline_size", 6)
	_timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_timer)
