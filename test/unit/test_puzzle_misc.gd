extends GutTest
## Уровни, прогресс слоёв и проверка словаря головоломок (docs/tech/puzzles-spec.md).

const BALANCE: Dictionary = {
	"clock": {"minutes_per_day": 1440},
	"puzzles": {"progress_reset_days": 2},
}

var progress: PuzzleProgress
var state: Dictionary


func before_each() -> void:
	DataLoader.clear_cache()
	state = {}
	progress = PuzzleProgress.new(state, BALANCE)


func _at(day: int, hours: int = 12) -> int:
	return (day - 1) * 1440 + hours * 60


# --- Уровни ------------------------------------------------------------------

func test_level_comes_from_the_service_only() -> void:
	# Решено 15.11.2026: ступень задаёт ситуация, глобальных уровней сложности пока нет.
	assert_eq(PuzzleLevels.level_for_service(1), 2, "учебный сервис — лёгкая ступень")
	assert_eq(PuzzleLevels.level_for_service(2), 3)
	assert_eq(PuzzleLevels.level_for_service(3), 4)
	assert_eq(PuzzleLevels.level_for_service(4), 4, "тяжелее тяжёлой не бывает")
	assert_eq(PuzzleLevels.level_for_service(0), 2, "и легче лёгкой")


func test_parameters_come_from_balance_json() -> void:
	var password: Dictionary = PuzzleLevels.password(4)
	assert_eq([int(password["length"]), int(password["attempts"]), int(password["known"])], [7, 4, 0])
	var matrix: Dictionary = PuzzleLevels.matrix(4)
	assert_eq([int(matrix["size"]), int(matrix["buffer"]), int(matrix["sequences"]), int(matrix["noise"])], [7, 7, 3, 3])


func test_general_settings_of_a_section_reach_every_level() -> void:
	assert_true(PuzzleLevels.password(2).has("max_tries"))
	assert_true(PuzzleLevels.matrix(3).has("nodes_cap"))


# --- Прогресс слоёв ----------------------------------------------------------

func test_new_service_has_nothing() -> void:
	assert_eq(progress.layers("node_a", "svc", _at(1)), 0)
	assert_eq(progress.attempts("node_a", "svc", _at(1)), 0)


func test_layers_and_attempts_accumulate() -> void:
	progress.record("node_a", "svc", _at(1), 1)
	progress.record("node_a", "svc", _at(1, 13), 0)
	progress.record("node_a", "svc", _at(1, 14), 2)
	assert_eq(progress.layers("node_a", "svc", _at(1, 15)), 3)
	assert_eq(progress.attempts("node_a", "svc", _at(1, 15)), 3)


func test_progress_is_per_service() -> void:
	progress.record("node_a", "svc_one", _at(1), 1)
	assert_eq(progress.layers("node_a", "svc_two", _at(1)), 0)
	assert_eq(progress.layers("node_b", "svc_one", _at(1)), 0)


func test_layers_melt_after_two_days_without_progress() -> void:
	progress.record("node_a", "svc", _at(1), 1)
	assert_eq(progress.layers("node_a", "svc", _at(2, 23)), 1, "почти два дня — ещё держатся")
	assert_eq(progress.layers("node_a", "svc", _at(3)), 0, "два дня прошло — растаяли")
	assert_eq(progress.attempts("node_a", "svc", _at(3)), 0, "вместе с ними обнулился и счётчик")


func test_new_layer_restarts_the_melting() -> void:
	progress.record("node_a", "svc", _at(1), 1)
	progress.record("node_a", "svc", _at(2, 20), 1)
	assert_eq(progress.layers("node_a", "svc", _at(4, 10)), 2, "продвижение продлило срок")


func test_failure_does_not_extend_the_melting() -> void:
	# Иначе можно было бы держать слои вечно, проваливаясь раз в день.
	progress.record("node_a", "svc", _at(1), 1)
	progress.record("node_a", "svc", _at(2, 20), 0)
	assert_eq(progress.layers("node_a", "svc", _at(3, 12)), 0, "ровно двое суток от последнего слоя")


func test_opened_service_is_forgotten() -> void:
	progress.record("node_a", "svc", _at(1), 1)
	progress.clear_service("node_a", "svc")
	assert_eq(progress.layers("node_a", "svc", _at(1)), 0)
	assert_eq(progress.attempts("node_a", "svc", _at(1)), 0)


func test_finished_trace_resets_the_whole_node() -> void:
	progress.record("node_a", "svc_one", _at(1), 1)
	progress.record("node_a", "svc_two", _at(1), 1)
	progress.record("node_b", "svc_one", _at(1), 1)
	progress.reset_node("node_a")
	assert_eq(progress.layers("node_a", "svc_one", _at(1)), 0)
	assert_eq(progress.layers("node_a", "svc_two", _at(1)), 0)
	assert_eq(progress.layers("node_b", "svc_one", _at(1)), 1, "чужой узел не тронут")


func test_a_node_id_prefix_does_not_clash() -> void:
	# «node_a» не должен стирать «node_ab».
	progress.record("node_ab", "svc", _at(1), 1)
	progress.reset_node("node_a")
	assert_eq(progress.layers("node_ab", "svc", _at(1)), 1)


func test_progress_survives_save_and_load() -> void:
	GameState.reset()
	var in_game := PuzzleProgress.new(GameState.puzzle_state(), BALANCE)
	in_game.record("node_a", "svc", _at(1), 2)
	var saved: Dictionary = GameState.to_dict()
	GameState.reset()
	assert_eq(PuzzleProgress.new(GameState.puzzle_state(), BALANCE).layers("node_a", "svc", _at(1)), 0)
	GameState.from_dict(saved)
	assert_eq(PuzzleProgress.new(GameState.puzzle_state(), BALANCE).layers("node_a", "svc", _at(1)), 2)


# --- Сид ---------------------------------------------------------------------

func test_seed_is_stable() -> void:
	assert_eq(PuzzleProgress.seed_for(7, "node_a", "svc", 0, 0), PuzzleProgress.seed_for(7, "node_a", "svc", 0, 0))


func test_seed_changes_with_attempt_alert_node_and_game_seed() -> void:
	var base: int = PuzzleProgress.seed_for(7, "node_a", "svc", 0, 0)
	assert_ne(base, PuzzleProgress.seed_for(7, "node_a", "svc", 0, 1), "новая попытка — новая головоломка")
	assert_ne(base, PuzzleProgress.seed_for(7, "node_a", "svc", 1, 0), "осторожная цель — новое слово")
	assert_ne(base, PuzzleProgress.seed_for(7, "node_b", "svc", 0, 0))
	assert_ne(base, PuzzleProgress.seed_for(8, "node_a", "svc", 0, 0), "другое прохождение — другие головоломки")


# --- Проверка словаря --------------------------------------------------------

func _validate(words: Dictionary) -> PuzzleValidator:
	var validator := PuzzleValidator.new()
	validator.validate(words, {})
	return validator


func test_real_dictionary_is_valid() -> void:
	var validator := PuzzleValidator.new()
	validator.validate(DataLoader.puzzle_words(), DataLoader.balance())
	assert_eq(validator.errors.size(), 0, "\n".join(validator.errors))
	assert_eq(validator.warnings.size(), 0, "\n".join(validator.warnings))


func test_wrong_length_is_an_error() -> void:
	var validator: PuzzleValidator = _validate({"5": {"common": ["кот"]}})
	assert_gt(validator.errors.size(), 0)
	assert_string_contains("\n".join(validator.errors), "кот")


func test_yo_and_foreign_letters_are_errors() -> void:
	assert_gt(_validate({"5": {"common": ["актёр"]}}).errors.size(), 0)
	assert_gt(_validate({"5": {"common": ["apple"]}}).errors.size(), 0)
	assert_gt(_validate({"5": {"common": ["ab-cd"]}}).errors.size(), 0)


func test_duplicate_across_tiers_is_an_error() -> void:
	var validator: PuzzleValidator = _validate({"5": {"common": ["ветер"], "rare": ["ветер"]}})
	assert_string_contains("\n".join(validator.errors), "повтор")


func test_unknown_tier_and_key_are_errors() -> void:
	assert_gt(_validate({"5": {"epic": ["ветер"]}}).errors.size(), 0)
	assert_gt(_validate({"пять": {"common": ["ветер"]}}).errors.size(), 0)


func test_empty_dictionary_is_an_error() -> void:
	assert_gt(_validate({}).errors.size(), 0)


func test_missing_words_for_a_level_are_reported() -> void:
	var balance: Dictionary = {"puzzles": {"password": {"levels": {"2": {"length": 5, "tiers": ["common"], "known": 0, "candidates": [5, 40]}}}}}
	var validator := PuzzleValidator.new()
	validator.validate({"7": {"common": ["магазин"]}}, balance)
	assert_string_contains("\n".join(validator.errors), "нет слов длины 5")
