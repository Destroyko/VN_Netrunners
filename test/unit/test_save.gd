extends GutTest
## SaveSystem, SaveMigrations, SaveManager: запись и загрузка всего состояния, Rng, слоты,
## битые сейвы, миграции версий, автосейв (docs/tech/architecture.md, «Сохранения»).

const TEST_DIR: String = "user://test_saves"


func before_each() -> void:
	SaveSystem.dir = TEST_DIR
	_clean()
	GameState.reset()
	Clock.reload_config()


func after_each() -> void:
	_clean()
	SaveSystem.dir = SaveSystem.DEFAULT_DIR
	Clock.stop()


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(TEST_DIR):
		return
	for name: String in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR.path_join(name))


func _write_raw(slot: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file := FileAccess.open(SaveSystem.path_of(slot), FileAccess.WRITE)
	file.store_string(text)
	file.close()


# --- Запись и загрузка ----------------------------------------------------------

func test_save_and_load_restore_the_whole_world() -> void:
	GameState.set_money(321)
	GameState.set_flag("world.test_saved")
	Clock.set_time(3, 14 * 60)
	Needs.set_energy(42.0)
	Mailbox.deliver("mail_test_order")
	Quests.start("side_test_courier")
	Economy.earn(10, "Тест")
	assert_eq(SaveSystem.save(SaveSystem.SLOT_MANUAL), "")

	GameState.reset()
	assert_eq(GameState.money, 0)
	assert_eq(SaveSystem.load_slot(SaveSystem.SLOT_MANUAL), "")
	assert_eq(GameState.money, 331)
	assert_true(GameState.has_flag("world.test_saved"))
	assert_eq(GameState.day, 3)
	assert_eq(GameState.minute, 14 * 60)
	assert_almost_eq(Needs.energy(), 42.0, 0.001)
	assert_true(Quests.is_active("side_test_courier"), "квест продолжается с того же этапа")
	assert_eq(Economy.history().size(), 1, "история банка")
	assert_gt(Mailbox.inbox().size(), 0, "почта")


func test_rng_continues_the_same_sequence_after_load() -> void:
	Rng.set_seed(777)
	Rng.randi_range(0, 1000)
	Rng.stream("news").randi()
	SaveSystem.save(SaveSystem.SLOT_MANUAL)
	var expected_main: int = Rng.randi_range(0, 1000000)
	var expected_stream: int = Rng.stream("news").randi()
	Rng.set_seed(1)
	SaveSystem.load_slot(SaveSystem.SLOT_MANUAL)
	assert_eq(Rng.get_seed(), 777)
	assert_eq(Rng.randi_range(0, 1000000), expected_main, "общий поток — с того же места")
	assert_eq(Rng.stream("news").randi(), expected_stream, "именованный поток — тоже")


func test_live_connection_is_dropped_on_load() -> void:
	Effects.apply({"reveal_node": {"node": "node_training_pc", "open": ["svc_login"]}})
	var t := Terminal.new()
	t.execute("connect 10.0.0.7")
	assert_true(t.session.has_connection())
	SaveSystem.save(SaveSystem.SLOT_MANUAL)
	SaveSystem.load_slot(SaveSystem.SLOT_MANUAL)
	assert_false(Terminal.new().session.has_connection(), "после загрузки герой дома, не на узле")
	assert_true(Network.for_game().is_known("node_training_pc"), "адресная книга осталась")


func test_load_clears_stuck_pauses() -> void:
	SaveSystem.save(SaveSystem.SLOT_MANUAL)
	Clock.pause(PassOutCurtain.PAUSE_REASON)
	SaveSystem.load_slot(SaveSystem.SLOT_MANUAL)
	assert_false(Clock.is_paused())


# --- Слоты ----------------------------------------------------------------------

func test_latest_is_the_newest_slot() -> void:
	assert_eq(SaveSystem.latest(), "", "сейвов нет")
	SaveSystem.save(SaveSystem.SLOT_AUTO)
	SaveSystem.save(SaveSystem.SLOT_MANUAL)
	var all: Array = SaveSystem.list()
	assert_eq(all.size(), 2)
	assert_true(["auto", "manual"].has(SaveSystem.latest()))
	assert_true(((all[0] as Dictionary)["meta"] as Dictionary).has("date"), "в метаданных дата для меню")


func test_saving_again_overwrites_the_slot() -> void:
	GameState.set_money(1)
	SaveSystem.save(SaveSystem.SLOT_MANUAL)
	GameState.set_money(2)
	SaveSystem.save(SaveSystem.SLOT_MANUAL)
	SaveSystem.load_slot(SaveSystem.SLOT_MANUAL)
	assert_eq(GameState.money, 2)
	assert_false(FileAccess.file_exists(SaveSystem.path_of(SaveSystem.SLOT_MANUAL) + ".tmp"), "временный файл убран")


# --- Ошибки ---------------------------------------------------------------------

func test_missing_or_broken_save_keeps_current_game() -> void:
	GameState.set_money(50)
	assert_ne(SaveSystem.load_slot("nope"), "")
	_write_raw("broken", "{не json")
	assert_string_contains(SaveSystem.load_slot("broken"), "повреждён")
	assert_eq(GameState.money, 50, "текущая игра не тронута")
	assert_eq(SaveSystem.list().size(), 0, "битый сейв в списке не показывается")


func test_save_from_newer_version_is_refused() -> void:
	SaveSystem.save(SaveSystem.SLOT_MANUAL)
	var data: Dictionary = SaveSystem.read(SaveSystem.SLOT_MANUAL)["data"]
	(data["state"] as Dictionary)["version"] = GameState.SAVE_VERSION + 1
	_write_raw(SaveSystem.SLOT_MANUAL, JSON.stringify(data))
	assert_string_contains(SaveSystem.load_slot(SaveSystem.SLOT_MANUAL), "более новой версии")


# --- Миграции -------------------------------------------------------------------

func _times_ten(s: Dictionary) -> Dictionary:
	s["money"] = int(s.get("money", 0)) * 10
	return s


func _rename(s: Dictionary) -> Dictionary:
	s["renamed"] = true
	return s


func test_migrations_run_step_by_step() -> void:
	var steps: Dictionary = {1: _times_ten, 2: _rename}
	var got: Dictionary = SaveMigrations.migrate({"version": 1, "money": 5}, 3, steps)
	assert_true(bool(got["ok"]))
	var state: Dictionary = got["state"]
	assert_eq(int(state["money"]), 50)
	assert_true(bool(state["renamed"]))
	assert_eq(int(state["version"]), 3)


func test_missing_migration_step_is_an_error() -> void:
	var got: Dictionary = SaveMigrations.migrate({"version": 1}, 3, {1: _rename})
	assert_false(bool(got["ok"]))
	assert_string_contains(str(got["error"]), "версии 2")


func test_current_version_needs_no_migration() -> void:
	assert_true(bool(SaveMigrations.migrate(GameState.to_dict())["ok"]))


# --- Автосейв -------------------------------------------------------------------

func test_autosave_at_new_day_while_game_runs() -> void:
	Clock.start()
	Clock.set_time(1, 23 * 60 + 59)
	Clock.advance(1)
	await get_tree().process_frame
	assert_true(SaveSystem.exists(SaveSystem.SLOT_AUTO), "новый день — автосейв")


func test_no_autosave_outside_the_game() -> void:
	Clock.set_time(1, 23 * 60 + 59)
	Clock.advance(1)
	await get_tree().process_frame
	assert_false(SaveSystem.exists(SaveSystem.SLOT_AUTO), "часы не запущены (тест, отладка) — без автосейва")


func test_v1_items_and_pantry_move_to_containers() -> void:
	var old: Dictionary = {"version": 1, "flags": {"item.flash_backup": true, "story.x": true},
		"economy": {"pantry": {"food_noodles": 2}, "bills": []}}
	var got: Dictionary = SaveMigrations.migrate(old, 2)
	assert_true(bool(got["ok"]))
	var state: Dictionary = got["state"]
	var containers: Dictionary = (state["inventory"] as Dictionary)["containers"] as Dictionary
	assert_eq(str((containers["hero"][0] as Dictionary)["kind"]), "item_flash_backup", "флаг стал предметом")
	assert_eq((containers["fridge"] as Array).size(), 2, "запас — в холодильнике, по слоту на порцию")
	assert_false((state["flags"] as Dictionary).has("item.flash_backup"))
	assert_true((state["flags"] as Dictionary).has("story.x"), "чужие флаги на месте")
	assert_false((state["economy"] as Dictionary).has("pantry"))
	GameState.from_dict(state)
	assert_true(Inventory.has("item_flash_backup"))
	assert_eq(Inventory.count("food_noodles", Inventory.FRIDGE), 2)

