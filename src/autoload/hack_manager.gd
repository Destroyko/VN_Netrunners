extends Node
## Слушатель хода времени для взлома: часы сдвинулись — сеанс взлома тикает (трейс, обрыв по
## расписанию узла), последствия применяются один раз, а терминалы узнают о случившемся из шины
## (`session_advanced`). Логики здесь нет — правила в `HackSession` и `HackConsequences`.
##
## Раньше это делал сам терминал, и терминалов могло быть несколько: приходилось защищаться
## статическими переменными от двойного счёта (технический разбор 16.11.2026).


func _ready() -> void:
	EventBus.time_advanced.connect(_on_time_advanced)


func _on_time_advanced(_minute: int, minutes_passed: int) -> void:
	var net: Network = Network.for_game()
	var session := HackSession.new(net)
	if session.target_id().is_empty():
		return
	var was_tracing: bool = session.is_tracing()
	var now: int = net.abs_minute(GameState.day, GameState.minute)
	var events: Array[Dictionary] = session.advance(minutes_passed, now)
	HackConsequences.apply(events)
	# Пустой список тоже сообщаем, пока идёт трейс: окну нужно сдвинуть полоску.
	if was_tracing or not events.is_empty():
		EventBus.session_advanced.emit(events)
