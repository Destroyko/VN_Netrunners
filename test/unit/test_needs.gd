extends GutTest
## Needs и NeedsManager: энергия и сытость во времени, реплики, вырубание
## (docs/gameplay/needs.md).

const HOUR: int = 60

var _warned: Array[String] = []
var _passed_out: int = 0


func before_each() -> void:
	GameState.reset()
	Clock.reload_config()
	NeedsManager.always_on = true
	_warned.clear()
	_passed_out = 0
	EventBus.need_warned.connect(_on_warned)
	EventBus.passed_out.connect(_on_passed_out)


func after_each() -> void:
	NeedsManager.always_on = false
	EventBus.need_warned.disconnect(_on_warned)
	EventBus.passed_out.disconnect(_on_passed_out)


func _on_warned(kind: String) -> void:
	_warned.append(kind)


func _on_passed_out() -> void:
	_passed_out += 1


# --- Шкалы ----------------------------------------------------------------------

func test_new_game_starts_with_values_from_balance() -> void:
	assert_eq(Needs.energy(), 80.0)
	assert_eq(Needs.satiety(), 70.0)
	assert_eq(Needs.energy_max(), 100.0)


func test_awake_energy_and_satiety_melt_slowly() -> void:
	Needs.set_satiety(50.0)  # обычная сытость: без множителей
	Clock.advance(10 * HOUR)
	assert_almost_eq(Needs.energy(), 60.0, 0.01, "2 в час за ПК")
	assert_almost_eq(Needs.satiety(), 20.0, 0.01, "3 в час")


func test_full_energy_lasts_about_two_days_awake() -> void:
	Needs.set_energy(100.0)
	Needs.set_satiety(50.0)
	assert_almost_eq(Needs.hours_left(), 50.0, 0.01)


func test_sleep_restores_energy() -> void:
	Needs.set_energy(20.0)
	Needs.set_satiety(50.0)
	Clock.set_time(1, 22 * HOUR)
	Rest.sleep_until(2 * HOUR)
	assert_almost_eq(Needs.energy(), 68.0, 0.01, "12 в час во сне")


func test_energy_never_goes_above_max() -> void:
	Needs.set_energy(95.0)
	Clock.set_time(1, 22 * HOUR)
	Rest.sleep_until(8 * HOUR)
	assert_eq(Needs.energy(), 100.0)


func test_waiting_is_not_sleep() -> void:
	Needs.set_energy(50.0)
	Needs.set_satiety(50.0)
	Clock.set_time(1, 22 * HOUR)
	Rest.wait_until(23 * HOUR)
	assert_almost_eq(Needs.energy(), 48.0, 0.01)


func test_fed_hero_melts_slower_and_rests_better() -> void:
	Needs.set_satiety(90.0)
	assert_eq(Needs.band(), Needs.BAND_FED)
	assert_almost_eq(Needs.drain_per_hour(), 1.6, 0.001)
	assert_almost_eq(Needs.restore_per_hour(), 14.4, 0.001)


func test_hungry_hero_melts_faster_and_rests_worse() -> void:
	Needs.set_satiety(10.0)
	assert_eq(Needs.band(), Needs.BAND_HUNGRY)
	assert_almost_eq(Needs.drain_per_hour(), 3.0, 0.001)
	assert_almost_eq(Needs.restore_per_hour(), 6.0, 0.001)


func test_eating_fills_satiety_up_to_max() -> void:
	Needs.set_satiety(80.0)
	Needs.eat(50.0)
	assert_eq(Needs.satiety(), 100.0)


func test_satiety_stops_at_zero() -> void:
	Needs.set_satiety(1.0)
	Clock.advance(5 * HOUR)
	assert_eq(Needs.satiety(), 0.0)


# --- Реплики --------------------------------------------------------------------

func test_warns_once_when_two_hours_left() -> void:
	Needs.set_satiety(50.0)
	Needs.set_energy(4.2)  # 2.1 часа
	Clock.advance(5)
	assert_eq(_warned, [] as Array[String])
	Clock.advance(10)
	assert_eq(_warned, [Needs.EVENT_ENERGY_LOW] as Array[String])
	Clock.advance(30)
	assert_eq(_warned.size(), 1, "одна реплика, не спам")


func test_warning_repeats_after_rest() -> void:
	Needs.set_satiety(50.0)
	Needs.set_energy(3.0)
	Clock.advance(1)
	Clock.set_time(1, 22 * HOUR)
	Rest.sleep_until(6 * HOUR)
	Needs.set_energy(3.0)
	Clock.advance(1)
	assert_eq(_warned.count(Needs.EVENT_ENERGY_LOW), 2)


func test_hunger_thought_once_a_day() -> void:
	Needs.set_satiety(20.5)
	Clock.advance(20)
	Clock.advance(60)
	assert_eq(_warned.count(Needs.EVENT_HUNGRY), 1)
	Clock.advance(24 * HOUR)
	assert_eq(_warned.count(Needs.EVENT_HUNGRY), 2, "на следующие сутки — снова")


func test_nothing_is_counted_outside_the_game() -> void:
	NeedsManager.always_on = false
	Clock.advance(10 * HOUR)
	assert_eq(Needs.energy(), 80.0, "тесты и отладочные сцены двигают часы без потребностей")


# --- Вырубание ------------------------------------------------------------------

func test_zero_energy_passes_out_and_sleeps_until_full() -> void:
	Needs.set_satiety(50.0)
	Needs.set_energy(0.5)
	Clock.set_time(1, 14 * HOUR)
	Clock.advance(20)
	assert_eq(Needs.energy(), 0.0)
	await get_tree().process_frame
	assert_eq(_passed_out, 1)
	assert_eq(Needs.energy(), 100.0, "сон до полного восстановления, без будильника")
	assert_gt(Clock.total_minutes(), 14 * HOUR + 8 * HOUR, "проспал несколько часов")


func test_pass_out_interrupts_waiting() -> void:
	Needs.set_satiety(50.0)
	Needs.set_energy(1.0)
	Clock.set_time(1, 10 * HOUR)
	var report: Dictionary = Rest.wait_until(22 * HOUR)
	assert_eq(str(report["interrupted"]), "вырубился")
	assert_lt(int(report["minutes"]), 60)
	await get_tree().process_frame
	assert_eq(_passed_out, 1)


func test_pass_out_leaves_hack_session_running() -> void:
	# ПК сам ничего не делает: трейс на чужом узле идёт, пока герой спит.
	var minutes: Dictionary = {"n": 0}
	var spy := func(_m: int, passed: int) -> void: minutes["n"] += passed
	Needs.set_satiety(50.0)
	Needs.set_energy(0.1)
	Clock.advance(5)
	EventBus.time_advanced.connect(spy)
	await get_tree().process_frame
	EventBus.time_advanced.disconnect(spy)
	assert_gt(int(minutes["n"]), 8 * HOUR, "все, кто слушает часы, видят каждую минуту сна")


func test_hungry_pass_out_is_capped() -> void:
	Needs.set_satiety(0.0)
	var report: Dictionary = Rest.sleep_until_rested()
	assert_lte(int(report["minutes"]), 1440)


func test_needs_console_command() -> void:
	assert_string_contains(DebugCommands.run("needs"), "энергия: 80.0")
	DebugCommands.run("needs energy =10")
	assert_eq(Needs.energy(), 10.0)
	DebugCommands.run("needs satiety -20")
	assert_eq(Needs.satiety(), 50.0)
	assert_string_contains(DebugCommands.run("needs food 3"), "needs:")
