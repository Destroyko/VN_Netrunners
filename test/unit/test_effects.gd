extends GutTest
## Effects: единый язык изменений состояния из данных.


func before_each() -> void:
	GameState.reset()


func test_money_effect() -> void:
	Effects.apply({"money": 500})
	assert_eq(GameState.money, 500)
	Effects.apply({"money": -120})
	assert_eq(GameState.money, 380)


func test_heat_effect() -> void:
	Effects.apply({"heat": 10})
	assert_eq(GameState.heat, 10)


func test_set_and_clear_flag_effect() -> void:
	Effects.apply({"set_flag": "story.collectors_1"})
	assert_true(GameState.has_flag("story.collectors_1"))
	Effects.apply({"clear_flag": "story.collectors_1"})
	assert_false(GameState.has_flag("story.collectors_1"))


func test_rep_effect_accumulates() -> void:
	Effects.apply({"rep": ["client_wife", 10]})
	Effects.apply({"rep": ["client_wife", -4]})
	assert_eq(int(GameState.get_var_or(Effects.VAR_REP_PREFIX + "client_wife", 0)), 6)


func test_set_var_effect() -> void:
	Effects.apply({"set_var": ["progress.rank", 2]})
	assert_eq(int(GameState.get_var_or("progress.rank", 0)), 2)


func test_apply_all_applies_quest_outcome() -> void:
	# Исход murder из docs/tech/quest-format.md.
	Effects.apply_all([{"money": 500}, {"rep": ["client_wife", 10]}])
	assert_eq(GameState.money, 500)
	assert_eq(int(GameState.get_var_or(Effects.VAR_REP_PREFIX + "client_wife", 0)), 10)


func test_several_keys_in_one_effect() -> void:
	Effects.apply({"money": 100, "heat": 5})
	assert_eq(GameState.money, 100)
	assert_eq(GameState.heat, 5)


func test_known_types_cover_documented_dictionary() -> void:
	# Словарь из docs/tech/quest-format.md.
	var documented: Array = [
		"money", "rep", "heat", "set_flag", "unlock_quest", "add_file", "schedule_news",
	]
	for type: String in documented:
		assert_true(Effects.is_known(type), "тип эффекта из документации: " + type)
	assert_false(Effects.is_known("monney"), "опечатка не проходит")


func test_deferred_types_are_known_but_not_implemented() -> void:
	assert_true(Effects.is_known("schedule_news"))
	assert_false(Effects.is_implemented("schedule_news"), "нужен NewsManager из M2")
	assert_true(Effects.is_implemented("money"))
