extends GutTest
## HackSession: цель, подключение, трейс, отключение (docs/gameplay/hacking.md, «Трейс»).

const BALANCE: Dictionary = {
	"clock": {"minutes_per_day": 1440},
	"nodes": {"offline_days_after_sabotage": 3},
	"puzzles": {"services_reset_days": 7, "alert_difficulty_step": 1},
}

var net: Network
var session: HackSession
var state: Dictionary


func _definitions() -> Dictionary:
	return {
		"node_home_pc": {
			"id": "node_home_pc", "title": "Мой ПК", "address": "localhost",
			"known_from_start": true, "links": ["node_lab", "node_office", "node_free"], "services": [],
		},
		"node_lab": {
			"id": "node_lab", "title": "Учебный ПК", "address": "10.0.0.7",
			"links": ["node_home_pc"], "required_services": 1, "trace_minutes": 0,
			"services": [{
				"id": "svc_login", "name": "Вход", "puzzle": "password",
				"program": "passhound", "difficulty": 1,
			}],
		},
		"node_office": {
			"id": "node_office", "title": "Сервер фирмы", "address": "77.0.0.12",
			"links": ["node_home_pc"], "required_services": 2, "trace_minutes": 60,
			"online": {"from": "08:00", "to": "18:00"},
			"services": [
				{"id": "svc_login", "name": "Вход", "puzzle": "password", "program": "passhound", "difficulty": 2},
				{"id": "svc_fw", "name": "Фаервол", "puzzle": "matrix", "program": "gridrunner", "difficulty": 2},
			],
		},
		"node_free": {
			"id": "node_free", "title": "Открытый узел", "address": "10.0.0.50",
			"links": ["node_home_pc"], "required_services": 0, "trace_minutes": 0, "services": [],
		},
	}


func before_each() -> void:
	state = {}
	net = Network.new(_definitions(), state, BALANCE)
	session = HackSession.new(net)
	net.scan("node_home_pc")


func _at(day: int, hours: int, minutes: int = 0) -> int:
	return net.abs_minute(day, hours * 60 + minutes)


## Вскрыть оба сервиса офиса и войти: обычное начало взлома под трейсом.
func _enter_office(now: int) -> void:
	session.connect_to("77.0.0.12", now)
	session.begin_cracking("svc_login", "passhound", now, true)
	session.crack("svc_login", now)
	session.begin_cracking("svc_fw", "gridrunner", now, true)
	session.crack("svc_fw", now)
	session.connect_to("77.0.0.12", now)


# --- connect -----------------------------------------------------------------

func test_connect_to_unknown_address_fails() -> void:
	var result: NetResult = session.connect_to("5.5.5.5", _at(1, 9))
	assert_eq(result.code, NetResult.Code.UNKNOWN_ADDRESS)
	assert_false(session.has_connection())


func test_connect_to_own_pc_is_refused() -> void:
	assert_eq(session.connect_to("localhost", _at(1, 9)).code, NetResult.Code.LOCAL)


func test_connect_outside_prime_time_is_refused() -> void:
	var result: NetResult = session.connect_to("77.0.0.12", _at(1, 22))
	assert_eq(result.code, NetResult.Code.OFFLINE)
	assert_eq(result.message(), "узел не в сети")
	assert_eq(session.target_id(), "", "цель не выбрана: узел спит")


func test_connect_with_open_services_left_is_denied_with_progress() -> void:
	var result: NetResult = session.connect_to("77.0.0.12", _at(1, 9))
	assert_eq(result.code, NetResult.Code.SERVICES_LEFT)
	assert_eq(result.message(), "узел отказал: вскрыто 0 из 2 сервисов")


func test_denied_connect_still_picks_the_target() -> void:
	# Иначе программе-взломщику было бы не на что целиться.
	session.connect_to("10.0.0.7", _at(1, 9))
	assert_eq(session.target_id(), "node_lab")
	assert_false(session.has_connection(), "внутрь не пустили")
	assert_eq(session.current_id(), Network.HOME_ID, "терминал всё ещё дома")


func test_connect_after_cracking_lets_in() -> void:
	session.connect_to("10.0.0.7", _at(1, 9))
	session.crack("svc_login", _at(1, 9))
	var result: NetResult = session.connect_to("10.0.0.7", _at(1, 9))
	assert_true(result.is_ok())
	assert_true(session.has_connection())
	assert_eq(session.current_id(), "node_lab")


func test_node_without_services_opens_at_once() -> void:
	assert_true(session.connect_to("10.0.0.50", _at(1, 9)).is_ok())


func test_first_hack_is_reported_once() -> void:
	session.connect_to("10.0.0.50", _at(1, 9))
	session.disconnect_now()
	var again: NetResult = session.connect_to("10.0.0.50", _at(1, 10))
	assert_false(again.first_hack, "второй заход — не первый взлом")


func test_first_connect_marks_first_hack() -> void:
	assert_true(session.connect_to("10.0.0.50", _at(1, 9)).first_hack)
	assert_true(net.has_hacked("node_free"))


func test_connecting_twice_says_so() -> void:
	session.connect_to("10.0.0.50", _at(1, 9))
	assert_eq(session.connect_to("10.0.0.50", _at(1, 9)).code, NetResult.Code.ALREADY_CONNECTED)


func test_hop_to_another_node_closes_the_previous_hack() -> void:
	session.connect_to("10.0.0.50", _at(1, 9))
	session.connect_to("10.0.0.7", _at(1, 9))
	assert_eq(session.target_id(), "node_lab")
	assert_false(session.has_connection(), "к новому узлу ещё не пустили")


func test_failed_hop_keeps_the_old_session() -> void:
	# Узел вне сети не должен выбивать игрока из текущего взлома.
	session.connect_to("10.0.0.50", _at(1, 22))
	session.connect_to("77.0.0.12", _at(1, 22))
	assert_eq(session.target_id(), "node_free")
	assert_true(session.has_connection())


# --- dc ----------------------------------------------------------------------

func test_dc_without_connection() -> void:
	var result: NetResult = session.disconnect_now()
	assert_eq(result.code, NetResult.Code.NOT_CONNECTED)
	assert_eq(result.message(), "ты ни к чему не подключён")


func test_dc_closes_the_connection() -> void:
	session.connect_to("10.0.0.50", _at(1, 9))
	var result: NetResult = session.disconnect_now()
	assert_true(result.is_ok())
	assert_true(result.was_connected, "терминал пошлёт node_disconnected")
	assert_false(session.has_connection())
	assert_eq(session.current_id(), Network.HOME_ID)


func test_dc_before_connecting_gives_up_the_target() -> void:
	# Игрок решил отказаться от цели: событие node_disconnected не нужно.
	session.connect_to("77.0.0.12", _at(1, 9))
	var result: NetResult = session.disconnect_now()
	assert_true(result.is_ok())
	assert_false(result.was_connected)
	assert_eq(session.target_id(), "")


func test_dc_keeps_cracked_services() -> void:
	# Добровольный dc прогресс сохраняет: сбрасывает только доведённый трейс (puzzles-spec.md).
	session.connect_to("77.0.0.12", _at(1, 9))
	session.begin_cracking("svc_login", "passhound", _at(1, 9), true)
	session.crack("svc_login", _at(1, 9))
	session.disconnect_now()
	var result: NetResult = session.connect_to("77.0.0.12", _at(1, 10))
	assert_eq(result.code, NetResult.Code.SERVICES_LEFT)
	assert_eq(result.cracked, 1, "первый слой остался вскрыт")


# --- Программы-взломщики -----------------------------------------------------

func test_cracker_needs_a_target() -> void:
	var result: NetResult = session.begin_cracking("svc_login", "passhound", _at(1, 9), true)
	assert_eq(result.code, NetResult.Code.NO_TARGET)
	assert_string_contains(result.message(), "connect")


func test_cracker_rejects_unknown_service() -> void:
	session.connect_to("10.0.0.7", _at(1, 9))
	var result: NetResult = session.begin_cracking("svc_nope", "passhound", _at(1, 9), true)
	assert_eq(result.code, NetResult.Code.NO_SUCH_SERVICE)
	assert_string_contains(result.message(), "svc_nope")


func test_cracker_must_match_the_defence() -> void:
	session.connect_to("77.0.0.12", _at(1, 9))
	var result: NetResult = session.begin_cracking("svc_fw", "passhound", _at(1, 9), true)
	assert_eq(result.code, NetResult.Code.WRONG_PROGRAM)
	assert_eq(result.message(), "passhound не работает против этой защиты")
	assert_false(session.is_tracing(), "ошибка ввода трейс не запускает")


func test_cracker_refuses_already_open_service() -> void:
	session.connect_to("10.0.0.7", _at(1, 9))
	session.crack("svc_login", _at(1, 9))
	var result: NetResult = session.begin_cracking("svc_login", "passhound", _at(1, 9), true)
	assert_eq(result.code, NetResult.Code.ALREADY_CRACKED)


func test_crack_without_target_fails() -> void:
	assert_eq(session.crack("svc_login", _at(1, 9)).code, NetResult.Code.NO_TARGET)


func test_crack_reports_progress() -> void:
	session.connect_to("77.0.0.12", _at(1, 9))
	var result: NetResult = session.crack("svc_login", _at(1, 9))
	assert_eq(result.cracked, 1)
	assert_eq(result.required, 2)


# --- Старт трейса ------------------------------------------------------------

func test_first_cracker_starts_the_trace() -> void:
	session.connect_to("77.0.0.12", _at(1, 9))
	var result: NetResult = session.begin_cracking("svc_login", "passhound", _at(1, 9), true)
	assert_true(result.trace_started, "терминал пошлёт trace_started")
	assert_true(session.is_tracing())
	assert_eq(session.trace_left(), 60)


func test_connect_and_probe_do_not_start_the_trace() -> void:
	# Трейс начинается с первого взломщика, а не с connect и не с разведки (hacking.md).
	net.probe("77.0.0.12", _at(1, 9))
	session.connect_to("77.0.0.12", _at(1, 9))
	assert_false(session.is_tracing())


func test_second_cracker_does_not_restart_the_trace() -> void:
	session.connect_to("77.0.0.12", _at(1, 9))
	session.begin_cracking("svc_login", "passhound", _at(1, 9), true)
	session.advance(20, _at(1, 9, 20))
	session.crack("svc_login", _at(1, 9, 20))
	var second: NetResult = session.begin_cracking("svc_fw", "gridrunner", _at(1, 9, 20), true)
	assert_false(second.trace_started)
	assert_eq(session.trace_left(), 40, "отсчёт продолжается")


func test_no_trace_before_the_group_era() -> void:
	# Ворота давления закрыты: узлы с трейсом тоже безопасны (heat.md).
	session.connect_to("77.0.0.12", _at(1, 9))
	var result: NetResult = session.begin_cracking("svc_login", "passhound", _at(1, 9), false)
	assert_false(result.trace_started)
	assert_false(session.is_tracing())


func test_node_without_trace_never_traces() -> void:
	session.connect_to("10.0.0.7", _at(1, 9))
	var result: NetResult = session.begin_cracking("svc_login", "passhound", _at(1, 9), true)
	assert_false(result.trace_started)


func test_trace_does_not_run_without_a_target() -> void:
	assert_eq(session.advance(30, _at(1, 9, 30)).size(), 0)
	assert_false(session.is_tracing())


# --- Ход трейса --------------------------------------------------------------

func _types(events: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for event: Dictionary in events:
		result.append(str(event["type"]))
	return result


func test_trace_counts_down_in_game_minutes() -> void:
	session.connect_to("77.0.0.12", _at(1, 9))
	session.begin_cracking("svc_login", "passhound", _at(1, 9), true)
	session.advance(8, _at(1, 9, 8))
	assert_eq(session.trace_left(), 52)


func test_trace_warns_at_half_and_in_the_last_quarter() -> void:
	session.connect_to("77.0.0.12", _at(1, 9))
	session.begin_cracking("svc_login", "passhound", _at(1, 9), true)
	assert_eq(_types(session.advance(20, _at(1, 9, 20))), [] as Array[String])
	assert_eq(_types(session.advance(10, _at(1, 9, 30))), ["trace_half"] as Array[String])
	assert_eq(_types(session.advance(14, _at(1, 9, 44))), [] as Array[String])
	assert_eq(_types(session.advance(2, _at(1, 9, 46))), ["trace_last_quarter"] as Array[String])


func test_one_long_step_gives_both_warnings_in_order() -> void:
	session.connect_to("77.0.0.12", _at(1, 9))
	session.begin_cracking("svc_login", "passhound", _at(1, 9), true)
	var events: Array[Dictionary] = session.advance(50, _at(1, 9, 50))
	assert_eq(_types(events), ["trace_half", "trace_last_quarter"] as Array[String])


func test_finished_trace_ends_the_hack() -> void:
	_enter_office(_at(1, 9))
	var events: Array[Dictionary] = session.advance(60, _at(1, 10))
	assert_eq(_types(events), ["trace_finished"] as Array[String])
	assert_eq(events[0]["node"], "node_office")
	assert_true(bool(events[0]["was_connected"]))
	assert_false(session.has_connection(), "обрыв")
	assert_false(session.is_tracing())
	assert_eq(session.target_id(), "")


func test_finished_trace_resets_services_and_alerts_the_target() -> void:
	_enter_office(_at(1, 9))
	session.advance(60, _at(1, 10))
	assert_eq(net.cracked_count("node_office", _at(1, 10)), 0, "слои сброшены")
	assert_eq(net.alert_level("node_office"), 1, "цель осторожнее")
	assert_eq(net.effective_difficulty("node_office", 2), 3, "+1 к сложности")


func test_after_finished_trace_the_node_must_be_cracked_again() -> void:
	_enter_office(_at(1, 9))
	session.advance(60, _at(1, 10))
	var result: NetResult = session.connect_to("77.0.0.12", _at(1, 10, 5))
	assert_eq(result.code, NetResult.Code.SERVICES_LEFT)
	assert_eq(result.cracked, 0)


func test_finished_trace_keeps_the_hacked_record() -> void:
	_enter_office(_at(1, 9))
	session.advance(60, _at(1, 10))
	assert_true(net.has_hacked("node_office"))


func test_trace_finishing_before_connect_still_resets() -> void:
	# Трейс идёт и пока игрок не вошёл: цель выбрана, взломщик запущен.
	session.connect_to("77.0.0.12", _at(1, 9))
	session.begin_cracking("svc_login", "passhound", _at(1, 9), true)
	session.crack("svc_login", _at(1, 9))
	var events: Array[Dictionary] = session.advance(60, _at(1, 10))
	assert_false(bool(events[0]["was_connected"]))
	assert_eq(net.cracked_count("node_office", _at(1, 10)), 0)


func test_dc_stops_the_trace() -> void:
	_enter_office(_at(1, 9))
	session.advance(30, _at(1, 9, 30))
	session.disconnect_now()
	assert_false(session.is_tracing())
	assert_eq(session.advance(60, _at(1, 10, 30)).size(), 0, "конца трейса не будет")
	assert_eq(net.alert_level("node_office"), 0, "доброволец не настораживает цель")


func test_new_hack_starts_a_fresh_trace() -> void:
	_enter_office(_at(1, 9))
	session.advance(30, _at(1, 9, 30))
	session.disconnect_now()
	# Через неделю защита перенастроилась: сервисы снова закрыты, и взлом начинается заново.
	net.reset_services("node_office")
	session.connect_to("77.0.0.12", _at(1, 9, 40))
	session.begin_cracking("svc_login", "passhound", _at(1, 9, 40), true)
	assert_eq(session.trace_left(), 60, "новый заход — новый трейс")


# --- Обрыв по расписанию -----------------------------------------------------

func test_prime_time_ending_drops_the_connection() -> void:
	_enter_office(_at(1, 17, 50))
	var events: Array[Dictionary] = session.advance(20, _at(1, 18, 10))
	assert_eq(_types(events), ["connection_lost"] as Array[String])
	assert_false(session.has_connection())
	assert_false(session.is_tracing(), "трейс остановлен")


func test_dropped_connection_keeps_progress_and_does_not_alert() -> void:
	# Предложение из network.md: как при dc, прогресс сохраняется.
	_enter_office(_at(1, 17, 50))
	session.advance(20, _at(1, 18, 10))
	assert_eq(net.cracked_count("node_office", _at(1, 18, 10)), 2)
	assert_eq(net.alert_level("node_office"), 0)


func test_advance_inside_prime_time_changes_nothing() -> void:
	_enter_office(_at(1, 9))
	assert_eq(session.advance(5, _at(1, 9, 5)).size(), 0)
	assert_true(session.has_connection())


func test_prime_time_beats_trace_when_both_happen_at_once() -> void:
	# За один шаг и ушёл узел, и кончился трейс: считаем в пользу игрока.
	_enter_office(_at(1, 17, 40))
	var events: Array[Dictionary] = session.advance(60, _at(1, 18, 40))
	assert_eq(_types(events), ["connection_lost"] as Array[String])
	assert_eq(net.alert_level("node_office"), 0)


# --- Саботаж -----------------------------------------------------------------

func test_sabotage_while_connected_drops_the_connection() -> void:
	session.connect_to("10.0.0.50", _at(1, 9))
	var events: Array[Dictionary] = session.node_sabotaged("node_free", _at(1, 9, 5))
	assert_eq(_types(events), ["connection_lost"] as Array[String])
	assert_false(session.has_connection())
	assert_eq(net.alert_level("node_free"), 1)


func test_sabotage_of_another_node_does_not_disturb_the_hack() -> void:
	session.connect_to("10.0.0.50", _at(1, 9))
	var events: Array[Dictionary] = session.node_sabotaged("node_lab", _at(1, 9, 5))
	assert_eq(events.size(), 0)
	assert_true(session.has_connection())


func test_sabotaged_node_refuses_connections_then_returns() -> void:
	session.connect_to("10.0.0.50", _at(2, 9))
	session.node_sabotaged("node_free", _at(2, 9, 5))

	var refused: NetResult = session.connect_to("10.0.0.50", _at(3, 9))
	assert_eq(refused.code, NetResult.Code.OFFLINE)
	assert_eq(refused.back_at, _at(5, 9, 5), "терминал может сказать, когда вернётся")

	assert_true(session.connect_to("10.0.0.50", _at(5, 9, 5)).is_ok(), "через три дня снова в сети")


# --- Сейв --------------------------------------------------------------------

func test_hack_in_progress_survives_save_and_load() -> void:
	_enter_office(_at(1, 9))
	session.advance(25, _at(1, 9, 25))

	var restored := Network.new(_definitions(), state.duplicate(true), BALANCE)
	var loaded := HackSession.new(restored)
	assert_eq(loaded.target_id(), "node_office")
	assert_true(loaded.has_connection())
	assert_true(loaded.is_tracing())
	assert_eq(loaded.trace_left(), 35)
