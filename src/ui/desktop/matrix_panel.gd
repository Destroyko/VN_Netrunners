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
const TINT_FAIL: Color = Color(1.0, 0.4, 0.4)
const TINT_WIN: Color = Color(0.45, 1.0, 0.55)
const DEFAULT_TRIES: int = 3
## Базовый размер шрифта 16; цель крупнее на ~25%.
const TARGET_FONT_SIZE: int = 20
const COLOR_TARGET_DONE: String = "#5fd27a"
const COLOR_TARGET_TODO: String = "#c8ccd6"

## Выключатель анимаций: тесты гоняют партию мгновенно.
static var animate: bool = true

var puzzle: MatrixPuzzle

var _round_label: Label
var _targets: RichTextLabel
var _grid: GridContainer
var _note: Label
var _next_button: Button
var _done: bool = false
var _round_over: bool = false
var _gained: int = 0
var _offset: int = 0
var _rounds: int = 1
var _round: int = 0
var _next_round: Callable
var _tries_left: int = DEFAULT_TRIES
var _tries_total: int = DEFAULT_TRIES
var _retries_used: int = 0
## Идёт анимация перехода: ходы на это время закрыты.
var _busy: bool = false


## `rounds` — сколько раундов осталось сыграть, `next_round(index)` отдаёт головоломку раунда
## `index` (с 1), `layers_done` — сколько слоёв вскрыто раньше (только для подписи).
func setup(game: MatrixPuzzle, rounds: int = 1, next_round: Callable = Callable(), layers_done: int = 0) -> void:
	_rounds = maxi(rounds, 1)
	_next_round = next_round
	_offset = layers_done
	_tries_total = int(PuzzleLevels.section("matrix").get("tries", DEFAULT_TRIES))
	_tries_left = _tries_total

	_round_label = Label.new()
	add_child(_round_label)
	# Цель — крупно и по центру над сеткой; набранная часть окрашивается по ходу выбора.
	_targets = RichTextLabel.new()
	_targets.bbcode_enabled = true
	_targets.fit_content = true
	_targets.scroll_active = false
	_targets.add_theme_font_override("normal_font", PasswordPanel._mono())
	_targets.add_theme_font_size_override("normal_font_size", TARGET_FONT_SIZE)
	add_child(_targets)

	var center := CenterContainer.new()
	add_child(center)
	_grid = GridContainer.new()
	center.add_child(_grid)

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
	if _done or _round_over or _busy:
		return {}
	var result: Dictionary = puzzle.pick(cell)
	SessionLog.write("puzzle", "матрица: клетка %d → %s" % [cell, "ход" if bool(result["ok"]) else "нельзя"])
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
	if won:
		_gained += puzzle.layers()
		if _round + 1 < _rounds and _next_round.is_valid():
			# Слой вскрыт: сетка зеленеет и переворачивается к следующему слою.
			_round += 1
			var upcoming: MatrixPuzzle = _next_round.call(_round + _retries_used * RETRY_STRIDE) as MatrixPuzzle
			_transition(TINT_WIN, false, _start_round.bind(upcoming))
			return
		_done = true
		_note.text = "Все слои вскрыты."
		_grid.modulate = TINT_WIN
		_next_button.visible = true
		return
	# Тупик: тряска и красный цвет, затем новая сетка этого же слоя, пока есть попытки.
	_tries_left -= 1
	if _tries_left > 0 and _next_round.is_valid():
		_retries_used += 1
		var retry: MatrixPuzzle = _next_round.call(_round + _retries_used * RETRY_STRIDE) as MatrixPuzzle
		_transition(TINT_FAIL, true, _start_round.bind(retry))
		return
	_gained += puzzle.layers()
	_done = true
	_note.text = "Тупик. Попытки кончились."
	_grid.modulate = TINT_FAIL
	_next_button.visible = true


## Раунд раундов: чтобы повтор слоя не совпал с сеткой другого слоя.
const RETRY_STRIDE: int = 1000


## Переход между сетками: подсветка цветом (и тряска), затем плитки переворачиваются
## по горизонтали, и на обороте уже новая сетка.
func _transition(tint: Color, shake: bool, swap: Callable) -> void:
	if not animate:
		swap.call()
		return
	_busy = true
	_grid.modulate = tint
	var base: float = _grid.position.x
	var tween: Tween = create_tween()
	if shake:
		for step: int in 6:
			tween.tween_property(_grid, "position:x", base + (10.0 if step % 2 == 0 else -10.0), 0.05)
		tween.tween_property(_grid, "position:x", base, 0.06)
	tween.tween_interval(0.12)
	tween.tween_callback(_flip_out.bind(swap))


func _flip_out(swap: Callable) -> void:
	var tween: Tween = create_tween().set_parallel(true)
	for child: Node in _grid.get_children():
		var tile: Button = child as Button
		tile.pivot_offset = tile.size / 2.0
		tween.tween_property(tile, "scale:x", 0.0, 0.12)
	tween.chain().tween_callback(func() -> void:
		swap.call()
		_grid.modulate = Color.WHITE
		_flip_in())


func _flip_in() -> void:
	var tween: Tween = create_tween().set_parallel(true)
	for child: Node in _grid.get_children():
		var tile: Button = child as Button
		tile.pivot_offset = tile.size / 2.0
		tile.scale = Vector2(0.0, 1.0)
		tween.tween_property(tile, "scale:x", 1.0, 0.12)
	tween.chain().tween_callback(func() -> void: _busy = false)


func _on_next() -> void:
	finished.emit(_gained)


## Игрок закрыл окно или нажал «Выйти»: засчитываются уже вскрытые слои.
func abandon_gained() -> int:
	return _gained


func is_done() -> bool:
	return _done


func note_text() -> String:
	return _note.text


func _refresh() -> void:
	_round_label.text = "Слой %d из %d · попыток: %d из %d" % [_offset + _round + 1, _offset + _rounds, _tries_left, _tries_total]
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
	for index: int in puzzle.targets.size():
		var target: PackedInt32Array = puzzle.targets[index] as PackedInt32Array
		var matched: int = _matched_prefix(target)
		var names: PackedStringArray = []
		for position: int in target.size():
			var color: String = COLOR_TARGET_DONE if position < matched else COLOR_TARGET_TODO
			names.append("[color=%s]%s[/color]" % [color, MatrixPuzzle.SYMBOLS[target[position]]])
		lines.append("[center]%s[/center]" % "  ".join(names))
	_targets.text = "
".join(lines)


## Сколько первых символов цели уже набрано: окрашиваются по ходу выбора.
func _matched_prefix(target: PackedInt32Array) -> int:
	if puzzle.layers() > 0 and puzzle.contains_run(puzzle.buffer, target):
		return target.size()
	var count: int = 0
	while count < target.size() and count < puzzle.buffer.size() and puzzle.buffer[count] == target[count]:
		count += 1
	return count
