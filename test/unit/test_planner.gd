extends GutTest
## Планировщик и трекер (docs/gameplay/planner.md): квест из мини-квестов, какая задача в трекере,
## названия целей, неделя пн–вс. Неделя подработки — side_first_job.


func before_each() -> void:
	GameState.reset()
	Clock.set_time(1, 8 * 60)


func _start_week() -> void:
	Effects.apply({"unlock_quest": "side_first_job"})


func test_parent_waits_then_runs_its_part() -> void:
	_start_week()
	assert_eq(Planner.tracked(), "side_first_job")
	assert_string_contains(str(Planner.current_steps("side_first_job")[0]["text"]), "9:00", "до девяти — ждать")
	Clock.advance(60)
	assert_true(Quests.is_active("side_job_2"), "в 9:00 — первый заказ")
	assert_eq(Planner.subtitle("side_first_job"), Planner.title_of("side_job_2"), "подзаголовок — идущий заказ")
	assert_eq(str(Planner.current_steps("side_first_job")[0]["text"]), "Проверить почту", "шаги — из заказа")


func test_part_is_not_a_separate_task() -> void:
	_start_week()
	Clock.advance(60)
	assert_eq(Planner.tasks(), ["side_first_job"], "заказ не отдельной строкой — внутри недели")


func test_part_done_moves_parent_on() -> void:
	_start_week()
	Clock.advance(60)
	Quests.finish("side_job_2", Quests.OUTCOME_DONE)
	assert_eq(GameState.get_quest_stage("side_first_job"), "wait_1", "заказ сдан — ждать утра")
	assert_eq(Planner.subtitle("side_first_job"), "")
	Clock.advance(24 * 60)
	assert_true(Quests.is_active("side_job_3"))


func test_wait_counts_from_stage_start() -> void:
	var objective: Dictionary = {"type": "wait_until", "after": {"days": 1, "at": "09:00"}}
	assert_eq(QuestObjectives.wait_target(objective, 3), 3 * 1440 + 9 * 60, "день 4, 09:00")
	Clock.set_time(4, 8 * 60)
	assert_false(QuestObjectives.satisfied(objective, 3))
	Clock.set_time(4, 9 * 60)
	assert_true(QuestObjectives.satisfied(objective, 3))


func test_player_chooses_tracked_task() -> void:
	_start_week()
	Effects.apply({"unlock_quest": "side_test_courier"})
	assert_eq(Planner.tracked(), "side_first_job", "пока не выбрано — первая")
	Planner.track("side_test_courier")
	assert_eq(Planner.tracked(), "side_test_courier")
	GameState.set_quest_completed("side_test_courier")
	assert_eq(Planner.tracked(), "side_first_job", "выбранная закончилась — следующая")


func test_objective_names() -> void:
	assert_eq(Planner.objective_text({"type": "x", "title": "Своё"}), "Своё")
	assert_eq(Planner.objective_text({"type": "delete_file", "node": "node_job2_pc", "path": "/home/a/b.txt"}),
		"Удалить b.txt на %s" % str(DataLoader.nodes()["node_job2_pc"]["address"]))
	assert_eq(Planner.objective_text({"type": "visit_location", "location": "loc_kitchen"}), "Прийти: Кухня")


func test_week_starts_on_monday_and_lists_rent() -> void:
	var monday: int = Planner.week_start()
	assert_eq(int(Clock.date_of(monday)["weekday"]), 1, "неделя — с понедельника")
	assert_lte(monday, GameState.day)
	Clock.set_time(monday + 7, 9 * 60)
	Economy.issue("rent", "Аренда комнаты", 200)
	var items: Array = Planner.week_items()
	assert_eq(items.size(), 1)
	assert_string_contains(str(items[0]["text"]), "Аренда")
	assert_eq(Planner.bills().size(), 1, "неоплаченный счёт — в группе платежей")


func test_quest_without_deadline_is_not_in_week() -> void:
	Effects.apply({"unlock_quest": "side_first_job"})
	assert_eq(Planner.week_items().size(), 0, "у недели подработки срока нет — в календаре её нет")


func test_validator_knows_new_objectives() -> void:
	var v := Validator.new()
	v._mail = DataLoader.mail()
	v._validate_objectives("q", [
		{"type": "read_mail", "mail": "mail_ghost"},
		{"type": "complete_quest", "quest": "side_ghost"},
		{"type": "wait_until"},
	], DataLoader.nodes())
	var text: String = "\n".join(v.errors)
	assert_string_contains(text, "несуществующее письмо")
	assert_string_contains(text, "несуществующий квест")
	assert_string_contains(text, "until или after")
