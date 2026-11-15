class_name HackSession
extends RefCounted
## Один взлом: выбор цели, подключение, трейс, отключение (docs/gameplay/hacking.md, «Трейс»).
##
## Network отвечает на вопрос «что есть», HackSession — «что игрок сейчас делает». Состояние
## лежит в том же словаре, что и у Network (раздел session), поэтому взлом в разгаре попадает
## в сейв вместе с остальным миром.
##
## Жизнь взлома:
##   1. `connect <адрес>` на узле с невскрытыми сервисами отказывает, но узел становится целью —
##      иначе программе-взломщику («passhound svc_login») было бы не на что целиться;
##   2. первый запуск взломщика стартует трейс (не `connect` и не разведка);
##   3. сервисы вскрыты — `connect` пускает, трейс продолжает идти;
##   4. `dc`, обрыв или конец трейса закрывают взлом.
## Подключение к другому узлу закрывает предыдущий взлом так же, как `dc`.
##
## Чистая логика: время приходит параметром, события возвращаются списком — их шлёт терминал.

var _net: Network
var _state: Dictionary


func _init(network: Network) -> void:
	_net = network
	_state = network.session_state()


# --- Состояние ---------------------------------------------------------------

## Узел, против которого идёт взлом, или пустая строка.
func target_id() -> String:
	return str(_state.get("target", ""))


## Назвать это `is_connected` нельзя: такой метод уже есть у Object (про сигналы).
func has_connection() -> bool:
	return bool(_state.get("connected", false))


## Где сейчас терминал: на удалённом узле после `connect` или у себя дома.
func current_id() -> String:
	return target_id() if has_connection() else Network.HOME_ID


func is_tracing() -> bool:
	return bool(_state.get("tracing", false))


## Права администратора на узле: их даёт rootstep, и держатся они до конца сеанса.
## Не путать с правами дома: на своём ПК у героя полные права всегда (terminal-spec.md).
func has_admin() -> bool:
	return has_connection() and bool(_state.get("admin", false))


func grant_admin() -> void:
	if has_connection():
		_state["admin"] = true


func trace_left() -> int:
	return int(_state.get("trace_left", 0))


func trace_total() -> int:
	return int(_state.get("trace_total", 0))


# --- Подключение -------------------------------------------------------------

func connect_to(address: String, now: int) -> NetResult:
	var node_id: String = _net.id_by_address(address)
	if node_id.is_empty() or not _net.is_known(node_id):
		return NetResult.fail(NetResult.Code.UNKNOWN_ADDRESS, "", address)
	if node_id == Network.HOME_ID:
		return NetResult.fail(NetResult.Code.LOCAL, node_id, address)
	if has_connection() and target_id() == node_id:
		return NetResult.fail(NetResult.Code.ALREADY_CONNECTED, node_id, address)
	if not _net.is_online(node_id, now):
		var offline := NetResult.fail(NetResult.Code.OFFLINE, node_id, address)
		offline.back_at = _net.back_at(node_id, now)
		return offline

	# Другой узел — другой взлом. Тот же узел (повторный connect после вскрытия) трейс
	# не трогает: он идёт с первого взломщика, а не с каждой попытки войти.
	if not target_id().is_empty() and target_id() != node_id:
		_end()
	_state["target"] = node_id

	var cracked: int = _net.cracked_count(node_id, now)
	var required: int = _net.required_services(node_id)
	if cracked < required:
		var denied := NetResult.fail(NetResult.Code.SERVICES_LEFT, node_id, address)
		denied.cracked = cracked
		denied.required = required
		return denied

	_state["connected"] = true
	var result := NetResult.ok(node_id)
	result.address = address
	result.first_hack = _net.mark_hacked(node_id)
	return result


## `dc`: отключиться и прервать взлом на любой стадии, в том числе до подключения.
func disconnect_now() -> NetResult:
	var node_id: String = target_id()
	if node_id.is_empty():
		return NetResult.fail(NetResult.Code.NOT_CONNECTED)
	var result := NetResult.ok(node_id)
	result.was_connected = has_connection()
	_end()
	return result


# --- Взлом -------------------------------------------------------------------

## Игрок запустил программу-взломщик против сервиса. Здесь стартует трейс: на узле, где он
## есть, и только когда открыты ворота давления (`trace_enabled`, флаг gate.pressure).
func begin_cracking(service_id: String, program: String, now: int, trace_enabled: bool) -> NetResult:
	var node_id: String = target_id()
	if node_id.is_empty():
		return NetResult.fail(NetResult.Code.NO_TARGET)

	var service_def: Dictionary = _net.service(node_id, service_id)
	if service_def.is_empty():
		var missing := NetResult.fail(NetResult.Code.NO_SUCH_SERVICE, node_id)
		missing.service_id = service_id
		return missing
	if str(service_def.get("program", "")) != program:
		var wrong := NetResult.fail(NetResult.Code.WRONG_PROGRAM, node_id)
		wrong.program = program
		return wrong
	if _net.is_cracked(node_id, service_id, now):
		var done := NetResult.fail(NetResult.Code.ALREADY_CRACKED, node_id)
		done.service_id = service_id
		return done

	var result := NetResult.ok(node_id)
	result.service_id = service_id
	var minutes: int = int(_net.definition(node_id).get("trace_minutes", 0))
	if trace_enabled and minutes > 0 and not is_tracing():
		_state["tracing"] = true
		_state["trace_total"] = minutes
		_state["trace_left"] = minutes
		result.trace_started = true
	return result


## Головоломка решена: сервис вскрыт. Подключиться игрок должен сам — `connect` решает, хватает ли.
func crack(service_id: String, now: int) -> NetResult:
	var node_id: String = target_id()
	if node_id.is_empty():
		return NetResult.fail(NetResult.Code.NO_TARGET)
	if _net.service(node_id, service_id).is_empty():
		var missing := NetResult.fail(NetResult.Code.NO_SUCH_SERVICE, node_id)
		missing.service_id = service_id
		return missing

	_net.mark_cracked(node_id, service_id, now)
	var result := NetResult.ok(node_id)
	result.service_id = service_id
	result.cracked = _net.cracked_count(node_id, now)
	result.required = _net.required_services(node_id)
	return result


# --- Время -------------------------------------------------------------------

## Прошло `minutes` игровых минут, сейчас `now`. Возвращает события для терминала:
##   connection_lost — узел ушёл из сети (кончился прайм-тайм): обрыв как при `dc`,
##                     вскрытые сервисы остаются, трейс останавливается;
##   trace_half, trace_last_quarter — предупреждения игроку (desktop-layout.md);
##   trace_finished — трейс дошёл до конца: обрыв, цель настораживается, сервисы сбрасываются.
## Если за один шаг сошлись и обрыв, и конец трейса, считаем в пользу игрока: узел успел уйти.
func advance(minutes: int, now: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var node_id: String = target_id()
	if node_id.is_empty() or minutes <= 0:
		return events

	if not _net.is_online(node_id, now):
		events.append({"type": "connection_lost", "node": node_id, "was_connected": has_connection()})
		_end()
		return events

	if not is_tracing():
		return events

	var before: int = trace_left()
	var after: int = maxi(0, before - minutes)
	_state["trace_left"] = after

	if after == 0:
		events.append({"type": "trace_finished", "node": node_id, "was_connected": has_connection()})
		_net.reset_services(node_id)
		_net.raise_alert(node_id)
		_end()
		return events

	var total: int = trace_total()
	var half: int = ceili(total / 2.0)
	var quarter: int = ceili(total / 4.0)
	if before > half and after <= half:
		events.append({"type": "trace_half", "node": node_id, "left": after})
	if before > quarter and after <= quarter:
		events.append({"type": "trace_last_quarter", "node": node_id, "left": after})
	return events


## Игрок удалил net.sys на узле. Узел уходит из сети, а если игрок был внутри — вылетает.
func node_sabotaged(node_id: String, now: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	_net.sabotage(node_id, now)
	if target_id() == node_id:
		events.append({"type": "connection_lost", "node": node_id, "was_connected": has_connection()})
		_end()
	return events


# --- Внутреннее --------------------------------------------------------------

func _end() -> void:
	_state["target"] = ""
	_state["connected"] = false
	_state["admin"] = false
	_state["tracing"] = false
	_state["trace_left"] = 0
	_state["trace_total"] = 0
