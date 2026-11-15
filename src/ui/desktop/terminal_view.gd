class_name TerminalView
extends HSplitContainer
## Окно терминала: панели файлов и программ слева, вывод, строка ввода и индикатор трейса справа
## (docs/tech/desktop-layout.md, «Окно терминала»). Только показывает: команды выполняет `Terminal`.
##
## Клик по файлу или программе вставляет имя в строку ввода — «клик как альтернатива набору»
## (hacking-loop.md). Головоломка открывается отдельным окном: вид отдаёт запрос через
## `puzzle_requested` и принимает итог через `show_result`.

signal puzzle_requested(request: Dictionary)
## Команда выполнена: карта сети и режим стола перечитывают состояние.
signal result_shown

var terminal: Terminal

var _output: RichTextLabel
var _entry: LineEdit
var _prompt: Label
var _trace: ProgressBar
var _trace_label: Label
var _files: ItemList
var _programs: ItemList
var _history_pos: int = -1


func setup(shared_terminal: Terminal) -> void:
	terminal = shared_terminal
	_build()
	_print("Терминал. help — список команд.")
	_refresh()


func _build() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_offset = 150

	var side := VSplitContainer.new()
	side.custom_minimum_size = Vector2(130, 0)
	add_child(side)
	_files = _make_panel(side, "Файлы")
	_programs = _make_panel(side, "Программы")
	_files.item_selected.connect(_on_file_selected)
	_programs.item_selected.connect(_on_program_selected)

	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(main)

	var trace_row := HBoxContainer.new()
	main.add_child(trace_row)
	_trace_label = Label.new()
	_trace_label.text = "трейс"
	trace_row.add_child(_trace_label)
	_trace = ProgressBar.new()
	_trace.show_percentage = false
	_trace.max_value = 1.0
	_trace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trace.custom_minimum_size = Vector2(0, 14)
	trace_row.add_child(_trace)
	trace_row.visible = false
	trace_row.name = "TraceRow"

	_output = RichTextLabel.new()
	_output.scroll_following = true
	_output.selection_enabled = true
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.add_theme_font_override("normal_font", _mono_font())
	main.add_child(_output)

	var input_row := HBoxContainer.new()
	main.add_child(input_row)
	_prompt = Label.new()
	_prompt.add_theme_font_override("font", _mono_font())
	input_row.add_child(_prompt)
	_entry = LineEdit.new()
	_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry.add_theme_font_override("font", _mono_font())
	_entry.text_submitted.connect(_on_submitted)
	_entry.gui_input.connect(_on_entry_input)
	input_row.add_child(_entry)


func _make_panel(parent: Control, title: String) -> ItemList:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = title
	box.add_child(label)
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.allow_reselect = true
	box.add_child(list)
	parent.add_child(box)
	return list


static func _mono_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	return font


func focus_entry() -> void:
	_entry.grab_focus()


# --- Ввод ----------------------------------------------------------------------

func submit(line: String) -> void:
	_history_pos = -1
	_print(_prompt.text + line)
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
	_refresh()
	result_shown.emit()


func _print(text: String) -> void:
	_output.add_text(text + "\n")


## Напечатать строки от себя (приветствие, ошибки загрузки).
func print_lines(lines: PackedStringArray) -> void:
	for line: String in lines:
		_print(line)


func output_text() -> String:
	return _output.get_parsed_text()


## Приглашение, панели и индикатор трейса после каждой команды.
func _refresh() -> void:
	_prompt.text = terminal.prompt()
	_refresh_files()
	_refresh_programs()
	_refresh_trace()


func _refresh_files() -> void:
	_files.clear()
	for entry: Dictionary in terminal.fs().list(terminal.cwd(), terminal.admin()):
		var name: String = str(entry["name"]) + ("/" if bool(entry["is_dir"]) else "")
		if bool(entry.get("locked", false)):
			name += " 🔒"
		var index: int = _files.add_item(name)
		_files.set_item_metadata(index, entry)


func _refresh_programs() -> void:
	_programs.clear()
	for id: String in Programs.installed():
		var index: int = _programs.add_item(id)
		_programs.set_item_tooltip(index, Programs.about(id))
	if _programs.item_count == 0:
		_programs.add_item("(нет)", null, false)


func _refresh_trace() -> void:
	var row: Control = find_child("TraceRow", true, false) as Control
	var session: HackSession = terminal.session
	var tracing: bool = session != null and session.is_tracing()
	row.visible = tracing
	if tracing and session.trace_total() > 0:
		_trace.value = float(session.trace_left()) / float(session.trace_total())


func trace_visible() -> bool:
	return (find_child("TraceRow", true, false) as Control).visible


func trace_fraction() -> float:
	return _trace.value


func _on_file_selected(index: int) -> void:
	var entry: Dictionary = _files.get_item_metadata(index) as Dictionary
	_insert(str(entry["name"]))


func _on_program_selected(index: int) -> void:
	if _programs.is_item_selectable(index):
		_insert(_programs.get_item_text(index))


## Вставить имя в строку ввода после уже набранного.
func _insert(name: String) -> void:
	var text: String = _entry.text
	if not text.is_empty() and not text.ends_with(" "):
		text += " "
	_entry.text = text + name
	_entry.caret_column = _entry.text.length()
	_entry.grab_focus()


func entry_text() -> String:
	return _entry.text
