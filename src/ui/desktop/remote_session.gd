class_name RemoteSession
extends Control
## Удалённый сеанс — трансляция рабочего стола цели в окне, как в Radmin (docs/tech/desktop-layout.md,
## «Удалённый сеанс»). У цели обычная ОС: стол, обои, иконки, без консоли и хакерского софта.
## Сначала экран блокировки (как Win+L): имя пользователя и поле пароля. После входа — стол цели;
## «Проводник» открывается окном внутри трансляции.
##
## Правил здесь нет: пароль уходит в терминал (`submit`), файлы читает `FileBrowser`, а что разрешено
## (фаервол, права, трейс) решают системы — одинаково для мыши и для консоли.

const TASKBAR_HEIGHT: float = 26.0
const ICON_SIZE: Vector2 = Vector2(84, 60)
const APP_TITLES: Dictionary = {"files": "Проводник", "viewer": "Блокнот"}

var terminal: Terminal
var node_id: String = ""
var address: String = ""

var _desk: Dictionary = {}
var _submit: Callable
## Выполнить строку как команду консоли — так проводник копирует и удаляет.
var _run: Callable
var _lock: Control
var _desktop: Control
var _windows: Control
var _clock: Label


## `submit(text) -> String` — ввести пароль: пусто — вошли, иначе текст ошибки.
func setup(
	shared_terminal: Terminal, node: String, host: String, desk: Dictionary, submit: Callable,
	run: Callable = Callable()
) -> void:
	_run = run
	terminal = shared_terminal
	node_id = node
	address = host
	_desk = desk
	_submit = submit
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	var wallpaper := ColorRect.new()
	wallpaper.color = Color(str(desk.get("wallpaper", "#24476b")))
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	wallpaper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wallpaper)
	if terminal.login_pending():
		_show_lock()
	else:
		unlock()


func is_locked() -> bool:
	return _lock != null and is_instance_valid(_lock)


# --- Экран блокировки --------------------------------------------------------------

func _show_lock() -> void:
	_lock = CenterContainer.new()
	_lock.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_lock)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.45)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	_lock.add_child(panel)
	panel.add_child(LoginForm.create(str(_desk.get("user", "user")), _submit))


func lock_form() -> LoginForm:
	return _lock.find_children("*", "LoginForm", true, false)[0] as LoginForm if is_locked() else null


# --- Стол цели ---------------------------------------------------------------------

## Вошли (в окне или в консоли): экран блокировки уходит, появляется стол цели.
func unlock() -> void:
	if is_locked():
		_lock.queue_free()
		remove_child(_lock)
		_lock = null
	if _desktop != null:
		return
	_desktop = Control.new()
	_desktop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_desktop)

	var icons := VBoxContainer.new()
	icons.position = Vector2(8, 8)
	_desktop.add_child(icons)
	for app: Variant in _desk.get("apps", []) as Array:
		var icon := Button.new()
		icon.name = "Icon_" + str(app)
		icon.text = str(APP_TITLES.get(str(app), app))
		icon.custom_minimum_size = ICON_SIZE
		icon.focus_mode = Control.FOCUS_NONE
		icon.pressed.connect(open_app.bind(str(app)))
		icons.add_child(icon)

	# Окна внутри трансляции живут в своём слое: их нельзя утащить за край удалённого экрана.
	_windows = Control.new()
	_windows.set_anchors_preset(Control.PRESET_FULL_RECT)
	_windows.offset_bottom = -TASKBAR_HEIGHT
	_windows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desktop.add_child(_windows)

	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -TASKBAR_HEIGHT
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.08, 0.09, 0.12, 0.92)
	bar.add_theme_stylebox_override("panel", bar_style)
	_desktop.add_child(bar)
	var row := HBoxContainer.new()
	bar.add_child(row)
	var who := Label.new()
	who.text = "  %s@%s" % [_desk.get("user", "user"), address]
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(who)
	_clock = Label.new()
	row.add_child(_clock)
	refresh()


## Открыть приложение стола цели окном внутри трансляции; уже открытое — поднять.
func open_app(app: String) -> DesktopWindow:
	for window: DesktopWindow in app_windows():
		if window.app_id == app:
			window.move_to_front()
			return window
	var window := DesktopWindow.new()
	window.app_id = app
	window.title = str(APP_TITLES.get(app, app))
	window.set_minimum(Vector2(220, 160))
	window.focus_requested.connect(func(w: DesktopWindow) -> void: w.move_to_front())
	_windows.add_child(window)
	if app == "files":
		var browser := FileBrowser.new()
		browser.run_command = _run
		browser.file_opened.connect(open_file)
		browser.setup(terminal, node_id)
		window.body.add_child(browser)
	var area: Vector2 = _windows.size if _windows.size != Vector2.ZERO else Vector2(480, 300)
	window.size = Vector2(minf(320.0, area.x - 16.0), minf(230.0, area.y - 16.0))
	window.position = Vector2(ICON_SIZE.x + 16.0, 8.0)
	return window


## Показать файл узла в «Блокноте» внутри трансляции. Двоичный файл — без текста, как в жизни.
func open_file(file_path: String) -> DesktopWindow:
	var window: DesktopWindow = null
	for existing: DesktopWindow in app_windows():
		if existing.app_id == "viewer":
			window = existing
	if window == null:
		window = DesktopWindow.new()
		window.app_id = "viewer"
		window.set_minimum(Vector2(220, 140))
		window.focus_requested.connect(func(w: DesktopWindow) -> void: w.move_to_front())
		_windows.add_child(window)
		var text := TextEdit.new()
		text.editable = false
		text.size_flags_vertical = Control.SIZE_EXPAND_FILL
		text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		window.body.add_child(text)
		window.size = Vector2(300, 200)
		window.position = Vector2(ICON_SIZE.x + 40.0, 40.0)
	window.title = "Блокнот — %s" % FsPath.name_of(file_path)
	var data: Dictionary = Filesystem.for_node(node_id).file_data(file_path)
	(window.body.get_child(0) as TextEdit).text = str(data.get("text", "(двоичный файл)"))
	window.move_to_front()
	return window


func app_windows() -> Array[DesktopWindow]:
	var result: Array[DesktopWindow] = []
	if _windows == null:
		return result
	for child: Node in _windows.get_children():
		if child is DesktopWindow and not child.is_queued_for_deletion():
			result.append(child as DesktopWindow)
	return result


## После команды в консоли: файлы могли поменяться, часы — уйти вперёд.
func refresh() -> void:
	if _clock != null:
		_clock.text = "%02d:%02d  " % [Clock.hour(), Clock.minute_of_hour()]
	for window: DesktopWindow in app_windows():
		for child: Node in window.body.get_children():
			if child is FileBrowser:
				(child as FileBrowser).refresh()
