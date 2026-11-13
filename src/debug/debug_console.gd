extends CanvasLayer
## Интерфейс отладочной консоли: поле ввода, журнал, история команд.
## Открывается и закрывается клавишей F1. Только в отладочной сборке.
##
## Логики игры здесь нет: строка уходит в DebugCommands, ответ печатается в журнал.

const TOGGLE_KEY: Key = KEY_F1
const HISTORY_LIMIT: int = 50

@onready var _panel: PanelContainer = $Panel
@onready var _log: RichTextLabel = $Panel/Rows/Log
@onready var _entry: LineEdit = $Panel/Rows/Input

var _history: PackedStringArray = []
var _history_pos: int = -1


func _ready() -> void:
	# Консоль работает и когда игра на паузе.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.visible = false
	_entry.text_submitted.connect(_on_submitted)
	_print_line("Консоль разработчика. F1 — закрыть, help — список команд.")


func _input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == TOGGLE_KEY:
		_toggle()
		get_viewport().set_input_as_handled()
		return

	if not _panel.visible:
		return

	# Стрелки вверх-вниз — история команд.
	if key_event.keycode == KEY_UP:
		_step_history(-1)
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_DOWN:
		_step_history(1)
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_entry.grab_focus()
	else:
		_entry.release_focus()


func _on_submitted(text: String) -> void:
	_entry.clear()
	if text.strip_edges().is_empty():
		return
	_remember(text)
	_print_line("> " + text)
	var output: String = DebugCommands.run(text)
	if not output.is_empty():
		_print_line(output)


func _print_line(text: String) -> void:
	_log.append_text(text + "\n")


func _remember(text: String) -> void:
	_history.append(text)
	if _history.size() > HISTORY_LIMIT:
		_history = _history.slice(_history.size() - HISTORY_LIMIT)
	_history_pos = _history.size()


func _step_history(delta: int) -> void:
	if _history.is_empty():
		return
	_history_pos = clampi(_history_pos + delta, 0, _history.size())
	if _history_pos == _history.size():
		_entry.clear()
	else:
		_entry.text = _history[_history_pos]
		_entry.caret_column = _entry.text.length()
