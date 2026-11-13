extends GutTest
## GameState: хранение состояния и уведомления об изменениях.


func before_each() -> void:
	GameState.reset()


func test_flag_set_and_read() -> void:
	assert_false(GameState.has_flag("story.debt_revealed"), "новая игра — флага нет")
	GameState.set_flag("story.debt_revealed")
	assert_true(GameState.has_flag("story.debt_revealed"), "флаг поставлен")


func test_flag_cleared() -> void:
	GameState.set_flag("world.police_raid_done")
	GameState.clear_flag("world.police_raid_done")
	assert_false(GameState.has_flag("world.police_raid_done"))


func test_flag_change_sends_event() -> void:
	watch_signals(EventBus)
	GameState.set_flag("story.job_found")
	assert_signal_emitted_with_parameters(EventBus, "flag_changed", ["story.job_found", true])


func test_flag_set_twice_sends_one_event() -> void:
	watch_signals(EventBus)
	GameState.set_flag("story.job_found")
	GameState.set_flag("story.job_found")
	assert_signal_emit_count(EventBus, "flag_changed", 1, "повторная установка — не изменение")


func test_get_flags_returns_copy() -> void:
	GameState.set_flag("a.b")
	var flags: Dictionary = GameState.get_flags()
	flags.erase("a.b")
	assert_true(GameState.has_flag("a.b"), "правка копии не меняет состояние")


func test_money_added_and_spent() -> void:
	GameState.add_money(500)
	assert_eq(GameState.money, 500)
	GameState.add_money(-200)
	assert_eq(GameState.money, 300)
	assert_true(GameState.can_afford(300))
	assert_false(GameState.can_afford(301))


func test_money_event_carries_delta() -> void:
	watch_signals(EventBus)
	GameState.add_money(80)
	assert_signal_emitted_with_parameters(EventBus, "money_changed", [80, 80])


func test_heat_clamped_to_range() -> void:
	GameState.add_heat(150)
	assert_eq(GameState.heat, GameState.HEAT_MAX, "заметность не выше максимума")
	GameState.add_heat(-500)
	assert_eq(GameState.heat, GameState.HEAT_MIN, "и не ниже нуля")


func test_vars_stored() -> void:
	GameState.set_var("progress.rank", 2)
	assert_eq(int(GameState.get_var_or("progress.rank", 0)), 2)
	assert_eq(int(GameState.get_var_or("progress.nope", 7)), 7, "значение по умолчанию")


func test_quest_stage_tracked() -> void:
	assert_false(GameState.is_quest_started("side_cheating_husband"))
	GameState.set_quest_stage("side_cheating_husband", "collect")
	assert_true(GameState.is_quest_started("side_cheating_husband"))
	assert_eq(GameState.get_quest_stage("side_cheating_husband"), "collect")
	assert_false(GameState.is_quest_completed("side_cheating_husband"))
	GameState.set_quest_completed("side_cheating_husband", "silence")
	assert_true(GameState.is_quest_completed("side_cheating_husband"))


func test_save_round_trip() -> void:
	GameState.add_money(777)
	GameState.add_heat(42)
	GameState.set_flag("story.debt_revealed")
	GameState.set_var("progress.episode", 1)
	GameState.set_quest_stage("side_x", "decide")
	GameState.day = 5
	GameState.minute = 615
	var saved: Dictionary = GameState.to_dict()

	GameState.reset()
	assert_eq(GameState.money, 0, "после reset состояние чистое")

	GameState.from_dict(saved)
	assert_eq(GameState.money, 777)
	assert_eq(GameState.heat, 42)
	assert_eq(GameState.day, 5)
	assert_eq(GameState.minute, 615)
	assert_true(GameState.has_flag("story.debt_revealed"))
	assert_eq(int(GameState.get_var_or("progress.episode", 0)), 1)
	assert_eq(GameState.get_quest_stage("side_x"), "decide")
	assert_eq(int(saved.get("version", 0)), GameState.SAVE_VERSION, "в сейве есть версия формата")
