extends GutTest
## «Пароль»: метки, генерация, игра и гарантия решаемости (docs/tech/puzzles-spec.md, раздел 1).


func before_each() -> void:
	DataLoader.clear_cache()
	PasswordPuzzle.clear_cache()


# --- Метки: как в Wordle -----------------------------------------------------

func test_marks_exact_present_absent() -> void:
	# комар / кошка: к и о на местах, ш и вторая к — нет, а — есть, но не там.
	assert_eq(PasswordPuzzle.marks_for("комар", "кошка"), [2, 2, 0, 0, 1] as Array[int])


func test_all_exact() -> void:
	assert_eq(PasswordPuzzle.marks_for("ветер", "ветер"), [2, 2, 2, 2, 2] as Array[int])


func test_repeated_letters_are_not_marked_more_often_than_they_occur() -> void:
	# В «кошка» две к: одна встала на место, вторая из «комок» — «есть, но не там».
	assert_eq(PasswordPuzzle.marks_for("кошка", "комок"), [2, 2, 0, 0, 1] as Array[int])
	# Одна о в слове: пятью о помечена только та, что на месте.
	assert_eq(PasswordPuzzle.marks_for("лодка", "ооооо"), [0, 2, 0, 0, 0] as Array[int])


func test_feedback_code_is_unique_per_mark_pattern() -> void:
	assert_eq(PasswordPuzzle.feedback_code("комар", "комар"), 242, "все «точно»: 2·(1+3+9+27+81)")
	assert_ne(
		PasswordPuzzle.feedback_code("комар", "кошка"),
		PasswordPuzzle.feedback_code("комар", "комик")
	)


# --- Параметры уровней -------------------------------------------------------

func test_levels_match_the_spec_table() -> void:
	var easy: PasswordPuzzle = PasswordPuzzle.generate(2, 1)
	assert_eq([easy.length, easy.max_attempts, easy.known.size()], [5, 6, 2])
	var medium: PasswordPuzzle = PasswordPuzzle.generate(3, 1)
	assert_eq([medium.length, medium.max_attempts, medium.known.size()], [5, 5, 1])
	var hard: PasswordPuzzle = PasswordPuzzle.generate(4, 1)
	assert_eq([hard.length, hard.max_attempts, hard.known.size()], [7, 4, 0])


func test_known_letters_stand_on_their_own_places() -> void:
	for seed_value: int in range(1, 8):
		var puzzle: PasswordPuzzle = PasswordPuzzle.generate(3, seed_value, 1)
		for position: int in puzzle.known.keys():
			assert_eq(puzzle.word[position], str(puzzle.known[position]))


func test_at_least_three_letters_stay_unknown() -> void:
	# Иначе слово выдаётся само и головоломки нет (puzzles-spec.md).
	for level: int in [2, 3, 4]:
		var puzzle: PasswordPuzzle = PasswordPuzzle.generate(level, 3, 10)
		assert_gte(puzzle.length - puzzle.known.size(), 3, "уровень %d" % level)


func test_deepscan_adds_known_letters() -> void:
	var plain: PasswordPuzzle = PasswordPuzzle.generate(3, 5)
	var scanned: PasswordPuzzle = PasswordPuzzle.generate(3, 5, 1)
	assert_eq(scanned.known.size(), plain.known.size() + 1)


func test_answer_comes_from_the_levels_tiers() -> void:
	for seed_value: int in range(1, 10):
		assert_eq(Words.tier_index(PasswordPuzzle.generate(2, seed_value).word), 0, "лёгкий — только частые слова")


# --- Детерминизм -------------------------------------------------------------

func test_same_seed_gives_the_same_puzzle() -> void:
	for level: int in [2, 3, 4]:
		var first: PasswordPuzzle = PasswordPuzzle.generate(level, 4242)
		var second: PasswordPuzzle = PasswordPuzzle.generate(level, 4242)
		assert_eq(first.word, second.word)
		assert_eq(first.known, second.known)
		assert_eq(first.metrics, second.metrics)


func test_different_seeds_give_different_puzzles() -> void:
	var words: Dictionary = {}
	for seed_value: int in range(1, 20):
		words[PasswordPuzzle.generate(3, seed_value).word] = true
	assert_gt(words.size(), 5, "двадцать сидов — не одно и то же слово")


# --- Решаемость --------------------------------------------------------------

func test_every_generated_puzzle_is_solvable_within_the_attempts() -> void:
	# Главная гарантия конвейера: солвер решает за допустимое число попыток.
	for level: int in [2, 3, 4]:
		for seed_value: int in range(1, 13):
			var puzzle: PasswordPuzzle = PasswordPuzzle.generate(level, seed_value)
			assert_true(bool(puzzle.metrics["accepted"]), "принят: уровень %d, сид %d" % [level, seed_value])
			assert_lte(int(puzzle.metrics["solver_attempts_worst"]), puzzle.max_attempts)


func test_candidates_are_inside_the_levels_range() -> void:
	for level: int in [2, 3, 4]:
		var bounds: Array = PuzzleLevels.password(level)["candidates"] as Array
		for seed_value: int in range(1, 8):
			var count: int = int(PasswordPuzzle.generate(level, seed_value).metrics["candidates_after_hints"])
			assert_true(count >= int(bounds[0]) and count <= int(bounds[1]), "уровень %d: %d кандидатов" % [level, count])


func test_a_bot_playing_the_solvers_moves_wins_within_the_attempts() -> void:
	# Метрики честные: если играть так, как считает солвер, действительно выигрываешь.
	for level: int in [2, 3, 4]:
		for seed_value: int in range(1, 5):
			var puzzle: PasswordPuzzle = PasswordPuzzle.generate(level, seed_value)
			var pool: PackedStringArray = puzzle.candidates()
			var won: bool = false
			while not puzzle.is_over():
				var guess: String = str(PasswordSolver.analyze(pool)["first"])
				var turn: Dictionary = puzzle.guess(guess)
				assert_true(bool(turn["valid"]), "бот называет слова из словаря")
				won = bool(turn["solved"])
				var code: int = PasswordPuzzle.feedback_code(puzzle.word, guess)
				var next: PackedStringArray = []
				for candidate: String in pool:
					if PasswordPuzzle.feedback_code(candidate, guess) == code:
						next.append(candidate)
				pool = next
			assert_true(won, "уровень %d, сид %d" % [level, seed_value])


# --- Игра --------------------------------------------------------------------

func _puzzle() -> PasswordPuzzle:
	return PasswordPuzzle.generate(2, 11)


func _wrong_word(puzzle: PasswordPuzzle, skip: int = 0) -> String:
	var found: int = 0
	for word: String in Words.all(puzzle.length):
		if word != puzzle.word:
			if found == skip:
				return word
			found += 1
	return ""


func test_wrong_length_does_not_cost_an_attempt() -> void:
	var puzzle: PasswordPuzzle = _puzzle()
	var turn: Dictionary = puzzle.guess("кот")
	assert_false(bool(turn["valid"]))
	assert_eq(turn["reason"], "length")
	assert_eq(puzzle.attempts_left(), puzzle.max_attempts)


func test_word_outside_the_dictionary_does_not_cost_an_attempt() -> void:
	# Опечатка не тратит попытку (puzzles-spec.md).
	var puzzle: PasswordPuzzle = _puzzle()
	var turn: Dictionary = puzzle.guess("ццццц")
	assert_false(bool(turn["valid"]))
	assert_eq(turn["reason"], "unknown")
	assert_eq(puzzle.history.size(), 0)


func test_a_wrong_word_costs_an_attempt_and_gives_marks() -> void:
	var puzzle: PasswordPuzzle = _puzzle()
	var turn: Dictionary = puzzle.guess(_wrong_word(puzzle))
	assert_true(bool(turn["valid"]))
	assert_false(bool(turn["solved"]))
	assert_eq((turn["marks"] as Array).size(), puzzle.length)
	assert_eq(puzzle.attempts_left(), puzzle.max_attempts - 1)


func test_guessing_the_word_solves_it() -> void:
	var puzzle: PasswordPuzzle = _puzzle()
	var turn: Dictionary = puzzle.guess(puzzle.word)
	assert_true(bool(turn["solved"]))
	assert_true(puzzle.solved)
	assert_true(puzzle.is_over())
	assert_eq(turn["marks"], [2, 2, 2, 2, 2] as Array[int])


func test_input_case_and_spaces_are_forgiven() -> void:
	var puzzle: PasswordPuzzle = _puzzle()
	assert_true(bool(puzzle.guess("  " + puzzle.word.to_upper() + " ")["solved"]))


func test_running_out_of_attempts_is_a_failure() -> void:
	var puzzle: PasswordPuzzle = _puzzle()
	var last: Dictionary = {}
	for index: int in puzzle.max_attempts:
		last = puzzle.guess(_wrong_word(puzzle, index))
	assert_true(bool(last["failed"]))
	assert_true(puzzle.is_over())
	assert_false(puzzle.solved)


func test_no_guesses_after_the_end() -> void:
	var puzzle: PasswordPuzzle = _puzzle()
	puzzle.guess(puzzle.word)
	assert_eq(puzzle.guess(puzzle.word)["reason"], "over")


func test_non_strict_guess_spends_an_attempt_on_a_non_word() -> void:
	var puzzle: PasswordPuzzle = PasswordPuzzle.generate(2, 3, 0)
	var turn: Dictionary = puzzle.guess("ъъъъъ", false)
	assert_true(turn["valid"])
	assert_false(turn["in_dictionary"])
	assert_eq(puzzle.history.size(), 1)

