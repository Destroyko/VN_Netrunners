extends GutTest
## NodeValidator: проверка формата узлов (docs/tech/terminal-spec.md).

var validator: NodeValidator


func before_each() -> void:
	validator = NodeValidator.new()


## Учебный узел — эталон правильного формата.
func _good_node() -> Dictionary:
	return {
		"id": "node_test",
		"title": "Тестовый ПК",
		"address": "10.0.0.7",
		"difficulty": 1,
		"trace_minutes": 0,
		"required_services": 1,
		"root_required": false,
		"logs_path": "/log",
		"services": [
			{
				"id": "svc_login", "port": 22,
				"name": "Вход по паролю",
				"puzzle": "password",
				"difficulty": 1,
				"program": "passhound",
			},
		],
		"files": {
			"/home/zametka.txt": {"text": "кличка кота"},
			"/log/access.log": {"log": true},
		},
		"on_hacked": [{"set_flag": "node.test.hacked"}],
	}


func _check(node: Dictionary) -> bool:
	validator.validate_all({str(node.get("id", "node_test")): node})
	return validator.errors.is_empty()


func _text() -> String:
	return "\n".join(validator.errors)


func test_correct_node_passes() -> void:
	assert_true(_check(_good_node()), _text())
	assert_eq(validator.warnings.size(), 0, "лишних предупреждений нет")


func test_missing_required_field_is_error() -> void:
	var node: Dictionary = _good_node()
	node.erase("address")
	assert_false(_check(node))
	assert_string_contains(_text(), "address")


func test_id_must_match_key() -> void:
	var node: Dictionary = _good_node()
	node["id"] = "node_other"
	validator.validate_all({"node_test": node})
	assert_false(validator.errors.is_empty())


func test_duplicate_address_is_error() -> void:
	var first: Dictionary = _good_node()
	var second: Dictionary = _good_node()
	second["id"] = "node_second"
	validator.validate_all({"node_test": first, "node_second": second})
	assert_false(validator.errors.is_empty())
	assert_string_contains("\n".join(validator.errors), "10.0.0.7")


func test_unknown_puzzle_type_is_error() -> void:
	var node: Dictionary = _good_node()
	node["services"][0]["puzzle"] = "sudoku"
	assert_false(_check(node))
	assert_string_contains(_text(), "sudoku")


func test_both_mvp_puzzles_are_allowed() -> void:
	for puzzle: String in ["password", "matrix"]:
		validator = NodeValidator.new()
		var node: Dictionary = _good_node()
		node["services"][0]["puzzle"] = puzzle
		assert_true(_check(node), puzzle + ": " + _text())


func test_service_without_a_port_is_error() -> void:
	var node: Dictionary = _good_node()
	(node["services"][0] as Dictionary).erase("port")
	assert_false(_check(node))
	assert_string_contains(_text(), "port")


func test_two_services_on_one_port_is_error() -> void:
	var node: Dictionary = _good_node()
	node["services"].append({
		"id": "svc_other", "port": 22, "name": "Ещё один", "puzzle": "matrix", "program": "gridrunner",
	})
	assert_false(_check(node))
	assert_string_contains(_text(), "порт 22 уже занят")


func test_duplicate_service_id_is_error() -> void:
	var node: Dictionary = _good_node()
	node["services"].append({
		"id": "svc_login", "port": 23, "name": "Ещё один", "puzzle": "matrix", "program": "gridrunner",
	})
	node["required_services"] = 2
	assert_false(_check(node))


func test_required_services_more_than_services_is_error() -> void:
	var node: Dictionary = _good_node()
	node["required_services"] = 3
	assert_false(_check(node))
	assert_string_contains(_text(), "нельзя взломать")


func test_node_without_services_is_allowed() -> void:
	# Свой ПК: взламывать нечего, но файловая система настоящая.
	var node: Dictionary = _good_node()
	node["services"] = []
	node["required_services"] = 0
	assert_true(_check(node), _text())


func test_difficulty_out_of_range_is_error() -> void:
	var node: Dictionary = _good_node()
	node["difficulty"] = 7
	assert_false(_check(node))


func test_negative_trace_is_error() -> void:
	var node: Dictionary = _good_node()
	node["trace_minutes"] = -5
	assert_false(_check(node))


func test_file_path_outside_known_roots_is_error() -> void:
	# Корней ровно четыре: /home, /log, /sys, /prog (docs/tech/terminal-spec.md).
	var node: Dictionary = _good_node()
	node["files"] = {"home/zametka.txt": {"text": "..."}, "/log/access.log": {"log": true}}
	assert_false(_check(node))

	validator = NodeValidator.new()
	var stray: Dictionary = _good_node()
	stray["files"] = {"/root/zametki.txt": {"text": "..."}, "/log/access.log": {"log": true}}
	assert_false(_check(stray), "старый /root больше не корень")

	validator = NodeValidator.new()
	var ok: Dictionary = _good_node()
	ok["files"] = {"/prog/nightly.sh": {"text": "..."}, "/log/access.log": {"log": true}}
	assert_true(_check(ok), _text())


## Связи и прайм-тайм — docs/gameplay/network.md.
func _linked_pair(first_links: Array, second_links: Array) -> Dictionary:
	var first: Dictionary = _good_node()
	first["links"] = first_links
	var second: Dictionary = _good_node()
	second["id"] = "node_second"
	second["address"] = "10.0.0.8"
	second["links"] = second_links
	return {"node_test": first, "node_second": second}


func test_two_way_link_passes() -> void:
	validator.validate_all(_linked_pair(["node_second"], ["node_test"]))
	assert_eq(validator.errors.size(), 0, "\n".join(validator.errors))


func test_one_way_link_is_error() -> void:
	# Иначе scan с одной стороны видит узел, а с другой нет.
	validator.validate_all(_linked_pair(["node_second"], []))
	assert_false(validator.errors.is_empty())
	assert_string_contains("\n".join(validator.errors), "односторонняя")


func test_link_to_missing_node_is_error() -> void:
	var node: Dictionary = _good_node()
	node["links"] = ["node_net_takogo"]
	assert_false(_check(node))


func test_self_link_is_error() -> void:
	var node: Dictionary = _good_node()
	node["links"] = ["node_test"]
	assert_false(_check(node))


func test_device_type_is_checked() -> void:
	var node: Dictionary = _good_node()
	node["device"] = "router"
	assert_true(_check(node), _text())
	validator = NodeValidator.new()
	node["device"] = "toaster"
	assert_false(_check(node))
	assert_string_contains(_text(), "toaster")


func test_chain_from_start_node_is_reachable() -> void:
	var nodes: Dictionary = _linked_pair(["node_second"], ["node_test"])
	(nodes["node_test"] as Dictionary)["known_from_start"] = true
	validator.validate_all(nodes)
	assert_eq(validator.warnings.size(), 0, "
".join(validator.warnings))


func test_node_outside_every_chain_is_warned_about() -> void:
	var nodes: Dictionary = _linked_pair([], [])
	(nodes["node_test"] as Dictionary)["known_from_start"] = true
	validator.validate_all(nodes)
	assert_eq(validator.errors.size(), 0, "недостижимость — не ошибка")
	assert_eq(validator.warnings.size(), 1)
	assert_string_contains(validator.warnings[0], "node_second")


func test_node_opened_by_an_order_is_not_lost() -> void:
	# Вход не через scan: заказ открывает узел сам (reveal_node), и это нормально.
	var nodes: Dictionary = _linked_pair([], [])
	(nodes["node_test"] as Dictionary)["known_from_start"] = true
	validator.validate_all(nodes, {"node_second": true})
	assert_eq(validator.warnings.size(), 0, "
".join(validator.warnings))


func test_node_opened_by_an_order_also_opens_its_neighbours() -> void:
	var nodes: Dictionary = _linked_pair(["node_second"], ["node_test"])
	var third: Dictionary = _good_node()
	third["id"] = "node_third"
	third["address"] = "10.0.0.9"
	third["links"] = []
	nodes["node_third"] = third
	(nodes["node_test"] as Dictionary)["known_from_start"] = true
	validator.validate_all(nodes, {"node_third": true})
	assert_eq(validator.warnings.size(), 0, "
".join(validator.warnings))


func test_reveal_in_on_hacked_is_checked() -> void:
	# Червь на телефоне открывает следующий узел: ссылка должна вести на существующий.
	var node: Dictionary = _good_node()
	node["on_hacked"] = [{"reveal_node": "node_nowhere"}]
	assert_false(_check(node))
	assert_string_contains(_text(), "node_nowhere")


func test_reveal_in_on_hacked_with_unknown_service_is_error() -> void:
	var nodes: Dictionary = _linked_pair([], [])
	(nodes["node_test"] as Dictionary)["on_hacked"] = [
		{"reveal_node": {"node": "node_second", "open": ["svc_nope"]}}
	]
	validator.validate_all(nodes)
	assert_string_contains("
".join(validator.errors), "svc_nope")


func test_reachability_is_silent_without_start_nodes() -> void:
	# Нет узлов «известных с начала» — не от чего считать цепочки.
	validator.validate_all(_linked_pair([], []))
	assert_eq(validator.warnings.size(), 0)


func test_online_window_passes() -> void:
	var node: Dictionary = _good_node()
	node["online"] = {"from": "08:00", "to": "18:00"}
	assert_true(_check(node), _text())


func test_online_without_field_is_error() -> void:
	var node: Dictionary = _good_node()
	node["online"] = {"from": "08:00"}
	assert_false(_check(node))


func test_online_with_bad_time_is_error() -> void:
	for bad: String in ["8-00", "25:00", "08:70", "утро"]:
		validator = NodeValidator.new()
		var node: Dictionary = _good_node()
		node["online"] = {"from": bad, "to": "18:00"}
		assert_false(_check(node), "время должно быть чч:мм: " + bad)


func test_no_online_means_always_available() -> void:
	assert_true(_check(_good_node()), "нет поля online — узел в сети круглосуточно")


func test_empty_file_description_is_warning_not_error() -> void:
	var node: Dictionary = _good_node()
	node["files"]["/home/pustoy.dat"] = {}
	assert_true(_check(node), "пустое описание файла не ломает данные")
	assert_eq(validator.warnings.size(), 1)


func test_file_id_must_be_unique_across_all_data() -> void:
	# По file_id квест ищет файл у игрока, где бы тот его ни спрятал.
	var first: Dictionary = _good_node()
	first["files"]["/home/dolgi.csv"] = {"size_kb": 10, "file_id": "file_evidence_dolgi"}
	var second: Dictionary = _good_node()
	second["id"] = "node_second"
	second["address"] = "10.0.0.8"
	second["files"] = {
		"/home/kopiya.csv": {"size_kb": 10, "file_id": "file_evidence_dolgi"},
		"/log/access.log": {"log": true},
	}
	validator.validate_all({"node_test": first, "node_second": second})
	assert_false(validator.errors.is_empty())
	assert_string_contains("\n".join(validator.errors), "file_evidence_dolgi")


func test_unique_file_ids_pass() -> void:
	var node: Dictionary = _good_node()
	node["files"]["/home/dolgi.csv"] = {"size_kb": 10, "file_id": "file_evidence_dolgi"}
	node["files"]["/home/hotel.jpg"] = {"size_kb": 20, "file_id": "file_evidence_hotel"}
	assert_true(_check(node), _text())


func test_logs_path_without_files_is_error() -> void:
	var node: Dictionary = _good_node()
	node["files"] = {"/home/zametka.txt": {"text": "..."}}
	assert_false(_check(node))
	assert_string_contains(_text(), "logs_path")


func test_unknown_effect_in_on_hacked_is_error() -> void:
	var node: Dictionary = _good_node()
	node["on_hacked"] = [{"set_flagg": "node.test.hacked"}]
	assert_false(_check(node))


func test_real_nodes_from_data_folder_are_valid() -> void:
	# Три тестовых взлома и ПК героя должны проходить проверку.
	DataLoader.clear_cache()
	var nodes: Dictionary = DataLoader.nodes()
	assert_gt(nodes.size(), 0, "в data/nodes есть узлы")
	validator.validate_all(nodes)
	assert_eq(validator.errors.size(), 0, "\n".join(validator.errors))
	for id: String in ["node_home_pc", "node_training_pc", "node_husband_pc", "node_office_server"]:
		assert_true(nodes.has(id), "узел на месте: " + id)


func test_unknown_wall_is_error() -> void:
	var node: Dictionary = _good_node()
	(node["services"][0] as Dictionary)["wall"] = "moat"
	assert_false(_check(node))
	assert_string_contains(_text(), "неизвестная стена")

