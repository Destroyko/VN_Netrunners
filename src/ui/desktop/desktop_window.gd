class_name DesktopWindow
extends Control
## Окно рабочего стола: заголовок с кнопками, перетаскивание за заголовок, растягивание за угол,
## фокус по клику (docs/tech/desktop-layout.md, «Окна»). Содержимое — любой Control в `body`.
##
## Окно только показывает и не хранит правил игры: закрытие ничего не ломает в логике.

signal closed(window: DesktopWindow)
signal focus_requested(window: DesktopWindow)
signal state_changed(window: DesktopWindow)

## Шаг сетки отступов: 4, 8, 12, 16 (docs/tech/desktop-ui-spec.md).
const GAP: int = 8
const PAD: int = 12
const ICON_SIZE: int = 20
const BUTTON_SIZE: Vector2 = Vector2(32, 24)


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
		if _frame != null:
			_apply_theme()


## Куда складывать содержимое.
var body: VBoxContainer

var _panel: Panel
var _frame: StyleBoxFlat
var _title_label: Label
var _title_bar: HBoxContainer
var _title_panel: PanelContainer
var _title_style: StyleBoxFlat
var _icon_rect: TextureRect
var _margin: MarginContainer
var _buttons: Array[Button] = []
var _saved_rect: Rect2 = Rect2()
var _dragging: bool = false
var _resizing: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
## Тема оформления окна: у окна своего ПК — тема ПК героя, у окна чужого узла — тема этого узла
## (docs/art/themes.md). Задаётся до `_build`, поэтому окно удалённого сеанса создаёт `theme_id` заранее.
var theme_id: String = GameTheme.pc_theme_id():
	set(value):
		theme_id = value
		if _frame != null:
			_apply_theme()
## Значок приложения в шапке (имя из `assets/ui/icons/<тема>/glyph/`), "" — без значка.
var icon_id: String = "":
	set(value):
		icon_id = value
		_refresh_icon()


func _init() -> void:
	custom_minimum_size = minimum_window_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	_frame = StyleBoxFlat.new()
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	# Рамка в 1 px: содержимое отступает на неё, чтобы не перекрывать скругление.
	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = 1
	rows.offset_top = 1
	rows.offset_right = -1
	rows.offset_bottom = -1
	rows.add_theme_constant_override("separation", 0)
	add_child(rows)

	# Шапка — отдельная плашка своего тона: значок, название, три кнопки.
	_title_style = StyleBoxFlat.new()
	_title_panel = PanelContainer.new()
	_title_panel.custom_minimum_size = Vector2(0, WindowRules.TITLE_HEIGHT)
	_title_panel.gui_input.connect(_on_title_input)
	rows.add_child(_title_panel)
	_title_bar = HBoxContainer.new()
	_title_bar.add_theme_constant_override("separation", GAP)
	_title_panel.add_child(_title_bar)

	_icon_rect = TextureRect.new()
	_icon_rect.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_bar.add_child(_icon_rect)

	_title_label = Label.new()
	_title_label.text = title
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_bar.add_child(_title_label)
	_buttons.append(_add_title_button("─", "Свернуть", minimize, false))
	_buttons.append(_add_title_button("□", "Развернуть", toggle_maximize, false))
	_buttons.append(_add_title_button("✕", "Закрыть", close, true))

	# Содержимое не липнет к рамке: поле вокруг тела окна.
	_margin = MarginContainer.new()
	_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_margin.add_theme_constant_override("margin_left", PAD)
	_margin.add_theme_constant_override("margin_right", PAD)
	_margin.add_theme_constant_override("margin_top", GAP)
	_margin.add_theme_constant_override("margin_bottom", PAD)
	rows.add_child(_margin)
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", GAP)
	body.clip_contents = true
	_margin.add_child(body)

	var handle := Control.new()
	handle.name = "ResizeHandle"
	handle.custom_minimum_size = Vector2(16, 16)
	handle.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	handle.offset_left = -16
	handle.offset_top = -16
	handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	handle.gui_input.connect(_on_handle_input)
	add_child(handle)
	_apply_theme()


## Кнопка шапки: одного размера, без фона; при наведении тон плашки, у «закрыть» — `danger`.
func _add_title_button(text: String, tip: String, action: Callable, is_close: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(BUTTON_SIZE.x, BUTTON_SIZE.y)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.set_meta("is_close", is_close)
	button.pressed.connect(action)
	_title_bar.add_child(button)
	return button


## Тон шапки и рамки по теме и по фокусу: активное окно заметнее неактивного.
func _apply_theme() -> void:
	var panel: Color = GameTheme.color("panel", theme_id)
	var background: Color = GameTheme.color("background", theme_id)
	var accent: Color = GameTheme.color("accent", theme_id)
	var border: Color = GameTheme.color("border", theme_id)
	var raised: Color = GameTheme.color("panel_raised", theme_id)
	var text: Color = GameTheme.color("text", theme_id)
	var dim: Color = GameTheme.color("text_dim", theme_id)
	var radius: int = int((GameTheme.load_theme(theme_id).get("shape", {}) as Dictionary).get("radius", 4))
	var dark: bool = panel.get_luminance() < 0.4

	theme = GameTheme.build(theme_id)
	_frame.bg_color = panel
	_frame.border_color = accent if is_focused else border
	_frame.set_border_width_all(1)
	_frame.set_corner_radius_all(radius + 1)
	# На светлой теме тень мягче: тёмный ореол на светлом фоне читается грязным пятном.
	var shadow: float = (0.35 if is_focused else 0.2) * (1.0 if dark else 0.5)
	_frame.shadow_color = Color(0, 0, 0, shadow)
	_frame.shadow_size = 10 if is_focused else 5
	_frame.shadow_offset = Vector2(0, 3)
	_panel.add_theme_stylebox_override("panel", _frame)

	var bar: Color
	if dark:
		bar = background.lerp(accent, 0.3) if is_focused else background.lerp(panel, 0.3)
	else:
		bar = raised if is_focused else panel.darkened(0.06)
	_title_style.bg_color = bar
	_title_style.corner_radius_top_left = radius
	_title_style.corner_radius_top_right = radius
	_title_style.border_color = border
	_title_style.border_width_bottom = 1
	_title_style.content_margin_left = PAD
	_title_style.content_margin_right = GAP
	_title_style.content_margin_top = 0
	_title_style.content_margin_bottom = 0
	_title_panel.add_theme_stylebox_override("panel", _title_style)
	_title_label.add_theme_color_override("font_color", text if is_focused else dim)
	_icon_rect.modulate = Color(1, 1, 1, 1.0 if is_focused else 0.6)

	for button: Button in _buttons:
		var is_close: bool = bool(button.get_meta("is_close", false))
		var hover := StyleBoxFlat.new()
		hover.bg_color = GameTheme.color("danger", theme_id) if is_close else bar.lerp(text, 0.14)
		hover.set_corner_radius_all(radius)
		var empty := StyleBoxFlat.new()
		empty.bg_color = Color(0, 0, 0, 0)
		empty.set_corner_radius_all(radius)
		for state: String in ["normal", "focus"]:
			button.add_theme_stylebox_override(state, empty)
		for state: String in ["hover", "pressed"]:
			button.add_theme_stylebox_override(state, hover)
		button.add_theme_color_override("font_color", text if is_focused else dim)
		var hover_text: Color = Color.WHITE if is_close else text
		button.add_theme_color_override("font_hover_color", hover_text)
		button.add_theme_color_override("font_pressed_color", hover_text)
	_refresh_icon()


func _refresh_icon() -> void:
	if _icon_rect == null:
		return
	var texture: Texture2D = GameTheme.icon(icon_id, theme_id) if not icon_id.is_empty() else null
	_icon_rect.texture = texture
	_icon_rect.visible = texture != null


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
