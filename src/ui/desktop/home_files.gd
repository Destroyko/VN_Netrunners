class_name HomeFiles
extends VBoxContainer
## Окно «Файлы» — проводник своего ПК (docs/tech/desktop-layout.md, «Файлы и рабочий стол»).
## Тот же `FileBrowser`, что в удалённом сеансе, но команды идут на свой ПК (`execute_local`),
## даже если открыт сеанс с чужим узлом. Права, логи и вопросы «y/n» — как в консоли.
##
## Рабочий стол — папка `/home/desktop`, скачанное — `/home/downloads` («Загрузки»).

## Что-то на своём ПК поменялось (удалил, переименовал, переместил): стол перерисует значки.
signal changed
## Открыли текстовый файл: стол показывает «Блокнот» (тот же, что у `edit`).
signal edit_requested(request: Dictionary)

var browser: FileBrowser
var _terminal: Terminal


func setup(terminal: Terminal, start_path: String = Terminal.HOME_DIR) -> void:
	name = "HomeFiles"
	_terminal = terminal
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser = FileBrowser.new()
	browser.path = start_path
	browser.run_command = run_local
	browser.confirm_delete = confirm_delete
	browser.cat_on_open = false
	browser.file_opened.connect(_open_file)
	browser.setup(terminal, Network.HOME_ID)
	add_child(browser)


## Показать папку (например, клик по файлу на рабочем столе открывает стол).
func open_path(path: String) -> void:
	browser.path = path
	browser.refresh()


## Файл своего ПК открывается в «Блокноте» той же командой `edit`, что и в консоли.
func _open_file(path: String) -> void:
	var result: TermResult = _terminal.execute_local("edit \"%s\"" % path)
	if str(result.request.get("type", "")) == "edit":
		edit_requested.emit(result.request)


func refresh() -> void:
	browser.refresh()


## Команда на своём ПК. Вопрос «y/n» (системный файл, замена) — окном подтверждения окна,
## отдельно от вопроса консоли (ISS-004).
func run_local(line: String) -> String:
	var result: TermResult = _terminal.execute_local(line)
	if not _terminal.local_question().is_empty():
		_ask(_terminal.local_question(), func(yes: bool) -> void: _finish(_terminal.answer_local(yes)))
		return ""
	changed.emit()
	return _last_line(result)


## «Удалить» в меню: окно спрашивает само (ISS-007): «Вы действительно хотите удалить файл …?»,
## для системного — «…системный файл …?». «Да» удаляет без второго вопроса.
func confirm_delete(path: String) -> void:
	var kind: String = "системный файл" if _terminal.home_fs().is_system(path) else "файл"
	_ask("Вы действительно хотите удалить %s %s?" % [kind, FsPath.name_of(path)], func(yes: bool) -> void:
		if not yes:
			return
		_terminal.execute_local("rm \"%s\"" % path)
		if not _terminal.local_question().is_empty():
			_finish(_terminal.answer_local(true))
		else:
			_finish(TermResult.new()))


func _ask(question: String, answered: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.name = "HomeConfirm"
	dialog.dialog_text = question
	dialog.ok_button_text = "Да"
	dialog.cancel_button_text = "Нет"
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		answered.call(true))
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
		answered.call(false))
	add_child(dialog)
	dialog.popup_centered()


func _finish(result: TermResult) -> void:
	browser.set_status(_last_line(result))
	browser.refresh()
	changed.emit()


static func _last_line(result: TermResult) -> String:
	return result.lines[result.lines.size() - 1] if not result.lines.is_empty() else ""
