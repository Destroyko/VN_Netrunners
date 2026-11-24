extends CanvasLayer
## Смартфон (docs/gameplay/devices.md, «Смартфон»): поверх сцены квартиры и рабочего стола.
## Свёрнутый лежит в правом нижнем углу и показывает строку состояния — самочувствие, деньги и
## непрочитанное видны всегда. `Q`, клик по строке — достать; `Q`, `Esc`, клик снова — убрать.
## `J` — сразу на «Задачах» (планировщик); на них же `J` убирает телефон.
##
## Правил здесь нет: приложения те же, что на ПК (данные одни), и читают свои системы.
## Телефон есть только в игре: сцена его «берёт» (`attach`) и «отдаёт» (`detach`); в главном
## меню и настройках его нет. Пока открыто меню игры, телефон спрятан.

## Размеры телефона — из рендера модели разработчика (`assets/ui/phone/phone_screen.json`,
## `tools/blockout/phone_frames.py`): экран 9:19 с закруглёнными углами. Интерфейс рисуется в экране
## шириной SCREEN_WIDTH логических пикселей, всё остальное пересчитывается от рендера.
const SCREEN_WIDTH: float = 360.0
const MARGIN: float = 12.0
const LAYOUT_PATH: String = "res://assets/ui/phone/phone_screen.json"
const MASK_PATH: String = "res://assets/ui/phone/phone_screen_mask.png"
const BEZEL_PATH: String = "res://assets/ui/phone/phone_%s.png"
## Запасные размеры, если рендера нет: пропорции прежнего замера.
const DEFAULT_LAYOUT: Dictionary = {"x": 82, "y": 82, "w": 669, "h": 1436, "image_w": 833, "image_h": 1600,
	"safe_inset": 29}
## Сколько свёрнутого телефона торчит над краем экрана: рамка, отступ и строка состояния.
const PEEK_EXTRA: float = 18.0

const APP_HOME: String = "home"
## Значки домашнего экрана по порядку. `stub` — приложение следующих шагов: значок серый.
const APPS: Array[Dictionary] = [
	{"id": "messages", "title": "Сообщения"},
	{"id": "mail", "title": "Почта"},
	{"id": "bank", "title": "Банк"},
	{"id": "news", "title": "Новости"},
	{"id": "shop", "title": "Магазин"},
	{"id": "alarm", "title": "Будильник"},
	{"id": "tasks", "title": "Задачи"},
	{"id": "map", "title": "Карта", "stub": true},
]

var frame: Control
var _layout: Dictionary = {}
var _k: float = 1.0
var _bezel: TextureRect
var _bezel_phase: String = ""
var _screen_pos: Vector2 = Vector2.ZERO
var _screen_size: Vector2 = Vector2.ZERO
var _image_size: Vector2 = Vector2.ZERO
var _inset: float = 16.0
var _status_height: float = 34.0
var _status: PhoneStatus
var _screen: MarginContainer
var _nav: HBoxContainer
var _app: String = APP_HOME
var _open: bool = false
## Чья сцена сейчас держит телефон (null — телефона нет на экране).
var _owner: Node = null
var _bottom: float = 0.0
## Телефон показывается на экране у этой сцены (false — только держится для игры, см. attach).
var _phone_shown: bool = true


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_apply()


## Ширина телефона на экране (логическая, без поправки на тесное окно): сцены оставляют под него место.
var WIDTH: float:
	get:
		return _image_size.x if _image_size.x > 0.0 else 448.0


# --- Кто держит телефон ----------------------------------------------------------------

## Сцена игры держит телефон. `bottom` — сколько места внизу занято (панель задач ПК).
## `phone_shown` — false: игра идёт, но телефона на экране нет (за ПК: всё нужное продублировано
## приложениями стола, 24.11.2026); Q и J тогда ничего не делают.
func attach(owner: Node, bottom: float = 0.0, phone_shown: bool = true) -> void:
	_owner = owner
	_bottom = bottom
	_phone_shown = phone_shown
	close()


func detach(owner: Node) -> void:
	if _owner != owner:
		return
	_owner = null
	close()


## Телефон можно достать и он виден на экране.
func is_available() -> bool:
	return _phone_shown and in_game()


## Идёт игра (сцена держит телефон, меню не открыто), с телефоном на экране или без него.
## От этого зависят и другие слои игры, например инвентарь.
func in_game() -> bool:
	return is_instance_valid(_owner) and not Clock.is_paused_by(PauseMenu.PAUSE_REASON)


# --- Открыть и закрыть -----------------------------------------------------------------

func open(app: String = "") -> void:
	if not is_available():
		return
	_open = true
	show_app(app if not app.is_empty() else _app)


func close() -> void:
	_open = false
	_app = APP_HOME
	_apply()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func is_open() -> bool:
	return _open


func current_app() -> String:
	return _app if _open else ""


## Будильник от объекта в мире: кровать даёт «Спать» и «Подождать».
func open_alarm(modes: PackedStringArray) -> void:
	open("alarm")
	var alarm: AlarmApp = _screen.get_child(0) as AlarmApp if _screen.get_child_count() > 0 else null
	if alarm != null:
		alarm.set_modes(modes)


func show_app(app: String) -> void:
	_app = app
	for child: Node in _screen.get_children():
		_screen.remove_child(child)
		child.queue_free()
	_screen.add_child(_make_app(app))
	_apply()


func _make_app(app: String) -> Control:
	match app:
		"messages":
			return MessagesApp.new()
		"mail":
			return MailApp.new()
		"bank":
			return BankApp.new()
		"news":
			return NewsApp.new()
		"shop":
			return ShopApp.new()
		"tasks":
			return PlannerApp.new()
		"alarm":
			var alarm := AlarmApp.new()
			alarm.rested.connect(func(_mode: String) -> void: close())
			return alarm
	return _home()


func _home() -> Control:
	var grid := GridContainer.new()
	grid.name = "Home"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for app: Dictionary in APPS:
		var button := Button.new()
		button.name = "App_" + str(app["id"])
		button.custom_minimum_size = Vector2(100, 72)
		button.text = str(app["title"]) + _badge(str(app["id"]))
		button.disabled = bool(app.get("stub", false))
		button.pressed.connect(show_app.bind(str(app["id"])))
		grid.add_child(button)
	return grid


func _badge(app: String) -> String:
	var count: int = 0
	if app == "messages":
		count = Messenger.unread_count()
	elif app == "mail":
		count = Mailbox.unread_count()
	return "\n● %d" % count if count > 0 else ""


## Свёрнут — видна только строка состояния у нижнего края; открыт — весь телефон.
func _apply() -> void:
	var shown: bool = is_available()
	frame.visible = shown
	if not shown:
		_open = false
	_screen.visible = _open
	_nav.visible = _open
	_refresh_bezel()
	# Телефон не выше экрана игры: в тесном окне весь корпус пересчитывается меньше (масштаб < 1).
	var room: float = get_viewport().get_visible_rect().size.y - 2.0 * MARGIN - _bottom
	var scale_now: float = clampf(room / _image_size.y, 0.4, 1.0)
	frame.scale = Vector2(scale_now, scale_now)
	var width: float = _image_size.x * scale_now
	var height: float = _image_size.y * scale_now
	# Открытый целиком стоит у угла; свёрнутый спрятан ниже края и торчит только верхом с состоянием.
	var peek: float = (_screen_pos.y + _inset + _status_height + PEEK_EXTRA) * scale_now
	var left: float = -MARGIN - width
	var top: float = -_bottom - MARGIN - height if _open else -_bottom - peek
	frame.offset_left = left
	frame.offset_top = top
	frame.offset_right = left + _image_size.x
	frame.offset_bottom = top + _image_size.y


## Рамка по времени суток комнаты: день, вечер или ночь (утро как день).
func _refresh_bezel() -> void:
	if _bezel == null:
		return
	var phase: String = Clock.time_of_day()
	phase = "day" if phase == "morning" else phase
	if phase == _bezel_phase:
		return
	_bezel_phase = phase
	var path: String = BEZEL_PATH % phase
	_bezel.texture = load(path) as Texture2D if ResourceLoader.exists(path) else null


# --- Ввод -------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	# Меню игры открылось или закрылось — телефон прячется и возвращается.
	if frame.visible != is_available():
		_apply()


## Esc закрывает открытый телефон раньше, чем его увидит сцена (иначе откроется меню игры).
func _input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or not [KEY_Q, KEY_J].has(key.keycode):
		return
	# Пока печатают, буквы — это текст; пока идёт диалог, телефон не достать.
	if _typing_in_field() or DialogueManager.is_active() or not is_available():
		return
	get_viewport().set_input_as_handled()
	if key.keycode == KEY_Q:
		toggle()
	elif _open and _app == "tasks":
		close()
	else:
		open("tasks")


func _typing_in_field() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _on_status_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		toggle()


# --- Сборка -----------------------------------------------------------------------------

func _load_layout() -> void:
	_layout = DEFAULT_LAYOUT.duplicate()
	if FileAccess.file_exists(LAYOUT_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
		if parsed is Dictionary:
			_layout.merge(parsed as Dictionary, true)
	_k = SCREEN_WIDTH / float(_layout["w"])
	_screen_pos = Vector2(float(_layout["x"]), float(_layout["y"])) * _k
	_screen_size = Vector2(float(_layout["w"]), float(_layout["h"])) * _k
	_image_size = Vector2(float(_layout["image_w"]), float(_layout["image_h"])) * _k
	_inset = ceilf(float(_layout["safe_inset"]) * _k)


func _build() -> void:
	_load_layout()
	frame = Control.new()
	frame.name = "Phone"
	frame.anchor_left = 1.0
	frame.anchor_right = 1.0
	frame.anchor_top = 1.0
	frame.anchor_bottom = 1.0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	# Экран: скруглённая маска обрезает всё, что внутри (clip_children), поэтому приложения не
	# заходят за закруглённые углы; внутренние отступы — safe_inset рендера.
	var clip := TextureRect.new()
	clip.name = "ScreenClip"
	clip.position = _screen_pos
	clip.size = _screen_size
	clip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	clip.stretch_mode = TextureRect.STRETCH_SCALE
	if ResourceLoader.exists(MASK_PATH):
		clip.texture = load(MASK_PATH) as Texture2D
	clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.add_child(clip)
	var back := ColorRect.new()
	back.color = GameTheme.color("background")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(back)
	var pad := MarginContainer.new()
	pad.name = "Pad"
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, int(_inset))
	clip.add_child(pad)
	var column := VBoxContainer.new()
	pad.add_child(column)
	_status = PhoneStatus.new()
	_status.gui_input.connect(_on_status_input)
	_status.mouse_filter = Control.MOUSE_FILTER_STOP
	_status.tooltip_text = "Телефон (Q)"
	_status.custom_minimum_size = Vector2(0, _status_height)
	column.add_child(_status)
	_screen = MarginContainer.new()
	_screen.name = "Screen"
	_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_screen.clip_contents = true
	column.add_child(_screen)
	_nav = HBoxContainer.new()
	_nav.name = "Nav"
	_nav.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_nav)
	var home := Button.new()
	home.name = "Home"
	home.text = "Домой"
	home.flat = true
	home.pressed.connect(show_app.bind(APP_HOME))
	_nav.add_child(home)
	var hide_button := Button.new()
	hide_button.name = "Hide"
	hide_button.text = "Убрать (Q)"
	hide_button.flat = true
	hide_button.pressed.connect(close)
	_nav.add_child(hide_button)
	_screen.add_child(_home())

	# Рамка корпуса поверх интерфейса: экран в ней вырезан, мышь она не трогает.
	_bezel = TextureRect.new()
	_bezel.name = "Bezel"
	_bezel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bezel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bezel.stretch_mode = TextureRect.STRETCH_SCALE
	_bezel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_bezel)
	frame.size = _image_size
	get_viewport().size_changed.connect(_apply)


# --- Для тестов --------------------------------------------------------------------------

func status() -> PhoneStatus:
	return _status


func app_node() -> Control:
	return _screen.get_child(_screen.get_child_count() - 1) as Control if _screen.get_child_count() > 0 else null
