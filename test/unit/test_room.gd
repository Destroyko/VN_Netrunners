extends GutTest
## Инвентарь и комната: предметы в данных, эффекты, флешка-резерв
## (docs/gameplay/hacking.md, «Комната»; решено 13.11.2026).

const FLASH: String = "item_flash_backup"

var home: Filesystem


func before_each() -> void:
	GameState.reset()
	Filesystem.for_node(Network.HOME_ID)
	home = Filesystem.for_node(Network.HOME_ID)
	watch_signals(EventBus)


func _break_pc() -> void:
	home.remove("/", SystemFiles.FILE_X_SERVER, true, true)
	home.remove("/", SystemFiles.FILE_NET, true, true)


# --- Инвентарь ----------------------------------------------------------------

func test_hero_starts_with_nothing() -> void:
	assert_eq(Inventory.items().size(), 0)
	assert_false(Inventory.has(FLASH))


func test_item_comes_from_the_data_file() -> void:
	assert_true(Inventory.is_item(FLASH))
	assert_eq(Inventory.kind_of(FLASH), Inventory.KIND_RESTORE)
	assert_false(Inventory.is_item("_note"))


func test_give_and_take() -> void:
	assert_true(Inventory.give(FLASH))
	assert_true(Inventory.has(FLASH))
	assert_eq(Inventory.items(), PackedStringArray([FLASH]))
	assert_true(Inventory.take(FLASH))
	assert_false(Inventory.has(FLASH))
	assert_false(Inventory.take(FLASH), "забрать нечего")


func test_unknown_item_cannot_be_given() -> void:
	assert_false(Inventory.give("item_ghost"))
	assert_false(Inventory.has("item_ghost"))
	assert_push_error_count(1)


func test_item_is_an_instance_not_a_flag() -> void:
	Inventory.give(FLASH)
	assert_false(GameState.has_flag("item.flash_backup"), "с сейва v2 предмет — экземпляр в контейнере")
	assert_eq(Inventory.count(FLASH, Inventory.HERO), 1)


# --- Эффекты и условие --------------------------------------------------------

func test_give_item_effect_and_condition() -> void:
	assert_false(Conditions.check({"has_item": FLASH}))
	Effects.apply({"give_item": FLASH})
	assert_true(Conditions.check({"has_item": FLASH}))
	Effects.apply({"take_item": FLASH})
	assert_false(Conditions.check({"has_item": FLASH}))


func test_new_effect_and_condition_are_known_to_the_validator() -> void:
	assert_true(Effects.is_implemented("give_item"))
	assert_true(Conditions.is_known("has_item"))


# --- Монитор и системный блок -------------------------------------------------

func test_monitor_of_a_healthy_pc_opens_the_desktop() -> void:
	var report: Dictionary = Room.monitor(home)
	assert_true(bool(report["desktop"]))
	assert_eq((report["lines"] as PackedStringArray).size(), 0)


func test_monitor_of_a_broken_pc_shows_errors() -> void:
	_break_pc()
	var report: Dictionary = Room.monitor(home)
	assert_false(bool(report["desktop"]))
	assert_string_contains("\n".join(report["lines"] as PackedStringArray), "x-server.sys")


func test_old_os_does_not_boot_even_with_files() -> void:
	GameState.set_var(Terminal.VAR_OS, Terminal.OS_OLD)
	var report: Dictionary = Room.monitor(home)
	assert_false(bool(report["desktop"]))
	assert_string_contains("\n".join(report["lines"] as PackedStringArray), "операционная система")


func test_hardware_lists_the_os() -> void:
	assert_string_contains("\n".join(Room.hardware()), "normal")


# --- Флешка -------------------------------------------------------------------

func test_without_the_flash_nothing_is_fixed() -> void:
	_break_pc()
	var result: Dictionary = Room.use_item(FLASH, home)
	assert_false(bool(result["ok"]))
	assert_false(SystemFiles.has_desktop(home))


func test_flash_restores_system_files() -> void:
	_break_pc()
	Inventory.give(FLASH)
	var result: Dictionary = Room.use_item(FLASH, home)
	assert_true(bool(result["ok"]))
	assert_eq((result["restored"] as PackedStringArray).size(), 2)
	assert_true(SystemFiles.has_desktop(home))
	assert_true(SystemFiles.has_network(home))
	assert_signal_emitted(EventBus, "system_restored")


func test_flash_installs_the_normal_os_over_the_old_one() -> void:
	GameState.set_var(Terminal.VAR_OS, Terminal.OS_OLD)
	Inventory.give(FLASH)
	var result: Dictionary = Room.use_item(FLASH, home)
	assert_true(bool(result["os_changed"]))
	assert_eq(Room.os_level(), Terminal.OS_NORMAL)
	assert_true(bool(Room.monitor(home)["desktop"]))


func test_flash_never_downgrades_the_hacker_os() -> void:
	GameState.set_var(Terminal.VAR_OS, "hacker")
	Inventory.give(FLASH)
	Room.use_item(FLASH, home)
	assert_eq(Room.os_level(), "hacker")


func test_flash_does_not_touch_user_files() -> void:
	home.put_file("/home/notes.txt", {"text": "мои заметки"})
	_break_pc()
	Inventory.give(FLASH)
	Room.use_item(FLASH, home)
	assert_true(home.has_file("/home/notes.txt"))


func test_flash_is_not_consumed_and_works_again() -> void:
	Inventory.give(FLASH)
	_break_pc()
	Room.use_item(FLASH, home)
	_break_pc()
	assert_true(bool(Room.use_item(FLASH, home)["ok"]))
	assert_true(Inventory.has(FLASH))


func test_healthy_pc_has_nothing_to_fix() -> void:
	Inventory.give(FLASH)
	var result: Dictionary = Room.use_item(FLASH, home)
	assert_true(bool(result["ok"]))
	assert_string_contains("\n".join(result["lines"] as PackedStringArray), "чинить нечего")
	assert_signal_not_emitted(EventBus, "system_restored")


# --- Проверка данных ----------------------------------------------------------

func _validate(items: Dictionary) -> ItemValidator:
	var validator := ItemValidator.new()
	validator.validate(items)
	return validator


func test_real_items_file_is_valid() -> void:
	var validator: ItemValidator = _validate(DataLoader.items())
	assert_eq(validator.errors.size(), 0, "\n".join(validator.errors))
	assert_eq(validator.warnings.size(), 0)


func test_item_without_prefix_or_known_kind_is_an_error() -> void:
	var errors: String = "\n".join(_validate({"flash": {"kind": "magic", "name": "x", "about": "y"}}).errors)
	assert_string_contains(errors, "item_")
	assert_string_contains(errors, "magic")


func test_empty_items_file_is_an_error() -> void:
	assert_gt(_validate({}).errors.size(), 0)
