class_name HomeFilePicker
extends VBoxContainer
## Мини-проводник по своему ПК: выбрать файлы (несколько сразу) — например, чтобы прикрепить к
## письму. Папки открываются двойным щелчком, «Вверх» — на уровень выше; файл можно и утащить
## мышью в письмо. Только показывает: читает `Filesystem` своего ПК, ничего не меняет.

signal files_chosen(paths: PackedStringArray)

const START_DIR: String = "/home"
## Что тащится из списка: такой же словарь примет любое окно, куда можно бросить свой файл.
const DRAG_KEY: String = "home_files"

var _dir: String = START_DIR
var _path: Label
var _list: FileList
var _entries: Array[Dictionary] = []


func _init() -> void:
	name = "HomeFilePicker"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	add_child(head)
	var up := Button.new()
	up.name = "Up"
	up.text = "Вверх"
	up.pressed.connect(func() -> void: open_dir(_dir.get_base_dir() if _dir != START_DIR else _dir))
	head.add_child(up)
	_path = Label.new()
	head.add_child(_path)
	_list = FileList.new()
	_list.name = "Files"
	_list.select_mode = ItemList.SELECT_MULTI
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 120)
	_list.item_activated.connect(_on_activated)
	_list.drag_source = _drag_data
	add_child(_list)
	var choose := Button.new()
	choose.name = "Choose"
	choose.text = "Прикрепить выбранные"
	choose.pressed.connect(func() -> void: files_chosen.emit(selected_paths()))
	add_child(choose)


func _ready() -> void:
	open_dir(START_DIR)


func open_dir(path: String) -> void:
	_dir = path
	_path.text = path
	_list.clear()
	_entries = Filesystem.for_node(Network.HOME_ID).list(path, true)
	for e: Dictionary in _entries:
		_list.add_item(("%s/" if bool(e["is_dir"]) else "%s") % str(e["name"]))


func current_dir() -> String:
	return _dir


## Выбранные файлы (папки не прикрепляются).
func selected_paths() -> PackedStringArray:
	var paths: PackedStringArray = []
	for index: int in _list.get_selected_items():
		var e: Dictionary = _entries[index]
		if not bool(e["is_dir"]):
			paths.append(str(e["path"]))
	return paths


## Выделить файлы по имени — для тестов.
func select_names(names: PackedStringArray) -> void:
	_list.deselect_all()
	for i: int in _entries.size():
		if names.has(str(_entries[i]["name"])):
			_list.select(i, false)


func _on_activated(index: int) -> void:
	var e: Dictionary = _entries[index]
	if bool(e["is_dir"]):
		open_dir(str(e["path"]))
	else:
		files_chosen.emit(PackedStringArray([str(e["path"])]))


## Тащим выделенные файлы (или тот, за который взялись, если он не выделен).
func _drag_data(index: int) -> Variant:
	var e: Dictionary = _entries[index]
	if bool(e["is_dir"]):
		return null
	var paths: PackedStringArray = selected_paths()
	if not paths.has(str(e["path"])):
		paths = PackedStringArray([str(e["path"])])
	return {DRAG_KEY: paths}
