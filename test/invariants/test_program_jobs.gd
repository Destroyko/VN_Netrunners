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
	assert_false(Clock.is_fast_forwarding(), "ПК перезагружен: полоски нет, ввод открыт (И-11)")
	assert_false(t.has_job(), "программа на выключенном ПК не идёт")


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

## Передача идёт через полночь, автосейв пишет мир посреди полоски. После загрузки программы нет
## и итога нет; потраченные до сейва минуты остались — состояние согласовано (И-6).
func test_autosave_mid_transfer_loads_consistent_world() -> void:
	learn_programs()
	enter("node_job3_server")
	Clock.set_time(1, 23 * 60 + 55)
	_running_clock()
	var save_now: Callable = func(_day: int) -> void: SaveSystem.save(SaveSystem.SLOT_AUTO)
	EventBus.day_started.connect(save_now)
	run("cp /home/backup/2025-01-10.bak")
	assert_true(t.has_job(), "4200 КБ — 9 минут под полоской")
	Clock.tick(120.0)
	EventBus.day_started.disconnect(save_now)
	assert_false(t.has_job())
	assert_true(t.home_fs().has_file("/home/downloads/2025-01-10.bak"), "в игре передача дошла")

	Clock.stop()
	assert_eq(SaveSystem.load_slot(SaveSystem.SLOT_AUTO), "")
	assert_eq(GameState.day, 2)
	assert_eq(GameState.minute, 0, "сейв — на полуночи, посреди передачи")
	assert_false(Filesystem.for_node(Network.HOME_ID).has_file("/home/downloads/2025-01-10.bak"),
		"итога нет: файл не успел скачаться")
	assert_eq(HackSession.new(Network.for_game()).target_id(), "", "живое соединение сброшено")
	var fresh := Terminal.new()
	assert_false(fresh.has_job())
	assert_false(fresh.is_remote())
	assert_false(Clock.is_fast_forwarding(), "в главном меню часы остановлены — полоски нет")


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
