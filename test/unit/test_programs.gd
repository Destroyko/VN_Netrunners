extends "res://test/unit/terminal_fixture.gd"
## Программы: описания в данных, выдача флагом и требования на языке условий
## (docs/tech/terminal-spec.md, «Программы»; решено 15.11.2026).

const PATH: String = "res://data/programs.json"


func after_each() -> void:
	DataLoader.clear_cache()


## Подменить data/programs.json на время теста: так проверяем новые программы без правки файла.
func _use(definitions: Dictionary) -> void:
	DataLoader.clear_cache()
	DataLoader._cache[PATH] = definitions


func _strong() -> Dictionary:
	return {
		"kind": "cracker", "puzzle": "password", "minutes": "hack_step", "about": "тест",
		"requires": [{"skill_at_least": ["hacking", 6]}, {"rank_at_least": 3}],
	}


# --- Описания в данных -------------------------------------------------------

func test_real_programs_come_from_the_data_file() -> void:
	assert_eq(Programs.ids(), PackedStringArray(["deepscan", "gridrunner", "logwipe", "passhound", "rootstep"]))
	assert_eq(Programs.kind_of("passhound"), Programs.KIND_CRACKER)
	assert_eq(Programs.puzzle_of("gridrunner"), "matrix")
	assert_eq(Programs.kind_of("rootstep"), Programs.KIND_AUTO)
	assert_eq(Programs.minutes_for("passhound"), 3)


func test_comment_keys_are_not_programs() -> void:
	assert_false(Programs.is_program("_note"))
	assert_false(Programs.ids().has("_note_requires"))


func test_new_program_is_added_by_data_alone() -> void:
	_use({"_note": "x", "newcomer": _strong()})
	assert_true(Programs.is_program("newcomer"))
	assert_eq(Programs.ids(), PackedStringArray(["newcomer"]))
	assert_eq(Programs.minutes_for("newcomer"), 3)


# --- Выдача флагом -----------------------------------------------------------

func test_nothing_is_installed_at_the_start() -> void:
	assert_eq(Programs.installed().size(), 0)


func test_a_flag_installs_a_program() -> void:
	GameState.set_flag(Programs.flag_for("passhound"))
	assert_true(Programs.is_installed("passhound"))
	assert_false(Programs.is_installed("rootstep"))


func test_unknown_name_is_never_installed() -> void:
	GameState.set_flag(Programs.flag_for("ghost"))
	assert_false(Programs.is_installed("ghost"))


func test_empty_requirements_do_not_install_by_themselves() -> void:
	# «Нет требований» значит «приходит только по выдаче», а не «доступна всем».
	assert_eq(Programs.requirements("passhound").size(), 0)
	assert_false(Programs.requirements_met("passhound"))


# --- Требования --------------------------------------------------------------

func test_requirements_open_the_program_when_all_are_met() -> void:
	_use({"strong": _strong()})
	GameState.set_var("skill.hacking", 6)
	assert_false(Programs.is_installed("strong"), "навыка хватает, ранга нет")
	GameState.set_var("progress.rank", 3)
	assert_true(Programs.is_installed("strong"))


func test_every_requirement_matters() -> void:
	_use({"strong": _strong()})
	GameState.set_var("progress.rank", 3)
	GameState.set_var("skill.hacking", 5)
	assert_false(Programs.is_installed("strong"), "навыка не хватило на единицу")


func test_a_granted_flag_beats_unmet_requirements() -> void:
	# Набор ОС и награды выдают программу вне прогрессии.
	_use({"strong": _strong()})
	GameState.set_flag(Programs.flag_for("strong"))
	assert_true(Programs.is_installed("strong"))


func test_a_program_appears_the_moment_the_hero_grows() -> void:
	_use({"strong": _strong()})
	GameState.set_var("progress.rank", 3)
	assert_eq(Programs.installed().size(), 0)
	GameState.set_var("skill.hacking", 7)
	assert_eq(Programs.installed(), PackedStringArray(["strong"]))


func test_requirements_use_the_shared_condition_language() -> void:
	# Не только навык и ранг: любое условие, которое знает Conditions.
	_use({"night": {"kind": "recon", "minutes": "deepscan", "about": "x", "requires": [{"flag": "world.something"}]}})
	assert_false(Programs.is_installed("night"))
	GameState.set_flag("world.something")
	assert_true(Programs.is_installed("night"))


# --- В терминале -------------------------------------------------------------

func test_progs_and_help_show_programs_unlocked_by_requirements() -> void:
	var defs: Dictionary = Programs.definitions().duplicate(true)
	(defs["passhound"] as Dictionary)["requires"] = [{"skill_at_least": ["hacking", 3]}]
	_use(defs)
	assert_eq(run("progs"), "программ не найдено")
	GameState.set_var("skill.hacking", 3)
	assert_string_contains(run("progs"), "passhound")
	assert_string_contains(run("help"), "passhound")


func test_a_program_unlocked_by_skill_runs() -> void:
	var defs: Dictionary = Programs.definitions().duplicate(true)
	(defs["passhound"] as Dictionary)["requires"] = [{"skill_at_least": ["hacking", 3]}]
	_use(defs)
	reach_training_pc()
	run("connect 10.0.0.7")
	assert_eq(run("passhound"), "программа не установлена: passhound")
	GameState.set_var("skill.hacking", 3)
	run("passhound")
	assert_eq(last.request["type"], "puzzle")


func test_autocomplete_follows_availability() -> void:
	var defs: Dictionary = Programs.definitions().duplicate(true)
	(defs["passhound"] as Dictionary)["requires"] = [{"skill_at_least": ["hacking", 3]}]
	_use(defs)
	assert_eq(t.complete("pass")["line"], "pass")
	GameState.set_var("skill.hacking", 3)
	assert_eq(t.complete("pass")["line"], "passhound ")


# --- Проверка данных ---------------------------------------------------------

func _validate(programs: Dictionary) -> ProgramValidator:
	var validator := ProgramValidator.new()
	validator.validate(programs, DataLoader.balance())
	return validator


func test_real_programs_file_is_valid() -> void:
	var validator: ProgramValidator = _validate(DataLoader.programs())
	assert_eq(validator.errors.size(), 0, "\n".join(validator.errors))
	assert_eq(validator.warnings.size(), 0, "\n".join(validator.warnings))


func test_empty_programs_file_is_an_error() -> void:
	assert_gt(_validate({}).errors.size(), 0)


func test_unknown_kind_is_an_error() -> void:
	var program: Dictionary = _strong()
	program["kind"] = "magic"
	assert_string_contains("\n".join(_validate({"p": program}).errors), "magic")


func test_cracker_needs_a_known_puzzle() -> void:
	var program: Dictionary = _strong()
	program["puzzle"] = "sudoku"
	assert_string_contains("\n".join(_validate({"p": program}).errors), "головоломки")


func test_minutes_key_must_exist_in_balance() -> void:
	var program: Dictionary = _strong()
	program["minutes"] = "nope"
	assert_string_contains("\n".join(_validate({"p": program}).errors), "nope")


func test_unknown_condition_in_requires_is_an_error() -> void:
	var program: Dictionary = _strong()
	program["requires"] = [{"skill_atleast": ["hacking", 6]}]
	assert_string_contains("\n".join(_validate({"p": program}).errors), "skill_atleast")


func test_requires_must_be_a_list() -> void:
	var program: Dictionary = _strong()
	program["requires"] = {"skill_at_least": ["hacking", 6]}
	assert_gt(_validate({"p": program}).errors.size(), 0)


func test_missing_requires_is_a_warning() -> void:
	var program: Dictionary = _strong()
	program.erase("requires")
	var validator: ProgramValidator = _validate({"p": program})
	assert_eq(validator.errors.size(), 0)
	assert_eq(validator.warnings.size(), 1)


func test_auto_program_without_a_handler_is_a_warning() -> void:
	var program: Dictionary = {"kind": "auto", "minutes": "logwipe", "about": "x", "requires": []}
	assert_string_contains("\n".join(_validate({"unknown_auto": program}).warnings), "обработчика")
