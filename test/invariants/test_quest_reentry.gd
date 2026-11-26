extends GutTest
## Квесты на стыке с эффектами, которые сами шлют события шины (`move_to` → `location_entered`,
## `unlock_quest` → `quest_completed`): обработка квеста вкладывается в саму себя
## (docs/tech/interactions.md; docs/issues.md: ISS-010, ISS-011, ISS-017).
## Квесты подкладываются в кэш DataLoader на место файлов data/quests/side.

const OpenIssue = preload("res://test/invariants/open_issue.gd")
const SLOT_A: String = "res://data/quests/side/side_test_courier.json"
const SLOT_B: String = "res://data/quests/side/side_job_6.json"


func before_each() -> void:
	GameState.reset()
	DataLoader.clear_cache()
	Clock.reload_config()
	Clock.set_time(1, 12 * 60 + 10)


func after_each() -> void:
	DataLoader.clear_cache()


func _inject(path: String, quest: Dictionary) -> void:
	DataLoader._cache[path] = quest


# --- ISS-010: цель с on_done, который сам закрывает этап ---------------------------------

## Этап 1: «зайти на кухню» (on_done — герой уходит в прихожую) и «зайти в прихожую». Переход в
## прихожую закрывает этап изнутри первой цели. Этап 2 («зайти в коридор») не должен считаться
## выполненным, пока герой не зашёл в коридор.
func test_nested_stage_change_does_not_leak_done_into_next_stage() -> void:
	_inject(SLOT_A, {
		"id": "side_probe_walk", "title": "проба", "type": "side",
		"stages": [
			{"id": "s1", "objectives": [
				{"type": "visit_location", "location": "loc_kitchen", "on_done": [{"move_to": "loc_hall"}]},
				{"type": "visit_location", "location": "loc_hall"},
			]},
			{"id": "s2", "objectives": [{"type": "visit_location", "location": "loc_corridor"}]},
		],
	})
	assert_true(Quests.start("side_probe_walk"))
	Locations.enter("loc_kitchen")
	assert_eq(GameState.get_quest_stage("side_probe_walk"), "s2")
	assert_false(Quests.is_done("side_probe_walk", "o0"), "в коридор не заходил — цель этапа 2 открыта")
	Quests.on_event({})
	assert_true(Quests.is_active("side_probe_walk"), "квест не закончился сам")


# --- ISS-011: исход квеста применяется дважды ---------------------------------------------

## Исход «done» платит 100 и открывает следующий квест, который сразу выполнен (его цель «по
## состоянию» уже верна). Его завершение (`quest_completed`) снова проверяет первый квест, пока тот
## ещё не помечен законченным.
func test_outcome_effects_apply_once() -> void:
	_inject(SLOT_A, {
		"id": "side_probe_pay", "title": "проба", "type": "side",
		"stages": [{"id": "s1", "objectives": [{"type": "visit_location", "location": "loc_kitchen"}]}],
		"outcomes": {"done": {"effects": [{"money": 100}, {"unlock_quest": "side_probe_next"}]}},
	})
	_inject(SLOT_B, {
		"id": "side_probe_next", "title": "проба", "type": "side",
		"stages": [{"id": "s1", "objectives": [{"type": "wait_until"}]}],
	})
	GameState.set_money(0)
	assert_true(Quests.start("side_probe_pay"))
	Locations.enter("loc_kitchen")
	assert_true(GameState.is_quest_completed("side_probe_pay"))
	assert_true(GameState.is_quest_completed("side_probe_next"))
	assert_eq(GameState.money, 100, "награда за исход — один раз")


## Исход с `move_to`: переход шлёт `location_entered`, квест ещё не помечен законченным —
## снова `finish`, снова `move_to`… Сейчас это бесконечная рекурсия (Stack overflow), поэтому
## при RUN_OPEN_ISSUES=1 тест сыплет ошибками движка; после исправления — обычная проверка.
func test_outcome_with_move_to_finishes_once() -> void:
	_inject(SLOT_A, {
		"id": "side_probe_move", "title": "проба", "type": "side",
		"stages": [{"id": "s1", "objectives": [{"type": "visit_location", "location": "loc_kitchen"}]}],
		"outcomes": {"done": {"effects": [{"money": 100}, {"move_to": "loc_hall"}]}},
	})
	GameState.set_money(0)
	assert_true(Quests.start("side_probe_move"))
	Locations.enter("loc_kitchen")
	assert_true(GameState.is_quest_completed("side_probe_move"))
	assert_eq(GameState.money, 100)
	assert_eq(Locations.current(), "loc_hall")


# --- ISS-017: цель «файл на месте» после команды без события --------------------------------

## `mv` на своём ПК событий не шлёт: цель `file_at` ждёт ближайшего часа игры (И-14).
func test_file_at_objective_closes_right_after_local_mv() -> void:
	_inject(SLOT_A, {
		"id": "side_probe_file", "title": "проба", "type": "side",
		"stages": [{"id": "s1", "objectives": [{"type": "file_at", "path": "/home/notes/readme.txt"}]}],
	})
	assert_true(Quests.start("side_probe_file"))
	var t := Terminal.new()
	t.execute("mv /home/readme.txt /home/notes/readme.txt")
	assert_true(Filesystem.for_node(Network.HOME_ID).has_file("/home/notes/readme.txt"))
	assert_true(GameState.is_quest_completed("side_probe_file"), "файл на месте — цель выполнена сразу")
