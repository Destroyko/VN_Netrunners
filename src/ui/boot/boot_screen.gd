class_name BootScreen
extends Control
## Экран загрузки при запуске (docs/roadmap.md, шаг 6а): ставит общую тему интерфейса, подгружает
## тяжёлые картинки (фоны и маски кадров) с полоской прогресса и открывает главное меню. Картинки
## остаются в памяти (`_kept`), поэтому комната потом открывается без паузы. Правил игры здесь нет.

## Не быстрее: полоса, мелькнувшая на пол-кадра, выглядит ошибкой.
const MIN_SECONDS: float = 0.8
const ASSET_DIRS: PackedStringArray = ["res://assets/backgrounds", "res://assets/masks"]
const TITLE: String = "NETRUNNERS"

## Загруженные ресурсы: без ссылки кэш Godot их сбросил бы.
static var _kept: Array = []

var _bar: ProgressBar
var _status: Label
var _paths: PackedStringArray = []
var _loaded: int = 0
var _elapsed: float = 0.0
var _going: bool = false


## Что подгружать: картинки фонов и масок. Меню и вспомогательные слои (облака) — не нужны сразу.
static func assets_to_preload() -> PackedStringArray:
	var found: PackedStringArray = []
	for dir_path: String in ASSET_DIRS:
		for file: String in DirAccess.get_files_at(dir_path):
			if file.ends_with(".png") and not file.begins_with("bg_menu"):
				found.append(dir_path.path_join(file))
	found.sort()
	return found


func _ready() -> void:
	get_tree().root.theme = GameTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = GameTheme.color("background")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(360, 0)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var title := Label.new()
	title.text = TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", GameTheme.color("accent"))
	box.add_child(title)
	_bar = ProgressBar.new()
	_bar.name = "Bar"
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 8)
	box.add_child(_bar)
	_status = Label.new()
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", GameTheme.color("text_dim"))
	box.add_child(_status)

	_paths = assets_to_preload()
	_bar.max_value = maxf(1.0, float(_paths.size()))
	for path: String in _paths:
		ResourceLoader.load_threaded_request(path)
	_status.text = "Загрузка…"


func _process(delta: float) -> void:
	_elapsed += delta
	while _loaded < _paths.size():
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(_paths[_loaded])
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			break
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_kept.append(ResourceLoader.load_threaded_get(_paths[_loaded]))
		_loaded += 1
	_bar.value = float(_loaded)
	if _loaded >= _paths.size() and _elapsed >= MIN_SECONDS and not _going:
		_going = true
		get_tree().change_scene_to_file(Screens.MAIN_MENU)
