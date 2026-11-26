extends Node
## Двигатель сюжета (docs/tech/story-engine.md): единственная точка входа для квестов, триггеров и
## отложенных эффектов. Сигналы шины превращаются в события и встают в очередь (`StoryQueue`),
## которая разбирается по одному. Логики здесь нет — только подписки и перехват действий.

## Сигналы, на которые реагируют квесты (цели и цели «по состоянию»). Триггеры добавляют свои.
const QUEST_EVENTS: PackedStringArray = [
	"node_connected", "node_disconnected", "file_read", "file_copied", "file_deleted", "file_edited",
	"file_moved", "attachment_saved", "mail_sent", "mail_read", "dialogue_ended", "quest_completed",
	"location_entered",
]
## Имена аргументов сигналов, которые цели квестов читают короче.
const ARG_ALIASES: Dictionary = {"node_id": "node", "location_id": "location", "dialogue_id": "dialogue"}

## Сделанные подписки [[сигнал, обработчик]] — чтобы снять их при переподписке.
var _connected: Array = []


func _ready() -> void:
	connect_events()
	EventBus.time_advanced.connect(_on_time)
	EventBus.day_started.connect(func(day: int) -> void:
		StoryQueue.hold()
		Quests.on_day_started(day)
		StoryQueue.release())


## Подписаться заново — после правки данных в отладке и в тестах.
func connect_events() -> void:
	for pair: Array in _connected:
		if EventBus.is_connected(str(pair[0]), pair[1] as Callable):
			EventBus.disconnect(str(pair[0]), pair[1] as Callable)
	_connected.clear()
	var names: PackedStringArray = QUEST_EVENTS.duplicate()
	for name: String in Triggers.events():
		if not names.has(name):
			names.append(name)
	for sig: Dictionary in EventBus.get_signal_list():
		var name: String = str(sig["name"])
		if not names.has(name):
			continue
		var args: PackedStringArray = []
		for arg: Dictionary in sig["args"] as Array:
			args.append(str(ARG_ALIASES.get(str(arg["name"]), str(arg["name"]))))
		var handler: Callable = _handler(name, args)
		EventBus.connect(name, handler)
		_connected.append([name, handler])


## Обработчик сигнала с N аргументами: собирает событие {"event": имя, аргумент: значение}.
func _handler(name: String, args: PackedStringArray) -> Callable:
	match args.size():
		0:
			return func() -> void: _post(name, args, [])
		1:
			return func(a: Variant) -> void: _post(name, args, [a])
		2:
			return func(a: Variant, b: Variant) -> void: _post(name, args, [a, b])
		3:
			return func(a: Variant, b: Variant, c: Variant) -> void: _post(name, args, [a, b, c])
		4:
			return func(a: Variant, b: Variant, c: Variant, d: Variant) -> void: _post(name, args, [a, b, c, d])
	return func(a: Variant = null, b: Variant = null, c: Variant = null, d: Variant = null, e: Variant = null) -> void:
		_post(name, args, [a, b, c, d, e])


func _post(name: String, args: PackedStringArray, values: Array) -> void:
	var event: Dictionary = {"event": name}
	for i: int in mini(args.size(), values.size()):
		event[args[i]] = values[i]
	StoryQueue.post(event)


## Ход часов: отложенные эффекты — каждую минуту, цели «дождаться» — раз в час игры.
func _on_time(_minute: int, passed: int) -> void:
	StoryQueue.hold()
	Schedule.on_time_passed()
	if passed >= 60 or GameState.minute % 60 == 0:
		StoryQueue.post({})
	StoryQueue.release()


## Перехват действия (сценарная реакция): можно ли сейчас `action` («attempt.pc_power_on»).
## {ok: true} — можно; {ok: false, text} — правило запретило, `text` — мысль героя.
func check(action: String) -> Dictionary:
	return Triggers.check_attempt(action)
