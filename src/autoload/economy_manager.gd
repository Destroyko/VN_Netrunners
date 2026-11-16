extends Node
## Слушатель экономики: начало дня → `Economy.on_day_started` (аренда, пеня, напоминания),
## ход часов → `Shop.on_time_passed` (доставка приехала).
## Логики здесь нет — только подписка (docs/tech/architecture.md, docs/gameplay/economy.md).


func _ready() -> void:
	EventBus.day_started.connect(Economy.on_day_started)
	EventBus.time_advanced.connect(func(_minute: int, _passed: int) -> void: Shop.on_time_passed())
