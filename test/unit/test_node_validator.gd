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
		"logs_path": "/sys/log",
		"services": [
			{
				"id": "svc_login",
				"name": "Вход по паролю",
				"puzzle": "password",
				"difficulty": 1,
				"program": "passhound",
			},
		],
		"files": {
			"/home/zametka.txt": {"text": "кличка кота"},
			"/sys/log/access.log": {"log": true},
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


func test_duplicate_service_id_is_error() -> void:
	var node: Dictionary = _good_node()
	node["services"].append({
		"id": "svc_login", "name": "Ещё один", "puzzle": "matrix", "program": "gridrunner",
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


func test_file_path_must_be_absolute() -> void:
	var node: Dictionary = _good_node()
	node["files"] = {"home/zametka.txt": {"text": "..."}, "/sys/log/access.log": {"log": true}}
	assert_false(_check(node))


func test_empty_file_description_is_warning_not_error() -> void:
	var node: Dictionary = _good_node()
	node["files"]["/home/pustoy.dat"] = {}
	assert_true(_check(node), "пустое описание файла не ломает данные")
	assert_eq(validator.warnings.size(), 1)


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
