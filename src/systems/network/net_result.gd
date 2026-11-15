class_name NetResult
extends RefCounted
## Результат сетевой операции: получилось или нет, и что именно не так.
##
## Тот же приём, что у FsResult: логика отдаёт код, а текст для игрока собирается здесь,
## по формулировкам из docs/tech/terminal-spec.md. Сеть не знает, кто её спрашивает:
## терминал печатает message(), квестовая проверка просто учитывает неуспех.

enum Code {
	OK,
	UNKNOWN_ADDRESS,
	OFFLINE,
	## `connect` отказал: вскрыто меньше сервисов, чем нужно. Узел при этом остаётся целью.
	SERVICES_LEFT,
	## Адрес — свой ПК: подключаться к самому себе незачем.
	LOCAL,
	ALREADY_CONNECTED,
	NOT_CONNECTED,
	## Программа запущена, а цель не выбрана.
	NO_TARGET,
	NO_SUCH_SERVICE,
	ALREADY_CRACKED,
	WRONG_PROGRAM,
}

var code: Code = Code.OK
var node_id: String = ""
var address: String = ""
var service_id: String = ""
var program: String = ""

## Для SERVICES_LEFT: сколько сервисов вскрыто и сколько нужно.
var cracked: int = 0
var required: int = 0
## Узел вскрыт впервые за всю игру: терминал применит `on_hacked` и пошлёт `hack_completed`.
var first_hack: bool = false
## Эта операция запустила трейс: терминал шлёт `trace_started`.
var trace_started: bool = false
## Был ли игрок подключён к узлу (для `dc`: событие `node_disconnected` — только тогда).
var was_connected: bool = false
## Для OFFLINE: абсолютная игровая минута, когда узел вернётся. -1 — по расписанию.
var back_at: int = -1
## Разведка (`probe`) и прочие данные для показа.
var info: Dictionary = {}


static func ok(for_node: String = "") -> NetResult:
	var result := NetResult.new()
	result.node_id = for_node
	return result


static func fail(error: Code, for_node: String = "", for_address: String = "") -> NetResult:
	var result := NetResult.new()
	result.code = error
	result.node_id = for_node
	result.address = for_address
	return result


func is_ok() -> bool:
	return code == Code.OK


## Текст ошибки для игрока. Формулировки — из спецификации терминала.
func message() -> String:
	match code:
		Code.OK:
			return ""
		Code.UNKNOWN_ADDRESS:
			return "неизвестный адрес: %s. scan покажет, что рядом" % address
		Code.OFFLINE:
			return "узел не в сети"
		Code.SERVICES_LEFT:
			return "узел отказал: вскрыто %d из %d сервисов" % [cracked, required]
		Code.LOCAL:
			return "это твой ПК"
		Code.ALREADY_CONNECTED:
			return "ты уже подключён"
		Code.NOT_CONNECTED:
			return "ты ни к чему не подключён"
		Code.NO_TARGET:
			return "сначала выбери цель: connect <адрес>"
		Code.NO_SUCH_SERVICE:
			return "нет такого сервиса: %s" % service_id
		Code.ALREADY_CRACKED:
			return "сервис уже вскрыт: %s" % service_id
		Code.WRONG_PROGRAM:
			return "%s не работает против этой защиты" % program
		_:
			return "неизвестная ошибка"
