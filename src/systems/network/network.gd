class_name Network
extends RefCounted
## Сеть: граф узлов, адресная книга, разведка и доступность (docs/gameplay/network.md).
##
## Здесь «что есть и что известно»: кто с кем связан, какие узлы игрок уже нашёл, какие
## сервисы вскрыты, когда узел в сети. Что игрок *делает* с узлом — подключается, взламывает,
## отключается — в HackSession.
##
## Чистая логика, как Filesystem: без сцен, без Clock и EventBus. Время приходит параметром
## `now` — абсолютной игровой минутой (см. abs_minute()), события шлёт вызывающий.
## Состояние — словарь, который отдаётся снаружи: в игре это словарь GameState, чтобы
## адресная книга и вскрытые сервисы попадали в сейв.
##
## Раскладка состояния:
##   known   — {node_id: true}: адресная книга
##   nodes   — {node_id: {cracked: {service_id: минута}, hacked, probed, offline_until, alert}}
##   session — текущий взлом, им владеет HackSession

## Узел героя: всегда известен, всегда в сети, с него начинается любой scan.
const HOME_ID: String = "node_home_pc"
const DEFAULT_DEVICE: String = "pc"
const NEVER: int = -1

var _defs: Dictionary
var _state: Dictionary

var _minutes_per_day: int = 1440
var _offline_minutes: int = 0
var _reset_minutes: int = 0
var _alert_step: int = 1
## Состояние текущего вторжения на узлы (вскрытые сервисы, пароли, права, трейс): node_access.gd.
var access: NodeAccess


func _init(definitions: Dictionary, state: Dictionary, balance: Dictionary = {}) -> void:
	_defs = definitions
	_state = state
	access = NodeAccess.new(self)
	for key: String in ["known", "nodes", "session"]:
		if not _state.has(key):
			_state[key] = {}

	var clock: Dictionary = balance.get("clock", {}) as Dictionary
	_minutes_per_day = int(clock.get("minutes_per_day", 1440))
	var nodes_cfg: Dictionary = balance.get("nodes", {}) as Dictionary
	_offline_minutes = int(nodes_cfg.get("offline_days_after_sabotage", 3)) * _minutes_per_day
	var puzzles: Dictionary = balance.get("puzzles", {}) as Dictionary
	_reset_minutes = int(puzzles.get("services_reset_days", 7)) * _minutes_per_day
	_alert_step = int(puzzles.get("alert_difficulty_step", 1))


## Сеть игры: узлы из data/nodes, состояние из GameState, числа из balance.json.
static func for_game() -> Network:
	return Network.new(DataLoader.nodes(), GameState.network_state(), DataLoader.balance())


## Абсолютная игровая минута: сквозной счёт с начала игры. Так «через три дня» и «через
## семь дней» считаются вычитанием, без возни с границами суток.
func abs_minute(day: int, minute: int) -> int:
	return (day - 1) * _minutes_per_day + minute


func session_state() -> Dictionary:
	return _state["session"] as Dictionary


# --- Узлы и адреса -----------------------------------------------------------

func has_node_def(node_id: String) -> bool:
	return _defs.has(node_id)


func definition(node_id: String) -> Dictionary:
	return _defs.get(node_id, {}) as Dictionary


## Id узла по адресу или пустая строка. Регистр в адресах не важен: `LocalHost` — тоже свой ПК.
func id_by_address(address: String) -> String:
	var wanted: String = address.strip_edges().to_lower()
	for node_id: String in _defs.keys():
		if str(definition(node_id).get("address", "")).to_lower() == wanted:
			return node_id
	return ""


func device_of(node_id: String) -> String:
	return str(definition(node_id).get("device", DEFAULT_DEVICE))


# --- Адресная книга ----------------------------------------------------------

func is_known(node_id: String) -> bool:
	if not has_node_def(node_id):
		return false
	return (_state["known"] as Dictionary).has(node_id) or bool(definition(node_id).get("known_from_start", false))


func mark_known(node_id: String) -> void:
	if has_node_def(node_id):
		(_state["known"] as Dictionary)[node_id] = true


## Имя узла игрок узнаёт после `probe`: scan показывает адрес и тип устройства, не больше
## (network.md, вопрос 2). Свой ПК и узлы «известные с начала» названы сразу.
func is_probed(node_id: String) -> bool:
	if bool(definition(node_id).get("known_from_start", false)):
		return true
	return bool(_peek(node_id).get("probed", false))


## Всё, что игрок знает: для команды `nodes` и карты сети. Порядок стабилен — по адресу.
func address_book() -> Array[Dictionary]:
	var book: Array[Dictionary] = []
	for node_id: String in _defs.keys():
		if is_known(node_id):
			book.append(book_entry(node_id))
	book.sort_custom(_by_address)
	return book


func book_entry(node_id: String) -> Dictionary:
	var def: Dictionary = definition(node_id)
	return {
		"id": node_id,
		"address": str(def.get("address", "")),
		"device": device_of(node_id),
		"title": str(def.get("title", "")) if is_probed(node_id) else "",
		"hacked": has_hacked(node_id),
	}


## Заказ выдал игроку точку входа: адрес попадает в книгу, а клиент ещё и называет, что это
## за узел, и может дать «логины» — сервисы, которые он знает и открывает заранее
## (network.md, «Как игрок попадает в сеть»). Возвращает false, если такого узла нет.
func reveal(node_id: String, open_services: Array, now: int, admin_login: bool = false) -> bool:
	if not has_node_def(node_id):
		return false
	mark_known(node_id)
	_entry(node_id)["probed"] = true
	if admin_login:
		_entry(node_id)["admin_login"] = true
	for service_id: Variant in open_services:
		if not service(node_id, str(service_id)).is_empty():
			access.mark_cracked(node_id, str(service_id), now)
	return true


## `scan`: соседи узла, на котором стоит игрок. Найденные попадают в адресную книгу навсегда.
func scan(from_id: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for link: Variant in definition(from_id).get("links", []) as Array:
		var neighbour: String = str(link)
		if not has_node_def(neighbour):
			continue
		mark_known(neighbour)
		found.append(book_entry(neighbour))
	found.sort_custom(_by_address)
	return found


## Стены — сервисы, которые мешают и после входа (docs/gameplay/hacking.md, «Стены»).
## Поле `wall` у сервиса; нет поля — обычный замок: мешает только войти.
const WALL_FIREWALL: String = "firewall"
const WALLS: PackedStringArray = [WALL_FIREWALL]


## Фаервол узла ещё стоит: исходящие передачи (скачать файл себе) заблокированы, даже если
## игрок уже внутри. Вскрыл сервис-фаервол — передачи открыты.
func firewall_up(node_id: String, now: int) -> bool:
	for service_variant: Variant in definition(node_id).get("services", []) as Array:
		var service_def: Dictionary = service_variant as Dictionary
		if str(service_def.get("wall", "")) == WALL_FIREWALL and not access.is_cracked(node_id, str(service_def.get("id", "")), now):
			return true
	return false


## На узле анализ действий (IDS): пока идёт трейс, «громкие» действия — те, что пишутся в журнал
## узла, — отъедают трейс сильнее. Инструмента против него у героя пока нет.
func has_ids(node_id: String) -> bool:
	return bool(definition(node_id).get("ids", false))


## Устройства с графическим сеансом: у цели обычная ОС с рабочим столом, и после входа рядом
## с консолью открывается её трансляция (docs/tech/desktop-layout.md, «Удалённый сеанс»).
## У роутера и сервера стола нет — только консоль.
const GRAPHICAL_DEVICES: PackedStringArray = ["pc"]
## Что может стоять на столе цели. Пока только проводник.
const REMOTE_APPS: PackedStringArray = ["files"]


func has_graphical_session(node_id: String) -> bool:
	return GRAPHICAL_DEVICES.has(device_of(node_id))



## Устройства, с которых работает `deepscan`: у них таблицы маршрутов на всю сеть.
const DEEPSCAN_DEVICES: PackedStringArray = ["router", "server"]


## `deepscan`: вся сеть, до которой можно дойти по связям от `from_id`, в максимальную глубину
## (обход в ширину). У каждой находки — `depth`: сколько переходов от узла, где стоит игрок.
## Найденные остаются в адресной книге навсегда, как после `scan`.
func deep_scan(from_id: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var depth: Dictionary = {from_id: 0}
	var queue: Array[String] = [from_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for link: Variant in definition(current).get("links", []) as Array:
			var neighbour: String = str(link)
			if not has_node_def(neighbour) or depth.has(neighbour):
				continue
			depth[neighbour] = int(depth[current]) + 1
			queue.append(neighbour)
			mark_known(neighbour)
			var entry: Dictionary = book_entry(neighbour)
			entry["depth"] = depth[neighbour]
			found.append(entry)
	return found


## `probe`: сервисы, защита, трейс и расписание. Трейс не запускает и ничего не стоит,
## кроме времени — смотреть можно сколько угодно (hacking.md).
func probe(address: String, now: int) -> NetResult:
	var node_id: String = id_by_address(address)
	if node_id.is_empty() or not is_known(node_id):
		return NetResult.fail(NetResult.Code.UNKNOWN_ADDRESS, "", address)
	if node_id == HOME_ID:
		return NetResult.fail(NetResult.Code.LOCAL, node_id, address)

	_entry(node_id)["probed"] = true
	var result := NetResult.ok(node_id)
	result.info = describe(node_id, now)
	return result


func describe(node_id: String, now: int) -> Dictionary:
	var def: Dictionary = definition(node_id)
	var services: Array[Dictionary] = []
	for service_variant: Variant in def.get("services", []) as Array:
		var service_def: Dictionary = service_variant as Dictionary
		var service_id: String = str(service_def.get("id", ""))
		services.append({
			"id": service_id,
			"port": int(service_def.get("port", 0)),
			"wall": str(service_def.get("wall", "")),
			"name": str(service_def.get("name", "")),
			"puzzle": str(service_def.get("puzzle", "")),
			"program": str(service_def.get("program", "")),
			"difficulty": effective_difficulty(node_id, int(service_def.get("difficulty", 1))),
			"cracked": access.is_cracked(node_id, service_id, now),
		})
	return {
		"id": node_id,
		"title": str(def.get("title", "")),
		"address": str(def.get("address", "")),
		"device": device_of(node_id),
		"services": services,
		"required_services": required_services(node_id),
		"cracked_services": access.cracked_count(node_id, now),
		"trace_minutes": int(def.get("trace_minutes", 0)),
		"ids": has_ids(node_id),
		"online": def.get("online", {}),
		"online_now": is_online(node_id, now),
	}


# --- Доступность -------------------------------------------------------------

## Окно доступности («прайм-тайм»): офис с 8 до 18, дом вечером. Нет поля — круглосуточно.
## Окно может переходить через полночь («22:00»–«06:00»).
func in_window(node_id: String, now: int) -> bool:
	var window: Dictionary = definition(node_id).get("online", {}) as Dictionary
	if window.is_empty():
		return true
	var from_minute: int = _parse_time(str(window.get("from", "00:00")))
	var to_minute: int = _parse_time(str(window.get("to", "00:00")))
	var minute: int = now % _minutes_per_day
	if from_minute <= to_minute:
		return minute >= from_minute and minute < to_minute
	return minute >= from_minute or minute < to_minute


## Узел вне сети не по расписанию: на нём удалили net.sys и владелец ещё не починил.
func is_sabotaged(node_id: String, now: int) -> bool:
	return int(_peek(node_id).get("offline_until", NEVER)) > now


func is_online(node_id: String, now: int) -> bool:
	if node_id == HOME_ID:
		return true
	return in_window(node_id, now) and not is_sabotaged(node_id, now) and not is_rebooting(node_id, now)


## Узел перезагружается (игрок сделал `reboot` на нём): недоступен минуту (вычитка 26.11.2026).
func is_rebooting(node_id: String, now: int) -> bool:
	return int(_peek(node_id).get("rebooting_until", NEVER)) > now


func reboot_node(node_id: String, now: int) -> void:
	_entry(node_id)["rebooting_until"] = now + REBOOT_MINUTES


## Когда узел вернётся после саботажа: абсолютная минута или -1.
func back_at(node_id: String, now: int) -> int:
	return int(_peek(node_id).get("offline_until", NEVER)) if is_sabotaged(node_id, now) else NEVER


## Саботаж: игрок удалил net.sys на чужой машине. Узел уходит из сети на
## `nodes.offline_days_after_sabotage` дней и настораживается. Не навсегда — иначе за
## сломанным узлом можно запереть квестовый файл и получить софтлок (hacking.md).
func sabotage(node_id: String, now: int) -> void:
	_entry(node_id)["offline_until"] = now + _offline_minutes
	raise_alert(node_id)


## Узлы, которые владелец уже починил: пора вернуть им net.sys. Саму запись о поломке
## снимает mark_repaired() — после того, как вызывающий положил файл на место.
func due_repairs(now: int) -> PackedStringArray:
	var due: PackedStringArray = []
	var nodes: Dictionary = _state["nodes"] as Dictionary
	for node_id: String in nodes.keys():
		var until: int = int((nodes[node_id] as Dictionary).get("offline_until", NEVER))
		if until != NEVER and until <= now:
			due.append(node_id)
	due.sort()
	return due


func mark_repaired(node_id: String) -> void:
	_entry(node_id).erase("offline_until")


# --- Сервисы -----------------------------------------------------------------

func required_services(node_id: String) -> int:
	return int(definition(node_id).get("required_services", 0))


## Порт сервиса: так сервис видит и называет игрок. Внутри игры (сейв, прогресс) — по id.
func port_of(node_id: String, service_id: String) -> int:
	return int(service(node_id, service_id).get("port", 0))


## Сервис на порту; пусто — на этом порту ничего нет.
func service_at_port(node_id: String, port: int) -> String:
	for service_variant: Variant in definition(node_id).get("services", []) as Array:
		var candidate: Dictionary = service_variant as Dictionary
		if int(candidate.get("port", 0)) == port:
			return str(candidate.get("id", ""))
	return ""


func service(node_id: String, service_id: String) -> Dictionary:
	for service_variant: Variant in definition(node_id).get("services", []) as Array:
		var candidate: Dictionary = service_variant as Dictionary
		if str(candidate.get("id", "")) == service_id:
			return candidate
	return {}


# --- Осторожность цели -------------------------------------------------------

## Сколько раз цель настораживалась: доведённый трейс, саботаж. Не затухает. Это же число
## идёт в сид пароля, поэтому «осторожная» цель получает новое слово (hacking-loop.md).
## Сколько слоёв узла `probe` уже раскрыл до конца (ISS-016). Защиту перенастроили (узел
## насторожился после трейса) — раскрытое не в счёт, сканировать заново.
func probe_layers(node_id: String) -> int:
	var entry: Dictionary = _peek(node_id)
	if int(entry.get("probe_alert", 0)) != alert_level(node_id):
		return 0
	return int(entry.get("probe_layers", 0))


func set_probe_layers(node_id: String, layers: int) -> void:
	var entry: Dictionary = _entry(node_id)
	entry["probe_layers"] = layers
	entry["probe_alert"] = alert_level(node_id)


## Внешний адрес своего ПК — им подписаны следы героя в логах чужих узлов (вычитка 25.11.2026).
static func external_address() -> String:
	return str((DataLoader.nodes().get(HOME_ID, {}) as Dictionary).get("external_address", "0.0.0.0"))


## Сколько минут чужой узел перезагружается после `reboot`.
const REBOOT_MINUTES: int = 1


func alert_level(node_id: String) -> int:
	return int(_peek(node_id).get("alert", 0))


func raise_alert(node_id: String) -> void:
	var entry: Dictionary = _entry(node_id)
	entry["alert"] = int(entry.get("alert", 0)) + 1


## +1 к сложности за каждое настораживание, но не выше потолка: после трёх провалов узел
## не должен становиться непроходимым.
func effective_difficulty(node_id: String, base: int) -> int:
	return mini(NodeValidator.MAX_DIFFICULTY, base + alert_level(node_id) * _alert_step)


# --- Взломанные узлы ---------------------------------------------------------

func has_hacked(node_id: String) -> bool:
	return bool(_peek(node_id).get("hacked", false))


## Список взломанных узлов хранится навсегда: защита восстанавливается, а знание о том,
## что ты здесь был, остаётся (hacking-loop.md). Возвращает true, если это первый взлом.
func mark_hacked(node_id: String) -> bool:
	var entry: Dictionary = _entry(node_id)
	var first: bool = not bool(entry.get("hacked", false))
	entry["hacked"] = true
	return first


func hacked_nodes() -> PackedStringArray:
	var result: PackedStringArray = []
	var nodes: Dictionary = _state["nodes"] as Dictionary
	for node_id: String in nodes.keys():
		if bool((nodes[node_id] as Dictionary).get("hacked", false)):
			result.append(node_id)
	result.sort()
	return result


# --- Состояние узла для NodeAccess -------------------------------------------

## Состояние узла в сейве, только читать (пустой словарь, если узла ещё нет).
func peek_node(node_id: String) -> Dictionary:
	return _peek(node_id)


## Состояние узла в сейве для записи (создаётся при первом обращении).
func node_entry(node_id: String) -> Dictionary:
	return _entry(node_id)


## Сколько минут живёт вскрытая защита (`puzzles.services_reset_days`).
func reset_minutes() -> int:
	return _reset_minutes


# --- Внутреннее --------------------------------------------------------------

## Чтение без побочных эффектов: не плодит в сейве пустые записи про узлы, которых игрок
## даже не касался.
func _peek(node_id: String) -> Dictionary:
	return (_state["nodes"] as Dictionary).get(node_id, {}) as Dictionary


func _entry(node_id: String) -> Dictionary:
	var nodes: Dictionary = _state["nodes"] as Dictionary
	if not nodes.has(node_id):
		nodes[node_id] = {}
	return nodes[node_id] as Dictionary


static func _by_address(a: Dictionary, b: Dictionary) -> bool:
	return str(a["address"]) < str(b["address"])


## «чч:мм» → минуты от начала суток. Формат проверяет валидатор, здесь — запасной ноль.
func _parse_time(value: String) -> int:
	var parts: PackedStringArray = value.split(":")
	if parts.size() != 2:
		return 0
	return int(parts[0]) * 60 + int(parts[1])
