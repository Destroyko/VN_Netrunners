class_name DumpPanel
extends VBoxContainer
## «Перехват в дампе»: сверху куски хэша (пойманные — зелёные, текущий — крупно), ниже ползёт
## дамп памяти. Клик по клетке нужного куска ловит его, клик мимо — красная тряска и сброс
## собранного. Правил здесь нет: всё решает `DumpPuzzle`, окно только показывает и двигает экран.

signal finished(gained: int)

const COLOR_CAUGHT: String = "#5fd27a"
const COLOR_CURRENT: String = "#f0f2f5"
const COLOR_LATER: String = "#5b606c"
const CELL_IDLE: Color = Color(0.1, 0.12, 0.15)
const TEXT_DUMP: Color = Color(0.62, 0.68, 0.72)
const TARGET_FONT_SIZE: int = 22

## Выключатель анимаций: тесты гоняют партию мгновенно.
static var animate: bool = true

var puzzle: DumpPuzzle

var _pieces: RichTextLabel
var _grid: GridContainer
var _note: Label
var _next_button: Button
var _scroll_seconds: float = 1.0
var _elapsed: float = 0.0
var _done: bool = false


func setup(game: DumpPuzzle) -> void:
	puzzle = game
	_scroll_seconds = maxf(0.2, float(PuzzleLevels.dump(puzzle.level).get("scroll_seconds", 1.0)))

	_pieces = RichTextLabel.new()
	_pieces.bbcode_enabled = true
	_pieces.fit_content = true
	_pieces.scroll_active = false
	_pieces.add_theme_font_override("normal_font", PasswordPanel._mono())
	_pieces.add_theme_font_size_override("normal_font_size", TARGET_FONT_SIZE)
	add_child(_pieces)

	var center := CenterContainer.new()
	add_child(center)
	_grid = GridContainer.new()
	_grid.columns = puzzle.width
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	center.add_child(_grid)
	for row: int in puzzle.rows_visible:
		for col: int in puzzle.width:
			var cell := Button.new()
			cell.custom_minimum_size = Vector2(42, 28)
			cell.focus_mode = Control.FOCUS_NONE
			cell.add_theme_font_override("font", PasswordPanel._mono())
			cell.add_theme_color_override("font_color", TEXT_DUMP)
			var style := StyleBoxFlat.new()
			style.bg_color = CELL_IDLE
			cell.add_theme_stylebox_override("normal", style)
			cell.add_theme_stylebox_override("hover", style)
			cell.add_theme_stylebox_override("pressed", style)
			cell.pressed.connect(click.bind(row, col))
			_grid.add_child(cell)

	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_note)
	_next_button = Button.new()
	_next_button.text = "Дальше"
	_next_button.visible = false
	_next_button.pressed.connect(func() -> void: finished.emit(1))
	add_child(_next_button)
	_refresh()


## Дамп ползёт в реальном времени: строка за `scroll_seconds`.
func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	while _elapsed >= _scroll_seconds:
		_elapsed -= _scroll_seconds
		step()


## Экран сдвинулся на строку. Отдельно от кадров, чтобы тест мог двигать дамп сам.
func step() -> void:
	if _done:
		return
	puzzle.scroll()
	_refresh()


## Клик по клетке экрана: `row` — строка на экране (0 — верхняя), `col` — столбец.
func click(row: int, col: int) -> Dictionary:
	if _done:
		return {}
	var result: Dictionary = puzzle.pick(puzzle.top + row, col)
	match str(result["result"]):
		DumpPuzzle.PICK_MISS:
			_flash(Color(1.0, 0.4, 0.4), true)
		DumpPuzzle.PICK_HIT:
			_flash(Color(0.5, 1.0, 0.6), false)
		DumpPuzzle.PICK_DONE:
			_done = true
			_grid.modulate = Color(0.5, 1.0, 0.6)
			_note.text = "Хэш собран."
			_next_button.visible = true
	_refresh()
	return result


## Игрок закрыл окно или нажал «Выйти»: хэш не собран — слоя нет.
func abandon_gained() -> int:
	return 1 if puzzle.is_solved() else 0


func is_done() -> bool:
	return _done


## Короткая вспышка цветом; промах ещё и трясёт экран.
func _flash(tint: Color, shake: bool) -> void:
	if not animate:
		return
	_grid.modulate = tint
	var tween: Tween = create_tween()
	if shake:
		var base: float = _grid.position.x
		for step_index: int in 6:
			tween.tween_property(_grid, "position:x", base + (8.0 if step_index % 2 == 0 else -8.0), 0.04)
		tween.tween_property(_grid, "position:x", base, 0.04)
	else:
		tween.tween_interval(0.2)
	tween.tween_property(_grid, "modulate", Color.WHITE, 0.15)


func _refresh() -> void:
	var parts: PackedStringArray = []
	for index: int in puzzle.targets.size():
		var names: PackedStringArray = []
		for value: int in puzzle.targets[index]:
			names.append(puzzle.symbol_name(value))
		var color: String = COLOR_LATER
		if index < puzzle.stage:
			color = COLOR_CAUGHT
		elif index == puzzle.stage:
			color = COLOR_CURRENT
		parts.append("[color=%s]%s[/color]" % [color, " ".join(names)])
	_pieces.text = "[center]%s[/center]" % "   ".join(parts)

	var rows: Array[int] = puzzle.visible_rows()
	for row: int in rows.size():
		var symbols: PackedInt32Array = puzzle.row_symbols(rows[row])
		for col: int in puzzle.width:
			var cell: Button = _grid.get_child(row * puzzle.width + col) as Button
			cell.text = puzzle.symbol_name(symbols[col])
			cell.disabled = _done
