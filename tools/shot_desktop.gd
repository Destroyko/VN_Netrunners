extends Node
## Снимок рабочего стола ПК в теме ОС:
##   godot --path . res://tools/shot_desktop.tscn -- normal|hacker [app[,app…]] [each] [часы]
## Нужен режим с окном. PNG в tools/out/desktop_<ОС>.png.
## Несколько приложений через запятую — открываются вместе, последнее в фокусе. С `each` — каждое
## отдельно, снимок на приложение: desktop_<ОС>_<app>.png. Псевдоприложение `start` — открытое меню «Пуск».
## `часы` — сколько игровых часов прокрутить перед снимком (чтобы пришли письма и заказы).


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var os_name: String = args[0] if args.size() > 0 else "normal"
	var apps: PackedStringArray = args[1].split(",") if args.size() > 1 else PackedStringArray()
	var each: bool = args.size() > 2 and args[2] == "each"
	var hours: int = int(args[3]) if args.size() > 3 else (int(args[2]) if args.size() > 2 and not each else 0)
	var root: Window = get_tree().root
	root.size = Vector2i(1280, 720)
	# Снимок — готовый кадр, без середины анимаций.
	DesktopWindow.animate = false
	GameStart.begin()
	GameState.set_var("pc.os", os_name)
	if hours > 0:
		Clock.advance(hours * 60)
	# SHOT_REVEAL="node_a,node_b" — открыть узлы как выданные заказом (с названием), SHOT_HACKED — взломанные.
	for node_id: String in OS.get_environment("SHOT_REVEAL").split(",", false):
		Network.for_game().reveal(node_id, [], GameState.minute)
	for node_id: String in OS.get_environment("SHOT_HACKED").split(",", false):
		Network.for_game().mark_hacked(node_id)
	# Почта: SHOT_MAIL="id,id" — доставить письма (последнее окажется сверху и откроется, если задан
	# SHOT_OPEN); SHOT_FOLDER=sent — показать «Отправленные».
	for letter: String in OS.get_environment("SHOT_MAIL").split(",", false):
		Mailbox.deliver(letter)
	var desktop: Control = (load(Screens.DESKTOP) as PackedScene).instantiate() as Control
	add_child(desktop)
	await get_tree().process_frame
	if not each:
		for app: String in apps:
			_open(desktop, app)
		await _shoot(root, "desktop_%s.png" % os_name)
		get_tree().quit()
		return
	for app: String in apps:
		var window: Control = _open(desktop, app)
		await _shoot(root, "desktop_%s_%s.png" % [os_name, app])
		if window != null:
			window.call("close")
		_close_popups()
		await get_tree().process_frame
	get_tree().quit()


func _open(desktop: Control, app: String) -> Control:
	if app == "start":
		var taskbar: Node = desktop.find_children("*", "Taskbar", true, false)[0]
		taskbar.call("open_start_menu")
		return null
	var window: Control = desktop.call("open_app", app) as Control
	# SHOT_MAX=1 — развернуть окно на весь стол (проверить, что строка цели поверх окон).
	if window != null and not OS.get_environment("SHOT_MAX").is_empty():
		(window as DesktopWindow).toggle_maximize()
	# SHOT_TERM="pwd;ls;abc" — выполнить команды в терминале перед снимком, SHOT_TYPE — набрать строку.
	if app == "terminal" and window != null:
		var view: TerminalView = (window as DesktopWindow).body.get_child(0) as TerminalView
		for line: String in OS.get_environment("SHOT_TERM").split(";", false):
			view.submit(line)
		view.entry().text = OS.get_environment("SHOT_TYPE")
		view.entry().caret_column = view.entry().text.length()
	# SHOT_HOVER=<id узла> — карточка узла на карте, как при наведении мыши.
	if app == "map" and window != null and not OS.get_environment("SHOT_HOVER").is_empty():
		var map: MapView = (window as DesktopWindow).body.get_child(0) as MapView
		map.call_deferred("_hover", OS.get_environment("SHOT_HOVER"))
	if app == "mail" and window != null:
		var mail: MailApp = window.find_child("MailApp", true, false) as MailApp
		if OS.get_environment("SHOT_FOLDER") == "sent":
			mail.show_folder(MailApp.FOLDER_SENT)
		elif not OS.get_environment("SHOT_OPEN").is_empty() and not Mailbox.inbox().is_empty():
			mail.open(str(Mailbox.inbox()[0]["uid"]))
	return window


func _close_popups() -> void:
	for popup: Node in get_tree().root.find_children("*", "Popup", true, false):
		(popup as Window).hide()


func _shoot(root: Window, file: String) -> void:
	for i: int in 5:
		await get_tree().process_frame
	root.get_texture().get_image().save_png("res://tools/out/" + file)
	print("saved ", file)
