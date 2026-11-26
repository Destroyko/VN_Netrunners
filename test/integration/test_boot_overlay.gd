extends GutTest
## Экран своего ПК при выключении, загрузке и установке системы с флешки (шаг 7.5): виден, пока
## идут минуты под полоской; «Выключить питание» прерывает установку без последствий.

const FLASH: String = "item_flash_backup"


func before_each() -> void:
	GameState.reset()
	Clock.configure({"real_seconds_per_minute": 4, "program_speedup": 3, "program_min_minutes": 2})
	Clock.start()


func after_each() -> void:
	PcPower.abort_boot()
	Clock.stop()
	Clock.reload_config()


func _wait_until_done() -> void:
	for i: int in 400:
		if not Clock.is_fast_forwarding():
			break
		Clock.tick(0.5)
	BootOverlay._process(0.0)


func test_boot_screen_shows_while_booting() -> void:
	PcPower.shut_down()
	assert_eq(BootOverlay.mode(), BootOverlay.SHUTDOWN, "завершение работы")
	_wait_until_done()
	assert_eq(BootOverlay.mode(), "", "выключился — экрана нет")
	PcPower.power_on()
	assert_eq(BootOverlay.mode(), BootOverlay.BOOT)
	_wait_until_done()
	assert_true(PcPower.is_on())
	assert_eq(BootOverlay.mode(), "", "загрузился — экрана нет")


func test_install_screen_and_power_off() -> void:
	Inventory.give(FLASH)
	Room.insert(Inventory.first_uid(FLASH), Filesystem.for_node(Network.HOME_ID))
	GameState.set_var(Terminal.VAR_OS, Terminal.OS_OLD)
	PcPower.shut_down()
	_wait_until_done()
	PcPower.power_on()
	assert_eq(BootOverlay.mode(), BootOverlay.INSTALL, "флешка в гнезде — установка")
	assert_string_contains((BootOverlay.find_child("Text", true, false) as RichTextLabel).text, "USB")
	(BootOverlay.find_child("PowerOff", true, false) as Button).emit_signal("pressed")
	BootOverlay._process(0.0)
	assert_eq(BootOverlay.mode(), "", "выключил питание — экран погас")
	assert_false(PcPower.is_on())
	assert_eq(Room.os_level(), Terminal.OS_OLD, "ничего не поставлено")
