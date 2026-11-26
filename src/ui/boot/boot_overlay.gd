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

## Строки появляются по ходу полоски: доля пройденного → строка.
const BOOT_LINES: Array = [
	[0.0, "CORVID BIOS v2.14"],
	[0.15, "проверка памяти .......... ок"],
	[0.35, "диск 0: найден"],
	[0.55, "загрузка ядра .........."],
	[0.8, "запуск служб .........."],
]
const INSTALL_LINES: Array = [
	[0.0, "CORVID BIOS v2.14"],
	[0.0, "загрузка с USB"],
	[0.06, "установщик системы"],
	[0.1, "разметка диска .......... ок"],
	[0.25, "копирование файлов системы .........."],
	[0.7, "восстановление /sys .........."],
	[0.9, "настройка загрузчика .........."],
]
const SHUTDOWN_LINES: Array = [[0.0, "завершение работы .........."]]

var _mode: String = ""
var _buffer: SubViewport
var _display: TextureRect
var _text: RichTextLabel
var _bar: Label
var _off: Button
var _perspective: ShaderMaterial


func _ready() -> void:
	layer = LAYER_FULL
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_hide()
	EventBus.pc_boot_started.connect(func(install: bool, _minutes: int) -> void: _show(INSTALL if install else BOOT))
	EventBus.pc_power_changed.connect(func(on: bool) -> void:
		if not on and Clock.is_fast_forwarding():
			_show(SHUTDOWN))


func mode() -> String:
	return _mode if _display.visible else ""


## Экран на мониторе в комнате (true) или на весь экран (false).
func on_monitor() -> bool:
	return _display.material != null


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
	var lines: Array = INSTALL_LINES if _mode == INSTALL else (SHUTDOWN_LINES if _mode == SHUTDOWN else BOOT_LINES)
	var shown: PackedStringArray = []
	for line: Array in lines:
		if progress >= float(line[0]):
			shown.append(str(line[1]))
	if _mode == INSTALL:
		var plugged: Dictionary = Room.inserted()
		if not plugged.is_empty():
			shown.insert(mini(2, shown.size()), "носитель: %s" % Inventory.label_of(plugged))
	_text.text = "\n".join(shown)
	_bar.text = TerminalView.progress_text(progress).replace("[lb]", "[").replace("[rb]", "]")


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
