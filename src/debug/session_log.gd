extends Node
## Журнал сессии и снимок «здесь баг» по F9 (docs/tech/testing.md, «Отчёт об ошибке»).
## Инфраструктура разработки, не игровая система: работает только в отладочной сборке и не
## в тестах (headless), чтобы прогоны не засоряли папку.
##
## Журнал: каждый запуск пишет `bugreports/sessions/<время>.log` — сид, команды терминала и
## консоли F1, головоломки и клики в них, события шины, ошибки Godot.
## Снимок (F9 или `bug [заметка]` в F1): `bugreports/<время>/` — screenshot.png, state.json
## (всё состояние игры), session.log (журнал до этого момента), note.txt (если есть заметка).
## Последний снимок — последний по имени папки.

const HOTKEY: Key = KEY_F9
## Сигналы, которые идут слишком часто, чтобы писать каждый.
const QUIET_SIGNALS: PackedStringArray = ["time_advanced"]
const TOAST_SECONDS: float = 3.0

var active: bool = false
var base_dir: String = ""

var _file: FileAccess
var _session_path: String = ""
var _started_ms: int = 0
var _scene_path: String = ""
var _toast: Label
var _catcher: RefCounted


func _ready() -> void:
	if OS.is_debug_build() and DisplayServer.get_name() != "headless":
		begin(_pick_base_dir())


## Включить журнал с папкой `dir`. Отдельно от _ready, чтобы тест включил его во временной папке.
func begin(dir: String) -> void:
	active = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started_ms = Time.get_ticks_msec()
	base_dir = dir
	var sessions: String = base_dir.path_join(BugReport.SESSIONS_SUBDIR)
	DirAccess.make_dir_recursive_absolute(sessions)
	_session_path = sessions.path_join(BugReport.stamp(Time.get_datetime_dict_from_system()) + ".log")
	_file = FileAccess.open(_session_path, FileAccess.WRITE)
	write("info", "сессия начата, Godot %s" % Engine.get_version_info().get("string", ""))
	_listen_to_event_bus()
	_catch_engine_errors()
	if _toast == null:
		_build_toast()


## Папка проекта, если в неё можно писать (запуск из редактора), иначе папка данных игры.
func _pick_base_dir() -> String:
	var project: String = ProjectSettings.globalize_path(BugReport.PROJECT_DIR)
	if OS.has_feature("editor") and DirAccess.make_dir_recursive_absolute(project) == OK:
		# Godot не должен импортировать скриншоты из этой папки как ресурсы.
		var ignore: String = project.path_join(".gdignore")
		if not FileAccess.file_exists(ignore):
			FileAccess.open(ignore, FileAccess.WRITE)
		return project
	return ProjectSettings.globalize_path(BugReport.USER_DIR)


## Записать строку в журнал. Вид — короткое слово: term, f1, puzzle, event, error, info.
func write(kind: String, text: String) -> void:
	if not active or _file == null:
		return
	_file.store_line(BugReport.line(Time.get_ticks_msec() - _started_ms, GameState.day, GameState.minute, kind, text))
	_file.flush()


func _process(_delta: float) -> void:
	if not active:
		return
	var scene: Node = get_tree().current_scene
	var path: String = scene.scene_file_path if scene != null else ""
	if path != _scene_path:
		_scene_path = path
		write("scene", path)


func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if active and key != null and key.pressed and not key.echo and key.keycode == HOTKEY:
		get_viewport().set_input_as_handled()
		snapshot("")


## Снимок «здесь баг». Возвращает путь к папке (пусто, если журнал выключен).
func snapshot(note: String) -> String:
	if not active:
		return ""
	var dir: String = base_dir.path_join(BugReport.stamp(Time.get_datetime_dict_from_system()))
	DirAccess.make_dir_recursive_absolute(dir)
	write("bug", "снимок %s%s" % [dir.get_file(), (": " + note) if not note.is_empty() else ""])

	var state: Dictionary = GameState.to_dict()
	state["_seed"] = Rng.get_seed()
	state["_scene"] = _scene_path
	state["_clock_running"] = Clock.running
	var json: FileAccess = FileAccess.open(dir.path_join("state.json"), FileAccess.WRITE)
	json.store_string(JSON.stringify(state, "  "))
	json.close()
	if not note.is_empty():
		FileAccess.open(dir.path_join("note.txt"), FileAccess.WRITE).store_string(note)
	DirAccess.copy_absolute(_session_path, dir.path_join("session.log"))
	_save_screenshot.call_deferred(dir)
	_show_toast("Снимок сохранён: bugreports/%s" % dir.get_file())
	return dir


## Скриншот — после отрисовки кадра, иначе на нём будет прошлый кадр без всплывших окон.
func _save_screenshot(dir: String) -> void:
	await RenderingServer.frame_post_draw
	var texture: ViewportTexture = get_viewport().get_texture()
	var image: Image = texture.get_image() if texture != null else null
	# Без экрана (headless) снимать нечего — остальное в снимке всё равно есть.
	if image != null and not image.is_empty():
		image.save_png(dir.path_join("screenshot.png"))


# --- Что пишем сами --------------------------------------------------------------

## Все сигналы шины событий: это и есть «что произошло в игре».
func _listen_to_event_bus() -> void:
	for info: Dictionary in EventBus.get_signal_list():
		var name: String = str(info["name"])
		if QUIET_SIGNALS.has(name):
			continue
		var count: int = (info["args"] as Array).size()
		EventBus.connect(name, _listener(name, count))


## Сигналы разной длины: GDScript не умеет «сколько угодно аргументов» у лямбды.
func _listener(name: String, count: int) -> Callable:
	match count:
		0:
			return func() -> void: write("event", name)
		1:
			return func(a: Variant) -> void: write("event", "%s(%s)" % [name, BugReport.describe_args([a])])
		2:
			return func(a: Variant, b: Variant) -> void: write("event", "%s(%s)" % [name, BugReport.describe_args([a, b])])
		3:
			return func(a: Variant, b: Variant, c: Variant) -> void: write("event", "%s(%s)" % [name, BugReport.describe_args([a, b, c])])
		4:
			return func(a: Variant, b: Variant, c: Variant, d: Variant) -> void: write("event", "%s(%s)" % [name, BugReport.describe_args([a, b, c, d])])
	return func(a: Variant = null, b: Variant = null, c: Variant = null, d: Variant = null, e: Variant = null) -> void:
		write("event", "%s(%s)" % [name, BugReport.describe_args([a, b, c, d, e])])


## Ошибки Godot (падения скриптов) — в тот же журнал. Ловец в отдельном файле: если API
## движка поменяется, сломается только он, а журнал продолжит работать.
func _catch_engine_errors() -> void:
	var script: Script = load("res://src/debug/error_catcher.gd") as Script
	if script == null or not script.can_instantiate() or not OS.has_method("add_logger"):
		write("info", "ошибки Godot в журнал не попадают: нет OS.add_logger")
		return
	_catcher = script.new()
	_catcher.set("sink", write.bind("error"))
	OS.call("add_logger", _catcher)


func _build_toast() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	_toast = Label.new()
	_toast.visible = false
	_toast.position = Vector2(16, 16)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	layer.add_child(_toast)


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	get_tree().create_timer(TOAST_SECONDS).timeout.connect(func() -> void: _toast.visible = false)
