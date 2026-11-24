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

## Размер шрифта консоли и полупериод мигания курсора.
const FONT_SIZE: int = 15
const BLINK_SECONDS: float = 0.53

var terminal: Terminal

var _scroll: ScrollContainer
var _output: RichTextLabel
## Строка ввода — такой же RichTextLabel, как вывод: тот же шрифт и та же высота строки, поэтому
## приглашение стоит ровно под выводом. Клавиши принимает невидимый `_entry`.
var _line: RichTextLabel
var _entry: LineEdit
## Текущее приглашение (простым текстом — для эха команды и журнала).
var _prompt_text: String = ""
var _trace: ProgressBar
var _history_pos: int = -1
var _paint: TerminalHighlight
var _has_lines: bool = false
var _cursor_on: bool = true
var _blink_left: float = BLINK_SECONDS
var _last_caret: int = -1
static var _font: Font


func setup(shared_terminal: Terminal) -> void:
	terminal = shared_terminal
	_build()
	terminal.ticked.connect(_on_ticked)
	print_lines(terminal.banner())
	_refresh()


func _build() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)
	_paint = TerminalHighlight.new(_host_theme())

	var trace_row := HBoxContainer.new()
	trace_row.name = "TraceRow"
	trace_row.visible = false
	add_child(trace_row)
	# Трейс — строка тревоги над экраном: подпись и полоса цвета предупреждения.
	var trace_back := StyleBoxFlat.new()
	trace_back.bg_color = _paint.colors["background"] as Color
	trace_row.add_theme_constant_override("separation", 8)
	var trace_label := Label.new()
	trace_label.text = " ТРЕЙС "
	trace_label.add_theme_font_override("font", _mono_font())
	trace_label.add_theme_color_override("font_color", _paint.colors["warn"] as Color)
	trace_row.add_child(trace_label)
	_trace = ProgressBar.new()
	_trace.show_percentage = false
	_trace.max_value = 1.0
	_trace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trace.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_trace.custom_minimum_size = Vector2(0, 6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = _paint.colors["warn"] as Color
	_trace.add_theme_stylebox_override("fill", fill)
	_trace.add_theme_stylebox_override("background", trace_back)
	trace_row.add_child(_trace)

	# Экран консоли: тёмный фон, вывод и строка ввода в одном прокручиваемом столбце.
	var screen := PanelContainer.new()
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = _paint.colors["background"] as Color
	style.set_content_margin_all(12)
	# Окно терминала без полей: нижние углы экрана повторяют скругление рамки окна.
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
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

	_output = _console_label("Output")
	_output.selection_enabled = true
	column.add_child(_output)
	_line = _console_label("Line")
	_line.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(_line)

	# Клавиши принимает обычное поле ввода, но его не видно: на экране — строка `_line` со своим
	# курсором. Поле живёт внутри строки размером в точку, чтобы не сдвигать раскладку.
	_entry = LineEdit.new()
	_entry.name = "Entry"
	_entry.modulate.a = 0.0
	_entry.size = Vector2(1, 1)
	_entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entry.add_theme_font_override("font", _mono_font())
	# Строка ввода — часть экрана, а не поле формы: без рамки, меню по правой кнопке и эмодзи.
	_entry.flat = true
	_entry.context_menu_enabled = false
	if "emoji_menu_enabled" in _entry:
		_entry.set("emoji_menu_enabled", false)
	_entry.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_entry.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# После Enter строка остаётся в редактировании (в Godot 4.4+ по умолчанию она его покидает) —
	# иначе после каждой команды приходилось бы снова щёлкать по полю.
	if "keep_editing_on_text_submit" in _entry:
		_entry.set("keep_editing_on_text_submit", true)
	_entry.text_submitted.connect(_on_submitted)
	_entry.gui_input.connect(_on_entry_input)
	_entry.text_changed.connect(func(_text: String) -> void: _wake_cursor())
	_entry.focus_entered.connect(_wake_cursor)
	_entry.focus_exited.connect(_redraw_line)
	_line.add_child(_entry)


## Текст консоли: моноширинный шрифт, без полей и межстрочного зазора, высота по содержимому.
func _console_label(label_name: String) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.name = label_name
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("normal_font", _mono_font())
	label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	label.add_theme_color_override("default_color", _paint.colors["text"] as Color)
	label.add_theme_constant_override("line_separation", 0)
	label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	label.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	label.add_theme_color_override("selection_color", Color(_paint.colors["path"] as Color, 0.35))
	return label


static func _mono_font() -> Font:
	if _font == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Courier New", "monospace"])
		_font = font
	return _font


## Тема окна, в котором терминал (своё окно — тема ПК героя).
func _host_theme() -> String:
	var node: Node = get_parent()
	while node != null:
		if node is DesktopWindow:
			return (node as DesktopWindow).theme_id
		node = node.get_parent()
	return GameTheme.pc_theme_id()


# --- Курсор ---------------------------------------------------------------------

## Курсор мигает, пока строка в фокусе; набрал или сдвинул — снова горит (как в настоящей консоли).
func _process(delta: float) -> void:
	if _entry == null:
		return
	if _entry.caret_column != _last_caret:
		_last_caret = _entry.caret_column
		_wake_cursor()
		return
	if not _entry.has_focus():
		return
	_blink_left -= delta
	if _blink_left <= 0.0:
		_blink_left = BLINK_SECONDS
		_cursor_on = not _cursor_on
		_redraw_line()


func _wake_cursor() -> void:
	_cursor_on = true
	_blink_left = BLINK_SECONDS
	_redraw_line()


## Строка ввода: приглашение, набранное с подсветкой и блочный курсор на месте каретки. Пароль не
## печатается вовсе — видно только курсор. Без фокуса курсор — пустая рамка.
func _redraw_line() -> void:
	if _line == null:
		return
	var typed: String = "" if _entry.secret else _entry.text
	var caret: int = clampi(_entry.caret_column, 0, typed.length())
	var before: String = typed.substr(0, caret)
	var under: String = typed.substr(caret, 1)
	var after: String = typed.substr(caret + 1)
	var cursor: String = ""
	var bg: String = (_paint.colors["background"] as Color).to_html(false)
	var fg: String = (_paint.colors["cursor"] as Color).to_html(false)
	var glyph: String = TerminalHighlight.escape(under if not under.is_empty() else " ")
	if _entry.has_focus() and _cursor_on:
		cursor = "[bgcolor=#%s][color=#%s]%s[/color][/bgcolor]" % [fg, bg, glyph]
	elif _entry.has_focus():
		cursor = _paint.command(under) if not under.is_empty() else " "
	else:
		cursor = "[u]%s[/u]" % glyph
	# Подсветка команды считается по всей строке, а курсор вставляется между её частями.
	var head: String = _paint.command(before) if not before.is_empty() else ""
	var tail: String = TerminalHighlight.escape(after)
	_line.text = _paint.prompt(_prompt_text) + head + cursor + tail


func focus_entry() -> void:
	_entry.grab_focus()


## Клик в любом месте экрана ставит курсор в строку ввода, как в настоящей консоли.
func _on_screen_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_entry.grab_focus()


# --- Ввод ----------------------------------------------------------------------

## Выполнить строку как введённую с клавиатуры. Итог возвращается — его показывает и проводник.
func submit(line: String) -> TermResult:
	_history_pos = -1
	# Пароль не печатается и не пишется в журнал — как в настоящей консоли.
	var shown: String = "" if terminal.login_pending() else line
	_print_bbcode(_paint.prompt(_prompt_text) + _paint.command(shown))
	SessionLog.write("term", _prompt_text + (shown if not terminal.login_pending() else "***"))
	var result: TermResult = terminal.execute(line)
	show_result(result)
	return result


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
		_print_bbcode(_paint.prompt(_prompt_text) + _paint.command(_entry.text))
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
		_has_lines = false
	# Вопрос («заменить? (y/n)») уже среди строк ответа: второй раз не печатаем.
	for line: String in result.lines:
		_print(line)
	var request: Dictionary = result.request
	match str(request.get("type", "")):
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


## Строка ответа: цвет по смыслу (ошибка, успех, предупреждение).
func _print(text: String) -> void:
	_print_bbcode(_paint.output(text))


## Перевод строки ставится перед новой строкой, а не после: под выводом нет пустой строки, и
## приглашение стоит сразу под последней строкой (баг F9 24.11.2026: приглашение «съезжало»).
func _print_bbcode(bbcode: String) -> void:
	_output.append_text(("\n" if _has_lines else "") + bbcode)
	_has_lines = true
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
	_prompt_text = terminal.prompt()
	_entry.secret = terminal.login_pending()
	_redraw_line()
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


## Строка ввода так, как её видит игрок (приглашение и набранное), без тегов.
func line_text() -> String:
	return _line.get_parsed_text()
