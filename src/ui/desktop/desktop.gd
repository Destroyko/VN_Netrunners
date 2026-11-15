class_name Desktop
extends Control
## Рабочий стол: иконки приложений, окна, панель задач (docs/tech/desktop-layout.md).
##
## Здесь только интерфейс: правила игры живут в системах, а стол читает GameState и слушает
## EventBus. Окно закрыли — логика не пострадала: терминал и прочее состояние живут в
## `GameState` и в `Terminal`, который держит стол, а не окно.

const DEBUG_CONSOLE: String = "res://src/debug/debug_console.tscn"
## Окно головоломки: не приложение, иконки у него нет.
const PUZZLE_APP: String = "puzzle"
## Удалённый сеанс: трансляция рабочего стола цели (экран блокировки, потом стол). Без иконки.
const REMOTE_APP: String = "remote"
const ICON_SIZE: Vector2 = Vector2(96, 72)

## Приложения: порядок = порядок иконок. `requires` — условие доступности на общем языке;
## пока оно не выполнено, иконка серая (игрок видит, что мир больше, чем открыто).
## `size` — размер окна при первом открытии. Содержимое M1: терминал настоящий, остальное — заглушки.
const APPS: Array[Dictionary] = [
	{"id": "terminal", "title": "Терминал", "color": Color(0.2, 0.55, 0.35), "size": Vector2(860, 520), "min": Vector2(520, 320)},
	{"id": "map", "title": "Карта сети", "color": Color(0.25, 0.4, 0.55), "size": Vector2(560, 380), "min": Vector2(320, 220)},
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
var _dialog: PuzzleDialog
var _puzzle_window: DesktopWindow
## Тренировочная головоломка из консоли разработчика: терминал о ней не знает.
var _practice: bool = false
## Консоль, к которой привязана трансляция: в неё уходят действия мышью.
var _remote_view: TerminalView
var _rows: VBoxContainer
var _emergency: Control
var _opened_count: int = 0


func _ready() -> void:
	terminal = Terminal.new()
	# Трейс может оборвать сеанс сам, пока окно терминала закрыто: окно головоломки и карта
	# должны узнать об этом и без него.
	terminal.ticked.connect(func(_result: TermResult) -> void: _on_result_shown())
	_build()
	_add_debug_console()
	apply_mode()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var rows := VBoxContainer.new()
	_rows = rows
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.add_theme_constant_override("separation", 0)
	add_child(rows)

	_area = Control.new()
	_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_area.clip_contents = true
	rows.add_child(_area)

	# Фон стола принимает файлы, брошенные из трансляции чужого ПК: они скачиваются к себе.
	var wallpaper := DesktopDropZone.new()
	wallpaper.name = "Wallpaper"
	wallpaper.color = Color(0.06, 0.07, 0.1)
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	wallpaper.mouse_filter = Control.MOUSE_FILTER_PASS
	wallpaper.remote_file_dropped.connect(_on_remote_file_dropped)
	wallpaper.menu_requested.connect(_on_wallpaper_menu)
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
	if app_id == "map":
		var map := MapView.new()
		map.setup(terminal)
		return map
	if app_id == "terminal":
		var view := TerminalView.new()
		view.setup(terminal)
		view.puzzle_requested.connect(_on_puzzle_requested.bind(view))
		view.remote_requested.connect(_on_remote_requested.bind(view))
		view.result_shown.connect(_on_result_shown)
		view.ready.connect(view.focus_entry)
		return view
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


## Головоломка открывается обычным окном поверх терминала: его можно свернуть и закрыть.
## Закрытие — это «выйти»: засчитывается то, что успели собрать. Игровое время при этом стоит
## (time.md). Итог уходит в терминал, а его ответ — в вывод окна терминала.
## Подключились к ПК или он спросил пароль: рядом с консолью — трансляция его рабочего стола,
## как в Radmin (desktop-layout.md, «Удалённый сеанс»). Пароль не введён — экран блокировки;
## ввести можно там или в консоли, путь один. Соединение закрылось — окно закрывается.
func _on_remote_requested(request: Dictionary, view: TerminalView) -> void:
	var node: String = str(request.get("node", ""))
	var old: DesktopWindow = window_of(REMOTE_APP)
	if old != null:
		if str(old.get_meta("node", "")) == node:
			focus(old)
			return
		old.close()
	var address: String = str(request.get("address", ""))
	var window := DesktopWindow.new()
	window.app_id = REMOTE_APP
	window.title = "Удалённый сеанс — %s" % address
	window.set_meta("node", node)
	window.set_minimum(Vector2(420, 300))
	window.closed.connect(_on_window_closed)
	window.closed.connect(func(_w: DesktopWindow) -> void:
		# Закрыли трансляцию у экрана блокировки — это отказ от входа, как пустая строка в консоли.
		if terminal.login_pending() and is_instance_valid(view):
			view.submit(""))
	window.focus_requested.connect(focus)
	window.state_changed.connect(func(_w: DesktopWindow) -> void: _sync_taskbar())
	_windows.add_child(window)
	window.size = Vector2(560, 400)
	window.position = WindowRules.cascade(_opened_count, window.size, _windows.size)
	var session := RemoteSession.new()
	window.body.add_child(session)
	_remote_view = view
	session.setup(terminal, node, address, terminal.net.remote_desktop(node), func(text: String) -> String:
		view.submit(text)
		return "" if not terminal.login_pending() else "доступ запрещён", run_remote_command)
	_open[REMOTE_APP] = window
	_opened_count += 1
	focus(window)


## После каждой команды окно удалённого узла сверяется с консолью: вошли — проводник,
## отменили вход или отключились — окно закрыто, файлы поменялись — список перечитан.
## Действие мышью в трансляции — команда той же консоли: путь один, правила одни. Если команда
## спросила подтверждение (системный файл), спрашиваем окном, а ответ уходит в консоль.
func run_remote_command(line: String) -> String:
	if _remote_view == null or not is_instance_valid(_remote_view):
		return ""
	var result: TermResult = _remote_view.submit(line)
	if terminal.has_question():
		var dialog := ConfirmationDialog.new()
		dialog.name = "RemoteConfirm"
		dialog.dialog_text = terminal.last_question()
		dialog.ok_button_text = "Да"
		dialog.cancel_button_text = "Нет"
		dialog.confirmed.connect(func() -> void: _answer_remote(dialog, "y"))
		dialog.canceled.connect(func() -> void: _answer_remote(dialog, "n"))
		add_child(dialog)
		dialog.popup_centered()
		return ""
	return result.lines[result.lines.size() - 1] if not result.lines.is_empty() else ""


func _answer_remote(dialog: ConfirmationDialog, answer: String) -> void:
	if is_instance_valid(_remote_view) and terminal.has_question():
		_remote_view.submit(answer)
	dialog.queue_free()


## Правая кнопка по своему столу: «Вставить» скачивает файл из буфера трансляции (как в RDP:
## скопировал там — вставил здесь). Вырезанный там файл здесь тоже просто копируется.
func _on_wallpaper_menu(at_position: Vector2) -> void:
	var menu := PopupMenu.new()
	menu.name = "WallpaperMenu"
	menu.add_item("Вставить", 0)
	var clip: Dictionary = FileBrowser.clipboard
	menu.set_item_disabled(0, clip.is_empty() or terminal.session.target_id() != str(clip.get("node", "")))
	menu.id_pressed.connect(func(_id: int) -> void: paste_to_own_desktop())
	menu.popup_hide.connect(menu.queue_free)
	add_child(menu)
	menu.position = Vector2i(get_screen_position() + at_position)
	menu.popup()


func paste_to_own_desktop() -> void:
	if not FileBrowser.clipboard.is_empty():
		_on_remote_file_dropped(FileBrowser.clipboard)


## Файл из трансляции брошен на свой стол — скачать к себе, как `cp` с узла.
func _on_remote_file_dropped(data: Dictionary) -> void:
	if terminal.session.target_id() != str(data.get("node", "")):
		return
	run_remote_command("cp \"%s\"" % str(data["remote_file"]))


func _sync_remote_window() -> void:
	var window: DesktopWindow = window_of(REMOTE_APP)
	if window == null:
		return
	var node: String = str(window.get_meta("node", ""))
	if terminal.login_pending():
		return
	var inside: bool = terminal.session.has_connection() and terminal.session.target_id() == node
	if not inside:
		window.close()
		return
	var session: RemoteSession = window.body.get_child(0) as RemoteSession
	if session.is_locked():
		session.unlock()
	else:
		session.refresh()


func _on_puzzle_requested(request: Dictionary, view: TerminalView) -> void:
	_show_puzzle(request, view)


## Отладка: головоломка без взлома и без подключения (команда `play` в консоли F1).
## Итог в игру не попадает, возвращается числом слоёв через `practice_finished`.
signal practice_finished(gained: int)


func play_puzzle(kind: String, level: int, seed_value: int) -> bool:
	if has_puzzle_open():
		return false
	var puzzle: RefCounted
	var layers_total: int = 1
	if kind == "password":
		puzzle = PasswordPuzzle.generate(level, seed_value, 0)
	elif kind == "dump":
		puzzle = DumpPuzzle.generate(level, seed_value)
	else:
		layers_total = int(PuzzleLevels.matrix(level)["sequences"])
		puzzle = MatrixPuzzle.generate_round(level, seed_value, 0)
	_show_puzzle({
		"type": "puzzle", "kind": kind, "node": "тренировка", "service": kind,
		"layers_done": 0, "layers_total": layers_total, "puzzle": puzzle,
		"rounds": layers_total, "seed": seed_value, "difficulty": level,
	}, null)
	return true


func _show_puzzle(request: Dictionary, view: TerminalView) -> void:
	if has_puzzle_open():
		return
	# Головоломка воспроизводится по виду, ступени и сиду — их и пишем в журнал.
	var puzzle_obj: Object = request.get("puzzle") as Object
	SessionLog.write("puzzle", "открыта: %s, ступень %s, сид %s, узел %s, порт %s" % [
		request.get("kind", ""), request.get("difficulty", request.get("level", "?")),
		puzzle_obj.get("puzzle_seed") if puzzle_obj != null else "?",
		request.get("node", ""), request.get("port", "-"),
	])
	_practice = view == null
	var window := DesktopWindow.new()
	window.app_id = PUZZLE_APP
	window.title = "Взлом"
	window.set_minimum(Vector2(420, 460))
	window.closed.connect(_on_window_closed)
	window.closed.connect(func(_w: DesktopWindow) -> void:
		# Окно уже закрывается: итог отдаём, а второй раз закрывать не надо.
		_puzzle_window = null
		if _dialog != null and is_instance_valid(_dialog):
			_dialog.abandon())
	window.focus_requested.connect(focus)
	window.state_changed.connect(func(_w: DesktopWindow) -> void: _sync_taskbar())
	_windows.add_child(window)
	_dialog = PuzzleDialog.new()
	window.body.add_child(_dialog)
	_dialog.setup(request)
	# Окно не меньше содержимого: широкая сетка дампа не должна обрезаться.
	var needed: Vector2 = _dialog.get_combined_minimum_size() + Vector2(16, WindowRules.TITLE_HEIGHT + 16)
	window.size = Vector2(440, 480).max(needed)
	window.position = WindowRules.cascade(_opened_count, window.size, _windows.size)
	_dialog.finished.connect(func(gained: int) -> void:
		var done_window: DesktopWindow = _puzzle_window
		_dialog = null
		_puzzle_window = null
		if view != null:
			view.show_result(terminal.finish_puzzle(gained))
		else:
			practice_finished.emit(gained)
		if is_instance_valid(done_window):
			done_window.close())
	_puzzle_window = window
	_open[PUZZLE_APP] = window
	_opened_count += 1
	focus(window)


func has_puzzle_open() -> bool:
	return _puzzle_window != null and is_instance_valid(_puzzle_window)


## Сеанс оборвали (`dc`, трейс), пока головоломка открыта: окну больше нечего решать.
func _close_stale_puzzle() -> void:
	if has_puzzle_open() and not _practice and terminal.current_puzzle() == null:
		var stale: DesktopWindow = _puzzle_window
		_dialog = null
		_puzzle_window = null
		stale.close()


## Команда выполнена: карта и режим стола перечитывают состояние.
func _on_result_shown() -> void:
	_close_stale_puzzle()
	_sync_remote_window()
	var map: DesktopWindow = window_of("map")
	if map != null:
		(map.body.get_child(0) as MapView).refresh()
	apply_mode()


# --- Аварийная консоль ----------------------------------------------------------

## Рабочий стол держится на x-server.sys и на ОС: нет их — вместо стола консоль на весь экран
## (hacking.md, «Свой ПК можно сломать»). Игрок видит, что натворил, и у него остаётся терминал.
func apply_mode() -> void:
	var report: Dictionary = Room.monitor(Filesystem.for_node(Network.HOME_ID))
	var broken: bool = not bool(report["desktop"])
	_rows.visible = not broken
	if broken and _emergency == null:
		_emergency = _make_emergency(report["lines"] as PackedStringArray)
		add_child(_emergency)
	elif not broken and _emergency != null:
		_emergency.queue_free()
		_emergency = null


func is_emergency() -> bool:
	return _emergency != null and is_instance_valid(_emergency)


func _make_emergency(lines: PackedStringArray) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0, 0, 0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(box)

	var back := Button.new()
	back.name = "BackToRoom"
	back.text = "Отойти от компьютера"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(Screens.ROOM))
	box.add_child(back)

	var view := TerminalView.new()
	view.setup(terminal)
	view.print_lines(lines)
	view.result_shown.connect(_on_result_shown)
	view.puzzle_requested.connect(_on_puzzle_requested.bind(view))
	view.remote_requested.connect(_on_remote_requested.bind(view))
	view.ready.connect(view.focus_entry)
	box.add_child(view)
	return root
