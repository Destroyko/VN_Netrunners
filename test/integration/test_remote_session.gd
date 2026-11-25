extends "res://test/integration/desktop_fixture.gd"
## Удалённый сеанс на столе: пароль после взлома, экран блокировки, вход в окне и в консоли,
## проводник с меню, буфер и перетаскивание (docs/tech/desktop-layout.md, «Удалённый сеанс»).

# --- Пароль после перехвата и окно входа ------------------------------------------

func test_login_window_opens_and_lets_in_with_the_password() -> void:
	Clock.set_time(1, 12 * 60)
	GameState.set_flag(Programs.flag_for("passhound"))
	var scene: PackedScene = load(Screens.DESKTOP) as PackedScene
	var desktop: Desktop = scene.instantiate() as Desktop
	add_child_autofree(desktop)
	await wait_frames(2)
	var view: TerminalView = desktop.open_app("terminal").body.get_child(0) as TerminalView
	for line: String in ["scan", "connect 10.0.0.1", "scan", "dc", "connect 10.0.0.7", "passhound 22"]:
		view.submit(line)
	var dialog: PuzzleDialog = desktop.find_children("*", "PuzzleDialog", true, false)[0] as PuzzleDialog
	var panel: DumpPanel = dialog.panel as DumpPanel
	var word: String = ""
	while not panel.is_done():
		var spot: Vector2i = _dump_spot(panel)
		if spot.x < 0:
			panel.step()
		else:
			panel.click(spot.x, spot.y)
	var note: String = (panel.find_children("*", "Label", true, false).filter(
		func(l: Node) -> bool: return (l as Label).text.begins_with("Хэш собран"))[0] as Label).text
	assert_string_contains(note, "Пароль:", "пароль крупно в окне взлома")
	word = note.get_slice("Пароль: ", 1).to_lower()
	(panel.get_children().filter(func(c: Node) -> bool: return c is Button).back() as Button).pressed.emit()
	await wait_frames(2)

	var login: DesktopWindow = desktop.window_of("remote")
	assert_not_null(login, "открылась трансляция")
	var form: LoginForm = (login.body.get_child(0) as RemoteSession).lock_form()
	assert_not_null(form, "сначала экран блокировки")
	form.field().text = "неверно"
	form.try_login()
	assert_eq(form.note_text(), "доступ запрещён")
	form.field().text = word
	form.try_login()
	await wait_frames(2)
	assert_true(desktop.terminal.session.has_connection(), "вошли через окно")
	assert_string_contains(view.output_text(), "подключено", "консоль тоже вошла")
	assert_false(view.output_text().contains(word), "пароль, набранный в окне, не печатается в консоли")
	var remote: DesktopWindow = desktop.window_of("remote")
	assert_not_null(remote, "трансляция осталась")
	assert_false((remote.body.get_child(0) as RemoteSession).is_locked(), "экран блокировки снят — виден стол цели")


func _desktop_at_the_training_password() -> Array:
	# Стол, учебный ПК взломан, сервер спрашивает пароль. Возвращает [стол, консоль, слово].
	Clock.set_time(1, 12 * 60)
	GameState.set_flag(Programs.flag_for("passhound"))
	var scene: PackedScene = load(Screens.DESKTOP) as PackedScene
	var desktop: Desktop = scene.instantiate() as Desktop
	add_child_autofree(desktop)
	await wait_frames(2)
	var view: TerminalView = desktop.open_app("terminal").body.get_child(0) as TerminalView
	for line: String in ["scan", "connect 10.0.0.1", "scan", "dc", "connect 10.0.0.7", "passhound 22"]:
		view.submit(line)
	var word: String = ""
	var dialog: PuzzleDialog = desktop.find_children("*", "PuzzleDialog", true, false)[0] as PuzzleDialog
	var panel: DumpPanel = dialog.panel as DumpPanel
	word = panel._password
	while not panel.is_done():
		var spot: Vector2i = _dump_spot(panel)
		if spot.x < 0:
			panel.step()
		else:
			panel.click(spot.x, spot.y)
	(panel.get_children().filter(func(c: Node) -> bool: return c is Button).back() as Button).pressed.emit()
	await wait_frames(2)
	return [desktop, view, word]


func test_password_typed_in_the_console_also_unlocks_the_session() -> void:
	var setup: Array = await _desktop_at_the_training_password()
	var desktop: Desktop = setup[0] as Desktop
	var view: TerminalView = setup[1] as TerminalView
	var session: RemoteSession = desktop.window_of("remote").body.get_child(0) as RemoteSession
	assert_true(session.is_locked())
	view.submit(str(setup[2]))
	await wait_frames(2)
	assert_false(session.is_locked(), "вошли в консоли — трансляция тоже вошла")


func test_explorer_opens_inside_the_session_and_closes_with_it() -> void:
	var setup: Array = await _desktop_at_the_training_password()
	var desktop: Desktop = setup[0] as Desktop
	var view: TerminalView = setup[1] as TerminalView
	view.submit(str(setup[2]))
	await wait_frames(2)
	var session: RemoteSession = desktop.window_of("remote").body.get_child(0) as RemoteSession
	var explorer: DesktopWindow = session.open_app("files")
	var browser: FileBrowser = explorer.body.get_child(0) as FileBrowser
	assert_true(browser.item_names().has("home/"), "видны каталоги узла")
	browser.open_item(browser.item_names().find("home/"))
	assert_eq(browser.path, "/home")
	assert_same(session.open_app("files"), explorer, "второй раз — то же окно")
	view.submit("dc")
	await wait_frames(2)
	assert_null(desktop.window_of("remote"), "соединение закрыто — трансляция закрылась")


func test_router_has_no_graphical_session() -> void:
	var scene: PackedScene = load(Screens.DESKTOP) as PackedScene
	var desktop: Desktop = scene.instantiate() as Desktop
	add_child_autofree(desktop)
	await wait_frames(2)
	var view: TerminalView = desktop.open_app("terminal").body.get_child(0) as TerminalView
	view.submit("scan")
	view.submit("connect 10.0.0.1")
	await wait_frames(2)
	assert_true(desktop.terminal.session.has_connection())
	assert_null(desktop.window_of("remote"), "у роутера стола нет — только консоль")


func test_entry_by_a_client_login_opens_the_desktop_unlocked() -> void:
	# Заказ дал логин: пароль не спрашивают, трансляция сразу показывает стол.
	Effects.apply({"reveal_node": {"node": "node_training_pc", "open": ["svc_login"]}})
	var scene: PackedScene = load(Screens.DESKTOP) as PackedScene
	var desktop: Desktop = scene.instantiate() as Desktop
	add_child_autofree(desktop)
	await wait_frames(2)
	var view: TerminalView = desktop.open_app("terminal").body.get_child(0) as TerminalView
	view.submit("connect 10.0.0.7")
	await wait_frames(2)
	var remote: DesktopWindow = desktop.window_of("remote")
	assert_not_null(remote)
	assert_false((remote.body.get_child(0) as RemoteSession).is_locked())


# --- Проводник в трансляции: меню как в Windows ------------------------------------

func _explorer_in_home() -> Array:
	# Учебный ПК по логину от заказчика, трансляция, проводник в /home. [стол, проводник].
	Effects.apply({"reveal_node": {"node": "node_training_pc", "open": ["svc_login"]}})
	FileBrowser.clipboard = {}
	var scene: PackedScene = load(Screens.DESKTOP) as PackedScene
	var desktop: Desktop = scene.instantiate() as Desktop
	add_child_autofree(desktop)
	await wait_frames(2)
	var view: TerminalView = desktop.open_app("terminal").body.get_child(0) as TerminalView
	view.submit("connect 10.0.0.7")
	await wait_frames(2)
	var session: RemoteSession = desktop.window_of("remote").body.get_child(0) as RemoteSession
	var browser: FileBrowser = session.open_app("files").body.get_child(0) as FileBrowser
	browser.open_item(browser.item_names().find("home/"))
	return [desktop, browser, session]


func _row(browser: FileBrowser, name: String) -> int:
	return browser.item_names().find(name)


func test_guest_cannot_delete_from_the_explorer() -> void:
	var setup: Array = await _explorer_in_home()
	var browser: FileBrowser = setup[1] as FileBrowser
	browser.act(_row(browser, "spisok_pokupok.txt"), FileBrowser.MENU_DELETE)
	assert_string_contains(browser.status_text(), "недостаточно прав")
	assert_true(Filesystem.for_node("node_training_pc").has_file("/home/spisok_pokupok.txt"))


func test_admin_renames_cuts_pastes_and_deletes() -> void:
	var setup: Array = await _explorer_in_home()
	var desktop: Desktop = setup[0] as Desktop
	var browser: FileBrowser = setup[1] as FileBrowser
	desktop.terminal.session.grant_admin()
	var fs: Filesystem = Filesystem.for_node("node_training_pc")
	browser.rename(_row(browser, "spisok_pokupok.txt"), "novoe.txt")
	assert_true(fs.has_file("/home/novoe.txt"), "переименован")
	browser.act(_row(browser, "novoe.txt"), FileBrowser.MENU_CUT)
	browser.path = "/prog"
	browser.refresh()
	browser.paste()
	assert_true(fs.has_file("/prog/novoe.txt"), "вырезан и вставлен в другую папку")
	browser.act(_row(browser, "novoe.txt"), FileBrowser.MENU_DELETE)
	assert_false(fs.has_file("/prog/novoe.txt"), "удалён")
	assert_string_contains((desktop.find_children("*", "TerminalView", true, false)[0] as TerminalView).output_text(),
		"rm", "действия мышью видны в консоли")


func test_copy_in_the_session_and_paste_on_own_desktop_downloads() -> void:
	var setup: Array = await _explorer_in_home()
	var desktop: Desktop = setup[0] as Desktop
	var browser: FileBrowser = setup[1] as FileBrowser
	browser.act(_row(browser, "spisok_pokupok.txt"), FileBrowser.MENU_COPY)
	desktop.paste_to_own_desktop()
	assert_true(desktop.terminal.home_fs().has_file(Terminal.DESKTOP_DIR + "/spisok_pokupok.txt"), "вставлен на свой стол — лежит в папке стола")


func test_dragging_a_file_onto_own_desktop_downloads_it() -> void:
	var setup: Array = await _explorer_in_home()
	var desktop: Desktop = setup[0] as Desktop
	var browser: FileBrowser = setup[1] as FileBrowser
	var data: Variant = browser.drag_data(_row(browser, "spisok_pokupok.txt"))
	var zone: DesktopDropZone = desktop.find_child("Wallpaper", true, false) as DesktopDropZone
	assert_true(zone._can_drop_data(Vector2.ZERO, data))
	zone._drop_data(Vector2.ZERO, data)
	assert_true(desktop.terminal.home_fs().has_file(Terminal.DESKTOP_DIR + "/spisok_pokupok.txt"), "брошен на стол — лёг на стол")


func test_files_window_stays_on_own_pc_during_session() -> void:
	var setup: Array = await _explorer_in_home()
	var desktop: Desktop = setup[0] as Desktop
	var own: Filesystem = desktop.terminal.home_fs()
	own.put_file("/home/spisok_pokupok.txt", {"text": "мой"})
	GameState.set_filesystem_state(Network.HOME_ID, own.to_dict())
	var result: TermResult = desktop.terminal.execute_local("rm /home/spisok_pokupok.txt")
	assert_true(result.lines.size() >= 0)
	assert_false(desktop.terminal.home_fs().has_file("/home/spisok_pokupok.txt"), "удалён свой файл")
	assert_true(Filesystem.for_node("node_training_pc").has_file("/home/spisok_pokupok.txt"), "чужой с тем же путём цел")
	assert_true(desktop.terminal.is_remote(), "сеанс с узлом не прервался")


func test_open_shows_the_file_in_a_notepad() -> void:
	var setup: Array = await _explorer_in_home()
	var browser: FileBrowser = setup[1] as FileBrowser
	var session: RemoteSession = setup[2] as RemoteSession
	browser.act(_row(browser, "spisok_pokupok.txt"), FileBrowser.MENU_OPEN)
	var viewer: DesktopWindow = null
	for window: DesktopWindow in session.app_windows():
		if window.app_id == "viewer":
			viewer = window
	assert_not_null(viewer, "открылся «Блокнот»")
	var expected: String = str(Filesystem.for_node("node_training_pc").file_data("/home/spisok_pokupok.txt").get("text", ""))
	assert_eq((viewer.body.get_child(0) as TextEdit).text, expected)


func test_closing_the_remote_window_disconnects() -> void:
	# Баг вердикта гейта M1: окно трансляции закрыли, а консоль осталась подключённой к узлу.
	var setup: Array = await _explorer_in_home()
	var desktop: Desktop = setup[0] as Desktop
	assert_true(desktop.terminal.session.has_connection())
	desktop.window_of("remote").close()
	await wait_frames(2)
	assert_false(desktop.terminal.session.has_connection(), "закрыть трансляцию = отключиться")
	assert_true(desktop.terminal.session.target_id().is_empty(), "и у двери тоже не стоим")
