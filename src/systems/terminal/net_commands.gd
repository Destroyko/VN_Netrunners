class_name NetCommands
extends RefCounted
## Команды сети: scan, probe, connect, dc, nodes (docs/tech/terminal-spec.md, «Сеть»).
## Правила сети — в Network и HackSession; здесь время, события, следы и тексты для игрока.

const NO_NETWORK: String = "сети нет: на этом ПК нет /sys/net.sys"

const PROBE_RULE: String = "----------------------------------------"

var _t: Terminal


func _init(terminal: Terminal) -> void:
	_t = terminal


## `scan`: соседи узла, на котором стоит игрок. Найденные остаются в адресной книге навсегда.
func scan(result: TermResult) -> void:
	if not _t.has_network():
		result.add(NO_NETWORK)
		return
	var found: Array[Dictionary] = _t.net.scan(_t.node_id())
	if found.is_empty():
		result.add("соседей не видно")
	for entry: Dictionary in found:
		result.add(book_line(entry))
	_t.spend(_t.minutes_of("terminal_command"), result)


## `nodes`: всё, что игрок уже знает. Только чтение — сеть для этого не нужна.
func nodes(result: TermResult) -> void:
	for entry: Dictionary in _t.net.address_book():
		result.add(book_line(entry))


## `probe`: сервисы узла и их состояние, сколько нужно для входа, есть ли мониторинг. Трейс не запускает.
func probe(args: PackedStringArray, result: TermResult) -> void:
	if not _t.has_network():
		result.add(NO_NETWORK)
		return
	# Без адреса — узел, к которому подключались последним (после connect).
	var address: String = args[0] if not args.is_empty() else _t.session.target_address()
	if address.is_empty():
		result.add("использование: probe [адрес]")
		return
	var seen: NetResult = _t.net.probe(address, _t.now())
	if not seen.is_ok():
		result.add(seen.message())
		return

	# Вывод как у настоящей утилиты (по образцу Hacknet): что открыто и что стоит на узле.
	# Ни программ, ни сложности, ни расписания — этого сканер знать не может (terminal-spec.md).
	# Слои — сервисы, мониторинг подключений, анализ действий; у каждого своя полоска, минута на
	# слой (решено 25.11.2026, ISS-016). Ctrl+C прерывает; раскрытые слои узел помнит.
	var node: String = seen.node_id
	var info: Dictionary = seen.info
	# Стол открывает рядом с консолью виджет «Защита узла» (шаг 7, часть 6).
	result.request = {"type": "probe", "node": node}
	result.add("сканирование %s .........." % info["address"])
	result.add("узел: %s (%s)" % [info["title"], info["device"]])
	result.add(PROBE_RULE)
	var layers: Array[String] = probe_lines(info)
	var known: int = mini(_t.net.probe_layers(node), layers.size())
	for i: int in known:
		result.add(layers[i])
	if known >= layers.size():
		_probe_footer(info, result)
		return
	_probe_layer(node, str(info["address"]), known, result)


## Строки слоёв в порядке сканирования: порты, мониторинг подключений, анализ действий.
## Мониторинг — с длиной трейса: игрок видит, сколько у него будет времени внутри.
static func probe_lines(info: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for service: Dictionary in info["services"] as Array:
		lines.append("  порт %-6d %-24s %s" % [
			int(service["port"]), service["name"], "открыт" if bool(service["cracked"]) else "закрыт"
		])
	var trace: int = int(info["trace_minutes"])
	lines.append("обнаружен мониторинг подключений: %s" % (("да, трейс %d мин" % trace) if trace > 0 else "нет"))
	lines.append("обнаружен анализ действий: %s" % ("да" if bool(info["ids"]) else "нет"))
	return lines


## Один слой под своей полоской; дошёл — строка слоя, отметка у узла и следующий слой.
func _probe_layer(node: String, address: String, index: int, result: TermResult) -> void:
	_t.spend_then(_t.minutes_of("probe", 1), result, func(done: TermResult) -> void:
		var seen: NetResult = _t.net.probe(address, _t.now())
		if not seen.is_ok():
			done.add(seen.message())
			return
		var layers: Array[String] = probe_lines(seen.info)
		done.add(layers[index])
		_t.net.set_probe_layers(node, index + 1)
		if index + 1 < layers.size():
			_probe_layer(node, address, index + 1, done)
		else:
			_probe_footer(seen.info, done), true)


func _probe_footer(info: Dictionary, result: TermResult) -> void:
	result.add(PROBE_RULE)
	result.add("для входа требуется сервисов: %d" % int(info["required_services"]))


func connect_to(args: PackedStringArray, result: TermResult) -> void:
	if not _t.has_network():
		result.add(NO_NETWORK)
		return
	if args.is_empty():
		result.add("использование: connect <адрес>")
		return

	var before_node: String = _t.session.target_id()
	var was_connected: bool = _t.session.has_connection()
	var tried: NetResult = _t.session.connect_to(args[0], _t.now())

	# Прыжок на другой узел закрыл прежний сеанс: следы и событие о выходе — как при `dc`.
	if was_connected and _t.session.target_id() != before_node:
		_t.hung_up(before_node, true)

	if tried.code == NetResult.Code.LOGIN_REQUIRED:
		# Как ssh: соединение есть, сервер спрашивает пароль. Ввести можно здесь же или в окне входа.
		var host: Dictionary = _t.net.definition(tried.node_id)
		result.add("соединение с %s установлено" % host.get("address", tried.node_id))
		_tell_trace(result)
		_t.begin_login(tried.node_id, tried.service_id)
		# У ПК рядом открывается трансляция с экраном блокировки; у роутера и сервера — только консоль.
		if _t.net.has_graphical_session(tried.node_id):
			result.request = {"type": "remote", "node": tried.node_id, "address": str(host.get("address", ""))}
		_t.spend(_t.minutes_of("terminal_command"), result)
		return
	if tried.code == NetResult.Code.SERVICES_LEFT:
		# Соединение есть, входа нет: узел становится целью взлома. Что за защита — покажет probe.
		var target: Dictionary = _t.net.definition(tried.node_id)
		result.add("соединение с %s установлено" % target.get("address", tried.node_id))
		result.add("вход отклонён")
		_tell_trace(result)
		_t.spend(_t.minutes_of("terminal_command"), result)
		return
	if not tried.is_ok():
		result.add(tried.message())
		if tried.code == NetResult.Code.OFFLINE and tried.back_at >= 0:
			var days: int = ceili(float(tried.back_at - _t.now()) / float(1440))
			result.add("вернётся примерно через %d дн." % maxi(days, 1))
		return

	_t.set_cwd(Terminal.HOME_DIR)
	var definition: Dictionary = _t.net.definition(tried.node_id)
	result.add("подключено: %s (%s)" % [definition.get("title", tried.node_id), definition.get("address", "")])
	_tell_trace(result)
	if _t.net.has_graphical_session(tried.node_id) and result.request.is_empty():
		result.request = {"type": "remote", "node": tried.node_id, "address": str(definition.get("address", ""))}
	_t.note(Logbook.CATEGORY_SESSION, "вход с неизвестного адреса", "login")
	EventBus.node_connected.emit(tried.node_id)
	if tried.first_hack:
		Effects.apply_all(definition.get("on_hacked", []) as Array)
		EventBus.hack_completed.emit(tried.node_id)
	_t.spend(_t.minutes_of("terminal_command"), result)


## `dc`: отключиться и прервать взлом на любой стадии, в том числе до подключения.
func disconnect_now(result: TermResult) -> void:
	var closed: NetResult = _t.session.disconnect_now()
	if not closed.is_ok():
		result.add(closed.message())
		return
	_t.hung_up(closed.node_id, closed.was_connected)
	result.add("отключено" if closed.was_connected else "цель сброшена")


# --- Общее -------------------------------------------------------------------

## Вернулся на узел, где тревога уже поднята: трейс продолжает тот же отсчёт.
func _tell_trace(result: TermResult) -> void:
	if _t.session.is_tracing():
		result.add("трейс: %d мин" % _t.session.trace_left())

## Строка адресной книги: адрес, тип, имя (после probe), пометка о взломе. Её же печатает deepscan.
static func book_line(entry: Dictionary) -> String:
	var title: String = str(entry["title"])
	var line: String = "%-16s %s" % [entry["address"], entry["device"]]
	if not title.is_empty():
		line += "  " + title
	if bool(entry["hacked"]):
		line += "  [взломан]"
	return line

