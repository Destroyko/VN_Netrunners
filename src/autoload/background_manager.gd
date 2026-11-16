extends Node
## Слушатель фоновых задач: ход часов → `BackgroundTasks.on_time_passed`. Логики нет — только
## подписка (docs/tech/architecture.md). reboot их останавливает (там же, в терминале).


func _ready() -> void:
	EventBus.time_advanced.connect(func(_minute: int, _passed: int) -> void: BackgroundTasks.on_time_passed())
