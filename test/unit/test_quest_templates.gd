extends GutTest
## Шаблоны квестов с подстановками и новые условия (docs/tech/story-engine.md, «Шаблоны»).
## Шаблон подкладывается в кэш DataLoader на место файла data/quests/side.

const SLOT: String = "res://data/quests/side/side_test_courier.json"
const TEMPLATE: Dictionary = {
	"id": "side_tpl_fetch", "title": "Скачать {file} с {node}", "type": "side", "template": true,
	"params": {"node": {"from": ["node_training_pc"]}, "file": {"sample": "/home/zametka.txt"}},
	"stages": [{"id": "s1", "objectives": [{"type": "read_file", "node": "{node}", "file": "{file}"}]}],
	"outcomes": {"done": {"effects": [{"money": 10}]}},
}


func before_each() -> void:
	GameState.reset()
	DataLoader.clear_cache()
	DataLoader._cache[SLOT] = TEMPLATE.duplicate(true)


func after_each() -> void:
	DataLoader.clear_cache()


func test_template_starts_an_instance_with_params() -> void:
	var id: String = Quests.start_instance("side_tpl_fetch", {"file": "/home/privet.txt"})
	assert_eq(id, "side_tpl_fetch#1")
	assert_true(Quests.is_active(id))
	assert_eq(str(Quests.definition(id)["title"]), "Скачать /home/privet.txt с node_training_pc", "параметры подставлены, недостающий — из from")
	var objective: Dictionary = (Quests.current_stage(id)["objectives"] as Array)[0]
	assert_eq(str(objective["node"]), "node_training_pc")


func test_instances_are_independent_and_repeatable() -> void:
	GameState.set_money(0)
	var first: String = Quests.start_instance("side_tpl_fetch", {"file": "/home/privet.txt"})
	var second: String = Quests.start_instance("side_tpl_fetch", {"file": "/home/zametka.txt"})
	assert_ne(first, second, "каждый запуск — новый экземпляр")
	EventBus.file_read.emit("node_training_pc", "/home/zametka.txt")
	assert_true(GameState.is_quest_completed(second), "свой файл — свой экземпляр")
	assert_true(Quests.is_active(first), "чужой не задет")
	assert_eq(GameState.money, 10)


func test_unlock_quest_effect_passes_params() -> void:
	Effects.apply({"unlock_quest": {"quest": "side_tpl_fetch", "params": {"file": "/home/privet.txt"}}})
	assert_true(Quests.is_active("side_tpl_fetch#1"))
	assert_true(Quests.start("side_tpl_fetch"), "шаблон по имени — тоже новый экземпляр")
	assert_true(Quests.is_active("side_tpl_fetch#2"))


func test_substitute_keeps_value_types() -> void:
	var out: Variant = QuestTemplates.substitute({"money": "{pay}", "text": "заплатят {pay}"}, {"pay": 300})
	assert_eq((out as Dictionary)["money"], 300, "строка ровно {pay} — значение как есть")
	assert_eq((out as Dictionary)["text"], "заплатят 300")


# --- Новые условия -----------------------------------------------------------------

func test_time_and_place_conditions() -> void:
	Locations.enter("loc_kitchen")
	assert_true(Conditions.check({"at_location": "loc_kitchen"}))
	Clock.set_time(1, 13 * 60)
	assert_true(Conditions.check({"time_between": ["12:00", "16:00"]}))
	Clock.set_time(1, 16 * 60)
	assert_false(Conditions.check({"time_between": ["12:00", "16:00"]}), "16:00 — уже вне окна")
	var today: String = Clock.WEEKDAYS[int(Clock.date_of(GameState.day)["weekday"])]
	assert_true(Conditions.check({"weekday": today}))
	assert_true(Conditions.check({"weekday": [today, "zz"]}))


func test_counter_and_heat_conditions() -> void:
	GameState.set_var("stats.jogs", 3)
	assert_false(Conditions.check({"var_at_least": ["stats.jogs", 4]}))
	GameState.set_var("stats.jogs", 4)
	assert_true(Conditions.check({"var_at_least": ["stats.jogs", 4]}))
	GameState.set_heat(50)
	assert_true(Conditions.check({"heat_at_least": 50}))
