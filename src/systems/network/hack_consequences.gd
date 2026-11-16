class_name HackConsequences
extends RefCounted
## Последствия событий взлома для мира (docs/gameplay/hacking.md, «Трейс»): что меняется в
## состоянии игры, когда сеанс закрылся, трейс дошёл до конца или узел ушёл из сети.
##
## Применяются ровно один раз на событие, где бы оно ни случилось: от хода часов (`HackManager`)
## или от действия игрока (`dc`, саботаж). Что игроку напечатать — решает терминал, не здесь.

## Ворота `gate.cover` (docs/tech/gates.md): пока открыты, за игроком подчищают — его сеансы
## на чужих узлах не оставляют записей в логах. Кто и почему подчищает — решают рельсы.
const GATE_COVER: String = "gate.cover"


static func traces_covered() -> bool:
	return GameState.has_flag(GATE_COVER)


## Применить события от `HackSession.advance` / `node_sabotaged`.
static func apply(events: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		var node: String = str(event.get("node", ""))
		match str(event["type"]):
			"connection_lost":
				session_closed(node, bool(event["was_connected"]))
			"trace_finished":
				# Цель перенастроила защиту: частичные слои и счётчики попыток узла обнуляются.
				PuzzleProgress.for_game().reset_node(node)
				EventBus.trace_finished.emit(node)
				session_closed(node, bool(event["was_connected"]))


## Сеанс с узлом закончился — по `dc`, обрыву или трейсу. Запись о выходе пишется всегда и
## после любой чистки: бесследно уйти нельзя (hacking.md) — если за игроком не подчищают.
static func session_closed(node: String, was_connected: bool) -> void:
	if not was_connected:
		return
	if not traces_covered():
		Logbook.for_node(node).append(
			Logbook.CATEGORY_SESSION, "сеанс закрыт", GameState.day, GameState.minute, false, "logout"
		)
	EventBus.node_disconnected.emit(node)
