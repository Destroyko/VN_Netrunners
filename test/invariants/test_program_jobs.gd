extends "res://test/unit/terminal_fixture.gd"
## Программа под полоской на стыке с питанием ПК, автосейвом и действиями мышью
## (docs/tech/interactions.md, матрица; docs/issues.md: ISS-001, ISS-003, ISS-006).
## Часы запущены: минуты программы идут ускоренно, итог — в конце полоски (`Terminal.spend_then`).

const OpenIssue = preload("res://test/invariants/open_issue.gd")
const TEST_DIR: String = "user://test_saves_invariants"

var _autosave_was: bool = true


func before_each() -> void:
	super.before_each()
	_autosave_was = SaveManager.autosave_enabled
	# Автосейв SaveManager отложен до конца кадра и пишет в настоящий каталог: здесь сейв делаем сами.
	SaveManager.autosave_enabled = false
	SaveSystem.dir = TEST_DIR


func after_each() -> void:
	Clock.stop()
	Clock.reload_config()
	SaveManager.autosave_enabled = _autosave_was
	if DirAccess.dir_exists_absolute(TEST_DIR):
		for name: String in DirAccess.get_files_at(TEST_DIR):
			DirAccess.remove_absolute(TEST_DIR.path_join(name))
	SaveSystem.dir = SaveSystem.DEFAULT_DIR


func _running_clock() -> void:
	Clock.configure({"real_seconds_per_minute": 4, "program_speedup": 3, "program_min_minutes": 2})
	Clock.start()


func _now() -> int:
	return Network.for_game().abs_minute(GameState.day, GameState.minute)


# --- ISS-001: перезагрузка посреди программы ------------------------------------------

func test_reboot_mid_program_frees_the_console() -> void:
	learn_programs()
	enter("node_training_pc")
	_running_clock()
	run("rootstep")
	assert_true(t.has_job())
	PcPower.reboot()
	assert_false(t.has_job(), "программа на выключенном ПК не идёт (И-11)")
	assert_true(PcPower.is_booting(), "идут минуты загрузки, а не программы")
	Clock.tick(60.0)
	assert_true(PcPower.is_on(), "минуты загрузки прошли — ПК включён")
	assert_false(PcPower.is_booting())


func test_reboot_mid_program_gives_no_result() -> void:
	learn_programs()
	enter("node_training_pc")
	_running_clock()
	var got: Array = []
	t.job_finished.connect(func(r: TermResult) -> void: got.append(r.text()))
	run("rootstep")
	PcPower.reboot()
	Clock.tick(60.0)
	assert_false(Network.for_game().access.has_root("node_training_pc", _now()), "прав нет: соединение оборвано")
	assert_false(t.is_remote())
	assert_string_contains(str(got), "соединение прервано", "итог программы — обрыв, а не права")


# --- ISS-003: автосейв посреди полоски ---------------------------------------------------

## Передача идёт через полночь: посреди полоски сохранить нельзя, автосейв ждёт её конца и
## пишет мир уже с итогом (ISS-003, И-21).
func test_autosave_waits_for_the_program() -> void:
	learn_programs()
	enter("node_job3_server")
	Clock.set_time(1, 23 * 60 + 58)
	_running_clock()
	SaveManager.autosave_enabled = true
	run("cp /home/backup/2025-01-10.bak")
	assert_true(t.has_job(), "4200 КБ — 9 минут под полоской")
	assert_eq(SaveSystem.save(SaveSystem.SLOT_MANUAL), SaveSystem.BUSY_ERROR, "ручной сейв — нельзя")
	Clock.tick(5.0)
	assert_eq(GameState.day, 2, "полночь прошла посреди полоски")
	assert_true(t.has_job())
	await wait_frames(1)
	assert_false(FileAccess.file_exists(SaveSystem.path_of(SaveSystem.SLOT_AUTO)), "автосейв ждёт")
	Clock.tick(120.0)
	assert_false(t.has_job())
	await wait_frames(2)
	SaveManager.autosave_enabled = false
	Clock.stop()
	assert_eq(SaveSystem.load_slot(SaveSystem.SLOT_AUTO), "")
	assert_true(Filesystem.for_node(Network.HOME_ID).has_file("/home/downloads/2025-01-10.bak"),
		"сейв — после полоски, с итогом")


# --- ISS-006: вторая команда посреди программы --------------------------------------------

## Действие мышью (перетащить файл из трансляции, «Вставить» на столе) идёт в консоль через
## `TerminalView.submit` — мимо закрытой строки ввода. Вторая программа не должна молча отменять
## итог первой.
func test_second_program_does_not_drop_the_first_result() -> void:
	learn_programs()
	enter("node_training_pc")
	Effects.apply({"add_file": {"node": "node_training_pc", "path": "/home/big.bin", "size_kb": 2000}})
	_running_clock()
	run("rootstep")
	assert_eq(t.execute("cp /home/big.bin").text(), Terminal.BUSY_TEXT, "вторая команда — отказ")
	assert_eq(t.execute_local("rm /home/desktop/x").text(), Terminal.BUSY_TEXT, "окно «Файлы» — тоже")
	Clock.tick(120.0)
	assert_true(Network.for_game().access.has_root("node_training_pc", _now()),
		"rootstep дошёл до конца полоски — права есть")


# --- ISS-002: программа во сне ------------------------------------------------------------

## Герой уснул посреди программы: минуты сна — её минуты, итог в ту же минуту, когда она дошла.
func test_program_finishes_during_sleep() -> void:
	learn_programs()
	enter("node_training_pc")
	_running_clock()
	var got: Array = []
	t.job_finished.connect(func(r: TermResult) -> void: got.append(r.text()))
	run("rootstep")
	assert_true(t.has_job())
	Rest.pass_time(60, Rest.MODE_SLEEP)
	assert_false(t.has_job(), "программа дошла во сне")
	assert_false(Clock.is_fast_forwarding(), "проснулся — полоски нет, ввод открыт")
	assert_true(Network.for_game().access.has_root("node_training_pc", _now()), "итог применён")
	assert_string_contains(str(got), "права администратора получены")


## Трейс дотикал во сне раньше конца передачи: файла нет.
func test_trace_cuts_the_program_during_sleep() -> void:
	learn_programs()
	GameState.set_flag(Programs.GATE_PRESSURE)
	reveal("node_office_server", ["svc_admin_login"])
	Clock.set_time(1, 10 * 60)
	run("connect 77.61.204.12")
	run("gridrunner 1194")
	solve_puzzle()
	assert_true(t.session.is_tracing())
	Effects.apply({"add_file": {"node": "node_office_server", "path": "/home/big.bin", "size_kb": 400000}})
	_running_clock()
	run("cp /home/big.bin")
	assert_true(t.has_job())
	Rest.pass_time(600, Rest.MODE_WAIT)
	assert_false(t.has_job())
	assert_false(t.home_fs().has_file("/home/downloads/big.bin"), "трейс оборвал раньше — файла нет")
	assert_false(t.is_remote())
