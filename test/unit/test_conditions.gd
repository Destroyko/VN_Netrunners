extends GutTest
## Conditions: единый язык проверок из данных.


func before_each() -> void:
	GameState.reset()


func after_each() -> void:
	Clock.reload_config()


func test_flag_condition() -> void:
	assert_false(Conditions.check({"flag": "story.debt_revealed"}))
	GameState.set_flag("story.debt_revealed")
	assert_true(Conditions.check({"flag": "story.debt_revealed"}))


func test_not_flag_condition() -> void:
	assert_true(Conditions.check({"not_flag": "story.collectors_1"}))
	GameState.set_flag("story.collectors_1")
	assert_false(Conditions.check({"not_flag": "story.collectors_1"}))


func test_money_at_least() -> void:
	GameState.add_money(200)
	assert_true(Conditions.check({"money_at_least": 200}), "хватает ровно")
	assert_false(Conditions.check({"money_at_least": 201}))


func test_heat_at_most() -> void:
	GameState.add_heat(30)
	assert_true(Conditions.check({"heat_at_most": 30}))
	assert_false(Conditions.check({"heat_at_most": 29}))


func test_day_at_least() -> void:
	GameState.day = 4
	assert_true(Conditions.check({"day_at_least": 4}))
	assert_false(Conditions.check({"day_at_least": 5}))


func test_rank_and_episode_read_state_vars() -> void:
	GameState.set_var(Conditions.VAR_RANK, 2)
	GameState.set_var(Conditions.VAR_EPISODE, 1)
	assert_true(Conditions.check({"rank_at_least": 2}))
	assert_false(Conditions.check({"rank_at_least": 3}))
	assert_true(Conditions.check({"episode_at_least": 1}))
	assert_false(Conditions.check({"episode_at_least": 2}))


func test_skill_at_least() -> void:
	# Навык взлома 0-10, docs/gameplay/skills.md.
	GameState.set_var(Conditions.VAR_SKILL_PREFIX + "hacking", 3)
	assert_true(Conditions.check({"skill_at_least": ["hacking", 3]}))
	assert_false(Conditions.check({"skill_at_least": ["hacking", 4]}))
	assert_false(Conditions.check({"skill_at_least": ["fitness", 1]}), "другой навык ещё 0")


func test_time_of_day_condition() -> void:
	Clock.set_time(1, 9 * 60)
	assert_true(Conditions.check({"time_of_day": "morning"}))
	assert_false(Conditions.check({"time_of_day": "night"}))


func test_several_keys_in_one_condition_are_all_required() -> void:
	GameState.set_flag("story.job_found")
	assert_false(Conditions.check({"flag": "story.job_found", "money_at_least": 100}))
	GameState.add_money(100)
	assert_true(Conditions.check({"flag": "story.job_found", "money_at_least": 100}))


func test_check_all_requires_every_condition() -> void:
	GameState.set_flag("story.job_found")
	var requires: Array = [{"flag": "story.job_found"}, {"not_flag": "story.collectors_1"}]
	assert_true(Conditions.check_all(requires), "как в trigger_collectors_step1")
	GameState.set_flag("story.collectors_1")
	assert_false(Conditions.check_all(requires))


func test_empty_requires_is_true() -> void:
	assert_true(Conditions.check_all([]), "нет требований — условие выполнено")


func test_check_any_needs_one() -> void:
	assert_false(Conditions.check_any([]), "пустой список — не выполнено")
	GameState.add_money(50)
	assert_true(Conditions.check_any([{"flag": "nope"}, {"money_at_least": 50}]))


func test_known_types_cover_documented_dictionary() -> void:
	# Словарь из docs/tech/quest-format.md — на эти типы опирается валидатор.
	var documented: Array = [
		"flag", "not_flag", "rank_at_least", "episode_at_least", "time_of_day", "money_at_least",
	]
	for type: String in documented:
		assert_true(Conditions.is_known(type), "тип условия из документации: " + type)
	assert_false(Conditions.is_known("flagg"), "опечатка не проходит")
