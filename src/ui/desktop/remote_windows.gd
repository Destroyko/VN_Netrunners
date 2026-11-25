class_name RemoteWindows
extends RefCounted
## Удалённый сеанс на рабочем столе (docs/tech/desktop-layout.md, «Удалённый сеанс»): окно
## трансляции стола цели, действия мышью в нём, буфер и перетаскивание файлов на свой стол.
##
## Правил здесь нет: действие мышью — команда той же консоли (путь один, правила одни). Если
## команда спросила подтверждение (системный файл), спрашиваем окном, а ответ уходит в консоль.
##
## Вынесено из `Desktop` (технический разбор 16.11.2026).

const APP_ID: String = "remote"

var _desktop: Desktop
var _terminal: Terminal
## Консоль, к которой привязана трансляция: в неё уходят действия мышью.
var _view: TerminalView


func _init(desktop: Desktop, terminal: Terminal) -> void:
	_desktop = desktop
	_terminal = terminal


## Подключились к ПК или он спросил пароль: трансляция его стола рядом с консолью. Пароль не
## введён — экран блокировки; ввести можно там или в консоли. Соединение закрылось — окно тоже.
func open(request: Dictionary, view: TerminalView) -> void:
	var node: String = str(request.get("node", ""))
	var old: DesktopWindow = _desktop.window_of(APP_ID)
	if old != null:
		if str(old.get_meta("node", "")) == node:
			_desktop.focus(old)
			return
		old.close()
	var address: String = str(request.get("address", ""))
	var window := DesktopWindow.new()
	window.app_id = APP_ID
	window.title = "Удалённый сеанс — %s" % address
	window.set_meta("node", node)
	window.set_minimum(Vector2(420, 300))
	window.closed.connect(func(_w: DesktopWindow) -> void:
		# Закрыть трансляцию — отключиться от узла, как в Radmin (вердикт гейта M1, 16.11.2026).
		# Если окно закрылось само из-за dc или обрыва, цели уже нет — второй раз не отключаемся.
		if _terminal.session.target_id() == node and is_instance_valid(view):
			# Программа на этом узле обрывается вместе с соединением: итога нет.
			view.interrupt()
			view.submit("dc"))
	var session := RemoteSession.new()
	# Трансляция — чужой экран во всё окно, без полей вокруг.
	window.set_flush(true)
	window.body.add_child(session)
	_view = view
	session.setup(_terminal, node, address, desktop_of(_terminal.net, node), func(text: String) -> String:
		view.submit(text)
		return "" if not _terminal.login_pending() else "доступ запрещён", run_command)
	_desktop.attach_window(window, Vector2(560, 400))


## Выполнить действие мышью как команду консоли. Возвращает последнюю строку ответа — её
## показывает проводник (например, «недостаточно прав»).
func run_command(line: String) -> String:
	if _view == null or not is_instance_valid(_view):
		return ""
	var result: TermResult = _view.submit(line)
	if _terminal.has_question():
		var dialog := ConfirmationDialog.new()
		dialog.name = "RemoteConfirm"
		dialog.dialog_text = _terminal.last_question()
		dialog.ok_button_text = "Да"
		dialog.cancel_button_text = "Нет"
		dialog.confirmed.connect(func() -> void: _answer(dialog, "y"))
		dialog.canceled.connect(func() -> void: _answer(dialog, "n"))
		_desktop.add_child(dialog)
		dialog.popup_centered()
		return ""
	return result.lines[result.lines.size() - 1] if not result.lines.is_empty() else ""


func _answer(dialog: ConfirmationDialog, answer: String) -> void:
	if is_instance_valid(_view) and _terminal.has_question():
		_view.submit(answer)
	dialog.queue_free()


## Правая кнопка по своему столу: «Вставить» скачивает файл из буфера трансляции (как в RDP:
## скопировал там — вставил здесь). Вырезанный там файл здесь тоже просто копируется.
func show_paste_menu(at_position: Vector2) -> void:
	var menu := PopupMenu.new()
	menu.name = "WallpaperMenu"
	menu.add_item("Вставить", 0)
	var clip: Dictionary = FileBrowser.clipboard
	menu.set_item_disabled(0, clip.is_empty() or _terminal.session.target_id() != str(clip.get("node", "")))
	menu.id_pressed.connect(func(_id: int) -> void: paste())
	menu.popup_hide.connect(menu.queue_free)
	_desktop.add_child(menu)
	menu.position = Vector2i(_desktop.get_screen_position() + at_position)
	menu.popup()


func paste() -> void:
	if not FileBrowser.clipboard.is_empty():
		drop_file(FileBrowser.clipboard)


## Файл из трансляции брошен на свой стол — скачать к себе, как `cp` с узла.
func drop_file(data: Dictionary) -> void:
	if _terminal.session.target_id() != str(data.get("node", "")):
		return
	# Брошенный на стол файл ложится на стол — в папку рабочего стола, а не в «Загрузки».
	run_command("cp \"%s\" %s/" % [str(data["remote_file"]), Terminal.DESKTOP_DIR])


## После каждой команды окно сверяется с консолью: вошли — стол цели, отменили вход или
## отключились — окно закрыто, файлы поменялись — список перечитан.
func sync() -> void:
	var window: DesktopWindow = _desktop.window_of(APP_ID)
	if window == null or _terminal.login_pending():
		return
	var node: String = str(window.get_meta("node", ""))
	var inside: bool = _terminal.session.has_connection() and _terminal.session.target_id() == node
	if not inside:
		window.close()
		return
	var session: RemoteSession = window.body.get_child(0) as RemoteSession
	if session.is_locked():
		session.unlock()
	else:
		session.refresh()


## Стол цели из данных узла (`desktop`): имя пользователя, обои, иконки. Чего нет — по умолчанию.
## Это данные для интерфейса, поэтому они читаются здесь, а не в сети.
static func desktop_of(net: Network, node_id: String) -> Dictionary:
	var def: Dictionary = net.definition(node_id).get("desktop", {}) as Dictionary
	return {
		"user": str(def.get("user", "user")),
		"wallpaper": str(def.get("wallpaper", "#24476b")),
		"apps": (def.get("apps", ["files"]) as Array).duplicate(),
	}

