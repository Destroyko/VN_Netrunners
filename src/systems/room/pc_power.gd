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
## Загрузка и установка идут игровым временем под полоской (`Clock.fast_forward`), как программа:
## пока минуты идут, ПК ещё выключен (`pc_boot_started`), в конце — `finish_power_on`. Время
## отсчитывает экран загрузки (`BootOverlay`), правила — здесь. Часы стоят (тесты) — всё сразу.
##
## Резервная флешка в гнезде (решено 25.11.2026, шаг 7.5): **каждое** включение ставит с неё
## систему — 30 минут. Забыл вынуть — ставится снова: выключи посреди установки, вынь флешку,
## включи — последствий нет, ПК загрузится как был.
##
## Чистые правила без сцен. Сцены узнают о переменах из сигнала `pc_power_changed`.

const VAR_POWER: String = "pc.power"
const ON: String = "on"
const OFF: String = "off"

## Идёт загрузка или установка: {install}. Живёт в памяти — сейв посреди полоски запрещён (ISS-003).
static var _booting: Dictionary = {}


static func is_on() -> bool:
	return str(GameState.get_var_or(VAR_POWER, ON)) == ON


## Выключить. Возвращает {stopped: прервано фоновых задач, node: с какого узла оборвано}.
static func shut_down() -> Dictionary:
	var report: Dictionary = {"stopped": 0, "node": ""}
	if not is_on():
		return report
	report["node"] = _drop_connection()
	# Программа под полоской гаснет вместе с ПК: остальные минуты не идут (ISS-001, И-11).
	Clock.cancel_fast_forward()
	report["stopped"] = BackgroundTasks.cancel_all()
	GameState.set_var(VAR_POWER, OFF)
	EventBus.pc_power_changed.emit(false)
	# «Завершение работы» — минута под полоской (экран выключения).
	Clock.fast_forward(_minutes("shutdown_minutes", 1), true)
	return report


## Включить. С резервной флешкой в гнезде — установка системы, иначе обычная загрузка; минуты
## идут под полоской. Часы идут — {pending: true, install, minutes}: доделает `finish_power_on`,
## когда полоска дойдёт (`BootOverlay`). Часы стоят — сразу отчёт загрузки
## (`SystemFiles.reboot`: theme, theme_changed, desktop, errors; при установке — installed,
## restored, os_changed).
static func power_on() -> Dictionary:
	if is_on() or is_booting():
		return {}
	var install: bool = install_pending()
	var minutes: int = install_minutes() if install else _minutes("boot_minutes", 2)
	_booting = {"install": install}
	Clock.fast_forward(minutes, true)
	if Clock.is_fast_forwarding():
		# Конец минут загрузки ловим сами: экран загрузки только показывает её.
		_listen(true)
		EventBus.pc_boot_started.emit(install, minutes)
		return {"pending": true, "install": install, "minutes": minutes}
	return finish_power_on()


static func _listen(on: bool) -> void:
	var done: Callable = PcPower._on_boot_time_passed
	var dropped: Callable = PcPower._on_boot_dropped
	if on:
		if not Clock.fast_forward_finished.is_connected(done):
			Clock.fast_forward_finished.connect(done)
		if not Clock.fast_forward_dropped.is_connected(dropped):
			Clock.fast_forward_dropped.connect(dropped)
		return
	if Clock.fast_forward_finished.is_connected(done):
		Clock.fast_forward_finished.disconnect(done)
	if Clock.fast_forward_dropped.is_connected(dropped):
		Clock.fast_forward_dropped.disconnect(dropped)


static func _on_boot_time_passed() -> void:
	finish_power_on()


## Отрезок бросили (выключили посреди загрузки, выход в меню): ничего не поставлено.
static func _on_boot_dropped() -> void:
	_listen(false)
	_booting = {}


## Минуты загрузки прошли: установить систему (если ставилась), включить, применить тему.
static func finish_power_on() -> Dictionary:
	_listen(false)
	if _booting.is_empty():
		return {}
	var install: bool = bool(_booting["install"])
	_booting = {}
	var home: Filesystem = Filesystem.for_node(Network.HOME_ID)
	var installed: Dictionary = {}
	if install:
		installed = Room.use_item(str(Room.inserted().get("kind", "")), home)
	GameState.set_var(VAR_POWER, ON)
	var report: Dictionary = SystemFiles.reboot(home)
	if install:
		report["installed"] = true
		report["restored"] = installed.get("restored", PackedStringArray())
		report["os_changed"] = installed.get("os_changed", false)
	EventBus.pc_power_changed.emit(true)
	return report


## Выключили посреди загрузки или установки: ничего не поставлено, ПК выключен.
static func abort_boot() -> void:
	if _booting.is_empty():
		return
	Clock.cancel_fast_forward()
	_on_boot_dropped()


static func is_booting() -> bool:
	return not _booting.is_empty()


## В гнезде резервная флешка: включение поставит с неё систему.
static func install_pending() -> bool:
	var plugged: Dictionary = Room.inserted()
	return not plugged.is_empty() and Inventory.kind_of(str(plugged.get("kind", ""))) == Inventory.KIND_RESTORE


static func install_minutes() -> int:
	return _minutes("install_minutes", 30)


## Перезагрузить: выключить и включить (с флешкой в гнезде — установка). Отчёт загрузки (или
## pending) плюс `stopped` и `node` выключения.
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
