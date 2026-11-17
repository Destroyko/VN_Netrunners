class_name Validator
extends RefCounted
## Проверка данных в data/: поля, типы условий и эффектов, висячие ссылки на id.
##
## Зачем: контент пишется руками и ИИ, опечатку в id игра молча проглотит
## и квест просто никогда не сработает. Валидатор ловит это до запуска.
## Запуск: godot --headless -s tools/validate_data.gd

## Типы целей этапа, docs/tech/quest-format.md.
const OBJECTIVE_TYPES: PackedStringArray = [
	"hack_node",
	"read_file",
	"copy_file",
	"delete_file",
	"wipe_logs",
	"mask_backup",
	"talk",
	"visit_location",
	"wait_until",
	"deliver",
	"file_at",
	"read_mail",
	"complete_quest",
]

const QUEST_TYPES: PackedStringArray = ["main", "side", "radiant"]
const CHANNELS: PackedStringArray = ["email", "messenger", "group_site"]

var errors: PackedStringArray = []
var warnings: PackedStringArray = []

# Узлы нужны проверке эффектов: reveal_node ссылается на узел и его сервисы.
var _nodes: Dictionary = {}
# Письма нужны проверке эффектов: send_message ссылается на письмо.
var _mail: Dictionary = {}
# Новости нужны проверке эффектов: schedule_news ссылается на новость.
var _news: Dictionary = {}
# Диалоги — для start_dialogue и цели talk; персонажи и глоссарий — для проверки диалогов.
var _dialogues: Dictionary = {}
# Локации — для move_to и цели visit_location.
var _locations: Dictionary = {}
# Сообщения мессенджера — для send_text.
var _messages: Dictionary = {}


## Проверить все данные из data/. true — ошибок нет.
func validate_all() -> bool:
	DataLoader.clear_cache()
	_dialogues = DataLoader.dialogues()
	_locations = DataLoader.locations()
	_messages = DataLoader.messages()
	var ok: bool = validate_data(
		DataLoader.nodes(), DataLoader.news(), DataLoader.quests(), DataLoader.triggers(),
		DataLoader.mail()
	)
	var dialogue_validator := DialogueValidator.new()
	dialogue_validator.validate(_dialogues, DataLoader.characters(), DataLoader.glossary())
	errors.append_array(dialogue_validator.errors)
	warnings.append_array(dialogue_validator.warnings)
	for id: String in _dialogues.keys():
		for node_variant: Variant in ((_dialogues[id] as Dictionary).get("nodes", {}) as Dictionary).values():
			var node: Dictionary = node_variant as Dictionary
			_validate_effects("диалог %s" % id, node.get("effects", []) as Array, DataLoader.quests())
			for choice_variant: Variant in node.get("choices", []) as Array:
				var choice: Dictionary = choice_variant as Dictionary
				_validate_conditions("диалог %s, выбор" % id, choice.get("requires", []) as Array)
				_validate_effects("диалог %s, выбор" % id, choice.get("effects", []) as Array, DataLoader.quests())
	var characters: Dictionary = DataLoader.characters()
	for id: String in _messages.keys():
		_validate_text_message(id, _messages[id] as Dictionary, characters)
	var location_validator := LocationValidator.new()
	location_validator.validate(_locations, _dialogues)
	errors.append_array(location_validator.errors)
	warnings.append_array(location_validator.warnings)
	for id: String in _locations.keys():
		for object_variant: Variant in (_locations[id] as Dictionary).get("objects", []) as Array:
			var object: Dictionary = object_variant as Dictionary
			if object == null:
				continue
			var at: String = "локация %s, объект %s" % [id, object.get("id", "")]
			_validate_conditions(at, object.get("requires", []) as Array)
			_validate_conditions(at, object.get("open_requires", []) as Array)
	ok = ok and errors.is_empty()
	_validate_balance()
	return ok and errors.is_empty()


## Та же проверка, но на переданных данных — так валидатор можно проверить тестами.
func validate_data(
	nodes: Dictionary, news: Dictionary, quests: Dictionary, triggers: Dictionary,
	mail: Dictionary = {}
) -> bool:
	errors.clear()
	warnings.clear()
	_nodes = nodes
	_mail = mail
	_news = news

	# Какие узлы открывают заказы: у них вход не через scan, и недостижимыми они не считаются.
	var revealed: Dictionary = {}
	for source: Dictionary in [nodes, quests, triggers]:
		Effects.collect_revealed(source, revealed)

	# Узлы проверяет отдельный класс, его находки подмешиваем к своим.
	var node_validator := NodeValidator.new()
	node_validator.validate_all(nodes, revealed)
	errors.append_array(node_validator.errors)
	warnings.append_array(node_validator.warnings)

	# Словарь головоломок и их параметры — тоже отдельный класс.
	var puzzle_validator := PuzzleValidator.new()
	puzzle_validator.validate(DataLoader.puzzle_words(), DataLoader.balance())
	errors.append_array(puzzle_validator.errors)
	warnings.append_array(puzzle_validator.warnings)

	var program_validator := ProgramValidator.new()
	program_validator.validate(DataLoader.programs(), DataLoader.balance())
	errors.append_array(program_validator.errors)
	warnings.append_array(program_validator.warnings)

	var item_validator := ItemValidator.new()
	item_validator.validate(DataLoader.items())
	errors.append_array(item_validator.errors)
	warnings.append_array(item_validator.warnings)

	for id: String in news.keys():
		_validate_news(id, news[id] as Dictionary)
	for id: String in quests.keys():
		_validate_quest(id, quests[id] as Dictionary, nodes, news, quests)
	for id: String in triggers.keys():
		_validate_trigger(id, triggers[id] as Dictionary, news, quests)
	for id: String in mail.keys():
		_validate_mail(id, mail[id] as Dictionary, quests)

	return errors.is_empty()


func summary() -> String:
	var lines: PackedStringArray = []
	for w: String in warnings:
		lines.append("ПРЕДУПРЕЖДЕНИЕ: " + w)
	for e: String in errors:
		lines.append("ОШИБКА: " + e)
	if errors.is_empty():
		lines.append("Данные в порядке: ошибок нет (предупреждений: %d)." % warnings.size())
	else:
		lines.append("Ошибок: %d, предупреждений: %d." % [errors.size(), warnings.size()])
	return "\n".join(lines)


# --- Проверки по типам файлов ------------------------------------------------

func _validate_balance() -> void:
	var balance: Dictionary = DataLoader.balance()
	if balance.is_empty():
		errors.append("data/balance.json не найден или пустой")
		return
	# Разделы, на которые уже опирается код.
	for section: String in ["clock", "action_minutes", "economy", "needs", "heat"]:
		if not balance.has(section):
			warnings.append("balance.json: нет раздела '%s'" % section)


func _validate_news(id: String, item: Dictionary) -> void:
	_require_fields("новость " + id, item, ["id"])


func _validate_quest(
	id: String, quest: Dictionary, nodes: Dictionary, news: Dictionary, quests: Dictionary
) -> void:
	var where: String = "квест " + id
	_require_fields(where, quest, ["id", "type"])

	var type: String = str(quest.get("type", ""))
	if not type.is_empty() and not QUEST_TYPES.has(type):
		errors.append("%s: неизвестный тип '%s'" % [where, type])

	if quest.has("channel") and not CHANNELS.has(str(quest["channel"])):
		errors.append("%s: неизвестный канал '%s'" % [where, quest["channel"]])

	_validate_conditions(where, quest.get("requires", []) as Array)

	# Мини-квест знает родителя: планировщик показывает его внутри родителя, а не отдельной строкой.
	if quest.has("parent") and not quests.has(str(quest["parent"])):
		errors.append("%s: parent ссылается на несуществующий квест '%s'" % [where, quest["parent"]])

	var stages: Array = quest.get("stages", []) as Array
	if stages.is_empty():
		errors.append("%s: нет этапов (stages)" % where)

	var outcomes: Dictionary = quest.get("outcomes", {}) as Dictionary

	# Квест со сроком обязан описать, что будет, если срок вышел:
	# иначе провал по времени проходит без последствий (docs/tech/quest-format.md).
	if quest.has("deadline_days"):
		if int(quest["deadline_days"]) <= 0:
			errors.append("%s: deadline_days должен быть больше нуля" % where)
		if not outcomes.has("expired"):
			errors.append("%s: есть срок (deadline_days), но нет исхода 'expired'" % where)

	var stage_ids: Dictionary = {}

	for stage_variant: Variant in stages:
		var stage: Dictionary = stage_variant as Dictionary
		if stage == null:
			errors.append("%s: этап должен быть объектом" % where)
			continue
		var stage_id: String = str(stage.get("id", ""))
		if stage_id.is_empty():
			errors.append("%s: у этапа нет id" % where)
			continue
		if stage_ids.has(stage_id):
			errors.append("%s: повторяющийся id этапа '%s'" % [where, stage_id])
		stage_ids[stage_id] = true

		var stage_where: String = "%s, этап %s" % [where, stage_id]
		_validate_conditions(stage_where, stage.get("requires", []) as Array)
		_validate_objectives(stage_where, stage.get("objectives", []) as Array, nodes)
		# Скрытой может быть только необязательная цель: обязательную скрытую игрок не увидит
		# и не поймёт, почему квест не закрывается.
		for objective_variant: Variant in stage.get("objectives", []) as Array:
			if objective_variant is Dictionary and bool((objective_variant as Dictionary).get("hidden", false)):
				errors.append("%s: скрытой (hidden) может быть только необязательная цель" % stage_where)
		_validate_objectives(stage_where, stage.get("optional", []) as Array, nodes)
		_validate_choices(stage_where, stage.get("choices", []) as Array, outcomes)
		_validate_effects(stage_where, stage.get("effects", []) as Array, quests)

	for outcome_id: String in outcomes.keys():
		var outcome: Dictionary = outcomes[outcome_id] as Dictionary
		var outcome_where: String = "%s, исход %s" % [where, outcome_id]
		_validate_effects(outcome_where, outcome.get("effects", []) as Array, quests)
		_validate_news_refs(outcome_where, outcome.get("news", []) as Array, news)


func _validate_trigger(
	id: String, trigger: Dictionary, news: Dictionary, quests: Dictionary
) -> void:
	var where: String = "триггер " + id
	_require_fields(where, trigger, ["id", "on", "effects"])

	var event_name: String = str(trigger.get("on", ""))
	if not event_name.is_empty() and not _event_exists(event_name):
		errors.append("%s: нет такого события в EventBus: '%s'" % [where, event_name])

	_validate_conditions(where, trigger.get("requires", []) as Array)
	_validate_effects(where, trigger.get("effects", []) as Array, quests)
	_validate_news_refs(where, trigger.get("news", []) as Array, news)


## Письмо: обязательные поля, id с префиксом, вложения с именем, ответы с уникальным id и
## проверенными условиями и эффектами.
## Сообщение мессенджера: от известного персонажа, с текстом, ответы — как у письма.
func _validate_text_message(id: String, message: Dictionary, characters: Dictionary) -> void:
	var where: String = "сообщение " + id
	_require_fields(where, message, ["id", "from", "text"])
	if not id.begins_with("msg_"):
		errors.append("%s: id должен начинаться с 'msg_'" % where)
	if not characters.is_empty() and not characters.has(str(message.get("from", ""))):
		errors.append("%s: неизвестный отправитель '%s' (нет в characters.json)" % [where, message.get("from", "")])
	var seen: Dictionary = {}
	for reply_variant: Variant in message.get("replies", []) as Array:
		var reply: Dictionary = reply_variant as Dictionary
		if reply == null:
			errors.append("%s: ответ должен быть объектом" % where)
			continue
		var reply_id: String = str(reply.get("id", ""))
		if reply_id.is_empty() or str(reply.get("text", "")).is_empty():
			errors.append("%s: у ответа нужны id и text" % where)
		elif seen.has(reply_id):
			errors.append("%s: два ответа с id '%s'" % [where, reply_id])
		seen[reply_id] = true
		_validate_conditions(where + ", ответ " + reply_id, reply.get("requires", []) as Array)
		_validate_effects(where + ", ответ " + reply_id, reply.get("effects", []) as Array, DataLoader.quests())


func _validate_mail(id: String, letter: Dictionary, quests: Dictionary) -> void:
	var where: String = "письмо " + id
	_require_fields(where, letter, ["id", "from", "subject", "body"])
	if not id.begins_with("mail_"):
		errors.append("%s: id должен начинаться с 'mail_'" % where)
	for file_variant: Variant in letter.get("attachments", []) as Array:
		var file: Dictionary = file_variant as Dictionary
		if file == null or str(file.get("name", "")).is_empty():
			errors.append("%s: у вложения нет name" % where)
	var seen: Dictionary = {}
	for reply_variant: Variant in letter.get("replies", []) as Array:
		var reply: Dictionary = reply_variant as Dictionary
		if reply == null:
			errors.append("%s: ответ должен быть объектом" % where)
			continue
		var reply_id: String = str(reply.get("id", ""))
		if reply_id.is_empty() or str(reply.get("text", "")).is_empty():
			errors.append("%s: у ответа нужны id и text" % where)
		elif seen.has(reply_id):
			errors.append("%s: два ответа с id '%s'" % [where, reply_id])
		seen[reply_id] = true
		_validate_conditions(where + ", ответ " + reply_id, reply.get("requires", []) as Array)
		_validate_effects(where + ", ответ " + reply_id, reply.get("effects", []) as Array, quests)


## `quest_choice` ведёт в существующий квест и существующий выбор одного из его этапов.
func _check_quest_choice(where: String, value: Variant, quests: Dictionary) -> PackedStringArray:
	var found: PackedStringArray = []
	var pick: Array = value as Array
	if pick == null or pick.size() != 2:
		found.append("%s: quest_choice ожидает [квест, выбор]" % where)
		return found
	if quests.is_empty():
		return found  # проверка без квестов (тесты частей валидатора)
	var quest: Dictionary = quests.get(str(pick[0]), {}) as Dictionary
	if quest.is_empty():
		found.append("%s: quest_choice ссылается на несуществующий квест '%s'" % [where, pick[0]])
		return found
	for stage: Dictionary in quest.get("stages", []) as Array:
		for choice: Dictionary in stage.get("choices", []) as Array:
			if str(choice.get("id", "")) == str(pick[1]):
				return found
	found.append("%s: в квесте '%s' нет выбора '%s'" % [where, pick[0], pick[1]])
	return found


# --- Общие проверки ----------------------------------------------------------

func _require_fields(where: String, data: Dictionary, fields: Array) -> void:
	for field: String in fields:
		if not data.has(field):
			errors.append("%s: нет обязательного поля '%s'" % [where, field])


func _validate_conditions(where: String, conditions: Array) -> void:
	for condition_variant: Variant in conditions:
		var condition: Dictionary = condition_variant as Dictionary
		if condition == null:
			errors.append("%s: условие должно быть объектом" % where)
			continue
		for type: String in condition.keys():
			if not Conditions.is_known(type):
				errors.append("%s: неизвестный тип условия '%s'" % [where, type])


func _validate_effects(where: String, effects: Array, quests: Dictionary) -> void:
	for effect_variant: Variant in effects:
		var effect: Dictionary = effect_variant as Dictionary
		if effect == null:
			errors.append("%s: эффект должен быть объектом" % where)
			continue
		for type: String in effect.keys():
			if not Effects.is_known(type):
				errors.append("%s: неизвестный тип эффекта '%s'" % [where, type])
				continue
			if type == "reveal_node":
				errors.append_array(NodeValidator.check_reveal(where, effect[type], _nodes))
			if type == "start_dialogue" and not _dialogues.is_empty() and not _dialogues.has(str(effect[type])):
				errors.append("%s: start_dialogue ссылается на несуществующий диалог '%s'" % [where, effect[type]])
			if type == "send_text" and not _messages.is_empty() and not _messages.has(str(effect[type])):
				errors.append("%s: send_text ссылается на несуществующее сообщение '%s'" % [where, effect[type]])
			if type == "move_to" and not _locations.is_empty() and not _locations.has(str(effect[type])):
				errors.append("%s: move_to ссылается на несуществующую локацию '%s'" % [where, effect[type]])
			if type == "schedule_news":
				var news_id: String = str((effect[type] as Dictionary).get("id", "")) if effect[type] is Dictionary else str(effect[type])
				if not _news.has(news_id):
					errors.append("%s: schedule_news ссылается на несуществующую новость '%s'" % [where, news_id])
			if type == "schedule":
				var spec: Dictionary = effect[type] as Dictionary if effect[type] is Dictionary else {}
				if spec.has("at") and Rest.parse_clock(str(spec["at"])) < 0:
					errors.append("%s: schedule.at — время ЧЧ:ММ, получено '%s'" % [where, spec["at"]])
				_validate_effects(where + ", schedule", spec.get("effects", []) as Array, quests)
			if type == "add_file":
				var file_spec: Dictionary = effect[type] as Dictionary if effect[type] is Dictionary else {}
				if str(file_spec.get("path", "")).is_empty():
					errors.append("%s: add_file без path" % where)
			if type == "quest_choice":
				errors.append_array(_check_quest_choice(where, effect[type], quests))
			if type == "send_message" and not _mail.has(str(effect[type])):
				errors.append("%s: send_message ссылается на несуществующее письмо '%s'" % [where, effect[type]])
			if type == "unlock_quest" and not quests.has(str(effect[type])):
				errors.append("%s: unlock_quest ссылается на несуществующий квест '%s'" % [where, effect[type]])


func _validate_objectives(where: String, objectives: Array, nodes: Dictionary) -> void:
	for objective_variant: Variant in objectives:
		var objective: Dictionary = objective_variant as Dictionary
		if objective == null:
			errors.append("%s: цель должна быть объектом" % where)
			continue
		var type: String = str(objective.get("type", ""))
		if type.is_empty():
			errors.append("%s: у цели нет поля type" % where)
			continue
		if not OBJECTIVE_TYPES.has(type):
			errors.append("%s: неизвестный тип цели '%s'" % [where, type])
		# Ссылку на узел проверяем, если это не подстановка шаблона radiant ({phone}).
		if objective.has("node"):
			var node_id: String = str(objective["node"])
			if not _is_template(node_id) and not nodes.has(node_id):
				errors.append("%s: цель ссылается на несуществующий узел '%s'" % [where, node_id])
		if type == "read_mail" and not _mail.is_empty() and not _mail.has(str(objective.get("mail", ""))):
			errors.append("%s: read_mail ссылается на несуществующее письмо '%s'" % [where, objective.get("mail", "")])
		if type == "complete_quest" and not DataLoader.quests().has(str(objective.get("quest", ""))):
			errors.append("%s: complete_quest ссылается на несуществующий квест '%s'" % [where, objective.get("quest", "")])
		if type == "wait_until" and not objective.has("until") and not objective.has("after"):
			errors.append("%s: у wait_until нужно until или after" % where)
		if type == "visit_location" and not _locations.is_empty() and not _locations.has(str(objective.get("location", ""))):
			errors.append("%s: visit_location ссылается на несуществующую локацию '%s'" % [where, objective.get("location", "")])
		if objective.has("on_done"):
			_validate_effects(where + ", on_done", objective["on_done"] as Array, {})


func _validate_choices(where: String, choices: Array, outcomes: Dictionary) -> void:
	for choice_variant: Variant in choices:
		var choice: Dictionary = choice_variant as Dictionary
		if choice == null:
			errors.append("%s: выбор должен быть объектом" % where)
			continue
		_require_fields(where + ", выбор", choice, ["id"])
		_validate_conditions(where + ", выбор " + str(choice.get("id", "?")), choice.get("requires", []) as Array)
		if choice.has("outcome") and not outcomes.has(str(choice["outcome"])):
			errors.append("%s: выбор '%s' ведёт в несуществующий исход '%s'" % [where, choice.get("id", "?"), choice["outcome"]])


func _validate_news_refs(where: String, news_refs: Array, news: Dictionary) -> void:
	for ref_variant: Variant in news_refs:
		var ref: Dictionary = ref_variant as Dictionary
		if ref == null:
			errors.append("%s: новость должна быть объектом" % where)
			continue
		var news_id: String = str(ref.get("id", ""))
		if news_id.is_empty():
			errors.append("%s: у новости нет id" % where)
		elif not news.has(news_id):
			errors.append("%s: ссылка на несуществующую новость '%s'" % [where, news_id])


func _is_template(value: String) -> bool:
	return value.begins_with("{") and value.ends_with("}")


## EventBus доступен, только когда скрипт запущен как SceneTree (так делают тесты и tools/).
func _event_exists(event_name: String) -> bool:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is not SceneTree:
		return true
	var bus: Node = (loop as SceneTree).root.get_node_or_null(^"EventBus")
	if bus == null:
		return true
	return bus.has_signal(event_name)
