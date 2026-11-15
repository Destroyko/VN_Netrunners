class_name MatrixPanel
extends VBoxContainer
## «Матрица»: собрать последовательности в буфер, выбирая ячейки по очереди из строки и
## столбца (docs/tech/puzzles-spec.md). Показывает партию `MatrixPuzzle`: правил здесь нет.

signal finished(gained: int)

const COLOR_LEGAL: Color = Color(0.25, 0.6, 0.4)
const COLOR_IDLE: Color = Color(0.17, 0.19, 0.24)
const COLOR_USED: Color = Color(0.1, 0.11, 0.14)

var puzzle: MatrixPuzzle

var _grid: GridContainer
var _buffer: Label
var _targets: Label
var _note: Label
var _done: bool = false


func setup(game: MatrixPuzzle) -> void:
	puzzle = game
	var title := Label.new()
	title.text = "Взлом: собери последовательности"
	add_child(title)

	_targets = Label.new()
	_targets.add_theme_font_override("font", PasswordPanel._mono())
	add_child(_targets)

	_grid = GridContainer.new()
	_grid.columns = puzzle.size
	add_child(_grid)
	for cell: int in puzzle.size * puzzle.size:
		var button := Button.new()
		button.custom_minimum_size = Vector2(46, 34)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(pick.bind(cell))
		_grid.add_child(button)

	_buffer = Label.new()
	_buffer.add_theme_font_override("font", PasswordPanel._mono())
	add_child(_buffer)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_note)

	var give_up := Button.new()
	give_up.name = "GiveUp"
	give_up.text = "Сдаться"
	give_up.pressed.connect(_give_up)
	add_child(give_up)
	_refresh()


## Выбрать ячейку. Ход принимает `MatrixPuzzle`, он же решает, закончилась ли партия.
func pick(cell: int) -> Dictionary:
	if _done:
		return {}
	var result: Dictionary = puzzle.pick(cell)
	if not bool(result["ok"]):
		_note.text = "Сюда нельзя: следующий ход — в той же строке или в том же столбце, что и прошлый."
	elif bool(result["finished"]):
		_refresh()
		_finish(int(result["layers"]))
		return result
	else:
		_note.text = ""
	_refresh()
	return result


func _give_up() -> void:
	if not _done:
		_finish(puzzle.layers())


func _finish(layers: int) -> void:
	_done = true
	for child: Node in _grid.get_children():
		(child as Button).disabled = true
	_note.text = "Собрано последовательностей: %d из %d." % [layers, puzzle.targets.size()]
	var give_up: Node = find_child("GiveUp", false, false)
	if give_up != null:
		give_up.queue_free()
	var button := Button.new()
	button.text = "Дальше"
	button.pressed.connect(func() -> void: finished.emit(layers))
	add_child(button)


## Игрок закрыл окно или нажал «Выйти»: засчитывается то, что успел собрать.
func abandon_gained() -> int:
	return puzzle.layers()


func is_done() -> bool:
	return _done


func note_text() -> String:
	return _note.text


func _refresh() -> void:
	var legal: PackedInt32Array = puzzle.legal_moves() if not _done else PackedInt32Array()
	for cell: int in puzzle.size * puzzle.size:
		var button: Button = _grid.get_child(cell) as Button
		var used: bool = puzzle.is_used(cell)
		button.text = ("×" if used else puzzle.symbol_name(cell) + ("~" if puzzle.is_noisy(cell) else ""))
		button.disabled = used or _done
		var style := StyleBoxFlat.new()
		style.bg_color = COLOR_USED if used else (COLOR_LEGAL if legal.has(cell) else COLOR_IDLE)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("disabled", style)
	var slots: PackedStringArray = []
	for index: int in puzzle.capacity:
		if index < puzzle.buffer.size():
			var value: int = puzzle.buffer[index]
			slots.append("░░" if value == MatrixPuzzle.JUNK else MatrixPuzzle.SYMBOLS[value])
		else:
			slots.append("__")
	_buffer.text = "Буфер: " + " ".join(slots)

	var done: Array[bool] = puzzle.collected()
	var lines: PackedStringArray = []
	for index: int in puzzle.targets.size():
		var names: PackedStringArray = []
		for value: int in puzzle.targets[index] as PackedInt32Array:
			names.append(MatrixPuzzle.SYMBOLS[value])
		lines.append("%s %s" % ["✓" if done[index] else "·", " ".join(names)])
	_targets.text = "Цели:\n" + "\n".join(lines)
