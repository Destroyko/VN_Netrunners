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


func autosave() -> String:
	var error: String = SaveSystem.save(SaveSystem.SLOT_AUTO)
	if not error.is_empty():
		push_warning("Автосейв: " + error)
	return error
