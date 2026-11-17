extends Node
## Идущий диалог и очередь (docs/tech/dialogue-format.md). Запросы — эффектом `start_dialogue`,
## окно — `DialogueOverlay`: оно показывает `current` и зовёт `advance()` / `choose()`.
## Пока идёт диалог, время стоит (`Clock.pause("dialog")`, gameplay/time.md).

const PAUSE_REASON: String = "dialog"

var current: DialogueRun = null
var _queue: PackedStringArray = []


func is_active() -> bool:
	return current != null


## Начать диалог или поставить в очередь, если идёт другой. Нет в данных — false.
func request(dialogue_id: String) -> bool:
	if not DialogueRun.exists(dialogue_id):
		push_error("DialogueManager: нет диалога %s" % dialogue_id)
		return false
	if current != null:
		_queue.append(dialogue_id)
		return true
	_start(dialogue_id)
	return true


func advance() -> void:
	if current == null:
		return
	current.advance()
	_after_step()


func choose(index: int) -> bool:
	if current == null:
		return false
	var ok: bool = current.choose(index)
	_after_step()
	return ok


## Сбросить всё (новая игра, загрузка): окно закроется, время пойдёт.
func clear() -> void:
	_queue.clear()
	if current != null:
		var finished_id: String = current.id
		current = null
		Clock.resume(PAUSE_REASON)
		EventBus.dialogue_ended.emit(finished_id)


func _start(dialogue_id: String) -> void:
	current = DialogueRun.begin(dialogue_id)
	if current == null:
		return
	Clock.pause(PAUSE_REASON)
	EventBus.dialogue_started.emit(dialogue_id)
	_after_step()


func _after_step() -> void:
	if current == null:
		return
	if not current.is_finished():
		EventBus.dialogue_node_changed.emit(current.id, current.node_id)
		return
	var finished_id: String = current.id
	current = null
	Clock.resume(PAUSE_REASON)
	EventBus.dialogue_ended.emit(finished_id)
	if not _queue.is_empty():
		var next_id: String = _queue[0]
		_queue.remove_at(0)
		_start(next_id)
