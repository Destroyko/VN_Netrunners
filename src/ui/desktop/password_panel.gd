class_name PasswordPanel
extends VBoxContainer
## «Пароль»: угадай слово по меткам, как в Wordle (docs/tech/puzzles-spec.md).
## Показывает партию `PasswordPuzzle` и передаёт слова в неё: правил здесь нет.

signal finished(gained: int)

const COLOR_EXACT: String = "#5fd27a"
const COLOR_PRESENT: String = "#e8c547"
const COLOR_ABSENT: String = "#7b8190"

var puzzle: PasswordPuzzle

var _board: RichTextLabel
var _note: Label
var _entry: LineEdit
var _done: bool = false


func setup(game: PasswordPuzzle) -> void:
	puzzle = game
	var title := Label.new()
	title.text = "Взлом: угадай пароль (%d букв)" % puzzle.length
	add_child(title)

	_board = RichTextLabel.new()
	_board.bbcode_enabled = true
	_board.fit_content = true
	_board.custom_minimum_size = Vector2(360, 160)
	_board.add_theme_font_override("normal_font", _mono())
	add_child(_board)

	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_note)

	_entry = LineEdit.new()
	_entry.placeholder_text = "слово из %d букв" % puzzle.length
	_entry.max_length = puzzle.length
	_entry.text_submitted.connect(_on_submitted)
	add_child(_entry)
	_refresh()
	_entry.ready.connect(_entry.grab_focus)


static func _mono() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	return font


func submit(text: String) -> Dictionary:
	if _done:
		return {}
	var result: Dictionary = puzzle.guess(text)
	if not bool(result["valid"]):
		_note.text = _reason_text(str(result["reason"]))
		_refresh()
		return result
	_refresh()
	if bool(result["solved"]):
		_finish(1, "Пароль подошёл.")
	elif bool(result["failed"]):
		_finish(0, "Попытки кончились. Было слово: %s." % puzzle.word)
	else:
		_note.text = "Осталось попыток: %d" % puzzle.attempts_left()
	return result


func _on_submitted(text: String) -> void:
	_entry.clear()
	submit(text)


func _finish(gained: int, message: String) -> void:
	_done = true
	_entry.editable = false
	_note.text = message
	var button := Button.new()
	button.text = "Дальше"
	button.pressed.connect(func() -> void: finished.emit(gained))
	add_child(button)


func is_done() -> bool:
	return _done


func note_text() -> String:
	return _note.text


## Подсказка без траты попытки: что за ввод не принят.
static func _reason_text(reason: String) -> String:
	match reason:
		"length":
			return "Нужно слово ровно нужной длины."
		"unknown":
			return "Такого слова в словаре нет. Попытка не потрачена."
	return "Ввод не принят."


func _refresh() -> void:
	var lines: PackedStringArray = []
	for entry: Dictionary in puzzle.history:
		lines.append(_row(str(entry["word"]), entry["marks"] as Array))
	for _i: int in puzzle.attempts_left():
		lines.append(_pattern_row())
	_board.text = "\n".join(lines)


## Строка с метками: цвет — как в Wordle, плюс знак, чтобы не полагаться только на цвет.
static func _row(word: String, marks: Array) -> String:
	var text: String = ""
	for index: int in word.length():
		var mark: int = int(marks[index])
		var color: String = COLOR_ABSENT
		var sign: String = " "
		if mark == PasswordPuzzle.MARK_EXACT:
			color = COLOR_EXACT
			sign = "="
		elif mark == PasswordPuzzle.MARK_PRESENT:
			color = COLOR_PRESENT
			sign = "~"
		text += "[color=%s]%s%s[/color] " % [color, word[index].to_upper(), sign]
	return text


## Пустая попытка с уже открытыми буквами: они помогают, но игрок видит, что их дали.
func _pattern_row() -> String:
	var text: String = ""
	for index: int in puzzle.length:
		var letter: String = "_"
		if puzzle.known.has(index):
			letter = str(puzzle.known[index]).to_upper()
		text += "[color=%s]%s[/color]  " % [COLOR_EXACT if letter != "_" else COLOR_ABSENT, letter]
	return text
