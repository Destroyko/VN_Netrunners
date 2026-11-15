extends GutTest
## Сеть на настоящих данных: связка Network + HackSession + Filesystem + data/nodes.
## Юнит-тесты проверяют правила на выдуманных узлах, а здесь — что реальные JSON складываются
## в рабочий первый взлом из docs/gameplay/hacking.md («Три ступени обучения»).

var net: Network
var session: HackSession


func before_each() -> void:
	DataLoader.clear_cache()
	GameState.reset()
	net = Network.for_game()
	session = HackSession.new(net)


func _now() -> int:
	return net.abs_minute(GameState.day, GameState.minute)


func test_home_sees_only_the_router() -> void:
	var found: Array[Dictionary] = net.scan(Network.HOME_ID)
	assert_eq(found.size(), 1)
	assert_eq(found[0]["id"], "node_home_router")
	assert_eq(found[0]["device"], "router")


func test_router_leads_to_the_training_pc() -> void:
	net.scan(Network.HOME_ID)
	var ids: Array[String] = []
	for entry: Dictionary in net.scan("node_home_router"):
		ids.append(str(entry["id"]))
	assert_true(ids.has("node_training_pc"), "адрес из письма соседки находится через scan")
	assert_true(ids.has(Network.HOME_ID))


func test_neighbours_address_from_the_mail_is_the_training_pc() -> void:
	# В /home/mail/sosedka.txt лежит адрес для тренировки: он обязан существовать в данных.
	assert_eq(net.id_by_address("10.0.0.7"), "node_training_pc")


func test_address_from_a_mail_is_not_a_way_in() -> void:
	# Адрес в письме — подсказка, куда идти, а не способ попасть (network.md).
	assert_eq(session.connect_to("10.0.0.7", _now()).code, NetResult.Code.UNKNOWN_ADDRESS)


func test_training_hack_start_to_finish() -> void:
	net.scan(Network.HOME_ID)
	net.scan("node_home_router")

	var info: Dictionary = net.probe("10.0.0.7", _now()).info
	assert_eq(info["required_services"], 1)
	assert_eq(info["trace_minutes"], 0, "учебный взлом без трейса")
	assert_true(bool(info["online_now"]), "круглосуточно")
	var service: Dictionary = (info["services"] as Array)[0] as Dictionary
	assert_eq(service["program"], "passhound")

	var denied: NetResult = session.connect_to("10.0.0.7", _now())
	assert_eq(denied.message(), "узел отказал: вскрыто 0 из 1 сервисов")

	var started: NetResult = session.begin_cracking("svc_login", "passhound", _now(), true)
	assert_true(started.is_ok())
	assert_false(started.trace_started, "на учебной машине трейса нет, даже в эпоху группы")
	session.crack("svc_login", _now())

	var entered: NetResult = session.connect_to("10.0.0.7", _now())
	assert_true(entered.is_ok())
	assert_true(entered.first_hack)

	# Дальше терминал работает с файловой системой этого узла.
	var files: Filesystem = Filesystem.for_node(session.current_id())
	assert_true(files.has_file("/home/privet.txt"), "записка соседки на месте")


func test_every_defined_link_is_walkable_both_ways() -> void:
	# Если валидатор пропустит односторонние связи, scan с одной стороны потеряет узел.
	for node_id: String in DataLoader.nodes().keys():
		for link: Variant in (DataLoader.nodes()[node_id] as Dictionary).get("links", []) as Array:
			var back: Array[String] = []
			for entry: Dictionary in net.scan(str(link)):
				back.append(str(entry["id"]))
			assert_true(back.has(node_id), "%s ← %s" % [node_id, link])


# --- Заказ как вход в сеть ---------------------------------------------------

func test_order_gives_entry_to_the_husbands_home() -> void:
	# Узел мужа ни с чем не связан: адрес и логины приходят из заказа, а не из scan.
	assert_eq(session.connect_to("92.44.18.3", _now()).code, NetResult.Code.UNKNOWN_ADDRESS)
	Effects.apply({"reveal_node": "node_husband_pc"})
	var denied: NetResult = session.connect_to("92.44.18.3", _now())
	assert_eq(denied.code, NetResult.Code.OFFLINE, "заказ не отменяет вечернее окно: сейчас утро")


func test_order_with_logins_lets_in_during_prime_time() -> void:
	GameState.minute = 19 * 60
	Effects.apply({"reveal_node": {"node": "node_husband_pc", "open": ["svc_firewall"]}})
	net = Network.for_game()
	session = HackSession.new(net)
	var entered: NetResult = session.connect_to("92.44.18.3", _now())
	assert_true(entered.is_ok(), entered.message())
	assert_true(entered.first_hack)


func test_order_without_logins_still_needs_the_hack() -> void:
	GameState.minute = 19 * 60
	Effects.apply({"reveal_node": "node_husband_pc"})
	net = Network.for_game()
	session = HackSession.new(net)
	var denied: NetResult = session.connect_to("92.44.18.3", _now())
	assert_eq(denied.message(), "узел отказал: вскрыто 0 из 1 сервисов")
	assert_eq(session.target_id(), "node_husband_pc", "цель выбрана: можно запускать gridrunner")
