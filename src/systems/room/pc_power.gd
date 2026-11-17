class_name PcPower
extends RefCounted
## Питание своего ПК: выключить, включить, перезагрузить (docs/gameplay/hacking.md, «Комната»;
## docs/tech/terminal-spec.md, `reboot`). Одно правило на все кнопки: меню стола, кнопку в
## комнате и команду `reboot` в терминале.
##
## Отойти от ПК ≠ выключить. Отошёл — стол спрятан и всё идёт фоном (tech/desktop-layout.md).
## Выключил — по-настоящему: открытые окна закрыты, подключение к узлу оборвано (как `dc`: запись
## о выходе, если за героем не подчищают), фоновые задачи (ночной подбор) прерваны. Включение —
## загрузка: применяется тема, проверяются системные файлы (нет x-server.sys — аварийная консоль).
##
## Чистые правила без сцен. Сцены узнают о переменах из сигнала `pc_power_changed`.

const VAR_POWER: String = "pc.power"
const ON: String = "on"
const OFF: String = "off"


static func is_on() -> bool:
	return str(GameState.get_var_or(VAR_POWER, ON)) == ON


## Выключить. Возвращает {stopped: прервано фоновых задач, node: с какого узла оборвано}.
static func shut_down() -> Dictionary:
	var report: Dictionary = {"stopped": 0, "node": ""}
	if not is_on():
		return report
	report["node"] = _drop_connection()
	report["stopped"] = BackgroundTasks.cancel_all()
	GameState.set_var(VAR_POWER, OFF)
	Clock.advance(_minutes("shutdown_minutes", 1))
	EventBus.pc_power_changed.emit(false)
	return report


## Включить: загрузка занимает время, тема применяется, системные файлы проверяются.
## Возвращает отчёт загрузки (`SystemFiles.reboot`): theme, theme_changed, desktop, errors.
static func power_on() -> Dictionary:
	if is_on():
		return {}
	GameState.set_var(VAR_POWER, ON)
	Clock.advance(_minutes("boot_minutes", 2))
	var report: Dictionary = SystemFiles.reboot(Filesystem.for_node(Network.HOME_ID))
	EventBus.pc_power_changed.emit(true)
	return report


## Перезагрузить: выключить и включить. Отчёт загрузки плюс `stopped` и `node` выключения.
static func reboot() -> Dictionary:
	var down: Dictionary = shut_down()
	var up: Dictionary = power_on()
	up.merge(down)
	return up


## Оборвать подключение к чужому узлу так же, как `dc`: запись о выходе (если нет `gate.cover`) и
## сигнал отключения — заметность за следы считает HeatManager. Возвращает узел или "".
static func _drop_connection() -> String:
	var session := HackSession.new(Network.for_game())
	var node: String = session.target_id()
	if node.is_empty():
		return ""
	var result: NetResult = session.disconnect_now()
	HackConsequences.session_closed(node, result.was_connected)
	return node


static func _minutes(key: String, fallback: int) -> int:
	return int((DataLoader.balance().get("pc", {}) as Dictionary).get(key, fallback))
