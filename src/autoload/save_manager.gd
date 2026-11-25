extends Node
## Автосейв (docs/tech/architecture.md, «Сохранения»): каждое начало нового дня игры, пока идёт
## игра (`Clock.running`) — тесты и отладочные сцены двигают часы без автосейва. Логики нет:
## сохраняет `SaveSystem`.

## Выключатель автосейва (настройка на будущее; тесты сейвов включают его явно).
var autosave_enabled: bool = true


func _ready() -> void:
	EventBus.day_started.connect(_on_day_started)


func _on_day_started(_day: int) -> void:
	if not autosave_enabled or not Clock.running:
		return
	# Начало дня приходит посреди хода часов (сон, промотка): пишем в конце кадра, когда всё,
	# что слушает смену дня, уже отработало.
	call_deferred("autosave")


## Автосейв ждёт, пока не кончится полоска программы (ISS-003), и пишет сразу после неё.
var _waiting: bool = false


func autosave() -> String:
	if not SaveSystem.can_save():
		if not _waiting:
			_waiting = true
			Clock.fast_forward_finished.connect(_after_program)
			Clock.fast_forward_dropped.connect(_after_program)
		return SaveSystem.BUSY_ERROR
	var error: String = SaveSystem.save(SaveSystem.SLOT_AUTO)
	if not error.is_empty():
		push_warning("Автосейв: " + error)
	return error


func _after_program() -> void:
	_waiting = false
	Clock.fast_forward_finished.disconnect(_after_program)
	Clock.fast_forward_dropped.disconnect(_after_program)
	# Конец кадра: итог программы и всё, что от него зависит, уже применились.
	call_deferred("autosave")
