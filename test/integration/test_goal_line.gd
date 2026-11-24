extends GutTest
## Строка цели (docs/gameplay/planner.md, «Как подаём»): одна текущая цель отслеживаемой задачи;
## строки нет без цели, во время диалога и под тем, что накрывает экран (меню паузы, затемнение).

var line: QuestTracker


func before_each() -> void:
	GameState.reset()
	Clock.set_time(1, 9 * 60)
	line = QuestTracker.new()
	add_child_autofree(line)


func test_no_goal_no_line() -> void:
	line.refresh()
	assert_false(line.visible, "нет задачи — строки нет")


func test_shows_title_and_only_the_current_goal() -> void:
	Effects.apply({"unlock_quest": "side_first_job"})
	assert_true(line.visible)
	assert_eq(line.title_text(), Planner.title_of("side_first_job"))
	assert_eq(line.goal_text(), QuestTracker.current_goal("side_first_job"))
	assert_false(line.goal_text().contains("\n"), "одна цель, без списка этапов")


func test_hidden_during_dialogue() -> void:
	Effects.apply({"unlock_quest": "side_first_job"})
	EventBus.dialogue_started.emit("any")
	assert_false(line.visible, "в диалоге строки нет")
	EventBus.dialogue_ended.emit("any")
	assert_true(line.visible)


func test_hidden_under_pause_menu() -> void:
	Effects.apply({"unlock_quest": "side_first_job"})
	var pause := PauseMenu.new()
	add_child_autofree(pause)
	pause.open()
	await wait_process_frames(2)
	assert_false(line.visible, "меню паузы накрыло экран — строки нет")
	pause.close()
	await wait_process_frames(2)
	assert_true(line.visible)


func test_hidden_under_pass_out_curtain() -> void:
	Effects.apply({"unlock_quest": "side_first_job"})
	var curtain := PassOutCurtain.new()
	add_child_autofree(curtain)
	await wait_process_frames(2)
	assert_false(line.visible, "затемнение — строки нет")
