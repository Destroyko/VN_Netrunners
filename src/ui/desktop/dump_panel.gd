class_name DumpPanel
extends VBoxContainer
## «Перехват в дампе»: сверху «поезд» кусков хэша (текущий по центру, пойманный уезжает влево и
## тает, следующий въезжает справа), ниже плавно ползёт дамп памяти. Клик по клетке нужного куска
## ловит его, клик мимо — красная тряска и сброс собранного. Наведение мыши — «лупа»: клетки
## подкрашиваются (`DumpPuzzle.lens`). Правил здесь нет: всё решает `DumpPuzzle`, окно только
## показывает и двигает экран.

signal finished(gained: int)

const COLOR_CAUGHT: Color = Color("#5fd27a")
const COLOR_CURRENT: Color = Color("#f0f2f5")
const COLOR_LATER: Color = Color("#5b606c")
## Клетка обычной сетки (8 в ряд). Широкая сетка (кусок в 6 байт) ужимает клетки, чтобы
## окно не разрасталось: не шире `MAX_GRID_WIDTH`, но и не уже `MIN_CELL_WIDTH`.
const CELL_SIZE: Vector2 = Vector2(42, 28)
const MAX_GRID_WIDTH: float = 460.0
const MIN_CELL_WIDTH: float = 30.0
const SMALL_FONT_SIZE: int = 13
const GAP: int = 2
const CELL_IDLE: Color = Color(0.1, 0.12, 0.15)
const CELL_NEAR: Color = Color(0.2, 0.23, 0.29)
const CELL_MATCH: Color = Color(0.15, 0.33, 0.2)
const CELL_WRONG: Color = Color(0.35, 0.14, 0.14)
const TEXT_DUMP: Color = Color(0.62, 0.68, 0.72)
const TARGET_FONT_SIZE: int = 22
## Фон окна (как у `DesktopWindow`): в него растворяются края «поезда».
const BACKGROUND: Color = Color(0.09, 0.1, 0.13)
const PIECE_GAP: int = 40
const FADE_WIDTH: float = 90.0
const TRAIN_SECONDS: float = 0.35

## Выключатель анимаций: тесты гоняют партию мгновенно.
static var animate: bool = true

var puzzle: DumpPuzzle

var _cell: Vector2 = CELL_SIZE
var _strip: Control
var _train: HBoxContainer
var _shown_stage: int = -1
var _grid: GridContainer
var _note: Label
var _next_button: Button
var _scroll_seconds: float = 1.0
var _elapsed: float = 0.0
var _done: bool = false
var _lens_enabled: bool = true
## Клетка под мышью (номер ребёнка сетки) или -1.
var _hovered: int = -1


func setup(game: DumpPuzzle) -> void:
	puzzle = game
	var config: Dictionary = PuzzleLevels.dump(puzzle.level)
	_scroll_seconds = maxf(0.2, float(config.get("scroll_seconds", 1.0)))
	_lens_enabled = bool(config.get("lens", true))
	_cell = cell_size_for(puzzle.width)

	_build_train()

	# Окно дампа обрезает сетку: в сетке на строку больше, и она плавно едет вверх внутри окна.
	var center := CenterContainer.new()
	add_child(center)
	var window := Control.new()
	window.clip_contents = true
	window.custom_minimum_size = Vector2(_grid_width(), puzzle.rows_visible * (_cell.y + GAP) - GAP)
	center.add_child(window)
	_grid = GridContainer.new()
	_grid.columns = puzzle.width
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	window.add_child(_grid)
	for row: int in puzzle.rows_visible + 1:
		for col: int in puzzle.width:
			var cell := Button.new()
			cell.custom_minimum_size = _cell
			cell.focus_mode = Control.FOCUS_NONE
			cell.add_theme_font_override("font", PasswordPanel._mono())
			if _cell.x < CELL_SIZE.x:
				cell.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
			cell.add_theme_color_override("font_color", TEXT_DUMP)
			cell.add_theme_color_override("font_hover_color", Color.WHITE)
			var style := StyleBoxFlat.new()
			style.bg_color = CELL_IDLE
			for state: String in ["normal", "hover", "pressed", "disabled"]:
				cell.add_theme_stylebox_override(state, style)
			cell.pressed.connect(click.bind(row, col))
			cell.mouse_entered.connect(_on_hover.bind(row * puzzle.width + col))
			cell.mouse_exited.connect(_on_hover.bind(-1))
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


## Ширина подписей известна точно только в дереве сцены (там применяется шрифт): ставим «поезд»
## на место ещё раз, без анимации.
func _ready() -> void:
	if puzzle != null:
		_train.position.x = train_offset(mini(puzzle.stage, puzzle.targets.size() - 1))


func _grid_width() -> float:
	return puzzle.width * (_cell.x + GAP) - GAP


## Размер клетки для сетки шириной `columns`: обычный, пока сетка влезает, иначе ужатый.
static func cell_size_for(columns: int) -> Vector2:
	if columns * (CELL_SIZE.x + GAP) - GAP <= MAX_GRID_WIDTH:
		return CELL_SIZE
	var width: float = maxf(MIN_CELL_WIDTH, floorf((MAX_GRID_WIDTH + GAP) / columns) - GAP)
	return Vector2(width, CELL_SIZE.y - 2)


## Дамп ползёт непрерывно: сетка сдвигается по пикселям, а раз в `scroll_seconds` экран
## перескакивает на строку вперёд и сдвиг обнуляется — глазу это незаметно.
func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	while _elapsed >= _scroll_seconds:
		_elapsed -= _scroll_seconds
		step()
	_grid.position.y = -(_elapsed / _scroll_seconds) * (_cell.y + GAP)


## Экран сдвинулся на строку. Отдельно от кадров, чтобы тест мог двигать дамп сам.
func step() -> void:
	if _done:
		return
	puzzle.scroll()
	_refresh()


## Клик по клетке сетки: `row` — строка сетки (0 — верхняя), `col` — столбец.
func click(row: int, col: int) -> Dictionary:
	if _done:
		return {}
	var result: Dictionary = puzzle.pick(puzzle.top + row, col)
	SessionLog.write("puzzle", "дамп: строка потока %d, столбец %d → %s (поймано %d)" % [
		puzzle.top + row, col, result["result"], int(result["stage"])])
	# После клика лупа гаснет: подсвеченный кусок либо пойман, либо уже не нужен.
	# Загорится снова, когда мышь перейдёт на другую клетку.
	_hovered = -1
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


## Цвет фона клетки сетки (для тестов лупы).
func cell_color(row: int, col: int) -> Color:
	var cell: Button = _grid.get_child(row * puzzle.width + col) as Button
	return (cell.get_theme_stylebox("normal") as StyleBoxFlat).bg_color


func _on_hover(index: int) -> void:
	_hovered = index
	_paint_lens()


## Короткая вспышка цветом; промах ещё и трясёт экран.
func _flash(tint: Color, shake: bool) -> void:
	if not animate:
		return
	_grid.modulate = tint
	var tween: Tween = create_tween()
	if shake:
		for step_index: int in 6:
			tween.tween_property(_grid, "position:x", 8.0 if step_index % 2 == 0 else -8.0, 0.04)
		tween.tween_property(_grid, "position:x", 0.0, 0.04)
	else:
		tween.tween_interval(0.2)
	tween.tween_property(_grid, "modulate", Color.WHITE, 0.15)


# --- «Поезд» кусков --------------------------------------------------------------

## Полоса с кусками хэша: обрезана по краям, края растворяются в фоне окна градиентом.
func _build_train() -> void:
	var center := CenterContainer.new()
	add_child(center)
	_strip = Control.new()
	_strip.clip_contents = true
	center.add_child(_strip)
	_train = HBoxContainer.new()
	_train.add_theme_constant_override("separation", PIECE_GAP)
	_strip.add_child(_train)
	for index: int in puzzle.targets.size():
		var names: PackedStringArray = []
		for value: int in puzzle.targets[index]:
			names.append(puzzle.symbol_name(value))
		var label := Label.new()
		label.text = " ".join(names)
		label.add_theme_font_override("font", PasswordPanel._mono())
		label.add_theme_font_size_override("font_size", TARGET_FONT_SIZE)
		_train.add_child(label)
	var height: float = (_train.get_child(0) as Label).get_minimum_size().y + 6.0
	_strip.custom_minimum_size = Vector2(_grid_width(), height)
	_strip.add_child(_fade(true, height))
	_strip.add_child(_fade(false, height))


## Градиент от фона окна к прозрачному: кусок не обрезается резко, а тает у края.
func _fade(left: bool, height: float) -> TextureRect:
	var clear := Color(BACKGROUND, 0.0)
	var gradient := Gradient.new()
	gradient.set_color(0, BACKGROUND if left else clear)
	gradient.set_color(1, clear if left else BACKGROUND)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = int(FADE_WIDTH)
	texture.height = 4
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size = Vector2(FADE_WIDTH, height)
	rect.position = Vector2(0.0 if left else _grid_width() - FADE_WIDTH, 0.0)
	return rect


## Где должен стоять «поезд», чтобы кусок `index` оказался по центру полосы. Считаем по
## минимальным размерам подписей: раскладка контейнера в этот момент может быть ещё не готова.
func train_offset(index: int) -> float:
	var x: float = 0.0
	for i: int in index:
		x += (_train.get_child(i) as Label).get_minimum_size().x + PIECE_GAP
	var width: float = (_train.get_child(index) as Label).get_minimum_size().x
	return _grid_width() / 2.0 - (x + width / 2.0)


func train_x() -> float:
	return _train.position.x


func _refresh_train() -> void:
	for index: int in _train.get_child_count():
		var label: Label = _train.get_child(index) as Label
		var color: Color = COLOR_LATER
		if index < puzzle.stage:
			color = COLOR_CAUGHT
		elif index == puzzle.stage:
			color = COLOR_CURRENT
		label.add_theme_color_override("font_color", color)
		# Пойманный кусок уезжает притушенным, как отцепленный вагон.
		label.modulate.a = 0.55 if index < puzzle.stage else 1.0
	var stage: int = mini(puzzle.stage, puzzle.targets.size() - 1)
	if stage == _shown_stage:
		return
	_shown_stage = stage
	var goal: float = train_offset(stage)
	if not animate or not is_inside_tree():
		_train.position.x = goal
		return
	var tween: Tween = create_tween()
	tween.tween_property(_train, "position:x", goal, TRAIN_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# --- Экран -----------------------------------------------------------------------

func _refresh() -> void:
	_refresh_train()
	for row: int in puzzle.rows_visible + 1:
		var symbols: PackedInt32Array = puzzle.row_symbols(puzzle.top + row)
		for col: int in puzzle.width:
			var cell: Button = _grid.get_child(row * puzzle.width + col) as Button
			cell.text = puzzle.symbol_name(symbols[col])
			cell.disabled = _done
	_paint_lens()


## Подкрасить клетки под лупой. Мышь стоит, а дамп едет — поэтому перекрашиваем и после сдвига.
func _paint_lens() -> void:
	var lens: Dictionary = {}
	var lens_row: int = -1
	if _lens_enabled and _hovered >= 0 and not _done:
		lens_row = _hovered / puzzle.width
		lens = puzzle.lens(puzzle.top + lens_row, _hovered % puzzle.width)
	for index: int in _grid.get_child_count():
		var color: Color = CELL_IDLE
		if index / puzzle.width == lens_row and lens.has(index % puzzle.width):
			match str(lens[index % puzzle.width]):
				DumpPuzzle.LENS_MATCH:
					color = CELL_MATCH
				DumpPuzzle.LENS_WRONG:
					color = CELL_WRONG
				_:
					color = CELL_NEAR
		var cell: Button = _grid.get_child(index) as Button
		(cell.get_theme_stylebox("normal") as StyleBoxFlat).bg_color = color
