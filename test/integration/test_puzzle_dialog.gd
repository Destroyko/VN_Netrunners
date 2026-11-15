extends GutTest
## Окна головоломок: панели «пароля» и «матрицы» и модальное окно на столе.
## Правила партии проверяют тесты puzzles; здесь — что окно ведёт партию и отдаёт итог.

var _gained: int = -1


func before_each() -> void:
	GameState.reset()
	_gained = -1


func _on_finished(gained: int) -> void:
	_gained = gained


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


func test_typo_does_not_spend_an_attempt() -> void:
	var panel: PasswordPanel = _password_panel()
	var before: int = panel.puzzle.attempts_left()
	panel.submit("ъъъъъ")
	assert_eq(panel.puzzle.attempts_left(), before)
	assert_string_contains(panel.note_text(), "не потрачена")


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


func test_give_up_reports_what_was_collected() -> void:
	var panel: MatrixPanel = _matrix_panel()
	panel.pick(panel.puzzle.solution[0])
	(panel.find_child("GiveUp", true, false) as Button).pressed.emit()
	assert_true(panel.is_done())
	var button: Button = panel.get_children().filter(func(c: Node) -> bool: return c is Button).back() as Button
	button.pressed.emit()
	assert_eq(_gained, panel.puzzle.layers())


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
	for line: String in ["scan", "connect 10.0.0.1", "scan", "dc", "connect 10.0.0.7", "passhound svc_login"]:
		view.submit(line)
	assert_true(desktop.has_puzzle_open(), "программа открыла головоломку поверх стола")

	var dialog: PuzzleDialog = desktop.find_children("*", "PuzzleDialog", true, false)[0] as PuzzleDialog
	var panel: PasswordPanel = dialog.panel as PasswordPanel
	panel.submit(panel.puzzle.word)
	var button: Button = panel.get_children().filter(func(c: Node) -> bool: return c is Button)[0] as Button
	button.pressed.emit()
	await wait_frames(2)
	assert_false(desktop.has_puzzle_open())
	assert_string_contains(view.output_text(), "вскрыт")
