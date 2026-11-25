class_name Desktop
extends Control
## Рабочий стол: иконки приложений, окна, панель задач (docs/tech/desktop-layout.md).
##
## Здесь только интерфейс: правила игры живут в системах, а стол читает GameState и слушает
## EventBus. Окно закрыли — логика не пострадала: терминал и прочее состояние живут в
## `GameState` и в `Terminal`, который держит стол, а не окно.

const DEBUG_CONSOLE: String = "res://src/debug/debug_console.tscn"
## Окна без иконки: головоломка и удалённый сеанс (их жизнь — в DesktopPuzzles и RemoteWindows).
const PUZZLE_APP: String = DesktopPuzzles.APP_ID
const REMOTE_APP: String = RemoteWindows.APP_ID
const ICON_SIZE: Vector2 = Vector2(96, 84)

## Приложения: порядок = порядок иконок. `requires` — условие доступности на общем языке;
## пока оно не выполнено, иконка серая (игрок видит, что мир больше, чем открыто).
## `size` — размер окна при первом открытии. Содержимое M1: терминал настоящий, остальное — заглушки.
const APPS: Array[Dictionary] = [
	{"id": "terminal", "title": "Терминал", "color": Color(0.2, 0.55, 0.35), "size": Vector2(860, 520), "min": Vector2(520, 320)},
	{"id": "map", "title": "Карта сети", "color": Color(0.25, 0.4, 0.55), "size": Vector2(560, 380), "min": Vector2(320, 220)},
	{"id": "files", "title": "Файлы", "color": Color(0.3, 0.45, 0.7), "size": Vector2(520, 380), "min": Vector2(320, 220)},
	{"id": "mail", "title": "Почта", "color": Color(0.6, 0.45, 0.25), "size": Vector2(640, 420), "min": Vector2(320, 220)},
	{"id": "bank", "title": "Банк", "color": Color(0.5, 0.5, 0.25), "size": Vector2(520, 380), "min": Vector2(320, 220)},
	# `gate` — значок скрыт, пока ворота закрыты (docs/tech/gates.md); `requires` — значок виден, но серый.
	{"id": "news", "title": "Новости", "color": Color(0.55, 0.3, 0.3), "size": Vector2(520, 380), "min": Vector2(320, 220),
		"gate": Gates.NEWS},
	{"id": "shop", "title": "Магазин", "color": Color(0.45, 0.3, 0.55), "size": Vector2(520, 380), "min": Vector2(320, 220),
		"gate": Gates.SHOP},
	{"id": "tasks", "title": "Задачи", "color": Color(0.35, 0.5, 0.35), "size": Vector2(440, 480), "min": Vector2(320, 260)},
	{"id": "messenger", "title": "Сообщения", "color": Color(0.25, 0.5, 0.55), "size": Vector2(640, 460), "min": Vector2(460, 300)},
	# «Работа» (поиск работы и подработки, devices.md) — шаг 8 M3: пока серая.
	{"id": "work", "title": "Работа", "color": Color(0.4, 0.4, 0.4), "size": Vector2(520, 380), "min": Vector2(320, 220), "stub": true},
	{"id": "group", "title": "Сайт группы", "color": Color(0.7, 0.25, 0.45), "size": Vector2(520, 380), "min": Vector2(320, 220),
		"requires": [{"flag": "gate.pressure"}]},
]

## Положение и размер окон запоминаются между открытиями в пределах сессии.
static var _remembered: Dictionary = {}

## Шина звука ПК: все звуки рабочего стола (оповещения, программы) должны идти в неё. Пока
## герой отошёл, она заглушена — снаружи не слышно, что ПК не выключен, а спрятан.
const PC_BUS: String = "PC"

## Стол, от которого герой отошёл: не уничтожен, а спрятан — окна, программы, открытые файлы и
## набранная команда остаются как были (разработчик, 17.11.2026).
static var _kept: Desktop = null

## Терминал живёт, пока открыт рабочий стол, а не окно: закрыл и открыл — история на месте.
var terminal: Terminal

var _area: Control
var _icons: VFlowContainer
var _toasts: MessageToasts
var _windows: Control
var _taskbar: Taskbar
var _open: Dictionary = {}
var _puzzles: DesktopPuzzles
var _remote: RemoteWindows
var _rows: VBoxContainer
var _emergency: Control
var _opened_count: int = 0
## Id темы этого стола (`GameTheme`): окна, значки и фон берут цвета из неё.
var theme_id: String = GameTheme.DEFAULT_ID
## Какой значок рисует приложение (`assets/ui/icons/<тема>/glyph/`).
## Ярлык приложения на столе — файл с этим окончанием и полем `app` (docs/tech/desktop-layout.md).
const SHORTCUT_EXT: String = ".lnk"
## Для каких приложений ярлык уже клали (один раз за игру).
const VAR_SHORTCUTS_MADE: String = "pc.shortcuts_made"
const APP_ICONS: Dictionary = {
	"terminal": "terminal", "map": "netmap", "files": "files", "mail": "mail", "bank": "bank", "news": "news",
	"shop": "shop", "tasks": "tasks", "messenger": "messenger", "work": "work", "group": "group",
}


func _ready() -> void:
	terminal = Terminal.new()
	_puzzles = DesktopPuzzles.new(self, terminal, func(gained: int) -> void: practice_finished.emit(gained))
	_remote = RemoteWindows.new(self, terminal)
	# Трейс может оборвать сеанс сам, пока окно терминала закрыто: окно головоломки и карта
	# должны узнать об этом и без него.
	terminal.ticked.connect(func(_result: TermResult) -> void: _on_result_shown())
	_build()
	_add_debug_console()
	set_pc_sound(true)
	_attach_phone()
	EventBus.passed_out.connect(_on_passed_out)
	# ПК загрузился (перезагрузка из меню или командой `reboot`) — стол собирается заново: окна
	# после настоящей перезагрузки закрыты.
	EventBus.pc_power_changed.connect(func(on: bool) -> void:
		if on and is_inside_tree() and is_visible_in_tree():
			call_deferred("_restart"))
	EventBus.mail_received.connect(func(_uid: String, _id: String) -> void: _refresh_mail_icon())
	EventBus.mail_read.connect(func(_uid: String, _id: String) -> void: _refresh_mail_icon())
	_refresh_mail_icon()
	EventBus.news_published.connect(func(_id: String) -> void: _refresh_news_icon())
	EventBus.news_read.connect(func(_id: String) -> void: _refresh_news_icon())
	_refresh_news_icon()
	apply_mode()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Оформление стола: тема ПК героя (по `pc.os` или подмене игрока), перезагрузка пересобирает стол.
	theme_id = GameTheme.pc_theme_id()
	theme = GameTheme.build(theme_id)
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
	wallpaper.color = GameTheme.color("background", theme_id)
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	wallpaper.mouse_filter = Control.MOUSE_FILTER_PASS
	wallpaper.remote_file_dropped.connect(func(data: Dictionary) -> void: _remote.drop_file(data))
	wallpaper.menu_requested.connect(func(at: Vector2) -> void: _remote.show_paste_menu(at))
	_area.add_child(wallpaper)

	# Значки идут столбцом сверху вниз и переносятся в следующий столбец, когда не помещаются по высоте.
	_icons = VFlowContainer.new()
	_icons.name = "Icons"
	_icons.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_icons.offset_left = 12
	_icons.offset_top = 12
	_icons.offset_bottom = -12
	_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icons.add_theme_constant_override("v_separation", 4)
	_icons.add_theme_constant_override("h_separation", 4)
	_area.add_child(_icons)
	ensure_shortcuts()
	_fill_icons()
	EventBus.flag_changed.connect(func(flag: String, _value: bool) -> void:
		if flag.begins_with("gate."):
			ensure_shortcuts()
			_fill_icons())

	# Самочувствие и деньги — в строке свёрнутого телефона (PhoneOverlay), трекер задачи — в
	# правом верхнем углу стола, мысли героя — внизу по центру.
	_windows = Control.new()
	_windows.set_anchors_preset(Control.PRESET_FULL_RECT)
	_windows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area.add_child(_windows)

	# Строка цели — поверх окон (её не закрывает ни одно окно), под затемнением, которое добавляется
	# к столу позже. В теме ОС; клик открывает «Задачи» окном стола.
	var tracker := QuestTracker.new()
	tracker.use_theme(theme_id)
	tracker.place_top_right()
	tracker.open_requested.connect(func() -> void: open_app("tasks"))
	_area.add_child(tracker)

	# Сообщения системы ПК — вверху по центру, поверх окон (не мысли героя).
	var notice := SystemNotice.new()
	notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 8)
	notice.grow_horizontal = Control.GROW_DIRECTION_BOTH

	# Уведомления о сообщениях — справа внизу над часами панели задач, поверх окон.
	_toasts = MessageToasts.new()
	_toasts.theme_id = theme_id
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toasts.is_reading = is_reading_messages
	_toasts.chat_requested.connect(open_chat)

	# Мысль поверх окон: её должно быть видно, даже когда стол завален окнами.
	var thoughts := HeroThoughts.new()
	thoughts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 16)
	thoughts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	thoughts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_area.add_child(thoughts)
	_area.add_child(notice)
	_area.add_child(_toasts)

	_taskbar = Taskbar.new()
	_taskbar.window_button_pressed.connect(_on_taskbar_button)
	_taskbar.menu_requested.connect(_on_menu)
	_taskbar.leave_requested.connect(leave_pc)
	rows.add_child(_taskbar)


func _make_icon(app: Dictionary) -> Button:
	var button := Button.new()
	button.name = "Icon_" + str(app["id"])
	button.custom_minimum_size = ICON_SIZE
	button.text = str(app["title"])
	# Значок стола без подложки: фон проступает только под мышью, как в настоящей ОС.
	button.theme_type_variation = "FlatButton"
	button.focus_mode = Control.FOCUS_NONE
	# Значок темы над подписью; серое приложение показывается блёклым.
	var icon: Texture2D = GameTheme.icon(str(APP_ICONS.get(str(app["id"]), "")), theme_id)
	if icon != null:
		button.icon = icon
		button.expand_icon = true
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", 44)
		button.add_theme_constant_override("h_separation", 0)
	else:
		var swatch := StyleBoxFlat.new()
		swatch.bg_color = app["color"] as Color
		button.add_theme_stylebox_override("normal", swatch)
		button.flat = false
	if not is_available(app):
		button.modulate = Color(1, 1, 1, 0.45)
	button.disabled = not is_available(app)
	button.tooltip_text = "" if is_available(app) else "Пока недоступно"
	button.pressed.connect(open_app.bind(str(app["id"])))
	return button


## Значки приложений; скрытые закрытыми воротами не рисуются.
func _fill_icons() -> void:
	for child: Node in _icons.get_children():
		_icons.remove_child(child)
		child.queue_free()
	# Стол — папка `/home/desktop`: значок приложения — есть его ярлык, остальное — файлы и папки.
	var on_desk: Dictionary = shortcut_apps()
	for app: Dictionary in APPS:
		if on_desk.has(str(app["id"])) and is_shown(app):
			_icons.add_child(_make_icon(app))
	for entry: Dictionary in Filesystem.for_node(Network.HOME_ID).list(Terminal.DESKTOP_DIR, true):
		if not str(entry["name"]).ends_with(SHORTCUT_EXT):
			_icons.add_child(_make_file_icon(entry))
	_refresh_news_icon()
	_refresh_mail_icon()


## Ярлыки приложений на столе: {id приложения: путь ярлыка}.
static func shortcut_apps() -> Dictionary:
	var result: Dictionary = {}
	var fs: Filesystem = Filesystem.for_node(Network.HOME_ID)
	for entry: Dictionary in fs.list(Terminal.DESKTOP_DIR, true):
		var path: String = str(entry["path"])
		if path.ends_with(SHORTCUT_EXT):
			var app: String = str(fs.file_data(path).get("app", ""))
			if not app.is_empty():
				result[app] = path
	return result


## Положить на стол ярлык каждого приложения — один раз за игру: удалённый игроком ярлык не
## возвращается сам, а приложение, появившееся в новой версии игры, получает ярлык. Спрятанное
## воротами получает ярлык, когда ворота откроются: иначе папка стола выдаёт скрытое.
static func ensure_shortcuts() -> void:
	var made: Array = (GameState.get_var_or(VAR_SHORTCUTS_MADE, []) as Array).duplicate()
	var fs: Filesystem = Filesystem.for_node(Network.HOME_ID)
	var changed: bool = false
	for app: Dictionary in APPS:
		var id: String = str(app["id"])
		if made.has(id) or not is_shown(app):
			continue
		# Ярлык — системный файл: удалить можно, но консоль спросит.
		fs.put_file("%s/%s%s" % [Terminal.DESKTOP_DIR, str(app["title"]), SHORTCUT_EXT], {"app": id, "system": true, "size_kb": 1})
		made.append(id)
		changed = true
	if changed:
		GameState.set_filesystem_state(Network.HOME_ID, fs.to_dict())
		GameState.set_var(VAR_SHORTCUTS_MADE, made)


## Значок файла или папки на столе: двойной смысл не нужен — клик открывает «Файлы» на столе.
func _make_file_icon(entry: Dictionary) -> Button:
	var button := Button.new()
	button.name = "File_" + str(entry["name"]).validate_node_name()
	button.custom_minimum_size = ICON_SIZE
	button.text = str(entry["name"])
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.theme_type_variation = "FlatButton"
	button.focus_mode = Control.FOCUS_NONE
	var icon: Texture2D = GameTheme.icon("files" if bool(entry["is_dir"]) else "file", theme_id)
	if icon != null:
		button.icon = icon
		button.expand_icon = true
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", 44)
		button.add_theme_constant_override("h_separation", 0)
	var path: String = str(entry["path"]) if bool(entry["is_dir"]) else Terminal.DESKTOP_DIR
	button.pressed.connect(func() -> void: open_files(path))
	return button


## Игрок читает сообщения: окно «Сообщения» открыто, не свёрнуто и в фокусе.
func is_reading_messages() -> bool:
	var window: DesktopWindow = window_of("messenger")
	return window != null and window.is_focused and not window.is_minimized and is_visible_in_tree()


## Открыть мессенджер на чате (клик по уведомлению).
func open_chat(contact: String) -> void:
	var window: DesktopWindow = open_app("messenger")
	if window != null:
		(window.body.get_child(0) as MessagesApp).open_chat(contact)


func toasts() -> MessageToasts:
	return _toasts


## «Блокнот» для `edit`: текст файла, «Сохранить» пишет его на тот узел, где файл открыт.
## «Блокнот» один (ISS-008): новый файл закрывает прошлый, несохранённое пропадает.
func open_editor(request: Dictionary, view: TerminalView) -> DesktopWindow:
	var old: DesktopWindow = window_of("editor")
	if old != null:
		old.close()
	var node: String = str(request["node"])
	var path: String = str(request["path"])
	terminal.begin_edit(node, path)
	var window := DesktopWindow.new()
	window.app_id = "editor"
	window.title = "Блокнот — %s" % FsPath.name_of(str(request["path"]))
	window.set_minimum(Vector2(360, 260))
	var editor := FileEditor.new()
	editor.setup(request)
	editor.saved.connect(func(text: String) -> void:
		var result: TermResult = terminal.save_edit(node, path, text)
		if view != null and is_instance_valid(view):
			view.show_result(result)
		# Терминал занят программой — окно остаётся, правка цела.
		if result.text() != Terminal.BUSY_TEXT:
			window.close())
	editor.cancelled.connect(window.close)
	window.closed.connect(func(_w: DesktopWindow) -> void:
		var now: Dictionary = terminal.editing()
		if str(now.get("node", "")) == node and str(now.get("path", "")) == path:
			terminal.end_edit())
	window.body.add_child(editor)
	attach_window(window, Vector2(520, 380))
	return window


## Открыть «Файлы» на папке `path`.
func open_files(path: String) -> void:
	var window: DesktopWindow = open_app("files")
	if window != null:
		(window.body.get_child(0) as HomeFiles).open_path(path)


## Непрочитанные новости — числом на иконке.
func _refresh_news_icon() -> void:
	var icon: Button = _icons.get_node_or_null("Icon_news") as Button
	if icon == null:
		return
	var unread: int = News.unread_count()
	icon.text = "Новости (%d)" % unread if unread > 0 else "Новости"


## Непрочитанные письма — числом на иконке: «Почта (2)».
func _refresh_mail_icon() -> void:
	var icon: Button = _icons.get_node_or_null("Icon_mail") as Button
	if icon == null:
		return
	var unread: int = Mailbox.unread_count()
	icon.text = "Почта (%d)" % unread if unread > 0 else "Почта"


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


## Виден ли значок: у приложения без `gate` — всегда, иначе когда ворота открыты.
static func is_shown(app: Dictionary) -> bool:
	var gate: String = str(app.get("gate", ""))
	return gate.is_empty() or Gates.is_open(gate)


static func is_available(app: Dictionary) -> bool:
	if not is_shown(app):
		return false
	if bool(app.get("stub", false)):
		return false
	return Conditions.check_all(app.get("requires", []) as Array)


## Открыть приложение или поднять уже открытое: одно окно на приложение.
func open_app(app_id: String) -> DesktopWindow:
	var app: Dictionary = app_definition(app_id)
	if app.is_empty() or not is_available(app):
		return null
	# Открыл мессенджер — уведомления о сообщениях больше не нужны.
	if app_id == "messenger" and _toasts != null:
		_toasts.clear()
	var existing: DesktopWindow = _open.get(app_id) as DesktopWindow
	if existing != null:
		if existing.is_minimized:
			existing.restore()
		focus(existing)
		return existing

	var window := DesktopWindow.new()
	window.app_id = app_id
	window.title = str(app["title"])
	window.icon_id = str(APP_ICONS.get(app_id, ""))
	window.set_minimum(app["min"] as Vector2)
	window.body.add_child(_make_content(app_id))
	# Консоль — свой экран во всё окно, как у настоящего эмулятора терминала.
	window.set_flush(app_id == "terminal" or app_id == "map")
	attach_window(window, app["size"] as Vector2)
	# Приложение помнит, где его закрыли: открываем там же (в пределах сессии).
	var remembered: Rect2 = _remembered.get(app_id, Rect2()) as Rect2
	if remembered.size != Vector2.ZERO:
		window.position = remembered.position
		window.size = remembered.size
	return window


## Поставить окно на стол: подписки, размер, место каскадом, панель задач, фокус. Общее для
## приложений, головоломки и удалённого сеанса.
func attach_window(window: DesktopWindow, size: Vector2) -> void:
	window.closed.connect(_on_window_closed)
	window.focus_requested.connect(focus)
	window.state_changed.connect(func(_w: DesktopWindow) -> void: _sync_taskbar())
	_windows.add_child(window)
	window.size = size
	window.position = WindowRules.cascade(_opened_count, window.size, _windows.size)
	_open[window.app_id] = window
	_opened_count += 1
	focus(window)
	window.play_open()


## Содержимое окна. Терминал и остальное подключаются здесь, остальные приложения — заглушки M1.
func _make_content(app_id: String) -> Control:
	if app_id == "map":
		var map := MapView.new()
		map.setup(terminal)
		return map
	if app_id == "files":
		var files := HomeFiles.new()
		files.setup(terminal, Terminal.DESKTOP_DIR)
		files.changed.connect(_fill_icons)
		files.edit_requested.connect(func(request: Dictionary) -> void: open_editor(request, null))
		return files
	if app_id == "bank":
		return BankApp.new()
	if app_id == "shop":
		return ShopApp.new()
	if app_id == "mail":
		return MailApp.new()
	if app_id == "news":
		return NewsApp.new()
	if app_id == "messenger":
		# На ПК — два столбца, как в мессенджере на компьютере.
		var messages := MessagesApp.new()
		messages.set_wide(true)
		return messages
	if app_id == "tasks":
		return PlannerApp.new()
	if app_id == "terminal":
		var view := TerminalView.new()
		view.setup(terminal)
		_connect_view(view)
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
	# Как в настоящей консоли: окно терминала стало активным — курсор сразу в строке ввода.
	if window.app_id == "terminal" and window.body.get_child_count() > 0:
		var view: TerminalView = window.body.get_child(0) as TerminalView
		if view != null:
			view.focus_entry.call_deferred()
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
		_taskbar.set_window(window.app_id, window.title, window.is_focused, window.is_minimized,
				GameTheme.icon(window.icon_id, theme_id) if not window.icon_id.is_empty() else null)


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


## Вырубился: реплика, экран гаснет, сон — и проснётся в комнате, а не за монитором
## (gameplay/needs.md, «Вырубание»).
func _on_passed_out() -> void:
	# Спрятанный стол (герой в комнате) не отвечает: занавес покажет комната.
	if not is_visible_in_tree():
		return
	NeedsManager.claim_pass_out()
	var curtain := PassOutCurtain.new()
	add_child(curtain)
	curtain.finished.connect(func() -> void:
		NeedsManager.sleep_after_pass_out()
		curtain.queue_free()
		leave_to(Screens.ROOM))
	curtain.play_falling_asleep()


func _on_menu(action: String) -> void:
	match action:
		"terminal":
			open_app("terminal")
		"files":
			open_app("files")
		"reboot":
			PcPower.reboot()
		"shut_down":
			shut_down()


## Отойти от ПК: кнопка справа на панели задач или Esc. Стол прячется, всё идёт фоном.
func leave_pc() -> void:
	if is_inside_tree() and is_visible_in_tree():
		leave_to(Screens.ROOM)


## Esc — отойти от ПК, если клавишу не забрало окно (диалог, всплывающее меню).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		leave_pc()


## За ПК телефона на экране нет: всё нужное продублировано приложениями стола, а состояние
## (энергия, деньги) — в панели задач. Игра при этом идёт, инвентарь и сцена держатся на `in_game`.
func _attach_phone() -> void:
	PhoneOverlay.attach(self, _taskbar.custom_minimum_size.y, false)


func _exit_tree() -> void:
	PhoneOverlay.detach(self)


## Ручное сохранение. Итог — сообщением системы вверху стола (не мыслью героя).
func save_game() -> String:
	var error: String = SaveSystem.save(SaveSystem.SLOT_MANUAL)
	var notice: SystemNotice = find_child("SystemNotice", true, false) as SystemNotice
	if notice != null:
		notice.show_text("игра сохранена" if error.is_empty() else "ошибка сохранения: " + error)
	return error


# --- Отойти от ПК и вернуться -------------------------------------------------------

## Выключить ПК из меню: стол не прячется, а закрывается насовсем, герой — в комнате.
func shut_down() -> void:
	PcPower.shut_down()
	if _kept == self:
		_kept = null
	get_tree().change_scene_to_file(Screens.ROOM)


## Собрать стол заново после загрузки ПК.
func _restart() -> void:
	if _kept == self:
		_kept = null
	get_tree().change_scene_to_file(Screens.DESKTOP)


## Отойти от ПК: стол прячется (а не уничтожается) и глохнет, открывается другая сцена.
## Сцену меняем после того, как стол перестал быть текущей сценой, — иначе смена его освободит.
func leave_to(path: String) -> void:
	var tree: SceneTree = get_tree()
	hide_pc()
	if tree.current_scene == self:
		tree.current_scene = null
	tree.change_scene_to_file(path)


## Спрятать стол: не видно, не слышно, ввод не принимает. Время и логика при этом идут —
## трейс, фоновые задачи, таймеры головоломок (не успел — провал, как при выходе).
func hide_pc() -> void:
	_kept = self
	visible = false
	set_pc_sound(false)
	PhoneOverlay.detach(self)


## Вернуть спрятанный стол как был. Режим (аварийная консоль) перепроверяется: пока герой был в
## комнате, ПК могли починить флешкой.
func show_pc() -> void:
	visible = true
	set_pc_sound(true)
	_attach_phone()
	apply_mode()
	if _kept == self:
		_kept = null


## Сесть за ПК: вернуть спрятанный стол, а если его нет — собрать новый.
static func enter_pc(tree: SceneTree) -> void:
	if not is_instance_valid(_kept):
		_kept = null
		tree.change_scene_to_file(Screens.DESKTOP)
		return
	var desktop: Desktop = _kept
	var old: Node = tree.current_scene
	tree.current_scene = desktop
	desktop.show_pc()
	if old != null and old != desktop:
		old.queue_free()


static func kept() -> Desktop:
	return _kept if is_instance_valid(_kept) else null


## Новая игра или выход в меню: спрятанный стол прошлой игры уничтожается.
static func discard_kept() -> void:
	if is_instance_valid(_kept):
		_kept.queue_free()
	_kept = null


## Звук ПК включить или заглушить (шина `PC` создаётся при первом обращении).
static func set_pc_sound(on: bool) -> void:
	var index: int = AudioServer.get_bus_index(PC_BUS)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, PC_BUS)
	AudioServer.set_bus_mute(index, not on)


static func pc_sound_on() -> bool:
	var index: int = AudioServer.get_bus_index(PC_BUS)
	return index < 0 or not AudioServer.is_bus_mute(index)


# --- Окна головоломки и удалённого сеанса ------------------------------------------

## Окно консоли подписывается на всё, что она может попросить у стола.
func _connect_view(view: TerminalView) -> void:
	view.puzzle_requested.connect(func(request: Dictionary) -> void: _puzzles.show(request, view))
	view.remote_requested.connect(func(request: Dictionary) -> void: _remote.open(request, view))
	view.edit_requested.connect(func(request: Dictionary) -> void: open_editor(request, view))
	view.result_shown.connect(_on_result_shown)
	view.ready.connect(view.focus_entry)


## Отладка: головоломка без взлома и без подключения (команда `play` в консоли F1).
## Итог в игру не попадает, возвращается числом слоёв через `practice_finished`.
signal practice_finished(gained: int)


func play_puzzle(kind: String, level: int, seed_value: int) -> bool:
	return _puzzles.play(kind, level, seed_value)


func has_puzzle_open() -> bool:
	return _puzzles.is_open()


## Действие мышью в трансляции — команда той же консоли (см. RemoteWindows).
func run_remote_command(line: String) -> String:
	return _remote.run_command(line)


## «Вставить» на своём столе: скачать файл из буфера трансляции.
func paste_to_own_desktop() -> void:
	_remote.paste()


## Команда выполнена: окна, карта и режим стола перечитывают состояние.
func _on_result_shown() -> void:
	_puzzles.close_stale()
	_remote.sync()
	# Команда могла положить файл на стол или убрать ярлык; «Файлы» показывают свежий каталог.
	_fill_icons()
	var files: DesktopWindow = window_of("files")
	if files != null:
		(files.body.get_child(0) as HomeFiles).refresh()
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
	back.pressed.connect(func() -> void: leave_to(Screens.ROOM))
	box.add_child(back)

	var view := TerminalView.new()
	view.setup(terminal)
	view.print_lines(lines)
	_connect_view(view)
	box.add_child(view)
	return root
