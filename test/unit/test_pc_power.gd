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
