class_name Quests
extends RefCounted
## Исполнитель квестов из JSON (docs/tech/quest-format.md): старт, этапы по порядку, цели по
## событиям шины, необязательные цели с бонусом, выбор, срок и исходы.
##
## Чистые правила без сцен. События шины передаёт сюда автозагрузка `QuestManager`. Квест
## начинается эффектом `unlock_quest` (триггер, ответ на письмо, другой квест), выбор делается
## эффектом `quest_choice` — обычно из ответа на письмо. Так почта и квесты не знают друг о
## друге: связывают их данные.
##
## Состояние — `GameState.quest_entry(id)`: {stage, started_day, done: {ключ цели: true},
## completed, outcome}. Ключ цели — "o<номер>" для обязательных и "p<номер>" для необязательных.

const OUTCOME_DONE: String = "done"
const OUTCOME_EXPIRED: String = "expired"


static func definition(id: String) -> Dictionary:
	return DataLoader.quests().get(id, {}) as Dictionary


static func is_active(id: String) -> bool:
	return GameState.is_quest_started(id) and not GameState.is_quest_completed(id)


static func active() -> Array:
	return GameState.quest_ids().filter(func(id: String) -> bool: return is_active(id))


## Начать квест. Нет в данных, уже начат или не выполнены `requires` — false.
static func start(id: String) -> bool:
	var def: Dictionary = definition(id)
	if def.is_empty():
		push_error("Quests: нет квеста в data/quests: %s" % id)
		return false
	if GameState.is_quest_started(id) or not Conditions.check_all(def.get("requires", []) as Array):
		return false
	var stages: Array = def.get("stages", []) as Array
	if stages.is_empty():
		return false
	var entry: Dictionary = GameState.quest_entry(id)
	entry["started_day"] = GameState.day
	_enter_stage(id, str((stages[0] as Dictionary)["id"]))
	return true


## Последний день срока (включительно): получен в день N, срок 3 — успеть до конца дня N+3.
static func due_day(id: String) -> int:
	var def: Dictionary = definition(id)
	if not def.has("deadline_days"):
		return 0
	return int(GameState.quest_entry(id).get("started_day", GameState.day)) + int(def["deadline_days"])


static func current_stage(id: String) -> Dictionary:
	var stage_id: String = GameState.get_quest_stage(id)
	for stage: Dictionary in definition(id).get("stages", []) as Array:
		if str(stage["id"]) == stage_id:
			return stage
	return {}


## Чекпоинты текущего этапа, как их видит игрок: [{key, objective, done, optional}].
## Скрытая цель (`"hidden": true`, только среди необязательных) появляется в списке лишь после
## выполнения — так игрок узнаёт, что в игре бывают этапы, о которых не говорят заранее
## (разработчик, 17.11.2026). Окна журнала пока нет — это его данные.
static func visible_objectives(id: String) -> Array:
	var stage: Dictionary = current_stage(id)
	var shown: Array = []
	for pair: Array in [["o", stage.get("objectives", []), false], ["p", stage.get("optional", []), true]]:
		var list: Array = pair[1] as Array
		for i: int in list.size():
			var key: String = "%s%d" % [pair[0], i]
			var objective: Dictionary = list[i]
			var done: bool = is_done(id, key)
			if bool(objective.get("hidden", false)) and not done:
				continue
			shown.append({"key": key, "objective": objective, "done": done, "optional": bool(pair[2])})
	return shown


static func is_done(id: String, key: String) -> bool:
	return bool((GameState.quest_entry(id).get("done", {}) as Dictionary).get(key, false))


## Случилось событие шины — закрыть подходящие цели у всех активных квестов.
static func on_event(event: Dictionary) -> void:
	for id: String in active():
		_progress(id, event)


## Начался день: сроки. Истёк — исход `expired`.
static func on_day_started(day: int) -> void:
	for id: String in active():
		var due: int = due_day(id)
		if due > 0 and day > due:
			finish(id, OUTCOME_EXPIRED)


## Выбор игрока на текущем этапе (эффект `quest_choice`). Чужой этап, нет такого выбора или не
## выполнены его `requires` — false.
static func choose(id: String, choice_id: String) -> bool:
	if not is_active(id):
		return false
	for choice: Dictionary in current_stage(id).get("choices", []) as Array:
		if str(choice.get("id", "")) != choice_id:
			continue
		if not Conditions.check_all(choice.get("requires", []) as Array):
			return false
		Effects.apply_all(choice.get("effects", []) as Array)
		if choice.has("outcome"):
			finish(id, str(choice["outcome"]))
		else:
			_next_stage(id)
		return true
	return false


## Закончить квест исходом: его эффекты и новости-последствия.
static func finish(id: String, outcome: String) -> void:
	if not is_active(id):
		return
	var result: Dictionary = (definition(id).get("outcomes", {}) as Dictionary).get(outcome, {}) as Dictionary
	Effects.apply_all(result.get("effects", []) as Array)
	for news: Dictionary in result.get("news", []) as Array:
		Effects.apply({"schedule_news": news})
	GameState.set_quest_completed(id, outcome)


# --- Внутреннее -----------------------------------------------------------------

static func _enter_stage(id: String, stage_id: String) -> void:
	var entry: Dictionary = GameState.quest_entry(id)
	entry["done"] = {}
	# День начала этапа: от него считается «дождаться утра».
	entry["stage_day"] = GameState.day
	GameState.set_quest_stage(id, stage_id)
	var stage: Dictionary = current_stage(id)
	Effects.apply_all(stage.get("effects", []) as Array)
	# Цели «по состоянию» могли быть выполнены заранее (файл уже лежит у героя).
	_progress(id, {})


static func _progress(id: String, event: Dictionary) -> void:
	var stage: Dictionary = current_stage(id)
	if stage.is_empty():
		return
	var stage_id: String = str(stage["id"])
	var done: Dictionary = GameState.quest_entry(id).get("done", {}) as Dictionary
	_mark(id, stage.get("optional", []) as Array, "p", event, done, true)
	_mark(id, stage.get("objectives", []) as Array, "o", event, done, false)
	GameState.quest_entry(id)["done"] = done
	# Цель могла закончить квест (эффект on_done) или сменить этап — тогда дальше не идём.
	if not is_active(id) or GameState.get_quest_stage(id) != stage_id:
		return
	if _stage_complete(stage, done):
		_next_stage(id)


static func _mark(id: String, list: Array, prefix: String, event: Dictionary, done: Dictionary, optional: bool) -> void:
	for i: int in list.size():
		var key: String = "%s%d" % [prefix, i]
		if done.has(key):
			continue
		var objective: Dictionary = list[i]
		var stage_day: int = int(GameState.quest_entry(id).get("stage_day", GameState.day))
		var hit: bool = QuestObjectives.satisfied(objective, stage_day) if QuestObjectives.is_state_objective(objective) \
			else (not event.is_empty() and QuestObjectives.matches(objective, event))
		if not hit:
			continue
		done[key] = true
		EventBus.quest_objective_done.emit(id, key, optional)
		Effects.apply_all(objective.get("on_done", []) as Array)


## Этап закрыт, когда выполнены все обязательные цели и в нём нет выбора (выбор ждёт игрока).
static func _stage_complete(stage: Dictionary, done: Dictionary) -> bool:
	if not (stage.get("choices", []) as Array).is_empty():
		return false
	var objectives: Array = stage.get("objectives", []) as Array
	for i: int in objectives.size():
		if not done.has("o%d" % i):
			return false
	return true


static func _next_stage(id: String) -> void:
	var stages: Array = definition(id).get("stages", []) as Array
	var current: String = GameState.get_quest_stage(id)
	for i: int in stages.size():
		if str((stages[i] as Dictionary)["id"]) == current:
			if i + 1 < stages.size():
				_enter_stage(id, str((stages[i + 1] as Dictionary)["id"]))
			else:
				finish(id, OUTCOME_DONE)
			return
