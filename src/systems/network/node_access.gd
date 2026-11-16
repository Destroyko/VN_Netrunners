class_name NodeAccess
extends RefCounted
## Состояние текущего вторжения на узлы (docs/gameplay/hacking.md): какие сервисы вскрыты, какие
## пароли добыты и введены, есть ли права администратора, идёт ли трейс узла. Всё это живёт,
## пока цель не перенастроила защиту (`puzzles.services_reset_days` или доведённый трейс).
##
## Вынесено из `Network` (технический разбор 16.11.2026): сеть — это граф, адреса и доступность,
## а здесь — что игрок успел сделать с узлом. Состояние — в том же словаре сейва, что у сети.

var _net: Network


func _init(network: Network) -> void:
	_net = network


## Вскрытый сервис не вечен: через `puzzles.services_reset_days` цель перенастраивает защиту
## (hacking-loop.md). Считаем лениво, по возрасту записи: тикать каждый день незачем.
func is_cracked(node_id: String, service_id: String, now: int) -> bool:
	var cracked: Dictionary = _net.peek_node(node_id).get("cracked", {}) as Dictionary
	if not cracked.has(service_id):
		return false
	return now - int(cracked[service_id]) < _net.reset_minutes()


func cracked_count(node_id: String, now: int) -> int:
	var count: int = 0
	for service_variant: Variant in _net.definition(node_id).get("services", []) as Array:
		if is_cracked(node_id, str((service_variant as Dictionary).get("id", "")), now):
			count += 1
	return count


func mark_cracked(node_id: String, service_id: String, now: int) -> void:
	var entry: Dictionary = _net.node_entry(node_id)
	if not entry.has("cracked"):
		entry["cracked"] = {}
	(entry["cracked"] as Dictionary)[service_id] = now


func reset_services(node_id: String) -> void:
	_net.node_entry(node_id).erase("cracked")
	_net.node_entry(node_id).erase("root_at")
	_net.node_entry(node_id).erase("trace")
	_net.node_entry(node_id).erase("passwords")


## Трейс живёт на узле, а не в сеансе (решено 16.11.2026): взлом поднял тревогу — у вторжения
## один общий отсчёт. `dc` ставит его на паузу, повторный `connect` продолжает с того же места.
## Сбрасывается вместе с вскрытой защитой (доведённый трейс, `services_reset_days`).
func has_trace(node_id: String) -> bool:
	return _net.peek_node(node_id).has("trace")


func start_trace(node_id: String, minutes: int, now: int) -> void:
	_net.node_entry(node_id)["trace"] = {"left": minutes, "total": minutes, "at": now}


func trace_left(node_id: String) -> int:
	return int((_net.peek_node(node_id).get("trace", {}) as Dictionary).get("left", 0))


func trace_total(node_id: String) -> int:
	return int((_net.peek_node(node_id).get("trace", {}) as Dictionary).get("total", 0))


func set_trace_left(node_id: String, minutes: int) -> void:
	if has_trace(node_id):
		((_net.peek_node(node_id)["trace"]) as Dictionary)["left"] = clampi(minutes, 0, trace_total(node_id))


func clear_trace(node_id: String) -> void:
	_net.node_entry(node_id).erase("trace")


## Тревога старше окна сброса защиты — цель успокоилась, отсчёта больше нет.
func drop_stale_trace(node_id: String, now: int) -> void:
	var trace: Dictionary = _net.peek_node(node_id).get("trace", {}) as Dictionary
	if not trace.is_empty() and now - int(trace.get("at", now)) >= _net.reset_minutes():
		clear_trace(node_id)


## Взломщик достал пароль сервиса (docs/gameplay/hacking.md, «Пароль после перехвата»). Игрок
## ещё должен ввести его сам — `entered` станет true. Живёт столько же, сколько вскрытый сервис:
## сервис сбросился — при следующем взломе будет новое слово.
func remember_password(node_id: String, service_id: String, word: String) -> void:
	var entry: Dictionary = _net.node_entry(node_id)
	if not entry.has("passwords"):
		entry["passwords"] = {}
	(entry["passwords"] as Dictionary)[service_id] = {"word": word, "entered": false}


func password_of(node_id: String, service_id: String) -> String:
	var passwords: Dictionary = _net.peek_node(node_id).get("passwords", {}) as Dictionary
	return str((passwords.get(service_id, {}) as Dictionary).get("word", ""))


## Сервис, пароль которого добыт, но ещё не введён (пусто — вводить нечего). Сервисы, открытые
## заказом («клиент дал логин»), пароля не требуют: слова у них нет.
func pending_login(node_id: String, now: int) -> String:
	var passwords: Dictionary = _net.peek_node(node_id).get("passwords", {}) as Dictionary
	for service_id: String in passwords.keys():
		var record: Dictionary = passwords[service_id] as Dictionary
		if not bool(record.get("entered", false)) and is_cracked(node_id, service_id, now):
			return service_id
	return ""


func enter_password(node_id: String, service_id: String) -> void:
	var passwords: Dictionary = _net.peek_node(node_id).get("passwords", {}) as Dictionary
	if passwords.has(service_id):
		(passwords[service_id] as Dictionary)["entered"] = true


## `rootstep` поднял права на узле: они держатся и после `dc`, пока цель не перенастроила защиту
## (доведённый трейс, `services_reset_days`) — как вскрытые сервисы.
func grant_root(node_id: String, now: int) -> void:
	_net.node_entry(node_id)["root_at"] = now


func has_root(node_id: String, now: int) -> bool:
	var entry: Dictionary = _net.peek_node(node_id)
	return entry.has("root_at") and now - int(entry["root_at"]) < _net.reset_minutes()


## Заказчик дал логин администратора: на этом узле игрок сразу с правами (удалить, положить —
## работа офисного технаря). Логин не взлом — сбросы сервисов его не трогают.
func has_admin_login(node_id: String) -> bool:
	return bool(_net.peek_node(node_id).get("admin_login", false))
