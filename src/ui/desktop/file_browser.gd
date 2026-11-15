class_name FileBrowser
extends VBoxContainer
## Проводник узла — «тонкий клиент» рядом с консолью (docs/tech/desktop-layout.md, концепция
## «взлом с виджетами»). Пока только смотреть: папки открываются двойным кликом, «..» — наверх.
## Копирование и перетаскивание — следующим шагом. Своего каталога у консоли он не меняет:
## у проводника свой путь, как у отдельной программы.

var terminal: Terminal
var node_id: String = ""
var path: String = FsPath.ROOT

var _path_label: Label
var _list: ItemList


func setup(shared_terminal: Terminal, node: String) -> void:
	terminal = shared_terminal
	node_id = node
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_path_label = Label.new()
	_path_label.add_theme_font_override("font", PasswordPanel._mono())
	add_child(_path_label)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_override("font", PasswordPanel._mono())
	_list.item_activated.connect(_on_activated)
	add_child(_list)
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


## Открыть папку по номеру строки (двойной клик). Файлы и закрытые папки не открываются.
func open_item(index: int) -> void:
	var entry: Dictionary = _list.get_item_metadata(index) as Dictionary
	if not bool(entry.get("is_dir", false)) or bool(entry.get("locked", false)):
		return
	if bool(entry.get("up", false)):
		path = FsPath.parent(path) if path != FsPath.ROOT else FsPath.ROOT
	else:
		path = str(entry["path"])
	refresh()


func item_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for index: int in _list.item_count:
		names.append(_list.get_item_text(index))
	return names


func _on_activated(index: int) -> void:
	open_item(index)
