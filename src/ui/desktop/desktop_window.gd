class_name DesktopWindow
extends Control
## Окно рабочего стола: заголовок с кнопками, перетаскивание за заголовок, растягивание за угол,
## фокус по клику (docs/tech/desktop-layout.md, «Окна»). Содержимое — любой Control в `body`.
##
## Окно только показывает и не хранит правил игры: закрытие ничего не ломает в логике.

signal closed(window: DesktopWindow)
signal focus_requested(window: DesktopWindow)
signal state_changed(window: DesktopWindow)

const FOCUSED_COLOR: Color = Color(0.35, 0.75, 1.0)
const IDLE_COLOR: Color = Color(0.35, 0.38, 0.45)

var app_id: String = ""
var title: String = "":
	set(value):
		title = value
		if _title_label != null:
			_title_label.text = value
var minimum_window_size: Vector2 = Vector2(320, 200)
var is_minimized: bool = false
var is_maximized: bool = false
var is_focused: bool = false:
	set(value):
		is_focused = value
		_frame.border_color = FOCUSED_COLOR if value else IDLE_COLOR
		_panel.add_theme_stylebox_override("panel", _frame)

## Куда складывать содержимое.
var body: VBoxContainer

var _panel: Panel
var _frame: StyleBoxFlat
var _title_label: Label
var _title_bar: HBoxContainer
var _saved_rect: Rect2 = Rect2()
var _dragging: bool = false
var _resizing: bool = false
var _drag_offset: Vector2 = Vector2.ZERO


func _init() -> void:
	custom_minimum_size = minimum_window_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	_frame = StyleBoxFlat.new()
	_frame.bg_color = Color(0.09, 0.1, 0.13)
	_frame.border_color = IDLE_COLOR
	_frame.set_border_width_all(2)
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_theme_stylebox_override("panel", _frame)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = 2
	rows.offset_top = 2
	rows.offset_right = -2
	rows.offset_bottom = -2
	rows.add_theme_constant_override("separation", 0)
	add_child(rows)

	_title_bar = HBoxContainer.new()
	_title_bar.custom_minimum_size = Vector2(0, WindowRules.TITLE_HEIGHT)
	_title_bar.gui_input.connect(_on_title_input)
	rows.add_child(_title_bar)

	_title_label = Label.new()
	_title_label.text = title
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_bar.add_child(_title_label)
	_add_title_button("─", "Свернуть", minimize)
	_add_title_button("□", "Развернуть", toggle_maximize)
	_add_title_button("✕", "Закрыть", close)

	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.clip_contents = true
	rows.add_child(body)

	var handle := Control.new()
	handle.name = "ResizeHandle"
	handle.custom_minimum_size = Vector2(16, 16)
	handle.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	handle.offset_left = -16
	handle.offset_top = -16
	handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	handle.gui_input.connect(_on_handle_input)
	add_child(handle)


func _add_title_button(text: String, tip: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	_title_bar.add_child(button)


# --- Состояние ----------------------------------------------------------------

func set_minimum(size: Vector2) -> void:
	minimum_window_size = size
	custom_minimum_size = size


func close() -> void:
	closed.emit(self)
	queue_free()


func minimize() -> void:
	is_minimized = true
	visible = false
	state_changed.emit(self)


func restore() -> void:
	is_minimized = false
	visible = true
	state_changed.emit(self)
	focus_requested.emit(self)


func toggle_maximize() -> void:
	var area: Vector2 = _area()
	if is_maximized:
		position = _saved_rect.position
		size = _saved_rect.size
	else:
		_saved_rect = Rect2(position, size)
		position = Vector2.ZERO
		size = area
	is_maximized = not is_maximized
	state_changed.emit(self)


## Область, в которой живут окна: родитель окна (слой окон рабочего стола).
func _area() -> Vector2:
	var parent_control: Control = get_parent() as Control
	return parent_control.size if parent_control != null else get_viewport_rect().size


# --- Мышь ----------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed:
		focus_requested.emit(self)


func _on_title_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed and not is_maximized
		_drag_offset = get_global_mouse_position() - global_position
		if button.pressed:
			focus_requested.emit(self)
		if button.pressed and button.double_click:
			toggle_maximize()
		return
	if _dragging and event is InputEventMouseMotion:
		var target: Vector2 = get_global_mouse_position() - _drag_offset - _parent_origin()
		position = WindowRules.clamp_position(target, size, _area())


func _on_handle_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_resizing = button.pressed and not is_maximized
		return
	if _resizing and event is InputEventMouseMotion:
		var wanted: Vector2 = get_global_mouse_position() - global_position
		size = WindowRules.clamp_size(wanted, minimum_window_size, position, _area())


func _parent_origin() -> Vector2:
	var parent_control: Control = get_parent() as Control
	return parent_control.global_position if parent_control != null else Vector2.ZERO
