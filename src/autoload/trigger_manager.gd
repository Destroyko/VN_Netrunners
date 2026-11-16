extends Node
## Слушатель триггеров: подписывается на те сигналы шины, на которые есть триггеры в данных, и
## зовёт `Triggers.fire`. Логики здесь нет (docs/tech/architecture.md).

## Сделанные подписки [[событие, обработчик]] — чтобы снять их при переподписке.
var _connected: Array = []


func _ready() -> void:
	connect_events()
	# Отложенные эффекты (`schedule`) — тоже «при событии»: при наступлении времени.
	EventBus.time_advanced.connect(func(_m: int, _p: int) -> void: Schedule.on_time_passed())


## Подписаться заново — после правки данных в отладке и в тестах. Аргументы сигнала триггеру не
## нужны, поэтому обработчик их отбрасывает (`unbind`) и получает только имя события.
func connect_events() -> void:
	for pair: Array in _connected:
		if EventBus.is_connected(str(pair[0]), pair[1] as Callable):
			EventBus.disconnect(str(pair[0]), pair[1] as Callable)
	_connected.clear()
	for event: String in Triggers.events():
		var argc: int = _arg_count(event)
		if argc < 0:
			continue
		var handler: Callable = _on_event.bind(event).unbind(argc)
		EventBus.connect(event, handler)
		_connected.append([event, handler])


func _on_event(event: String) -> void:
	Triggers.fire(event)


## Сколько аргументов у сигнала шины; нет такого сигнала — -1 (валидатор об этом уже сказал).
func _arg_count(event: String) -> int:
	for sig: Dictionary in EventBus.get_signal_list():
		if str(sig["name"]) == event:
			return (sig["args"] as Array).size()
	return -1
