extends "res://test/integration/desktop_fixture.gd"
## Окна головоломок: панели «пароля» и «матрицы» и модальное окно на столе.
## Правила партии проверяют тесты puzzles; здесь — что окно ведёт партию и отдаёт итог.

func _password_panel(level: int = 2, puzzle_seed: int = 1) -> PasswordPanel:
	var panel := PasswordPanel.new()
	panel.setup(PasswordPuzzle.generate(level, puzzle_seed, 0))
	panel.finished.connect(_on_finished)
	add_child_autofree(panel)
	return panel


func _matrix_panel(level: int = 2, puzzle_seed: int = 1) -> MatrixPanel:
	var panel := MatrixPanel.new()
	panel.setup(MatrixPuzzle.generate(level, puzzle_seed, PuzzleLevels.matrix(level)))
	panel.finished.connect(_on_finished)
	add_child_autofree(panel)
	return panel


func _wrong_word(puzzle: PasswordPuzzle) -> String:
	for candidate: String in Words.all(puzzle.length):
		if candidate != puzzle.word:
			return candidate
	return ""


# --- Пароль --------------------------------------------------------------------

func test_right_word_finishes_with_one_layer() -> void:
	var panel: PasswordPanel = _password_panel()
	panel.submit(panel.puzzle.word)
	assert_true(panel.is_done())
	assert_eq(_gained, -1, "итог отдаётся по кнопке «Дальше», а не сразу")
	var button: Button = panel.get_children().filter(func(c: Node) -> bool: return c is Button)[0] as Button
	button.pressed.emit()
	assert_eq(_gained, 1)


func test_word_outside_the_dictionary_costs_an_attempt_without_a_text() -> void:
	var panel: PasswordPanel = _password_panel()
	var before: int = panel.puzzle.attempts_left()
	panel.submit("ъъъъъ")
	assert_eq(panel.puzzle.attempts_left(), before - 1)
	assert_false(panel.note_text().contains("словар"), "игроку про словарь не говорим")


func test_running_out_of_attempts_ends_the_game_and_reveals_the_word() -> void:
	var panel: PasswordPanel = _password_panel()
	var wrong: String = _wrong_word(panel.puzzle)
	for _i: int in panel.puzzle.max_attempts:
		panel.submit(wrong)
	assert_true(panel.is_done())
	assert_string_contains(panel.note_text(), panel.puzzle.word)


func test_marks_are_shown_with_signs_not_only_colors() -> void:
	var row: String = PasswordPanel._row("ab", [PasswordPuzzle.MARK_EXACT, PasswordPuzzle.MARK_PRESENT])
	assert_string_contains(row, "A=")
	assert_string_contains(row, "B~")


func test_pool_holds_the_missing_letters_plus_decoys() -> void:
	var panel: PasswordPanel = _password_panel()
	var pool: Array[String] = panel.pool_letters()
	assert_gte(pool.size(), PasswordPanel.POOL_SIZE)
	for index: int in panel.puzzle.length:
		if not panel.puzzle.known.has(index):
			assert_true(pool.has(panel.puzzle.word[index]), "буква слова есть в пуле")
	assert_eq(PasswordPanel.build_pool(panel.puzzle), pool, "один сид — один пул")


func _letters_of(panel: PasswordPanel, word: String) -> Array[int]:
	# Индексы пула для букв слова, которых ещё нет в ячейках.
	var result: Array[int] = []
	var pool: Array[String] = panel.pool_letters()
	for index: int in word.length():
		if panel.puzzle.known.has(index):
			continue
		var found: int = pool.find(word[index])
		result.append(found)
		pool.remove_at(found)
	return result


func test_clicking_letters_fills_cells_and_solves() -> void:
	var panel: PasswordPanel = _password_panel()
	var word: String = panel.puzzle.word
	for index: int in word.length():
		if panel.puzzle.known.has(index):
			continue
		panel.place(panel.pool_letters().find(word[index]), index)
	assert_true(panel.is_done())
	assert_eq(panel.slot_text(), word)


func test_wrong_full_word_drops_absent_letters_and_returns_misplaced() -> void:
	var panel: PasswordPanel = _password_panel()
	var wrong: String = _wrong_word(panel.puzzle)
	var pool_before: int = panel.pool_letters().size()
	panel.submit(wrong)
	var marks: Array = panel.puzzle.history[0]["marks"] as Array
	var present: int = 0
	for mark: Variant in marks:
		if int(mark) == PasswordPuzzle.MARK_PRESENT:
			present += 1
	# Слово из головы игрока может состоять и не из букв пула: главное, что пул не растёт сверх «не там».
	assert_lte(panel.pool_letters().size(), pool_before + present, "лишние буквы пропали, «не там» вернулись")
	assert_false(panel.is_done())


func test_unplace_returns_the_letter_to_the_pool() -> void:
	var panel: PasswordPanel = _password_panel()
	var free: int = -1
	for index: int in panel.puzzle.length:
		if not panel.puzzle.known.has(index):
			free = index
			break
	var before: int = panel.pool_letters().size()
	panel.place_first_free(0)
	assert_eq(panel.pool_letters().size(), before - 1)
	panel.unplace(free)
	assert_eq(panel.pool_letters().size(), before)


# --- Матрица -------------------------------------------------------------------

func test_matrix_solution_collects_all_targets() -> void:
	var panel: MatrixPanel = _matrix_panel()
	for cell: int in panel.puzzle.solution:
		panel.pick(cell)
	assert_true(panel.is_done())
	assert_eq(panel.puzzle.layers(), panel.puzzle.targets.size())


func test_illegal_move_is_refused_with_a_hint() -> void:
	var panel: MatrixPanel = _matrix_panel()
	var legal: PackedInt32Array = panel.puzzle.legal_moves()
	var illegal: int = -1
	for cell: int in panel.puzzle.size * panel.puzzle.size:
		if not legal.has(cell):
			illegal = cell
			break
	var result: Dictionary = panel.pick(illegal)
	assert_false(bool(result["ok"]))
	assert_string_contains(panel.note_text(), "строке")
	assert_eq(panel.puzzle.picks.size(), 0)


func test_dead_end_ends_the_round_at_once() -> void:
	var panel: MatrixPanel = _matrix_panel()
	# Идём заведомо мимо решения, пока партия не закончится сама: буфер дозаполнять не нужно.
	var steps: int = 0
	while not panel.puzzle.is_finished() and steps < 30:
		var moves: PackedInt32Array = panel.puzzle.legal_moves()
		var wrong: int = moves[0]
		for cell: int in moves:
			var index: int = panel.puzzle.picks.size()
			if index >= panel.puzzle.solution.size() or cell != panel.puzzle.solution[index]:
				wrong = cell
				break
		panel.pick(wrong)
		steps += 1
	assert_true(panel.puzzle.is_finished())
	assert_lte(panel.puzzle.picks.size(), panel.puzzle.capacity)


func _factory(seed_value: int) -> Callable:
	return func(index: int) -> MatrixPuzzle: return MatrixPuzzle.generate_round(2, seed_value, index)


func _wrong_picks_until_dead_end(panel: MatrixPanel) -> void:
	var steps: int = 0
	var round_puzzle: MatrixPuzzle = panel.puzzle
	while panel.puzzle == round_puzzle and not panel.is_done() and steps < 30:
		var moves: PackedInt32Array = round_puzzle.legal_moves()
		if moves.is_empty():
			return
		var wrong: int = moves[0]
		for cell: int in moves:
			var index: int = round_puzzle.picks.size()
			if index >= round_puzzle.solution.size() or cell != round_puzzle.solution[index]:
				wrong = cell
				break
		panel.pick(wrong)
		steps += 1


func test_rounds_follow_one_another_and_total_is_reported() -> void:
	var first: MatrixPuzzle = MatrixPuzzle.generate_round(2, 5, 0)
	var panel := MatrixPanel.new()
	panel.setup(first, 2, _factory(5))
	panel.finished.connect(_on_finished)
	add_child_autofree(panel)
	for cell: int in first.solution:
		panel.pick(cell)
	assert_false(panel.is_done(), "второй слой впереди")
	assert_ne(panel.puzzle, first, "после слоя сразу новая сетка")
	for cell: int in panel.puzzle.solution:
		panel.pick(cell)
	assert_true(panel.is_done())
	(panel.get_children().filter(func(c: Node) -> bool: return c is Button).back() as Button).pressed.emit()
	assert_eq(_gained, 2)


func test_dead_end_gives_a_new_grid_for_the_same_layer_until_tries_run_out() -> void:
	var first: MatrixPuzzle = MatrixPuzzle.generate_round(2, 9, 0)
	var panel := MatrixPanel.new()
	panel.setup(first, 1, _factory(9))
	panel.finished.connect(_on_finished)
	add_child_autofree(panel)
	_wrong_picks_until_dead_end(panel)
	if panel.is_done():
		return # случайно выиграли: сид-зависимая редкость, повтор не проверить
	assert_ne(panel.puzzle, first, "тупик — новая сетка, а не конец")
	for _i: int in 5:
		_wrong_picks_until_dead_end(panel)
	assert_true(panel.is_done(), "попытки кончились")
	(panel.get_children().filter(func(c: Node) -> bool: return c is Button).back() as Button).pressed.emit()
	# «Неверный» путь иногда всё же собирает цель другим путём, так что 0 или 1.
	assert_true(_gained == 0 or _gained == 1)


# --- Модальное окно на столе ----------------------------------------------------

func test_dialog_picks_the_panel_by_puzzle_kind() -> void:
	var dialog := PuzzleDialog.new()
	add_child_autofree(dialog)
	dialog.setup({"type": "puzzle", "puzzle": PasswordPuzzle.generate(2, 1, 0), "node": "n", "service": "s"})
	assert_true(dialog.panel is PasswordPanel)
	var other := PuzzleDialog.new()
	add_child_autofree(other)
	other.setup({"type": "puzzle", "puzzle": MatrixPuzzle.generate(2, 1, PuzzleLevels.matrix(2)), "node": "n", "service": "s", "layers_total": 2})
	assert_true(other.panel is MatrixPanel)


func test_full_hack_through_the_desktop() -> void:
	Clock.set_time(1, 12 * 60)
	GameState.set_flag(Programs.flag_for("passhound"))
	var scene: PackedScene = load(Screens.DESKTOP) as PackedScene
	var desktop: Desktop = scene.instantiate() as Desktop
	add_child_autofree(desktop)
	await wait_frames(2)
	var view: TerminalView = desktop.open_app("terminal").body.get_child(0) as TerminalView
	for line: String in ["scan", "connect 10.0.0.1", "scan", "dc", "connect 10.0.0.7", "passhound 22"]:
		view.submit(line)
	assert_true(desktop.has_puzzle_open(), "программа открыла головоломку поверх стола")

	var dialog: PuzzleDialog = desktop.find_children("*", "PuzzleDialog", true, false)[0] as PuzzleDialog
	var panel: DumpPanel = dialog.panel as DumpPanel
	assert_not_null(desktop.window_of("puzzle"), "головоломка — обычное окно: его видно на панели задач")
	# Ловим куски через окно: прокрутка и клики, как у игрока.
	while not panel.is_done():
		var spot: Vector2i = _dump_spot(panel)
		if spot.x < 0:
			panel.step()
		else:
			panel.click(spot.x, spot.y)
	var button: Button = panel.get_children().filter(func(c: Node) -> bool: return c is Button).back() as Button
	button.pressed.emit()
	await wait_frames(2)
	assert_false(desktop.has_puzzle_open())
	assert_string_contains(view.output_text(), "открыт")


func _open_puzzle_on_desktop() -> Array:
	Clock.set_time(1, 12 * 60)
	GameState.set_flag(Programs.flag_for("passhound"))
	var scene: PackedScene = load(Screens.DESKTOP) as PackedScene
	var desktop: Desktop = scene.instantiate() as Desktop
	add_child_autofree(desktop)
	await wait_frames(2)
	var view: TerminalView = desktop.open_app("terminal").body.get_child(0) as TerminalView
	for line: String in ["scan", "connect 10.0.0.1", "scan", "dc", "connect 10.0.0.7", "passhound 22"]:
		view.submit(line)
	return [desktop, view]


func test_closing_the_puzzle_window_gives_up() -> void:
	var pair: Array = await _open_puzzle_on_desktop()
	var desktop: Desktop = pair[0] as Desktop
	assert_true(desktop.has_puzzle_open())
	desktop.window_of("puzzle").close()
	await wait_frames(2)
	assert_false(desktop.has_puzzle_open())
	assert_null(desktop.terminal.current_puzzle(), "партия закрыта, терминал свободен")


func test_exit_button_closes_the_puzzle() -> void:
	var pair: Array = await _open_puzzle_on_desktop()
	var desktop: Desktop = pair[0] as Desktop
	var exit: Button = desktop.find_child("Exit", true, false) as Button
	exit.pressed.emit()
	await wait_frames(2)
	assert_false(desktop.has_puzzle_open())


func test_disconnect_closes_the_puzzle_window() -> void:
	var pair: Array = await _open_puzzle_on_desktop()
	var desktop: Desktop = pair[0] as Desktop
	(pair[1] as TerminalView).submit("dc")
	await wait_frames(2)
	assert_false(desktop.has_puzzle_open())


func test_play_opens_a_puzzle_without_connection() -> void:
	var scene: PackedScene = load(Screens.DESKTOP) as PackedScene
	var desktop: Desktop = scene.instantiate() as Desktop
	add_child_autofree(desktop)
	await wait_frames(2)
	assert_true(desktop.play_puzzle("password", 2, 5))
	assert_true(desktop.has_puzzle_open())
	var got: Array = []
	desktop.practice_finished.connect(func(gained: int) -> void: got.append(gained))
	(desktop.find_child("Exit", true, false) as Button).pressed.emit()
	await wait_frames(2)
	assert_false(desktop.has_puzzle_open())
	assert_eq(got, [0])


func test_trace_ending_by_itself_closes_the_puzzle_window() -> void:
	# Трейс не замирает в головоломке (time.md, 15.11.2026): игрок думает — защита узла работает.
	Clock.set_time(1, 10 * 60)
	GameState.set_flag(Programs.flag_for("passhound"))
	GameState.set_flag(Programs.GATE_PRESSURE)
	Effects.apply_all([{"reveal_node": {"node": "node_office_server"}}])
	var scene: PackedScene = load(Screens.DESKTOP) as PackedScene
	var desktop: Desktop = scene.instantiate() as Desktop
	add_child_autofree(desktop)
	await wait_frames(2)
	var view: TerminalView = desktop.open_app("terminal").body.get_child(0) as TerminalView
	view.submit("connect 77.61.204.12")
	view.submit("passhound 8080")
	assert_true(desktop.has_puzzle_open())
	Clock.advance(desktop.terminal.session.trace_left())
	await wait_frames(2)
	assert_false(desktop.has_puzzle_open(), "сеанс оборван — головоломке не на что работать")
	assert_string_contains(view.output_text(), "трейс завершён: соединение с узлом разорвано")


# --- Перехват в дампе ------------------------------------------------------------

func test_dump_panel_catches_pieces_and_reports_one_layer() -> void:
	var panel := DumpPanel.new()
	panel.setup(DumpPuzzle.generate(2, 4))
	panel.finished.connect(_on_finished)
	add_child_autofree(panel)
	for _piece: int in panel.puzzle.targets.size():
		var spot: Vector2i = _dump_spot(panel)
		var guard: int = 0
		while spot.x < 0 and guard < 40:
			panel.step()
			spot = _dump_spot(panel)
			guard += 1
		panel.click(spot.x, spot.y)
	assert_true(panel.is_done())
	(panel.get_children().filter(func(c: Node) -> bool: return c is Button).back() as Button).pressed.emit()
	assert_eq(_gained, 1)


func test_dump_screen_follows_the_stream() -> void:
	var panel := DumpPanel.new()
	panel.setup(DumpPuzzle.generate(2, 4))
	add_child_autofree(panel)
	var grid: GridContainer = panel.find_children("*", "GridContainer", true, false)[0] as GridContainer
	var second_row_first: String = (grid.get_child(panel.puzzle.width) as Button).text
	panel.step()
	assert_eq((grid.get_child(0) as Button).text, second_row_first, "строки поехали вверх")


func test_play_dump_opens_from_the_console() -> void:
	var scene: PackedScene = load(Screens.DESKTOP) as PackedScene
	var desktop: Desktop = scene.instantiate() as Desktop
	add_child_autofree(desktop)
	await wait_frames(2)
	assert_true(desktop.play_puzzle("dump", 3, 9))
	var dialog: PuzzleDialog = desktop.find_children("*", "PuzzleDialog", true, false)[0] as PuzzleDialog
	assert_true(dialog.panel is DumpPanel)


func test_hover_lens_paints_exactly_what_the_puzzle_says() -> void:
	var panel := DumpPanel.new()
	panel.setup(DumpPuzzle.generate(2, 4))
	add_child_autofree(panel)
	panel._on_hover(panel.puzzle.width + 3)  # вторая строка, четвёртый столбец
	var lens: Dictionary = panel.puzzle.lens(panel.puzzle.top + 1, 3)
	for col: int in panel.puzzle.width:
		if lens.has(col):
			assert_ne(panel.cell_color(1, col), DumpPanel.CELL_IDLE, "столбец %d под лупой" % col)
		else:
			assert_eq(panel.cell_color(1, col), DumpPanel.CELL_IDLE, "столбец %d вне лупы" % col)
	panel._on_hover(-1)
	assert_eq(panel.cell_color(1, 3), DumpPanel.CELL_IDLE, "мышь ушла — лупа погасла")


func test_lens_goes_out_after_a_click() -> void:
	var panel := DumpPanel.new()
	panel.setup(DumpPuzzle.generate(2, 4))
	add_child_autofree(panel)
	panel._on_hover(3)
	panel.click(0, 3)
	for col: int in panel.puzzle.width:
		assert_eq(panel.cell_color(0, col), DumpPanel.CELL_IDLE)


func test_caught_piece_rolls_the_train_to_the_next_one() -> void:
	var panel := DumpPanel.new()
	panel.setup(DumpPuzzle.generate(3, 4))
	add_child_autofree(panel)
	assert_almost_eq(panel.train_x(), panel.train_offset(0), 0.5, "первый кусок по центру")
	var spot: Vector2i = _dump_spot(panel)
	var guard: int = 0
	while spot.x < 0 and guard < 40:
		panel.step()
		spot = _dump_spot(panel)
		guard += 1
	panel.click(spot.x, spot.y)
	assert_almost_eq(panel.train_x(), panel.train_offset(1), 0.5, "второй кусок по центру")
	assert_lt(panel.train_offset(1), panel.train_offset(0), "поезд едет влево")


func test_wide_dump_grid_shrinks_cells_to_fit() -> void:
	var normal: Vector2 = DumpPanel.cell_size_for(8)
	var wide: Vector2 = DumpPanel.cell_size_for(12)
	assert_eq(normal, DumpPanel.CELL_SIZE, "8 в ряд — обычные клетки")
	assert_lt(wide.x, normal.x, "12 в ряд — клетки уже")
	assert_lte(12 * (wide.x + DumpPanel.GAP) - DumpPanel.GAP, DumpPanel.MAX_GRID_WIDTH)


func test_puzzle_window_is_not_smaller_than_the_wide_dump() -> void:
	var scene: PackedScene = load(Screens.DESKTOP) as PackedScene
	var desktop: Desktop = scene.instantiate() as Desktop
	add_child_autofree(desktop)
	await wait_frames(2)
	desktop.play_puzzle("dump", 4, 3)
	await wait_frames(2)
	var window: DesktopWindow = desktop.window_of("puzzle")
	var dialog: PuzzleDialog = desktop.find_children("*", "PuzzleDialog", true, false)[0] as PuzzleDialog
	assert_gte(window.size.x, dialog.get_combined_minimum_size().x, "широкая сетка не обрезана")
	assert_eq((dialog.panel as DumpPanel).puzzle.current_target().size(), 5)


# --- Мягкие таймеры головоломок (16.11.2026) ---------------------------------------

func test_dump_time_out_is_a_failure() -> void:
	var panel := DumpPanel.new()
	panel.setup(DumpPuzzle.generate(2, 4))
	panel.finished.connect(_on_finished)
	add_child_autofree(panel)
	panel.tick_timer(float(PuzzleLevels.dump(2)["time_limit"]) + 1.0)
	assert_true(panel.is_done(), "время вышло — партия кончилась")
	(panel.get_children().filter(func(c: Node) -> bool: return c is Button).back() as Button).pressed.emit()
	assert_eq(_gained, 0, "хэш не собран — слоя нет")


func test_matrix_round_time_out_is_like_a_dead_end() -> void:
	var first: MatrixPuzzle = MatrixPuzzle.generate_round(2, 5, 0)
	var panel := MatrixPanel.new()
	panel.setup(first, 1, func(index: int) -> MatrixPuzzle: return MatrixPuzzle.generate_round(2, 5, index))
	add_child_autofree(panel)
	panel.tick_timer(float(PuzzleLevels.matrix(2)["round_seconds"]) + 1.0)
	assert_ne(panel.puzzle, first, "время слоя вышло — попытка потрачена, новая сетка")
	assert_false(panel.is_done(), "попытки ещё есть")
