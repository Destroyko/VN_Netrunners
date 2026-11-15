class_name TerminalView
extends VBoxContainer
## Окно терминала (docs/tech/desktop-layout.md, «Окно терминала»): один экран, как у настоящей
## консоли. Сверху заставка ОС, дальше вывод, строка ввода идёт сразу за последней строкой.
## Без боковых панелей и без контекстного меню у поля ввода. Только показывает: команды
## выполняет `Terminal`. Головоломка открывается отдельным окном: вид отдаёт запрос через
## `puzzle_requested` и принимает итог через `show_result`.

signal puzzle_requested(request: Dictionary)
## Подключились к ПК (или он спросил пароль): стол открывает трансляцию его рабочего стола.
signal remote_requested(request: Dictionary)
## Команда выполнена: карта сети и режим стола перечитывают состояние.
signal result_shown

const BACKGROUND: Color = Color(0.03, 0.04, 0.05)
const TEXT_COLOR: Color = Color(0.82, 0.86, 0.84)

var terminal: Terminal

var _scroll: ScrollContainer
var _output: RichTextLabel
var _entry: LineEdit
var _prompt: Label
var _trace: ProgressBar
var _history_pos: int = -1


func setup(shared_terminal: Terminal) -> void:
	terminal = shared_terminal
	_build()
	terminal.ticked.connect(_on_ticked)
	print_lines(terminal.banner())
	_refresh()


func _build() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)

	var trace_row := HBoxContainer.new()
	trace_row.name = "TraceRow"
	trace_row.visible = false
	add_child(trace_row)
	var trace_label := Label.new()
	trace_label.text = "трейс"
	trace_row.add_child(trace_label)
	_trace = ProgressBar.new()
	_trace.show_percentage = false
	_trace.max_value = 1.0
	_trace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trace.custom_minimum_size = Vector2(0, 14)
	trace_row.add_child(_trace)

	# Экран консоли: тёмный фон, вывод и строка ввода в одном прокручиваемом столбце.
	var screen := PanelContainer.new()
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.set_content_margin_all(8)
	screen.add_theme_stylebox_override("panel", style)
	screen.gui_input.connect(_on_screen_input)
	add_child(screen)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	screen.add_child(_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	_scroll.add_child(column)

	_output = RichTextLabel.new()
	_output.fit_content = true
	_output.scroll_active = false
	_output.selection_enabled = true
	_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output.add_theme_font_override("normal_font", _mono_font())
	_output.add_theme_color_override("default_color", TEXT_COLOR)
	column.add_child(_output)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 0)
	column.add_child(input_row)
	_prompt = Label.new()
	_prompt.add_theme_font_override("font", _mono_font())
	_prompt.add_theme_color_override("font_color", TEXT_COLOR)
	input_row.add_child(_prompt)
	_entry = LineEdit.new()
	_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry.add_theme_font_override("font", _mono_font())
	_entry.add_theme_color_override("font_color", TEXT_COLOR)
	# Строка ввода — часть экрана, а не поле формы: без рамки, меню по правой кнопке и эмодзи.
	_entry.flat = true
	_entry.context_menu_enabled = false
	if "emoji_menu_enabled" in _entry:
		_entry.set("emoji_menu_enabled", false)
	_entry.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_entry.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_entry.text_submitted.connect(_on_submitted)
	_entry.gui_input.connect(_on_entry_input)
	input_row.add_child(_entry)


static func _mono_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	return font


func focus_entry() -> void:
	_entry.grab_focus()


## Клик в любом месте экрана ставит курсор в строку ввода, как в настоящей консоли.
func _on_screen_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_entry.grab_focus()


# --- Ввод ----------------------------------------------------------------------

func submit(line: String) -> void:
	_history_pos = -1
	# Пароль не печатается и не пишется в журнал — как в настоящей консоли.
	var shown: String = "" if terminal.login_pending() else line
	_print(_prompt.text + shown)
	SessionLog.write("term", _prompt.text + (shown if not terminal.login_pending() else "***"))
	show_result(terminal.execute(line))


func _on_submitted(text: String) -> void:
	_entry.clear()
	submit(text)
	_entry.grab_focus()


func _on_entry_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_TAB:
			_complete()
			_entry.accept_event()
		KEY_UP:
			_step_history(-1)
			_entry.accept_event()
		KEY_DOWN:
			_step_history(1)
			_entry.accept_event()


func _complete() -> void:
	var report: Dictionary = terminal.complete(_entry.text)
	var options: PackedStringArray = report["options"] as PackedStringArray
	if options.size() > 1:
		_print(_prompt.text + _entry.text)
		_print("  ".join(options))
	_entry.text = str(report["line"])
	_entry.caret_column = _entry.text.length()


func _step_history(direction: int) -> void:
	var history: PackedStringArray = terminal.history()
	if history.is_empty():
		return
	if _history_pos == -1:
		_history_pos = history.size()
	_history_pos = clampi(_history_pos + direction, 0, history.size())
	_entry.text = "" if _history_pos == history.size() else history[_history_pos]
	_entry.caret_column = _entry.text.length()


# --- Вывод ---------------------------------------------------------------------

## Показать ответ терминала на команду.
func show_result(result: TermResult) -> void:
	if result.clear_screen:
		_output.clear()
	for line: String in result.lines:
		_print(line)
	if result.asks():
		_print(result.question)
	var request: Dictionary = result.request
	match str(request.get("type", "")):
		"progress":
			_print("[ %s: работает… ]" % str(request.get("title", "")))
		"puzzle":
			puzzle_requested.emit(request)
		"remote":
			remote_requested.emit(request)
	_refresh()
	result_shown.emit()


## Время прошло само: печатаем, что случилось с сеансом (если что-то), и двигаем полоску трейса.
func _on_ticked(result: TermResult) -> void:
	for line: String in result.lines:
		_print(line)
	_refresh()
	result_shown.emit()


func _print(text: String) -> void:
	_output.add_text(text + "\n")
	_scroll_to_end.call_deferred()


## Строка ввода всегда видна: после вывода прокручиваем к концу, когда раскладка пересчитана.
func _scroll_to_end() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


## Напечатать строки от себя (заставка, ошибки загрузки).
func print_lines(lines: PackedStringArray) -> void:
	for line: String in lines:
		_print(line)


func output_text() -> String:
	return _output.get_parsed_text()


## Приглашение и индикатор трейса после каждой команды.
func _refresh() -> void:
	_prompt.text = terminal.prompt()
	_entry.secret = terminal.login_pending()
	_refresh_trace()


func _refresh_trace() -> void:
	var row: Control = find_child("TraceRow", false, false) as Control
	var session: HackSession = terminal.session
	var tracing: bool = session != null and session.is_tracing()
	row.visible = tracing
	if tracing and session.trace_total() > 0:
		_trace.value = float(session.trace_left()) / float(session.trace_total())


func trace_visible() -> bool:
	return (find_child("TraceRow", false, false) as Control).visible


func trace_fraction() -> float:
	return _trace.value


func entry_text() -> String:
	return _entry.text


func entry() -> LineEdit:
	return _entry
