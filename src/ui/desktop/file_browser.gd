class_name FileBrowser
extends VBoxContainer
## Проводник узла внутри удалённого сеанса (docs/tech/desktop-layout.md, «Удалённый сеанс»).
## Папки — двойной клик, «..» — наверх. Правая кнопка — меню как в Windows: Открыть, Копировать,
## Вырезать, Вставить, Переименовать, Удалить. Файл можно утащить мышью на свой рабочий стол.
## Своего каталога у консоли он не меняет.
##
## Действия мышью — это те же команды консоли (`run_command("rm ...")`): права, фаервол, трейс и
## анализ действий работают одинаково, консоль показывает, что произошло, а последняя строка
## ответа видна внизу проводника (например, «недостаточно прав»).

## Файл открыт двойным кликом или «Открыть»: сеанс показывает его в окне просмотра.
signal file_opened(path: String)

const MENU_OPEN: int = 0
const MENU_COPY: int = 1
const MENU_CUT: int = 2
const MENU_PASTE: int = 3
const MENU_RENAME: int = 4
const MENU_DELETE: int = 5

## Буфер обмена проводника: {"remote_file": путь, "node": узел, "cut": вырезан ли}. Общий на всю
## сессию игры, как буфер в RDP: скопировал в трансляции — вставил у себя на столе.
static var clipboard: Dictionary = {}

var terminal: Terminal
var node_id: String = ""
var path: String = FsPath.ROOT
## Выполнить строку как команду консоли и вернуть итог. Не задано — проводник только смотрит.
var run_command: Callable

var _path_label: Label
var _list: FileList
var _status: Label
var _menu: PopupMenu
var _menu_index: int = -1
var _rename: ConfirmationDialog
var _rename_field: LineEdit


func setup(shared_terminal: Terminal, node: String) -> void:
	terminal = shared_terminal
	node_id = node
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_path_label = Label.new()
	_path_label.add_theme_font_override("font", PasswordPanel._mono())
	add_child(_path_label)
	_list = FileList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_override("font", PasswordPanel._mono())
	_list.allow_rmb_select = true
	_list.item_activated.connect(open_item)
	_list.item_clicked.connect(_on_item_clicked)
	_list.empty_clicked.connect(_on_empty_clicked)
	_list.drag_source = drag_data
	add_child(_list)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(0.85, 0.75, 0.45))
	_status.clip_text = true
	add_child(_status)

	_menu = PopupMenu.new()
	_menu.add_item("Открыть", MENU_OPEN)
	_menu.add_separator()
	_menu.add_item("Копировать", MENU_COPY)
	_menu.add_item("Вырезать", MENU_CUT)
	_menu.add_item("Вставить", MENU_PASTE)
	_menu.add_separator()
	_menu.add_item("Переименовать", MENU_RENAME)
	_menu.add_item("Удалить", MENU_DELETE)
	_menu.id_pressed.connect(func(id: int) -> void: act(_menu_index, id))
	add_child(_menu)

	_rename = ConfirmationDialog.new()
	_rename.title = "Переименовать"
	_rename_field = LineEdit.new()
	_rename.add_child(_rename_field)
	_rename.confirmed.connect(func() -> void: rename(_menu_index, _rename_field.text))
	add_child(_rename)
	refresh()


## Перечитать каталог: после команд в консоли файлы могли появиться или исчезнуть.
func refresh() -> void:
	_path_label.text = path
	_list.clear()
	if path != FsPath.ROOT:
		_list.add_item("..")
		_list.set_item_metadata(0, {"name": "..", "is_dir": true, "up": true})
	for entry: Dictionary in Filesystem.for_node(node_id).list(path, terminal.admin()):
		var name: String = str(entry["name"]) + ("/" if bool(entry["is_dir"]) else "")
		if bool(entry.get("locked", false)):
			name += "  [закрыт]"
		var index: int = _list.add_item(name)
		_list.set_item_metadata(index, entry)


## Открыть строку `index`: папку — войти в неё, файл — показать (и `cat` в консоли).
func open_item(index: int) -> void:
	var entry: Dictionary = _entry(index)
	if entry.is_empty() or bool(entry.get("locked", false)):
		return
	if not bool(entry.get("is_dir", false)):
		_run("cat " + _quoted(str(entry["path"])))
		file_opened.emit(str(entry["path"]))
		return
	if bool(entry.get("up", false)):
		path = FsPath.parent(path) if path != FsPath.ROOT else FsPath.ROOT
	else:
		path = str(entry["path"])
	refresh()


## Пункт меню для строки `index` (-1 — пустое место списка).
func act(index: int, action: int) -> void:
	var entry: Dictionary = file_at(index)
	match action:
		MENU_OPEN:
			open_item(index)
		MENU_COPY, MENU_CUT:
			if not entry.is_empty():
				clipboard = {"remote_file": str(entry["path"]), "node": node_id, "cut": action == MENU_CUT}
				_status.text = ("вырезано: " if action == MENU_CUT else "скопировано: ") + FsPath.name_of(str(entry["path"]))
		MENU_PASTE:
			paste()
		MENU_RENAME:
			if not entry.is_empty():
				_menu_index = index
				_rename_field.text = FsPath.name_of(str(entry["path"]))
				_rename.popup_centered(Vector2i(280, 80))
		MENU_DELETE:
			if not entry.is_empty():
				_run("rm " + _quoted(str(entry["path"])))


## Вставить в текущую папку. Вырезанный файл этого узла перемещается (`mv`). Скопированный —
## внутри узла не вставляется: так не умеет и консоль (`cp` на узле скачивает к себе); вставить
## скопированное можно у себя на рабочем столе.
func paste() -> void:
	if clipboard.is_empty() or str(clipboard.get("node", "")) != node_id or not bool(clipboard.get("cut", false)):
		return
	_run("mv %s %s" % [_quoted(str(clipboard["remote_file"])), _quoted(path.trim_suffix("/") + "/")])
	if not _status.text.begins_with("недостаточно"):
		clipboard = {}


func rename(index: int, new_name: String) -> void:
	var entry: Dictionary = file_at(index)
	var name: String = new_name.strip_edges()
	if entry.is_empty() or name.is_empty() or name.contains("/"):
		return
	var target: String = FsPath.parent(str(entry["path"])).trim_suffix("/") + "/" + name
	_run("mv %s %s" % [_quoted(str(entry["path"])), _quoted(target)])


## Файл в строке `index` (не папка, не «..»): его данные или пустой словарь.
func file_at(index: int) -> Dictionary:
	var entry: Dictionary = _entry(index)
	return {} if entry.is_empty() or bool(entry.get("is_dir", false)) else entry


## Что тащит мышь из строки `index`: файл узла (папки не тащатся).
func drag_data(index: int) -> Variant:
	var entry: Dictionary = file_at(index)
	if entry.is_empty() or not run_command.is_valid():
		return null
	return {"remote_file": str(entry["path"]), "node": node_id}


func item_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for index: int in _list.item_count:
		names.append(_list.get_item_text(index))
	return names


func status_text() -> String:
	return _status.text


func _entry(index: int) -> Dictionary:
	if index < 0 or index >= _list.item_count:
		return {}
	return _list.get_item_metadata(index) as Dictionary


func _run(line: String) -> void:
	if not run_command.is_valid():
		return
	var answer: String = str(run_command.call(line))
	_status.text = answer
	refresh()


func _quoted(value: String) -> String:
	return "\"%s\"" % value


func _on_item_clicked(index: int, at_position: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_RIGHT or not run_command.is_valid():
		return
	var entry: Dictionary = _entry(index)
	if entry.is_empty() or bool(entry.get("up", false)):
		return
	var is_file: bool = not bool(entry.get("is_dir", false))
	_menu.set_item_disabled(_menu.get_item_index(MENU_COPY), not is_file)
	_menu.set_item_disabled(_menu.get_item_index(MENU_CUT), not is_file)
	_menu.set_item_disabled(_menu.get_item_index(MENU_RENAME), not is_file)
	_menu.set_item_disabled(_menu.get_item_index(MENU_DELETE), not is_file)
	_menu.set_item_disabled(_menu.get_item_index(MENU_PASTE), not _can_paste())
	_popup_menu(index, at_position)


func _on_empty_clicked(at_position: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_RIGHT or not run_command.is_valid():
		return
	for id: int in [MENU_OPEN, MENU_COPY, MENU_CUT, MENU_RENAME, MENU_DELETE]:
		_menu.set_item_disabled(_menu.get_item_index(id), true)
	_menu.set_item_disabled(_menu.get_item_index(MENU_PASTE), not _can_paste())
	_popup_menu(-1, at_position)


func _can_paste() -> bool:
	return not clipboard.is_empty() and str(clipboard.get("node", "")) == node_id and bool(clipboard.get("cut", false))


func _popup_menu(index: int, at_position: Vector2) -> void:
	_menu_index = index
	_menu.position = Vector2i(_list.get_screen_position() + at_position)
	_menu.popup()
