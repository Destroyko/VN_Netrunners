extends GutTest
## Network: граф узлов, адресная книга, разведка и доступность (docs/gameplay/network.md).

const BALANCE: Dictionary = {
	"clock": {"minutes_per_day": 1440},
	"nodes": {"offline_days_after_sabotage": 3},
	"puzzles": {"services_reset_days": 7, "alert_difficulty_step": 1},
}

var net: Network
var state: Dictionary


func _definitions() -> Dictionary:
	return {
		"node_home_pc": {
			"id": "node_home_pc", "title": "Мой ПК", "address": "localhost",
			"known_from_start": true, "links": ["node_router"], "services": [],
		},
		"node_router": {
			"id": "node_router", "title": "Роутер", "address": "10.0.0.1", "device": "router",
			"links": ["node_home_pc", "node_lab", "node_office"], "services": [],
		},
		"node_lab": {
			"id": "node_lab", "title": "Учебный ПК", "address": "10.0.0.7",
			"links": ["node_router"], "required_services": 1, "trace_minutes": 0,
			"services": [{
				"id": "svc_login", "name": "Вход по паролю", "puzzle": "password",
				"program": "passhound", "difficulty": 1, "hints": ["подсказка"],
			}],
		},
		"node_office": {
			"id": "node_office", "title": "Сервер фирмы", "address": "77.0.0.12", "device": "server",
			"links": ["node_router"], "required_services": 2, "trace_minutes": 60, "ids": true,
			"online": {"from": "08:00", "to": "18:00"},
			"services": [
				{"id": "svc_login", "name": "Вход", "puzzle": "password", "program": "passhound", "difficulty": 2},
				{"id": "svc_fw", "name": "Фаервол", "puzzle": "matrix", "program": "gridrunner", "difficulty": 2, "wall": "firewall"},
			],
		},
		"node_night": {
			"id": "node_night", "title": "Ночной узел", "address": "10.9.9.9", "known_from_start": true,
			"links": [], "online": {"from": "22:00", "to": "06:00"}, "services": [],
		},
	}


func before_each() -> void:
	state = {}
	net = Network.new(_definitions(), state, BALANCE)


## Абсолютная минута: день, часы, минуты.
func _at(day: int, hours: int, minutes: int = 0) -> int:
	return net.abs_minute(day, hours * 60 + minutes)


# --- Адресная книга и scan ---------------------------------------------------

func test_only_start_nodes_are_known_at_first() -> void:
	assert_true(net.is_known("node_home_pc"))
	assert_false(net.is_known("node_router"), "роутер ещё не найден")
	assert_false(net.is_known("node_nonexistent"))


func test_scan_shows_only_neighbours() -> void:
	var found: Array[Dictionary] = net.scan("node_home_pc")
	assert_eq(found.size(), 1, "из дома виден один роутер")
	assert_eq(found[0]["id"], "node_router")
	assert_false(net.is_known("node_lab"), "сосед соседа так не находится")


func test_scan_adds_to_address_book_forever() -> void:
	net.scan("node_home_pc")
	assert_true(net.is_known("node_router"))
	# Книга живёт в состоянии: другой экземпляр над тем же словарём её видит.
	var again := Network.new(_definitions(), state, BALANCE)
	assert_true(again.is_known("node_router"))


func test_scan_walks_the_graph() -> void:
	net.scan("node_home_pc")
	var from_router: Array[Dictionary] = net.scan("node_router")
	assert_eq(from_router.size(), 3, "дом, учебный ПК и офис")
	assert_true(net.is_known("node_lab"))
	assert_true(net.is_known("node_office"))


func test_scan_gives_address_and_device_but_not_name() -> void:
	# network.md, вопрос 2: имя узла игрок узнаёт после probe.
	var found: Array[Dictionary] = net.scan("node_home_pc")
	assert_eq(found[0]["address"], "10.0.0.1")
	assert_eq(found[0]["device"], "router")
	assert_eq(found[0]["title"], "", "имени пока нет")


func test_probe_reveals_the_name() -> void:
	net.scan("node_home_pc")
	net.probe("10.0.0.1", _at(1, 9))
	var book: Array[Dictionary] = net.address_book()
	var router: Dictionary = {}
	for entry: Dictionary in book:
		if entry["id"] == "node_router":
			router = entry
	assert_eq(router["title"], "Роутер")


func test_own_pc_is_named_from_the_start() -> void:
	var book: Array[Dictionary] = net.address_book()
	assert_eq(book.size(), 2, "свой ПК и ночной узел, известный с начала")
	for entry: Dictionary in book:
		assert_ne(entry["title"], "", "известные с начала названы сразу")


func test_device_defaults_to_pc() -> void:
	assert_eq(net.device_of("node_lab"), "pc")
	assert_eq(net.device_of("node_office"), "server")


func test_address_lookup_ignores_case() -> void:
	assert_eq(net.id_by_address("LocalHost"), "node_home_pc")
	assert_eq(net.id_by_address(" 10.0.0.1 "), "node_router")
	assert_eq(net.id_by_address("1.1.1.1"), "")


func test_address_book_is_sorted_by_address() -> void:
	net.scan("node_home_pc")
	net.scan("node_router")
	var addresses: Array[String] = []
	for entry: Dictionary in net.address_book():
		addresses.append(str(entry["address"]))
	var sorted: Array[String] = addresses.duplicate()
	sorted.sort()
	assert_eq(addresses, sorted)


# --- probe -------------------------------------------------------------------

func test_probe_of_unknown_address_fails() -> void:
	# Адрес из чужой переписки — подсказка, куда идти, а не способ попасть (network.md).
	var result: NetResult = net.probe("77.0.0.12", _at(1, 9))
	assert_eq(result.code, NetResult.Code.UNKNOWN_ADDRESS)
	assert_string_contains(result.message(), "77.0.0.12")


func test_probe_describes_the_node() -> void:
	net.scan("node_home_pc")
	net.scan("node_router")
	var result: NetResult = net.probe("77.0.0.12", _at(1, 9))
	assert_true(result.is_ok())
	var info: Dictionary = result.info
	assert_eq(info["required_services"], 2)
	assert_eq(info["trace_minutes"], 60)
	assert_eq((info["services"] as Array).size(), 2)
	assert_true(bool(info["online_now"]))
	assert_eq(str((info["online"] as Dictionary)["from"]), "08:00")


func test_probe_shows_hints() -> void:
	net.scan("node_home_pc")
	net.scan("node_router")
	var info: Dictionary = net.probe("10.0.0.7", _at(1, 9)).info
	var service: Dictionary = (info["services"] as Array)[0] as Dictionary
	assert_eq((service["hints"] as Array)[0], "подсказка")


func test_probe_does_not_touch_the_session() -> void:
	# Разведка бесплатна и трейса не запускает (hacking.md).
	net.scan("node_home_pc")
	net.scan("node_router")
	net.probe("77.0.0.12", _at(1, 9))
	assert_eq(net.session_state().get("tracing", false), false)
	assert_eq(str(net.session_state().get("target", "")), "")


func test_probe_of_own_pc_is_refused() -> void:
	assert_eq(net.probe("localhost", _at(1, 9)).code, NetResult.Code.LOCAL)


# --- Заказ даёт точку входа --------------------------------------------------

func test_order_reveals_an_unreachable_node() -> void:
	# Сервер фирмы не связан с домом: адрес и вход приходят из заказа, а не из scan.
	assert_false(net.is_known("node_office"))
	assert_true(net.reveal("node_office", [], _at(1, 9)))
	assert_true(net.is_known("node_office"))
	assert_eq(net.id_by_address("77.0.0.12"), "node_office")


func test_order_names_the_node() -> void:
	# Клиент сказал, что это за узел: имя известно без probe.
	net.reveal("node_office", [], _at(1, 9))
	var entry: Dictionary = {}
	for row: Dictionary in net.address_book():
		if row["id"] == "node_office":
			entry = row
	assert_eq(entry["title"], "Сервер фирмы")


func test_order_logins_open_services_in_advance() -> void:
	net.reveal("node_office", ["svc_login"], _at(1, 9))
	assert_true(net.is_cracked("node_office", "svc_login", _at(1, 9)))
	assert_false(net.is_cracked("node_office", "svc_fw", _at(1, 9)), "фаервол клиент не открывает")


func test_order_logins_expire_like_any_cracked_service() -> void:
	net.reveal("node_office", ["svc_login"], _at(1, 9))
	assert_false(net.is_cracked("node_office", "svc_login", _at(9, 9)))


func test_order_ignores_unknown_services_and_nodes() -> void:
	assert_false(net.reveal("node_nowhere", [], _at(1, 9)))
	assert_true(net.reveal("node_office", ["svc_nope"], _at(1, 9)))
	assert_eq(net.cracked_count("node_office", _at(1, 9)), 0)


# --- Прайм-тайм --------------------------------------------------------------

func test_office_is_online_only_in_working_hours() -> void:
	assert_false(net.is_online("node_office", _at(1, 7, 59)))
	assert_true(net.is_online("node_office", _at(1, 8)))
	assert_true(net.is_online("node_office", _at(1, 17, 59)))
	assert_false(net.is_online("node_office", _at(1, 18)))


func test_window_repeats_every_day() -> void:
	assert_true(net.is_online("node_office", _at(5, 12)))
	assert_false(net.is_online("node_office", _at(5, 23)))


func test_node_without_window_is_always_online() -> void:
	assert_true(net.is_online("node_lab", _at(1, 3)))


func test_window_may_cross_midnight() -> void:
	assert_true(net.is_online("node_night", _at(1, 23)))
	assert_true(net.is_online("node_night", _at(2, 5, 59)))
	assert_false(net.is_online("node_night", _at(2, 6)))
	assert_false(net.is_online("node_night", _at(2, 12)))


func test_own_pc_is_always_online() -> void:
	assert_true(net.is_online("node_home_pc", _at(1, 3)))


# --- Саботаж -----------------------------------------------------------------

func test_sabotage_takes_node_offline_for_three_days() -> void:
	var start: int = _at(2, 10)
	net.sabotage("node_lab", start)
	assert_false(net.is_online("node_lab", start))
	assert_false(net.is_online("node_lab", _at(4, 23)), "ещё не починили")
	assert_true(net.is_online("node_lab", _at(5, 10)), "ровно через три дня вернулся")


func test_sabotage_is_not_forever() -> void:
	# Защита от софтлока: за сломанным узлом может лежать квестовый файл.
	net.sabotage("node_lab", _at(1, 10))
	assert_true(net.is_online("node_lab", _at(30, 10)))


func test_sabotage_makes_target_wary() -> void:
	assert_eq(net.alert_level("node_lab"), 0)
	net.sabotage("node_lab", _at(1, 10))
	assert_eq(net.alert_level("node_lab"), 1)


func test_back_at_reports_return_time() -> void:
	var start: int = _at(2, 10)
	net.sabotage("node_lab", start)
	assert_eq(net.back_at("node_lab", start), _at(5, 10))
	assert_eq(net.back_at("node_lab", _at(6, 0)), Network.NEVER, "вернулся — возвращаться не за чем")


func test_repairs_are_due_after_the_outage() -> void:
	net.sabotage("node_lab", _at(2, 10))
	assert_eq(net.due_repairs(_at(4, 0)).size(), 0)
	var due: PackedStringArray = net.due_repairs(_at(5, 10))
	assert_eq(due.size(), 1)
	assert_eq(due[0], "node_lab")
	net.mark_repaired("node_lab")
	assert_eq(net.due_repairs(_at(6, 0)).size(), 0, "починенный второй раз не чинят")


func test_sabotage_and_schedule_both_apply() -> void:
	# Офис ночью выключен по расписанию, а после саботажа не включится и днём.
	net.sabotage("node_office", _at(1, 10))
	assert_false(net.is_online("node_office", _at(2, 12)), "расписание в порядке, но узел сломан")
	assert_true(net.is_online("node_office", _at(5, 12)))


# --- Вскрытые сервисы --------------------------------------------------------

func test_service_stays_cracked_for_a_week() -> void:
	net.mark_cracked("node_lab", "svc_login", _at(1, 10))
	assert_true(net.is_cracked("node_lab", "svc_login", _at(1, 11)))
	assert_true(net.is_cracked("node_lab", "svc_login", _at(8, 9, 59)), "почти неделя")


func test_cracked_service_expires() -> void:
	# Иначе однажды взломанный узел остаётся открытым навсегда (hacking-loop.md).
	net.mark_cracked("node_lab", "svc_login", _at(1, 10))
	assert_false(net.is_cracked("node_lab", "svc_login", _at(8, 10)))
	assert_eq(net.cracked_count("node_lab", _at(8, 10)), 0)


func test_cracked_count_counts_services_of_the_node() -> void:
	net.mark_cracked("node_office", "svc_login", _at(1, 10))
	assert_eq(net.cracked_count("node_office", _at(1, 11)), 1)
	net.mark_cracked("node_office", "svc_fw", _at(1, 11))
	assert_eq(net.cracked_count("node_office", _at(1, 12)), 2)


func test_reset_services_closes_them_all() -> void:
	net.mark_cracked("node_office", "svc_login", _at(1, 10))
	net.mark_cracked("node_office", "svc_fw", _at(1, 10))
	net.reset_services("node_office")
	assert_eq(net.cracked_count("node_office", _at(1, 11)), 0)


# --- Осторожность ------------------------------------------------------------

func test_alert_raises_difficulty() -> void:
	assert_eq(net.effective_difficulty("node_lab", 1), 1)
	net.raise_alert("node_lab")
	assert_eq(net.effective_difficulty("node_lab", 1), 2)


func test_difficulty_is_capped() -> void:
	# После трёх провалов узел не должен стать непроходимым.
	for i: int in 6:
		net.raise_alert("node_lab")
	assert_eq(net.effective_difficulty("node_lab", 2), NodeValidator.MAX_DIFFICULTY)


func test_probe_shows_raised_difficulty() -> void:
	net.mark_known("node_lab")
	net.raise_alert("node_lab")
	var info: Dictionary = net.probe("10.0.0.7", _at(1, 9)).info
	assert_eq(((info["services"] as Array)[0] as Dictionary)["difficulty"], 2)


# --- Взломанные узлы ---------------------------------------------------------

func test_first_hack_is_reported_once() -> void:
	assert_true(net.mark_hacked("node_lab"), "первый раз")
	assert_false(net.mark_hacked("node_lab"), "второй — уже нет")


func test_hacked_list_survives_reset_of_defences() -> void:
	# Защита восстанавливается, а знание, что ты здесь был, остаётся.
	net.mark_hacked("node_lab")
	net.mark_cracked("node_lab", "svc_login", _at(1, 10))
	net.reset_services("node_lab")
	assert_true(net.has_hacked("node_lab"))
	assert_eq(net.hacked_nodes().size(), 1)


# --- Сейв --------------------------------------------------------------------

func test_state_survives_save_and_load() -> void:
	GameState.reset()
	GameState.set_network_state(state)
	net.scan("node_home_pc")
	net.mark_hacked("node_lab")
	net.sabotage("node_office", _at(1, 10))

	var saved: Dictionary = GameState.to_dict()
	GameState.reset()
	assert_false(Network.new(_definitions(), GameState.network_state(), BALANCE).is_known("node_router"))
	GameState.from_dict(saved)

	var loaded := Network.new(_definitions(), GameState.network_state(), BALANCE)
	assert_true(loaded.is_known("node_router"), "адресная книга")
	assert_true(loaded.has_hacked("node_lab"), "взломанные узлы")
	assert_eq(loaded.alert_level("node_office"), 1, "осторожность")
	assert_true(loaded.is_sabotaged("node_office", _at(2, 10)), "поломка")


func test_peeking_does_not_bloat_the_save() -> void:
	# Чтение не должно плодить записи про узлы, которых игрок не касался.
	net.is_cracked("node_lab", "svc_login", _at(1, 9))
	net.alert_level("node_lab")
	net.has_hacked("node_lab")
	assert_eq((state["nodes"] as Dictionary).size(), 0)


# --- deepscan ------------------------------------------------------------------

func test_deep_scan_goes_through_the_whole_network() -> void:
	# С учебного ПК scan видит только роутер, deep_scan — всё, что за ним.
	var found: Array[Dictionary] = net.deep_scan("node_lab")
	var depth: Dictionary = {}
	for entry: Dictionary in found:
		depth[str(entry["id"])] = int(entry["depth"])
	assert_eq(depth["node_router"], 1)
	assert_eq(depth["node_office"], 2, "сервер — через роутер")
	assert_eq(depth["node_home_pc"], 2)
	assert_false(depth.has("node_night"), "узел без связей не находится")
	assert_true(net.is_known("node_office"), "найденное остаётся в адресной книге")


func test_plain_scan_still_sees_only_neighbours() -> void:
	var found: Array[Dictionary] = net.scan("node_lab")
	assert_eq(found.size(), 1)


# --- Стены -----------------------------------------------------------------------

func test_firewall_is_up_until_its_service_is_cracked() -> void:
	var now: int = _at(1, 9)
	assert_true(net.firewall_up("node_office", now))
	assert_false(net.firewall_up("node_lab", now), "у учебного ПК фаервола нет")
	net.mark_cracked("node_office", "svc_fw", now)
	assert_false(net.firewall_up("node_office", now))


func test_ids_is_a_node_property() -> void:
	assert_true(net.has_ids("node_office"))
	assert_false(net.has_ids("node_lab"))
	assert_true(bool(net.describe("node_office", _at(1, 9))["ids"]))


# --- Пароли сервисов ---------------------------------------------------------------

func test_password_waits_to_be_entered_while_the_service_is_open() -> void:
	var now: int = _at(1, 9)
	net.mark_cracked("node_lab", "svc_login", now)
	net.remember_password("node_lab", "svc_login", "метро")
	assert_eq(net.pending_login("node_lab", now), "svc_login")
	net.enter_password("node_lab", "svc_login")
	assert_eq(net.pending_login("node_lab", now), "")


func test_service_opened_by_a_client_needs_no_password() -> void:
	net.mark_cracked("node_lab", "svc_login", _at(1, 9))
	assert_eq(net.pending_login("node_lab", _at(1, 9)), "", "слова нет — вводить нечего")

