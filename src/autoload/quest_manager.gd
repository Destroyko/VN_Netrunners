extends Node
## Слушатель квестов: события шины → `Quests` (цели, сроки). Логики здесь нет — только
## подписки (docs/tech/architecture.md). Что считается целью — `QuestObjectives`.


func _ready() -> void:
	EventBus.node_connected.connect(func(node: String) -> void: _event("node_connected", node))
	EventBus.node_disconnected.connect(func(node: String) -> void: _event("node_disconnected", node))
	EventBus.file_read.connect(func(node: String, path: String) -> void: _event("file_read", node, path))
	EventBus.file_copied.connect(func(node: String, path: String) -> void: _event("file_copied", node, path))
	EventBus.file_deleted.connect(func(node: String, path: String) -> void: _event("file_deleted", node, path))
	# Цели «по состоянию» (файл у героя, время) перепроверяются, когда что-то могло их выполнить.
	EventBus.attachment_saved.connect(func(_uid: String, _path: String) -> void: Quests.on_event({}))
	EventBus.mail_sent.connect(func(to: String, file_ids: PackedStringArray) -> void:
		Quests.on_event({"event": "mail_sent", "to": to, "file_ids": file_ids}))
	EventBus.time_advanced.connect(func(_m: int, passed: int) -> void: _on_time(passed))
	EventBus.dialogue_ended.connect(func(id: String) -> void:
		Quests.on_event({"event": "dialogue_ended", "dialogue": id}))
	# Прочитал письмо — цель «проверить почту» перепроверяется (она по состоянию).
	EventBus.mail_read.connect(func(_uid: String, _mail_id: String) -> void: Quests.on_event({}))
	# Мини-квест закончился — этап родителя («закончить мини-квест») перепроверяется.
	EventBus.quest_completed.connect(func(_id: String, _outcome: String) -> void: Quests.on_event({}))
	EventBus.location_entered.connect(func(id: String) -> void:
		Quests.on_event({"event": "location_entered", "location": id}))
	EventBus.day_started.connect(Quests.on_day_started)


func _event(name: String, node: String, path: String = "") -> void:
	Quests.on_event({"event": name, "node": node, "path": path})


## Ход часов — только для целей «дождаться»: раз в час игрового времени, а не каждую минуту.
func _on_time(passed: int) -> void:
	if passed >= 60 or GameState.minute % 60 == 0:
		Quests.on_event({})
