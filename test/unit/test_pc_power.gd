extends "res://test/unit/terminal_fixture.gd"
## PcPower: выключить, включить, перезагрузить свой ПК — одно правило для меню стола, кнопки в
## комнате и `reboot` (docs/gameplay/hacking.md, «Комната»).

var _changes: Array[bool] = []


func before_each() -> void:
	super.before_each()
	_changes.clear()
	EventBus.pc_power_changed.connect(_on_power)


func after_each() -> void:
	EventBus.pc_power_changed.disconnect(_on_power)


func _on_power(on: bool) -> void:
	_changes.append(on)


func test_pc_is_on_in_a_new_game() -> void:
	assert_true(PcPower.is_on())


func test_shut_down_and_power_on() -> void:
	PcPower.shut_down()
	assert_false(PcPower.is_on())
	assert_eq(_changes, [false] as Array[bool])
	PcPower.power_on()
	assert_true(PcPower.is_on())
	assert_eq(_changes, [false, true] as Array[bool], "загрузка — сигнал стола собраться заново")


func test_shut_down_drops_connection_like_dc() -> void:
	enter("node_training_pc")
	assert_true(t.session.has_connection())
	var report: Dictionary = PcPower.shut_down()
	assert_eq(str(report["node"]), "node_training_pc")
	assert_false(t.session.has_connection(), "выключил — связь оборвана")
	assert_signal_emitted(EventBus, "node_disconnected", "как dc: заметность за следы посчитается")


func test_shut_down_stops_background_tasks() -> void:
	t.home_fs().put_file("/home/downloads/arhiv.enc", {"encrypted": true, "locked": {"text": "x"}})
	BackgroundTasks.start_decrypt("/home/downloads/arhiv.enc")
	assert_eq(int(PcPower.shut_down()["stopped"]), 1)
	assert_eq(BackgroundTasks.tasks().size(), 0)


func test_boot_takes_time_and_applies_theme() -> void:
	t.home_fs().put_file("/sys/theme.sys", {"system": true, "file_id": "theme_corp"})
	PcPower.shut_down()
	var before: int = Clock.total_minutes()
	var report: Dictionary = PcPower.power_on()
	assert_eq(Clock.total_minutes() - before, int((DataLoader.balance()["pc"] as Dictionary)["boot_minutes"]))
	assert_true(bool(report["theme_changed"]))


func test_power_state_is_saved() -> void:
	PcPower.shut_down()
	var saved: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(saved)
	assert_false(PcPower.is_on())


func test_terminal_reboot_goes_through_pc_power() -> void:
	run("reboot")
	assert_true(PcPower.is_on(), "перезагрузка — снова включён")
	assert_eq(_changes, [false, true] as Array[bool])


# --- Установка с резервной флешки (шаг 7.5) --------------------------------------------

const FLASH: String = "item_flash_backup"


func _home() -> Filesystem:
	return Filesystem.for_node(Network.HOME_ID)


func _old_os_with_flash_inserted() -> void:
	GameState.set_var(Terminal.VAR_OS, Terminal.OS_OLD)
	Inventory.give(FLASH)
	assert_true(bool(Room.insert(Inventory.first_uid(FLASH), _home())["ok"]))


func test_inserting_the_flash_installs_nothing() -> void:
	_old_os_with_flash_inserted()
	assert_eq(Room.os_level(), Terminal.OS_OLD, "вставка сама ничего не ставит")


func test_power_on_with_the_flash_installs_the_system() -> void:
	_old_os_with_flash_inserted()
	PcPower.shut_down()
	var before: int = Clock.total_minutes()
	var report: Dictionary = PcPower.power_on()
	assert_true(bool(report.get("installed", false)))
	assert_eq(Room.os_level(), Terminal.OS_NORMAL)
	assert_eq(Clock.total_minutes() - before, PcPower.install_minutes(), "установка — 30 минут")
	assert_true(PcPower.is_on())


func test_forgotten_flash_installs_again_on_every_boot() -> void:
	_old_os_with_flash_inserted()
	PcPower.reboot()
	var report: Dictionary = PcPower.reboot()
	assert_true(bool(report.get("installed", false)), "флешку не вынули — снова установка")
	Room.eject()
	assert_false(bool(PcPower.reboot().get("installed", false)), "вынул — обычная загрузка")


func test_power_off_mid_install_changes_nothing() -> void:
	_old_os_with_flash_inserted()
	PcPower.shut_down()
	Clock.configure({"real_seconds_per_minute": 4, "program_speedup": 3, "program_min_minutes": 2})
	Clock.start()
	Clock.tick(10.0)
	var report: Dictionary = PcPower.power_on()
	assert_true(bool(report.get("pending", false)))
	assert_true(PcPower.is_booting())
	Clock.tick(5.0)
	PcPower.abort_boot()
	assert_false(PcPower.is_booting())
	assert_false(PcPower.is_on(), "выключили посреди установки")
	assert_eq(Room.os_level(), Terminal.OS_OLD, "ничего не поставлено")
	Room.eject()
	PcPower.power_on()
	Clock.tick(60.0)
	Clock.stop()
	Clock.reload_config()
	assert_true(PcPower.is_on(), "вынул флешку — ПК загрузился как был")
	assert_eq(Room.os_level(), Terminal.OS_OLD)
