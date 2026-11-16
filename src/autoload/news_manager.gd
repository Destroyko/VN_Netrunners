extends Node
## Слушатель новостей: начало дня → публикация последствий и одной фоновой новости.
## Логики здесь нет — только подписка (docs/tech/architecture.md, docs/gameplay/news.md).


func _ready() -> void:
	EventBus.day_started.connect(_on_day_started)


func _on_day_started(day: int) -> void:
	News.publish_due(day)
	News.publish_background(day)
