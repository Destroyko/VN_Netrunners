class_name DialogueRun
extends RefCounted
## Один идущий диалог (docs/tech/dialogue-format.md): где мы, какие выборы доступны, что дальше.
## Чистые правила без сцен: окно только показывает `node()` и зовёт `advance()` / `choose()`.
##
## Вход в узел: развилка (`branch`) проходится сразу до первого подходящего узла; эффекты узла
## применяются; реплика пишется в журнал. Узел с `end` — последний.

const VAR_JOURNAL: String = "dialogue.journal"
const JOURNAL_LIMIT: int = 300
## Предел переходов подряд без показа реплики: защита от развилок, ведущих по кругу.
const MAX_HOPS: int = 64

var id: String = ""
var node_id: String = ""
var _def: Dictionary = {}
var _finished: bool = false


static func definition(dialogue_id: String) -> Dictionary:
	return DataLoader.dialogues().get(dialogue_id, {}) as Dictionary


static func exists(dialogue_id: String) -> bool:
	return not definition(dialogue_id).is_empty()


## Начать диалог. Нет в данных — null.
static func begin(dialogue_id: String) -> DialogueRun:
	var def: Dictionary = definition(dialogue_id)
	if def.is_empty():
		push_error("DialogueRun: нет диалога в data/dialogues: %s" % dialogue_id)
		return null
	var run := DialogueRun.new()
	run.id = dialogue_id
	run._def = def
	run._enter(str(def.get("start", "")))
	return run


func node() -> Dictionary:
	return (_def.get("nodes", {}) as Dictionary).get(node_id, {}) as Dictionary


func is_finished() -> bool:
	return _finished


## Выборы, которые игрок видит сейчас (с выполненными `requires`), в порядке данных.
func choices() -> Array:
	var list: Array = node().get("choices", []) as Array
	return list.filter(func(c: Dictionary) -> bool: return Conditions.check_all(c.get("requires", []) as Array))


func has_choices() -> bool:
	return node().has("choices")


## Дальше по `next` (у узла с выборами — ничего: ждём выбор). Узел с `end` — диалог закончен.
func advance() -> void:
	if _finished or has_choices():
		return
	var current: Dictionary = node()
	if bool(current.get("end", false)) or not current.has("next"):
		_finished = true
		return
	_enter(str(current["next"]))


## Выбрать ответ: номер среди видимых `choices()`. Пишется в журнал, эффекты применяются.
func choose(index: int) -> bool:
	var visible: Array = choices()
	if _finished or index < 0 or index >= visible.size():
		return false
	var choice: Dictionary = visible[index]
	_journal("hero", str(choice.get("text", "")), true)
	Effects.apply_all(choice.get("effects", []) as Array)
	if choice.has("next"):
		_enter(str(choice["next"]))
	else:
		_finished = true
	return true


func _enter(target: String) -> void:
	var nodes: Dictionary = _def.get("nodes", {}) as Dictionary
	var hops: int = 0
	node_id = target
	while hops < MAX_HOPS:
		hops += 1
		var current: Dictionary = nodes.get(node_id, {}) as Dictionary
		if current.is_empty():
			push_error("DialogueRun: в %s нет узла %s" % [id, node_id])
			_finished = true
			return
		if not current.has("branch"):
			break
		var next_id: String = ""
		for rule: Dictionary in current["branch"] as Array:
			if Conditions.check_all(rule.get("requires", []) as Array):
				next_id = str(rule.get("next", ""))
				break
		if next_id.is_empty():
			_finished = true
			return
		node_id = next_id
	var shown: Dictionary = node()
	Effects.apply_all(shown.get("effects", []) as Array)
	if shown.has("text"):
		_journal(str(shown.get("speaker", "")), str(shown["text"]), false)


## Журнал реплик (`H`): последние `JOURNAL_LIMIT` строк, в сейве.
static func journal() -> Array:
	return GameState.get_var_or(VAR_JOURNAL, []) as Array


func _journal(speaker: String, text: String, is_choice: bool) -> void:
	var list: Array = journal().duplicate()
	list.append({"day": GameState.day, "minute": GameState.minute, "speaker": speaker,
		"text": DialogueText.plain(text), "choice": is_choice})
	while list.size() > JOURNAL_LIMIT:
		list.pop_front()
	GameState.set_var(VAR_JOURNAL, list)
