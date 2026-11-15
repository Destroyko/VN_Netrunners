extends GutTest
## DebugCommands: команды отладочной консоли.
## Логика консоли отделена от интерфейса именно для этих тестов.


func before_each() -> void:
	GameState.reset()
	Rng.set_seed(1)


func after_each() -> void:
	Clock.reload_config()


func test_unknown_command_reports_itself() -> void:
	assert_string_contains(DebugCommands.run("abracadabra"), "неизвестная команда")


func test_empty_line_does_nothing() -> void:
	assert_eq(DebugCommands.run("   "), "")


func test_help_lists_every_command() -> void:
	var output: String = DebugCommands.run("help")
	for name: String in DebugCommands.names():
		assert_string_contains(output, name)


func test_set_flag() -> void:
	DebugCommands.run("set_flag story.debt_revealed")
	assert_true(GameState.has_flag("story.debt_revealed"))
	DebugCommands.run("set_flag story.debt_revealed 0")
	assert_false(GameState.has_flag("story.debt_revealed"), "0 снимает флаг")


func test_set_flag_without_name_explains() -> void:
	assert_string_contains(DebugCommands.run("set_flag"), "имя флага")


func test_money_adds_and_sets() -> void:
	DebugCommands.run("money 500")
	assert_eq(GameState.money, 500)
	DebugCommands.run("money -200")
	assert_eq(GameState.money, 300)
	DebugCommands.run("money =50")
	assert_eq(GameState.money, 50, "= задаёт значение")


func test_money_rejects_not_a_number() -> void:
	DebugCommands.run("money много")
	assert_eq(GameState.money, 0)


func test_heat_adds_and_sets() -> void:
	DebugCommands.run("heat 30")
	assert_eq(GameState.heat, 30)
	DebugCommands.run("heat =0")
	assert_eq(GameState.heat, 0)


func test_time_advance_sends_events() -> void:
	Clock.configure({"minutes_per_day": 100})
	watch_signals(EventBus)
	DebugCommands.run("time +120")
	assert_eq(GameState.day, 2, "перешли через полночь")
	assert_signal_emitted(EventBus, "day_started")


func test_time_set_does_not_send_events() -> void:
	watch_signals(EventBus)
	DebugCommands.run("time 4 14:30")
	assert_eq(GameState.day, 4)
	assert_eq(GameState.minute, 14 * 60 + 30)
	assert_signal_not_emitted(EventBus, "day_started")


func test_time_rejects_bad_format() -> void:
	assert_string_contains(DebugCommands.run("time 4 14-30"), "чч:мм")


func test_seed_shows_and_sets() -> void:
	DebugCommands.run("seed 777")
	assert_eq(Rng.get_seed(), 777)
	assert_string_contains(DebugCommands.run("seed"), "777")


func test_effect_from_json() -> void:
	DebugCommands.run('effect {"money": 500}')
	assert_eq(GameState.money, 500)


func test_effect_rejects_unknown_type() -> void:
	assert_string_contains(DebugCommands.run('effect {"monney": 1}'), "неизвестный эффект")
	assert_eq(GameState.money, 0)


func test_effect_reports_not_implemented() -> void:
	assert_string_contains(DebugCommands.run('effect {"schedule_news": "news_x"}'), "не реализован")


func test_effect_rejects_broken_json() -> void:
	assert_string_contains(DebugCommands.run("effect {money: }"), "не разобрал JSON")
	assert_eq(GameState.money, 0, "битый ввод ничего не меняет")


func test_cond_checks_condition() -> void:
	GameState.set_flag("story.x")
	assert_string_contains(DebugCommands.run('cond {"flag": "story.x"}'), "true")
	assert_string_contains(DebugCommands.run('cond {"flag": "story.y"}'), "false")


func test_flags_lists_and_filters() -> void:
	assert_string_contains(DebugCommands.run("flags"), "флагов нет")
	GameState.set_flag("story.a")
	GameState.set_flag("world.b")
	assert_string_contains(DebugCommands.run("flags"), "story.a")
	var only_world: String = DebugCommands.run("flags world")
	assert_string_contains(only_world, "world.b")
	assert_false(only_world.contains("story.a"), "фильтр отсекает лишнее")


func test_quest_sets_stage() -> void:
	DebugCommands.run("quest side_cheating_husband decide")
	assert_eq(GameState.get_quest_stage("side_cheating_husband"), "decide")


func test_state_shows_key_numbers() -> void:
	GameState.add_money(123)
	GameState.add_heat(7)
	var output: String = DebugCommands.run("state")
	assert_string_contains(output, "123")
	assert_string_contains(output, "7")


# --- puzzle: песочница головоломок --------------------------------------------

func test_puzzle_command_describes_a_password() -> void:
	var text: String = DebugCommands.run("puzzle password 3 7")
	assert_string_contains(text, "«пароль», уровень 3")
	assert_string_contains(text, "загадано:")
	assert_string_contains(text, "candidates_after_hints")


func test_puzzle_command_describes_a_matrix_with_the_reference_solution() -> void:
	var text: String = DebugCommands.run("puzzle matrix 2 7")
	assert_string_contains(text, "«матрица», уровень 2")
	assert_string_contains(text, "цели:")
	assert_string_contains(text, "эталонное решение")
	assert_string_contains(text, "slack")


func test_puzzle_command_is_deterministic() -> void:
	assert_eq(DebugCommands.run("puzzle password 4 99"), DebugCommands.run("puzzle password 4 99"))


func test_puzzle_command_checks_its_arguments() -> void:
	assert_string_contains(DebugCommands.run("puzzle"), "нужно")
	assert_string_contains(DebugCommands.run("puzzle sudoku 2 1"), "password или matrix")
	assert_string_contains(DebugCommands.run("puzzle password 1 1"), "от 2 до 4")
	assert_string_contains(DebugCommands.run("puzzle password два 1"), "числа")


func test_puzzle_report_has_one_csv_row_per_puzzle() -> void:
	var report: Dictionary = PuzzleReport.run(2, 1)
	var rows: PackedStringArray = str(report["csv"]).strip_edges().split("
")
	assert_eq(rows.size(), 1 + 2 * 3 * 2, "заголовок + 2 типа × 3 уровня × 2 сида")
	assert_string_contains(rows[0], "kind,level,seed,accepted")
	assert_eq((report["summary"] as PackedStringArray).size() > 6, true)

