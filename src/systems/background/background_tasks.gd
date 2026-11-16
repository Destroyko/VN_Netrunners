class_name BackgroundTasks
extends RefCounted
## Фоновые задачи героя (docs/gameplay/hacking-loop.md): долгий офлайн-подбор пароля к
## зашифрованному архиву. Идёт по игровому времени — в том числе пока герой спит, — без сети и
## трейса. Перезагрузка своего ПК их останавливает (docs/tech/terminal-spec.md, `reboot`).
##
## Чистые правила без сцен. Ход часов подаёт автозагрузка `BackgroundManager`. Очередь —
## переменная состояния `bg.tasks` (сейв помнит): [{path, finish_at}] — путь архива на ПК героя
## и игровая минута (`Clock.total_minutes`), когда подбор закончится.

const VAR_TASKS: String = "bg.tasks"


static func tasks() -> Array:
	return GameState.get_var_or(VAR_TASKS, []) as Array


static func is_running(path: String) -> bool:
	for t: Dictionary in tasks():
		if str(t["path"]) == path:
			return true
	return false


## Сколько игровых минут занимает подбор (балансим на плейтесте).
static func brute_minutes() -> int:
	var section: Dictionary = DataLoader.balance().get("background", {}) as Dictionary
	return int(section.get("decrypt_minutes", 480))


## Поставить подбор пароля к архиву `path` на ПК героя. Нет файла / не зашифрован / уже в работе
## — false с причиной во втором возврате.
static func start_decrypt(path: String) -> Dictionary:
	var home: Filesystem = Filesystem.for_node(Network.HOME_ID)
	if not home.has_file(path):
		return {"ok": false, "reason": "нет такого файла"}
	if not bool(home.file_data(path).get("encrypted", false)):
		return {"ok": false, "reason": "файл не зашифрован"}
	if is_running(path):
		return {"ok": false, "reason": "подбор уже идёт"}
	var minutes: int = brute_minutes()
	var list: Array = tasks().duplicate()
	list.append({"path": path, "finish_at": Clock.total_minutes() + minutes})
	GameState.set_var(VAR_TASKS, list)
	return {"ok": true, "minutes": minutes}


## Прошло время: завершить задачи, чей срок пришёл (расшифровать архив).
static func on_time_passed() -> void:
	var list: Array = tasks()
	if list.is_empty():
		return
	var now: int = Clock.total_minutes()
	var left: Array = []
	var done: Array = []
	for t: Dictionary in list:
		(done if int(t["finish_at"]) <= now else left).append(t)
	if done.is_empty():
		return
	GameState.set_var(VAR_TASKS, left)
	for t: Dictionary in done:
		_unlock(str(t["path"]))


## Перезагрузка своего ПК: все фоновые задачи сбрасываются (подбор придётся запускать заново).
## Возвращает, сколько было прервано.
static func cancel_all() -> int:
	var count: int = tasks().size()
	GameState.set_var(VAR_TASKS, [])
	return count


## Расшифровать архив: содержимое из `locked` раскрывается, пометка `encrypted` снимается.
static func _unlock(path: String) -> void:
	var home: Filesystem = Filesystem.for_node(Network.HOME_ID)
	if not home.has_file(path):
		return
	var data: Dictionary = home.file_data(path)
	var content: Dictionary = (data.get("locked", {}) as Dictionary).duplicate(true)
	home.put_file(path, content)
	EventBus.decrypt_done.emit(path)
