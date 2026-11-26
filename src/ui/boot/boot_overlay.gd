extends CanvasLayer
## Экран своего ПК, пока он выключается, загружается или ставит систему с флешки (шаг 7.5).
## Чёрный экран с текстом, как у настоящего железа, и полоской: минуты идут ускоренно
## (`Clock.fast_forward`), как у программы. Во время загрузки и установки — «Выключить питание»:
## установка прерывается без последствий (`PcPower.abort_boot`).
##
## Где его видно (баг разработчика 25.11.2026): в комнате — **на мониторе**, в перспективе экрана
## на фоне (углы — поле `screen` у объекта-монитора в данных локации, `ScreenQuad`); за ПК
## (перезагрузка со стола) — на весь экран. Сам экран рисуется в свой буфер (`SubViewport`).
##
## Правил здесь нет: когда загрузка закончилась и что поставлено, решает `PcPower`; окно только
## показывает. Пока минуты не идут (часы стоят, тесты), экрана нет.

const SHUTDOWN: String = "shutdown"
const BOOT: String = "boot"
const INSTALL: String = "install"
## Буфер экрана на мониторе в комнате. Крупнее — мельче текст на мониторе: при 640×400 строки
## растягивались почти до размера монитора (баг разработчика 25.11.2026).
const MONITOR_BUFFER: Vector2i = Vector2i(1280, 800)
## Слой экрана: на мониторе в комнате — часть сцены, под инвентарём, телефоном и окнами
## (поверх них он ложился, баг разработчика 25.11.2026); за ПК — поверх всего.
const LAYER_MONITOR: int = 1
const LAYER_FULL: int = 70

## Загрузка как у настоящего железа (разработчик, 26.11.2026): сначала проверка комплектующих
## по-английски (доля пройденного → строка), потом заставка — название ОС по центру и бегущая
## полоска, как у Windows XP. Установка с флешки — те же проверки и строки установщика.
const POST_LINES: Array = [
	[0.0, "CORVID BIOS v2.14   (C) 2019"],
	[0.04, "CPU: 4 cores @ 3.20 GHz ................ ok"],
	[0.10, "Memory test: 16384 MB .................. ok"],
	[0.18, "GPU .................................... ok"],
	[0.24, "SSD 512 GB ............................. ok"],
	[0.30, "Ethernet ............................... ok"],
	[0.35, "USB controller ......................... ok"],
	[0.40, "Audio .................................. ok"],
]
## Доля загрузки, после которой проверки сменяются заставкой.
const POST_SHARE: float = 0.55
const INSTALL_LINES: Array = [
	[0.0, "Boot device: USB"],
	[0.06, "установщик системы"],
	[0.1, "разметка диска .......... ок"],
	[0.25, "копирование файлов системы .........."],
	[0.7, "восстановление /sys .........."],
	[0.9, "настройка загрузчика .........."],
]
## Выключение: первая часть — окна закрываются по одному (это делает стол), вторая — гаснет экран.
const SHUTDOWN_FADE_FROM: float = 0.55
## Название ОС на заставке (заглушка — как в заставке терминала, open-questions.md).
const OS_TITLE: String = "Corvid Linux"

var _mode: String = ""
var _buffer: SubViewport
var _display: TextureRect
var _text: RichTextLabel
var _bar: Label
var _console: Control
var _splash: Control
var _runner: Control
var _time: float = 0.0
## Доля общего отрезка, которую ещё занимает выключение (перезагрузка); 0 — сразу загрузка.
var _boot_from: float = 0.0
var _off: Button
var _perspective: ShaderMaterial


func _ready() -> void:
	layer = LAYER_FULL
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_hide()
	EventBus.pc_boot_started.connect(_on_boot_started)
	EventBus.pc_power_changed.connect(func(on: bool) -> void:
		if not on and Clock.is_fast_forwarding():
			_show(SHUTDOWN))


func mode() -> String:
	return _mode if _display.visible else ""


## Экран на мониторе в комнате (true) или на весь экран (false).
func on_monitor() -> bool:
	return _display.material != null


## Загрузка началась. Сразу после выключения (перезагрузка) минуты идут одним отрезком: первая
## его часть — ещё выключение, загрузка показывается после неё.
func _on_boot_started(install: bool, minutes: int) -> void:
	var shutdown_left: bool = _display.visible and _mode == SHUTDOWN
	_boot_from = 0.0
	if shutdown_left:
		var total: float = float(minutes) + float(_shutdown_minutes())
		_boot_from = float(_shutdown_minutes()) / total if total > 0.0 else 0.0
	_show(INSTALL if install else BOOT)


static func _shutdown_minutes() -> int:
	return int((DataLoader.balance().get("pc", {}) as Dictionary).get("shutdown_minutes", 1))


func _show(what: String) -> void:
	_mode = what
	_display.visible = true
	_off.visible = what != SHUTDOWN
	_place()
	_redraw()


func _hide() -> void:
	_display.visible = false
	_off.visible = false
	_mode = ""


func _process(_delta: float) -> void:
	if not _display.visible:
		return
	_time += _delta
	_runner.queue_redraw()
	# Минуты прошли (или их бросили) — экран больше не нужен: дальше стол или комната.
	if not Clock.is_fast_forwarding() and not PcPower.is_booting():
		_hide()
		return
	_place()
	_redraw()


## Куда показывать: монитор текущей сцены, если он есть, иначе весь экран.
func _place() -> void:
	var view: Vector2 = _display.get_viewport_rect().size
	var quad: PackedVector2Array = _monitor_quad()
	if quad.size() == 4:
		layer = LAYER_MONITOR
		_buffer.size = MONITOR_BUFFER
		var to_screen: Basis = ScreenQuad.square_to_quad(quad)
		_perspective.set_shader_parameter("screen_to_uv", to_screen.inverse())
		_perspective.set_shader_parameter("view_size", view)
		_display.material = _perspective
		_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Кнопка — под левым нижним углом монитора: в комнате игрок смотрит на ПК со стороны.
		_off.position = quad[3] + Vector2(0, 12)
	else:
		layer = LAYER_FULL
		_buffer.size = Vector2i(view)
		_display.material = null
		_display.mouse_filter = Control.MOUSE_FILTER_STOP
		_off.position = view - _off.get_combined_minimum_size() - Vector2(48, 48)


func _monitor_quad() -> PackedVector2Array:
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	if scene != null and scene.has_method("monitor_screen_quad"):
		return scene.call("monitor_screen_quad") as PackedVector2Array
	return PackedVector2Array()


func _redraw() -> void:
	var progress: float = Clock.fast_progress()
	var shutting: bool = _mode == SHUTDOWN or progress < _boot_from
	if _mode != SHUTDOWN and not shutting and _boot_from > 0.0:
		progress = (progress - _boot_from) / (1.0 - _boot_from)
	if shutting:
		if _mode != SHUTDOWN:
			progress = progress / _boot_from
		# Сначала стол закрывает окна, потом экран гаснет.
		_console.visible = false
		_splash.visible = false
		_off.visible = false
		_display.modulate.a = clampf((progress - SHUTDOWN_FADE_FROM) / (1.0 - SHUTDOWN_FADE_FROM), 0.0, 1.0)
		return
	_off.visible = true
	_display.modulate.a = 1.0
	var install: bool = _mode == INSTALL
	var splash: bool = not install and progress >= POST_SHARE
	_console.visible = not splash
	_splash.visible = splash
	if splash:
		return
	var post: float = progress / POST_SHARE if not install else minf(1.0, progress * 6.0)
	var shown: PackedStringArray = []
	for line: Array in POST_LINES:
		if post >= float(line[0]) / POST_LINES[POST_LINES.size() - 1][0] * 0.9:
			shown.append(str(line[1]))
	if install:
		var plugged: Dictionary = Room.inserted()
		for line: Array in INSTALL_LINES:
			if progress >= float(line[0]):
				shown.append(str(line[1]))
		if not plugged.is_empty():
			shown.insert(mini(POST_LINES.size() + 1, shown.size()), "носитель: %s" % Inventory.label_of(plugged))
		_bar.text = TerminalView.progress_text(progress).replace("[lb]", "[").replace("[rb]", "]")
	else:
		if post >= 0.95:
			shown.append("загружена тема: %s" % GameTheme.pc_theme_id())
		_bar.text = ""
	_text.text = "\n".join(shown)


## Бегущие блоки заставки: три квадрата едут слева направо по дорожке, снова и снова.
func _draw_runner() -> void:
	var track: Vector2 = _runner.size
	var block: float = track.y - 6.0
	var span: float = track.x + block * 3.0
	var head: float = fmod(_time * 140.0, span) - block * 3.0
	_runner.draw_rect(Rect2(Vector2.ZERO, track), Color(0.55, 0.6, 0.7), false, 2.0)
	for i: int in 3:
		var x: float = head + i * (block + 4.0)
		if x > 2.0 and x + block < track.x - 2.0:
			_runner.draw_rect(Rect2(x, 3.0, block, block), Color(0.35, 0.6, 1.0))


func _build() -> void:
	_buffer = SubViewport.new()
	_buffer.name = "ScreenBuffer"
	_buffer.size = MONITOR_BUFFER
	_buffer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_buffer)
	var screen := ColorRect.new()
	screen.name = "BootScreen"
	screen.color = Color.BLACK
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_buffer.add_child(screen)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	screen.add_child(margin)
	_console = margin
	_splash = CenterContainer.new()
	_splash.name = "Splash"
	_splash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_splash.visible = false
	screen.add_child(_splash)
	var splash_column := VBoxContainer.new()
	splash_column.add_theme_constant_override("separation", 24)
	_splash.add_child(splash_column)
	var title := Label.new()
	title.name = "OsTitle"
	title.text = OS_TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", GameTheme.font("heading"))
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	splash_column.add_child(title)
	_runner = Control.new()
	_runner.name = "Runner"
	_runner.custom_minimum_size = Vector2(180, 18)
	_runner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_runner.draw.connect(_draw_runner)
	splash_column.add_child(_runner)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var font: Font = GameTheme.font("mono")
	_text = RichTextLabel.new()
	_text.name = "Text"
	_text.fit_content = true
	_text.scroll_active = false
	_text.add_theme_font_override("normal_font", font)
	_text.add_theme_color_override("default_color", Color(0.78, 0.8, 0.82))
	column.add_child(_text)
	_bar = Label.new()
	_bar.name = "Bar"
	_bar.add_theme_font_override("font", font)
	_bar.add_theme_color_override("font_color", Color(0.78, 0.8, 0.82))
	column.add_child(_bar)

	_display = TextureRect.new()
	_display.name = "Display"
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	_display.texture = _buffer.get_texture()
	add_child(_display)
	_perspective = ShaderMaterial.new()
	_perspective.shader = load("res://src/ui/boot/screen_quad.gdshader") as Shader

	_off = Button.new()
	_off.name = "PowerOff"
	_off.text = "Выключить питание"
	_off.focus_mode = Control.FOCUS_NONE
	_off.pressed.connect(func() -> void: PcPower.abort_boot())
	add_child(_off)
