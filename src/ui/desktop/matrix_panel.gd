class_name MatrixPanel
extends VBoxContainer
## «Матрица»: собрать цепочку символов, выбирая ячейки по очереди из строки и столбца
## (docs/tech/puzzles-spec.md). Слой защиты = раунд: собрал цель — «Дальше» ведёт в следующий
## раунд с новой сеткой. Тупик (цель уже не собрать) кончает раунд сразу, не заставляя добивать
## цепочку. Показывает партию `MatrixPuzzle`: правил здесь нет.

signal finished(gained: int)

const COLOR_LEGAL: Color = Color(0.25, 0.6, 0.4)
const COLOR_IDLE: Color = Color(0.17, 0.19, 0.24)
const COLOR_USED: Color = Color(0.1, 0.11, 0.14)

var puzzle: MatrixPuzzle

var _round_label: Label
var _targets: Label
var _grid: GridContainer
var _chain: Label
var _note: Label
var _next_button: Button
var _done: bool = false
var _round_over: bool = false
var _gained: int = 0
var _offset: int = 0
var _rounds: int = 1
var _round: int = 0
var _next_round: Callable


## `rounds` — сколько раундов осталось сыграть, `next_round(index)` отдаёт головоломку раунда
## `index` (с 1), `layers_done` — сколько слоёв вскрыто раньше (только для подписи).
func setup(game: MatrixPuzzle, rounds: int = 1, next_round: Callable = Callable(), layers_done: int = 0) -> void:
	_rounds = maxi(rounds, 1)
	_next_round = next_round
	_offset = layers_done

	_round_label = Label.new()
	add_child(_round_label)
	_targets = Label.new()
	_targets.add_theme_font_override("font", PasswordPanel._mono())
	add_child(_targets)

	var center := CenterContainer.new()
	add_child(center)
	_grid = GridContainer.new()
	center.add_child(_grid)

	_chain = Label.new()
	_chain.add_theme_font_override("font", PasswordPanel._mono())
	_chain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_chain)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_note)

	_next_button = Button.new()
	_next_button.text = "Дальше"
	_next_button.visible = false
	_next_button.pressed.connect(_on_next)
	add_child(_next_button)
	_start_round(game)


func _start_round(game: MatrixPuzzle) -> void:
	puzzle = game
	_round_over = false
	_note.text = ""
	_next_button.visible = false
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_grid.columns = puzzle.size
	for cell: int in puzzle.size * puzzle.size:
		var button := Button.new()
		button.custom_minimum_size = Vector2(46, 34)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(pick.bind(cell))
		_grid.add_child(button)
	_refresh()


## Выбрать ячейку. Ход принимает `MatrixPuzzle`, он же решает, закончился ли раунд.
func pick(cell: int) -> Dictionary:
	if _done or _round_over:
		return {}
	var result: Dictionary = puzzle.pick(cell)
	if not bool(result["ok"]):
		_note.text = "Сюда нельзя: следующий ход — в той же строке или в том же столбце, что и прошлый."
	elif bool(result["finished"]):
		_refresh()
		_end_round()
		return result
	else:
		_note.text = ""
	_refresh()
	return result


func _end_round() -> void:
	_round_over = true
	for child: Node in _grid.get_children():
		(child as Button).disabled = true
	var won: bool = puzzle.layers() == puzzle.targets.size()
	_gained += puzzle.layers()
	var more: bool = won and _round + 1 < _rounds and _next_round.is_valid()
	if more:
		_note.text = "Слой вскрыт."
	elif won:
		_done = true
		_note.text = "Все слои вскрыты."
	else:
		_done = true
		_note.text = "Тупик: эту цепочку уже не собрать."
	_next_button.visible = true


func _on_next() -> void:
	if _done:
		finished.emit(_gained)
		return
	_round += 1
	_start_round(_next_round.call(_round) as MatrixPuzzle)


## Игрок закрыл окно или нажал «Выйти»: засчитываются уже вскрытые слои.
func abandon_gained() -> int:
	return _gained


func is_done() -> bool:
	return _done


func note_text() -> String:
	return _note.text


func _refresh() -> void:
	_round_label.text = "Слой %d из %d" % [_offset + _round + 1, _offset + _rounds]
	var legal: PackedInt32Array = puzzle.legal_moves() if not _round_over else PackedInt32Array()
	for cell: int in puzzle.size * puzzle.size:
		var button: Button = _grid.get_child(cell) as Button
		var used: bool = puzzle.is_used(cell)
		button.text = ("×" if used else puzzle.symbol_name(cell) + ("~" if puzzle.is_noisy(cell) else ""))
		button.disabled = used or _round_over
		var style := StyleBoxFlat.new()
		style.bg_color = COLOR_USED if used else (COLOR_LEGAL if legal.has(cell) else COLOR_IDLE)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("disabled", style)

	var lines: PackedStringArray = []
	var done: Array[bool] = puzzle.collected()
	for index: int in puzzle.targets.size():
		var names: PackedStringArray = []
		for value: int in puzzle.targets[index] as PackedInt32Array:
			names.append(MatrixPuzzle.SYMBOLS[value])
		lines.append("%s %s" % ["✓" if done[index] else "Цель:", " ".join(names)])
	_targets.text = "\n".join(lines)

	var slots: PackedStringArray = []
	for index: int in puzzle.capacity:
		if index < puzzle.buffer.size():
			var value: int = puzzle.buffer[index]
			slots.append("░░" if value == MatrixPuzzle.JUNK else MatrixPuzzle.SYMBOLS[value])
		else:
			slots.append("__")
	_chain.text = "Цепочка: %s\nХодов осталось: %d" % [" ".join(slots), puzzle.capacity - puzzle.buffer.size()]
