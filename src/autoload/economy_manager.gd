extends Node
## Слушатель экономики: начало дня → `Economy.on_day_started` (аренда, пеня, напоминания).
## Логики здесь нет — только подписка (docs/tech/architecture.md, docs/gameplay/economy.md).


func _ready() -> void:
	EventBus.day_started.connect(Economy.on_day_started)
