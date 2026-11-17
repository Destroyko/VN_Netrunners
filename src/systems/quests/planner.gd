class_name Planner
extends RefCounted
## Планировщик задач и трекер (docs/gameplay/planner.md): что игрок видит о квестах. Чистые
## правила без сцен — какие задачи показать, какой следить, как назвать цель, что на неделе.
##
## Квест из мини-квестов: этап родителя с целью `complete_quest` — это мини-квест; пока он идёт,
## текущие задачи берутся из него, а название — родителя. Между мини-квестами — свои цели
## родителя («дождаться утра», «поговорить», «прийти»). Мини-квест помечен `parent` и отдельной
## строкой в планировщике не показывается.

const VAR_TRACKED: String = "planner.tracked"
## Группы планировщика по порядку: платежи, сюжет, остальное.
const GROUP_BILLS: String = "bills"
const GROUP_MAIN: String = "main"
const GROUP_SIDE: String = "side"
const GROUP_TITLES: Dictionary = {
	GROUP_BILLS: "Аренда и платежи",
	GROUP_MAIN: "Основной сюжет",
	GROUP_SIDE: "Другие задачи",
}


## Активные задачи верхнего уровня (без мини-квестов): сюжетные первыми, дальше — по порядку начала.
static func tasks() -> Array:
	var ids: Array = Quests.active().filter(func(id: String) -> bool:
		return not Quests.definition(id).has("parent"))
	var main: Array = ids.filter(func(id: String) -> bool: return group_of(id) == GROUP_MAIN)
	var rest: Array = ids.filter(func(id: String) -> bool: return group_of(id) != GROUP_MAIN)
	return main + rest


static func group_of(id: String) -> String:
	return GROUP_MAIN if str(Quests.definition(id).get("type", "")) == "main" else GROUP_SIDE


## Какую задачу показывает трекер: выбранную игроком, а если её нет или она закончилась —
## первую из списка (сюжетная впереди). "" — задач нет.
static func tracked() -> String:
	var all: Array = tasks()
	var chosen: String = str(GameState.get_var_or(VAR_TRACKED, ""))
	if all.has(chosen):
		return chosen
	return str(all[0]) if not all.is_empty() else ""


static func track(id: String) -> void:
	GameState.set_var(VAR_TRACKED, id)
	EventBus.task_tracked.emit(id)


static func title_of(id: String) -> String:
	return DialogueText.with_names(str(Quests.definition(id).get("title", id)))


## Мини-квест, который сейчас идёт внутри задачи ("" — сейчас цель самого родителя).
static func current_part(id: String) -> String:
	for item: Dictionary in Quests.visible_objectives(id):
		var objective: Dictionary = item["objective"] as Dictionary
		if bool(item["done"]) or str(objective.get("type", "")) != "complete_quest":
			continue
		var part: String = str(objective.get("quest", ""))
		if Quests.is_active(part):
			return part
	return ""


## Текущие задачи: [{text, done, optional}]. Идёт мини-квест — его цели (и его мини-квестов).
static func current_steps(id: String) -> Array:
	var part: String = current_part(id)
	if not part.is_empty():
		return current_steps(part)
	var steps: Array = []
	for item: Dictionary in Quests.visible_objectives(id):
		steps.append({
			"text": objective_text(item["objective"] as Dictionary),
			"done": bool(item["done"]),
			"optional": bool(item["optional"]),
		})
	return steps


## Подзаголовок: название идущего мини-квеста ("" — его нет).
static func subtitle(id: String) -> String:
	var part: String = current_part(id)
	if part.is_empty():
		return ""
	var deeper: String = subtitle(part)
	return title_of(part) if deeper.is_empty() else deeper


## Как цель называется для игрока: `title` из данных, иначе — по типу цели.
static func objective_text(objective: Dictionary) -> String:
	if objective.has("title"):
		return DialogueText.with_names(str(objective["title"]))
	var file: String = str(objective.get("path", objective.get("file", ""))).get_file()
	var at: String = _address(str(objective.get("node", "")))
	match str(objective.get("type", "")):
		"read_mail":
			return "Проверить почту"
		"deliver":
			return "Написать на %s" % str(objective.get("to", ""))
		"file_at":
			return "Положить %s на %s" % [file, at]
		"delete_file":
			return "Удалить %s на %s" % [file, at]
		"copy_file":
			return "Скопировать %s с %s" % [file, at]
		"read_file":
			return "Прочитать %s на %s" % [file, at]
		"hack_node":
			return "Подключиться к %s" % at
		"wipe_logs":
			return "Почистить логи на %s" % at
		"talk":
			return "Поговорить"
		"visit_location":
			var location: Dictionary = Locations.def_of(str(objective.get("location", "")))
			return "Прийти: %s" % str(location.get("title", objective.get("location", "")))
		"complete_quest":
			return title_of(str(objective.get("quest", "")))
		"wait_until":
			return "Дождаться"
	return str(objective.get("type", ""))


static func _address(node_id: String) -> String:
	var node: Dictionary = DataLoader.nodes().get(node_id, {}) as Dictionary
	return str(node.get("address", node_id))


# --- Неделя ----------------------------------------------------------------------------

## Понедельник текущей недели (игровой день). Неделя — пн–вс, как аренда (planner.md).
static func week_start(day: int = GameState.day) -> int:
	var weekday: int = int(Clock.date_of(day)["weekday"])  # 0 — воскресенье
	return day - ((weekday + 6) % 7)


## Сроки недели по дням: [{day, text}] — неоплаченные счета и сроки квестов.
static func week_items(day: int = GameState.day) -> Array:
	var first: int = week_start(day)
	var items: Array = []
	for b: Dictionary in Economy.unpaid():
		var due: int = int(b["due_day"])
		if due >= first and due < first + 7:
			items.append({"day": due, "group": GROUP_BILLS, "text": "%s — %d ₽" % [str(b["title"]), Economy.total_of(b)]})
	for id: String in Quests.active():
		var due: int = Quests.due_day(id)
		# 0 — у квеста нет срока (неделя первых дней игры начинается раньше дня 1).
		if due > 0 and due >= first and due < first + 7:
			items.append({"day": due, "group": group_of(id), "text": "Срок: " + title_of(id)})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["day"]) < int(b["day"]))
	return items


## Неоплаченные счета — отдельной группой планировщика (с просрочкой — тоже).
static func bills() -> Array:
	var lines: Array = []
	for b: Dictionary in Economy.unpaid():
		var overdue: String = " (просрочен)" if Economy.is_overdue(b) else ""
		lines.append("%s — %d ₽, до %s%s" % [str(b["title"]), Economy.total_of(b), Clock.format_date(int(b["due_day"])), overdue])
	return lines
