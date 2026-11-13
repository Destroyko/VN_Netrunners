extends GutTest
## Validator: ловит опечатки и висячие ссылки в данных.
##
## Проверяем на словарях, а не на файлах: так тест не зависит от содержимого data/.

var validator: Validator


func before_each() -> void:
	validator = Validator.new()


## Узел по полному формату: иначе на нём споткнётся NodeValidator,
## а здесь проверяются квесты. Сам формат узла — в test_node_validator.gd.
func _nodes() -> Dictionary:
	return {
		"node_husband_pc": {
			"id": "node_husband_pc",
			"title": "Домашний ПК",
			"address": "92.44.18.3",
			"required_services": 0,
			"logs_path": "/sys/log",
			"services": [],
			"files": {"/sys/log/access.log": {"log": true}},
		},
	}


func _news() -> Dictionary:
	return {"news_local_murder": {"id": "news_local_murder"}}


## Сокращённый «Неверный муж» из docs/tech/quest-format.md — эталон правильных данных.
func _good_quest() -> Dictionary:
	return {
		"id": "side_cheating_husband",
		"title": "Неверный муж",
		"type": "side",
		"channel": "messenger",
		"requires": [{"episode_at_least": 1}, {"rank_at_least": 1}],
		"stages": [
			{
				"id": "collect",
				"objectives": [
					{"type": "hack_node", "node": "node_husband_pc"},
					{"type": "copy_file", "node": "node_husband_pc", "file": "/home/photos/hotel.jpg"},
				],
			},
			{
				"id": "decide",
				"choices": [{"id": "give_evidence", "outcome": "murder"}],
			},
		],
		"outcomes": {
			"murder": {
				"effects": [{"money": 500}, {"rep": ["client_wife", 10]}],
				"news": [{"delay_days": 1, "id": "news_local_murder"}],
			},
		},
	}


func _validate(quest: Dictionary) -> bool:
	return validator.validate_data(_nodes(), _news(), {str(quest.get("id", "q")): quest}, {})


func test_correct_quest_passes() -> void:
	assert_true(_validate(_good_quest()), validator.summary())
	assert_eq(validator.errors.size(), 0)


func test_empty_data_passes() -> void:
	assert_true(validator.validate_data({}, {}, {}, {}), "пустой контент — не ошибка")


func test_missing_type_is_error() -> void:
	var quest: Dictionary = _good_quest()
	quest.erase("type")
	assert_false(_validate(quest))
	assert_string_contains(validator.summary(), "type")


func test_unknown_quest_type_is_error() -> void:
	var quest: Dictionary = _good_quest()
	quest["type"] = "sidequest"
	assert_false(_validate(quest))


func test_unknown_channel_is_error() -> void:
	var quest: Dictionary = _good_quest()
	quest["channel"] = "telegram"
	assert_false(_validate(quest))


func test_quest_without_stages_is_error() -> void:
	var quest: Dictionary = _good_quest()
	quest["stages"] = []
	assert_false(_validate(quest))


func test_typo_in_condition_is_caught() -> void:
	var quest: Dictionary = _good_quest()
	quest["requires"] = [{"flagg": "story.x"}]
	assert_false(_validate(quest))
	assert_string_contains(validator.summary(), "flagg")


func test_typo_in_effect_is_caught() -> void:
	var quest: Dictionary = _good_quest()
	var outcomes: Dictionary = quest["outcomes"]
	outcomes["murder"]["effects"] = [{"monney": 500}]
	assert_false(_validate(quest))


func test_unknown_objective_type_is_caught() -> void:
	var quest: Dictionary = _good_quest()
	quest["stages"][0]["objectives"] = [{"type": "steal_node", "node": "node_husband_pc"}]
	assert_false(_validate(quest))


func test_objective_pointing_to_missing_node_is_caught() -> void:
	var quest: Dictionary = _good_quest()
	quest["stages"][0]["objectives"] = [{"type": "hack_node", "node": "node_opechatka"}]
	assert_false(_validate(quest))
	assert_string_contains(validator.summary(), "node_opechatka")


func test_mask_backup_objective_passes() -> void:
	# Подмена архива — отдельный этап заметания следов (docs/gameplay/hacking.md).
	var quest: Dictionary = _good_quest()
	quest["stages"][0]["optional"] = [
		{"type": "mask_backup", "node": "node_husband_pc", "file": "/home/photos/hotel.jpg"},
	]
	assert_true(_validate(quest), validator.summary())


func test_optional_wipe_logs_objective_with_bonus_passes() -> void:
	# Соглашение из quest-format.md: заметание следов — необязательная цель с бонусом.
	var quest: Dictionary = _good_quest()
	quest["stages"][0]["optional"] = [
		{
			"type": "wipe_logs",
			"node": "node_husband_pc",
			"on_done": [{"money": 40}, {"rep": ["group", 1]}],
		},
	]
	assert_true(_validate(quest), validator.summary())


func test_radiant_template_node_is_allowed() -> void:
	# У radiant-квестов узел подставляется параметром: {phone}.
	var quest: Dictionary = _good_quest()
	quest["type"] = "radiant"
	quest["stages"][0]["objectives"] = [{"type": "hack_node", "node": "{phone}"}]
	assert_true(_validate(quest), validator.summary())


func test_choice_to_missing_outcome_is_caught() -> void:
	var quest: Dictionary = _good_quest()
	quest["stages"][1]["choices"] = [{"id": "give_evidence", "outcome": "nope"}]
	assert_false(_validate(quest))
	assert_string_contains(validator.summary(), "nope")


func test_missing_news_reference_is_caught() -> void:
	var quest: Dictionary = _good_quest()
	var outcomes: Dictionary = quest["outcomes"]
	outcomes["murder"]["news"] = [{"delay_days": 1, "id": "news_net_takogo"}]
	assert_false(_validate(quest))


func test_duplicate_stage_id_is_caught() -> void:
	var quest: Dictionary = _good_quest()
	quest["stages"][1]["id"] = "collect"
	assert_false(_validate(quest))


func test_correct_trigger_passes() -> void:
	# Пример trigger_collectors_step1 из docs/tech/architecture.md.
	var trigger: Dictionary = {
		"id": "trigger_collectors_step1",
		"on": "day_started",
		"requires": [{"flag": "story.job_found"}, {"not_flag": "story.collectors_1"}],
		"effects": [{"set_flag": "story.collectors_1"}],
		"once": true,
	}
	assert_true(validator.validate_data({}, {}, {}, {"trigger_collectors_step1": trigger}), validator.summary())


func test_trigger_with_unknown_event_is_caught() -> void:
	var trigger: Dictionary = {
		"id": "trigger_x",
		"on": "day_begun",
		"effects": [{"set_flag": "a.b"}],
	}
	assert_false(validator.validate_data({}, {}, {}, {"trigger_x": trigger}))
	assert_string_contains(validator.summary(), "day_begun")


func test_real_data_folder_is_valid() -> void:
	# Главная проверка: то, что лежит в data/, не ломает игру.
	assert_true(validator.validate_all(), validator.summary())
