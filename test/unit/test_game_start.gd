extends GutTest
## GameStart: одно начало новой игры для всех кнопок (найдено 17.11.2026: кнопка главного меню
## пропускала стартовые деньги и запуск первой подработки).


func after_each() -> void:
	Clock.stop()


func test_new_game_gives_start_money_and_starts_first_job() -> void:
	GameStart.begin()
	assert_eq(GameState.money, 150, "стартовые деньги")
	assert_true(Clock.running, "время пошло")
	assert_true(Filesystem.for_node(Network.HOME_ID).has_file("/home/dnevnik/01_nachalo.txt"),
		"game_started: дневник на месте")
	assert_true(Quests.is_active("side_first_job"), "неделя подработки началась")
	assert_eq(GameState.get_quest_stage("side_first_job"), "start", "первый заказ ждёт 9:00")
