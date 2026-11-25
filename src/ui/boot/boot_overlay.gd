extends CanvasLayer
## Экран своего ПК, пока он выключается, загружается или ставит систему с флешки (шаг 7.5).
## Чёрный экран с текстом, как у настоящего железа, и полоской: минуты идут ускоренно
## (`Clock.fast_forward`), как у программы. Во время загрузки и установки внизу — «Выключить
## питание»: установка прерывается без последствий (`PcPower.abort_boot`).
##
## Правил здесь нет: когда загрузка закончилась и что поставлено, решает `PcPower`; окно только
## показывает. Пока минуты не идут (часы стоят, тесты), экрана нет.

const SHUTDOWN: String = "shutdown"
const BOOT: String = "boot"
const INSTALL: String = "install"

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
var _screen: ColorRect
var _text: RichTextLabel
var _bar: Label
var _off: Button


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_screen.visible = false
	EventBus.pc_boot_started.connect(func(install: bool, _minutes: int) -> void: _show(INSTALL if install else BOOT))
	EventBus.pc_power_changed.connect(func(on: bool) -> void:
		if not on and Clock.is_fast_forwarding():
			_show(SHUTDOWN))


func mode() -> String:
	return _mode if _screen.visible else ""


func _show(what: String) -> void:
	_mode = what
	_screen.visible = true
	_off.visible = what != SHUTDOWN
	_redraw()


func _process(_delta: float) -> void:
	if not _screen.visible:
		return
	# Минуты прошли (или их бросили) — экран больше не нужен: дальше стол или комната.
	if not Clock.is_fast_forwarding() and not PcPower.is_booting():
		_screen.visible = false
		_mode = ""
		return
	_redraw()


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
	_screen = ColorRect.new()
	_screen.name = "BootScreen"
	_screen.color = Color.BLACK
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_screen)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	_screen.add_child(margin)
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
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	_off = Button.new()
	_off.name = "PowerOff"
	_off.text = "Выключить питание"
	_off.size_flags_horizontal = Control.SIZE_SHRINK_END
	_off.focus_mode = Control.FOCUS_NONE
	_off.pressed.connect(func() -> void: PcPower.abort_boot())
	column.add_child(_off)
