extends Node
## Слушатель заметности: связывает события шины с правилами `Heat`.
## Логики здесь нет — только подписки (docs/tech/architecture.md, docs/gameplay/heat.md).


func _ready() -> void:
	EventBus.puzzle_failed.connect(_on_puzzle_failed)
	EventBus.trace_finished.connect(_on_trace_finished)
	EventBus.node_disconnected.connect(_on_node_disconnected)
	EventBus.time_advanced.connect(func(_minute: int, _passed: int) -> void: Heat.on_time_passed())


func _on_puzzle_failed(_kind: String, _difficulty: int, _node_id: String, _service_id: String, attempt: int) -> void:
	Heat.gain(Heat.puzzle_failed_cost(attempt))


func _on_trace_finished(_node_id: String) -> void:
	Heat.gain(Heat.trace_finished_cost())


## Запись о выходе уже написана терминалом, так что неустранимая единица входит в цену.
func _on_node_disconnected(node_id: String) -> void:
	Heat.pay_traces(node_id)

