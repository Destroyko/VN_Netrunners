class_name Desktop
extends Control
## Рабочий стол: иконки приложений, окна, панель задач (docs/tech/desktop-layout.md).
##
## Здесь только интерфейс: правила игры живут в системах, а стол читает GameState и слушает
## EventBus. Окно закрыли — логика не пострадала: терминал и прочее состояние живут в
## `GameState` и в `Terminal`, который держит стол, а не окно.

const DEBUG_CONSOLE: String = "res://src/debug/debug_console.tscn"
const ICON_SIZE: Vector2 = Vector2(96, 72)

## Приложения: порядок = порядок иконок. `requires` — условие доступности на общем языке;
## пока оно не выполнено, иконка серая (игрок видит, что мир больше, чем открыто).
## `size` — размер окна при первом открытии. Содержимое M1: терминал настоящий, остальное — заглушки.
const APPS: Array[Dictionary] = [
	{"id": "terminal", "title": "Терминал", "color": Color(0.2, 0.55, 0.35), "size": Vector2(860, 520), "min": Vector2(520, 320)},
	{"id": "files", "title": "Файлы", "color": Color(0.3, 0.45, 0.7), "size": Vector2(520, 380), "min": Vector2(320, 220)},
	{"id": "mail", "title": "Почта", "color": Color(0.6, 0.45, 0.25), "size": Vector2(520, 380), "min": Vector2(320, 220)},
	{"id": "bank", "title": "Банк", "color": Color(0.5, 0.5, 0.25), "size": Vector2(520, 380), "min": Vector2(320, 220)},
	{"id": "news", "title": "Новости", "color": Color(0.55, 0.3, 0.3), "size": Vector2(520, 380), "min": Vector2(320, 220)},
	{"id": "shop", "title": "Магазин", "color": Color(0.45, 0.3, 0.55), "size": Vector2(520, 380), "min": Vector2(320, 220)},
	{"id": "messenger", "title": "Мессенджер", "color": Color(0.25, 0.5, 0.55), "size": Vector2(520, 380), "min": Vector2(320, 220)},
	{"id": "work", "title": "Работа", "color": Color(0.4, 0.4, 0.4), "size": Vector2(520, 380), "min": Vector2(320, 220)},
	{"id": "group", "title": "Сайт группы", "color": Color(0.7, 0.25, 0.45), "size": Vector2(520, 380), "min": Vector2(320, 220),
		"requires": [{"flag": "gate.pressure"}]},
]

## Положение и размер окон запоминаются между открытиями в пределах сессии.
static var _remembered: Dictionary = {}

## Терминал живёт, пока открыт рабочий стол, а не окно: закрыл и открыл — история на месте.
var terminal: Terminal

var _area: Control
var _icons: GridContainer
var _windows: Control
var _taskbar: Taskbar
var _open: Dictionary = {}
var _opened_count: int = 0


func _ready() -> void:
	terminal = Terminal.new()
	_build()
	_add_debug_console()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.add_theme_constant_override("separation", 0)
	add_child(rows)

	_area = Control.new()
	_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_area.clip_contents = true
	rows.add_child(_area)

	var wallpaper := ColorRect.new()
	wallpaper.color = Color(0.06, 0.07, 0.1)
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	wallpaper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area.add_child(wallpaper)

	_icons = GridContainer.new()
	_icons.columns = 1
	_icons.position = Vector2(12, 12)
	_icons.add_theme_constant_override("v_separation", 8)
	_area.add_child(_icons)
	for app: Dictionary in APPS:
		_icons.add_child(_make_icon(app))

	_windows = Control.new()
	_windows.set_anchors_preset(Control.PRESET_FULL_RECT)
	_windows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area.add_child(_windows)

	_taskbar = Taskbar.new()
	_taskbar.window_button_pressed.connect(_on_taskbar_button)
	_taskbar.menu_requested.connect(_on_menu)
	rows.add_child(_taskbar)


func _make_icon(app: Dictionary) -> Button:
	var button := Button.new()
	button.name = "Icon_" + str(app["id"])
	button.custom_minimum_size = ICON_SIZE
	button.text = str(app["title"])
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	var swatch := StyleBoxFlat.new()
	swatch.bg_color = (app["color"] as Color) if is_available(app) else Color(0.25, 0.25, 0.28)
	button.add_theme_stylebox_override("normal", swatch)
	button.add_theme_stylebox_override("hover", swatch)
	button.add_theme_stylebox_override("pressed", swatch)
	button.disabled = not is_available(app)
	button.tooltip_text = "" if is_available(app) else "Пока недоступно"
	button.pressed.connect(open_app.bind(str(app["id"])))
	return button


func _add_debug_console() -> void:
	if not OS.is_debug_build():
		return
	var scene: PackedScene = load(DEBUG_CONSOLE) as PackedScene
	if scene != null:
		add_child(scene.instantiate())


# --- Приложения ----------------------------------------------------------------

static func app_definition(app_id: String) -> Dictionary:
	for app: Dictionary in APPS:
		if str(app["id"]) == app_id:
			return app
	return {}


static func is_available(app: Dictionary) -> bool:
	return Conditions.check_all(app.get("requires", []) as Array)


## Открыть приложение или поднять уже открытое: одно окно на приложение.
func open_app(app_id: String) -> DesktopWindow:
	var app: Dictionary = app_definition(app_id)
	if app.is_empty() or not is_available(app):
		return null
	var existing: DesktopWindow = _open.get(app_id) as DesktopWindow
	if existing != null:
		if existing.is_minimized:
			existing.restore()
		focus(existing)
		return existing

	var window := DesktopWindow.new()
	window.app_id = app_id
	window.title = str(app["title"])
	window.set_minimum(app["min"] as Vector2)
	window.closed.connect(_on_window_closed)
	window.focus_requested.connect(focus)
	window.state_changed.connect(func(_w: DesktopWindow) -> void: _sync_taskbar())
	_windows.add_child(window)
	_apply_geometry(window, app)
	window.body.add_child(_make_content(app_id))
	_open[app_id] = window
	_opened_count += 1
	focus(window)
	return window


func _apply_geometry(window: DesktopWindow, app: Dictionary) -> void:
	var remembered: Rect2 = _remembered.get(window.app_id, Rect2()) as Rect2
	var area: Vector2 = _windows.size
	if remembered.size != Vector2.ZERO:
		window.position = remembered.position
		window.size = remembered.size
		return
	window.size = app["size"] as Vector2
	window.position = WindowRules.cascade(_opened_count, window.size, area)


## Содержимое окна. Терминал и остальное подключаются здесь, остальные приложения — заглушки M1.
func _make_content(app_id: String) -> Control:
	var label := Label.new()
	label.text = "Здесь будет приложение «%s».\nВ M1 это заглушка." % str(app_definition(app_id).get("title", app_id))
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func focus(window: DesktopWindow) -> void:
	for other: DesktopWindow in open_windows():
		other.is_focused = other == window
	window.move_to_front()
	_sync_taskbar()


func open_windows() -> Array[DesktopWindow]:
	var result: Array[DesktopWindow] = []
	for window: Variant in _open.values():
		if is_instance_valid(window):
			result.append(window as DesktopWindow)
	return result


func window_of(app_id: String) -> DesktopWindow:
	var window: DesktopWindow = _open.get(app_id) as DesktopWindow
	return window if is_instance_valid(window) else null


func _on_window_closed(window: DesktopWindow) -> void:
	_remembered[window.app_id] = Rect2(window.position, window.size)
	_open.erase(window.app_id)
	_taskbar.remove_window(window.app_id)
	_sync_taskbar()


func _sync_taskbar() -> void:
	for window: DesktopWindow in open_windows():
		_taskbar.set_window(window.app_id, window.title, window.is_focused, window.is_minimized)


func _on_taskbar_button(app_id: String) -> void:
	var window: DesktopWindow = window_of(app_id)
	if window == null:
		return
	if window.is_minimized:
		window.restore()
	elif window.is_focused:
		window.minimize()
	else:
		focus(window)


func _on_menu(action: String) -> void:
	match action:
		"back_to_room":
			get_tree().change_scene_to_file(Screens.ROOM)
		"main_menu":
			get_tree().change_scene_to_file(Screens.MAIN_MENU)
