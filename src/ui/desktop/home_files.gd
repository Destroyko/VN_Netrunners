class_name HomeFiles
extends VBoxContainer
## Окно «Файлы» — проводник своего ПК (docs/tech/desktop-layout.md, «Файлы и рабочий стол»).
## Тот же `FileBrowser`, что в удалённом сеансе, но команды идут на свой ПК (`execute_local`),
## даже если открыт сеанс с чужим узлом. Права, логи и вопросы «y/n» — как в консоли.
##
## Рабочий стол — папка `/home/desktop`, скачанное — `/home/downloads` («Загрузки»).

## Что-то на своём ПК поменялось (удалил, переименовал, переместил): стол перерисует значки.
signal changed

var browser: FileBrowser
var _terminal: Terminal


func setup(terminal: Terminal, start_path: String = Terminal.HOME_DIR) -> void:
	name = "HomeFiles"
	_terminal = terminal
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser = FileBrowser.new()
	browser.path = start_path
	browser.run_command = run_local
	browser.setup(terminal, Network.HOME_ID)
	add_child(browser)


## Показать папку (например, клик по файлу на рабочем столе открывает стол).
func open_path(path: String) -> void:
	browser.path = path
	browser.refresh()


func refresh() -> void:
	browser.refresh()


## Команда на своём ПК. Вопрос «y/n» (системный файл, замена) — окном подтверждения.
func run_local(line: String) -> String:
	var result: TermResult = _terminal.execute_local(line)
	if _terminal.has_question():
		var dialog := ConfirmationDialog.new()
		dialog.name = "HomeConfirm"
		dialog.dialog_text = _terminal.last_question()
		dialog.ok_button_text = "Да"
		dialog.cancel_button_text = "Нет"
		dialog.confirmed.connect(func() -> void: _answer(dialog, "y"))
		dialog.canceled.connect(func() -> void: _answer(dialog, "n"))
		add_child(dialog)
		dialog.popup_centered()
		return ""
	changed.emit()
	return result.lines[result.lines.size() - 1] if not result.lines.is_empty() else ""


func _answer(dialog: ConfirmationDialog, answer: String) -> void:
	_terminal.execute_local(answer)
	dialog.queue_free()
	browser.refresh()
	changed.emit()
