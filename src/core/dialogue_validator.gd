class_name DialogueValidator
extends RefCounted
## Проверка диалогов (docs/tech/dialogue-format.md): у узла ровно одно продолжение, ссылки ведут
## в существующие узлы, все узлы достижимы, говорящие и эмоции известны, термины есть в
## глоссарии. Условия и эффекты проверяет общий `Validator`.

const EMOTIONS: PackedStringArray = ["neutral", "smile", "surprise", "anger", "sad", "embarrassed", "thoughtful"]
const ENDINGS: PackedStringArray = ["next", "choices", "branch", "end"]

var errors: PackedStringArray = []
var warnings: PackedStringArray = []


func validate(dialogues: Dictionary, characters: Dictionary, glossary: Dictionary) -> void:
	errors.clear()
	warnings.clear()
	for id: String in dialogues.keys():
		_validate_one(id, dialogues[id] as Dictionary, characters, glossary)


func _validate_one(id: String, dlg: Dictionary, characters: Dictionary, glossary: Dictionary) -> void:
	var where: String = "диалог " + id
	if not id.begins_with("dlg_"):
		errors.append("%s: id должен начинаться с 'dlg_'" % where)
	var nodes: Dictionary = dlg.get("nodes", {}) as Dictionary
	var start: String = str(dlg.get("start", ""))
	if not nodes.has(start):
		errors.append("%s: нет стартового узла '%s'" % [where, start])
		return
	for node_id: String in nodes.keys():
		var node: Dictionary = nodes[node_id] as Dictionary
		var at: String = "%s, узел %s" % [where, node_id]
		var ways: int = 0
		for key: String in ENDINGS:
			if node.has(key):
				ways += 1
		if ways != 1:
			errors.append("%s: нужно ровно одно из next / choices / branch / end" % at)
		if node.has("speaker") and not characters.has(str(node["speaker"])):
			errors.append("%s: неизвестный говорящий '%s'" % [at, node["speaker"]])
		if node.has("emotion") and not EMOTIONS.has(str(node["emotion"])):
			errors.append("%s: неизвестная эмоция '%s'" % [at, node["emotion"]])
		for target: String in _targets(node):
			if not nodes.has(target):
				errors.append("%s: ссылка на несуществующий узел '%s'" % [at, target])
		var texts: Array = [str(node.get("text", ""))]
		for choice: Variant in node.get("choices", []) as Array:
			texts.append(str((choice as Dictionary).get("text", "")))
		for text: String in texts:
			for term: String in DialogueText.terms(text):
				if not glossary.has(term):
					errors.append("%s: термина '%s' нет в data/glossary.json" % [at, term])
	for node_id: String in nodes.keys():
		if not _reachable(nodes, start).has(node_id):
			warnings.append("%s: узел '%s' недостижим" % [where, node_id])


func _targets(node: Dictionary) -> PackedStringArray:
	var found: PackedStringArray = []
	if node.has("next"):
		found.append(str(node["next"]))
	for choice: Variant in node.get("choices", []) as Array:
		if (choice as Dictionary).has("next"):
			found.append(str((choice as Dictionary)["next"]))
	for rule: Variant in node.get("branch", []) as Array:
		found.append(str((rule as Dictionary).get("next", "")))
	return found


func _reachable(nodes: Dictionary, start: String) -> Dictionary:
	var seen: Dictionary = {}
	var stack: Array = [start]
	while not stack.is_empty():
		var current: String = str(stack.pop_back())
		if seen.has(current) or not nodes.has(current):
			continue
		seen[current] = true
		for target: String in _targets(nodes[current] as Dictionary):
			stack.append(target)
	return seen
