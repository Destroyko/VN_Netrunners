class_name PlannerApp
extends ScrollContainer
## Приложение «Задачи» — планировщик (docs/gameplay/planner.md) в телефоне и на ПК, данные одни.
## Сверху — неделя пн–вс со сроками (счета, сроки квестов), ниже — задачи по группам: платежи,
## сюжет, остальное; у задачи — идущий мини-квест, шаги и «Следить» (для трекера в углу).
## Правил здесь нет: всё считает `Planner`.

var _rows: VBoxContainer


func _init() -> void:
	name = "PlannerApp"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	add_child(_rows)


func _ready() -> void:
	for sig: Signal in [EventBus.quest_stage_changed, EventBus.quest_completed]:
		sig.connect(func(_q: String, _s: String) -> void: refresh())
	EventBus.task_tracked.connect(func(_q: String) -> void: refresh())
	EventBus.quest_objective_done.connect(func(_q: String, _k: String, _o: bool) -> void: refresh())
	EventBus.day_started.connect(func(_day: int) -> void: refresh())
	refresh()


func refresh() -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_week()
	var bills: Array = Planner.bills()
	if not bills.is_empty():
		_header(Planner.GROUP_TITLES[Planner.GROUP_BILLS])
		for line: String in bills:
			_text(line)
	var tasks: Array = Planner.tasks()
	if tasks.is_empty() and bills.is_empty():
		_text("Задач нет.")
	var group: String = ""
	for id: String in tasks:
		if Planner.group_of(id) != group:
			group = Planner.group_of(id)
			_header(str(Planner.GROUP_TITLES[group]))
		_task(id)


## Неделя: семь дней строкой, у дня со сроками — что в этот день. Сегодня — отмечено.
func _week() -> void:
	var first: int = Planner.week_start()
	var items: Array = Planner.week_items()
	_header("Неделя")
	for day: int in range(first, first + 7):
		var due: Array = items.filter(func(item: Dictionary) -> bool: return int(item["day"]) == day)
		var marker: String = "▶ " if day == GameState.day else "   "
		var text: String = marker + Clock.format_date(day)
		for item: Dictionary in due:
			text += "\n      " + str(item["text"])
		var line: Label = _text(text)
		line.name = "Day_%d" % day
		if day < GameState.day:
			line.add_theme_color_override("font_color", Color("#7d8590"))


func _task(id: String) -> void:
	var box := VBoxContainer.new()
	box.name = "Task_" + id
	_rows.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = Planner.title_of(id)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var track := Button.new()
	track.name = "Track"
	var tracked: bool = Planner.tracked() == id
	track.text = "В трекере" if tracked else "Следить"
	track.disabled = tracked
	track.pressed.connect(Planner.track.bind(id))
	head.add_child(track)
	var part: String = Planner.subtitle(id)
	if not part.is_empty():
		var sub := Label.new()
		sub.text = part
		sub.add_theme_color_override("font_color", Color("#aab0bb"))
		box.add_child(sub)
	for step: Dictionary in Planner.current_steps(id):
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.text = "%s %s%s" % ["✓" if bool(step["done"]) else "•", str(step["text"]),
			" (необязательно)" if bool(step["optional"]) else ""]
		if bool(step["done"]):
			line.add_theme_color_override("font_color", Color("#7d8590"))
		box.add_child(line)


func _header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("#ffcf5a"))
	_rows.add_child(label)


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(label)
	return label


# --- Для тестов --------------------------------------------------------------------------

func text() -> String:
	var lines: PackedStringArray = []
	for node: Node in _rows.find_children("*", "Label", true, false):
		lines.append((node as Label).text)
	return "\n".join(lines)


func track_button(id: String) -> Button:
	return _rows.get_node_or_null("Task_%s" % id).find_child("Track", true, false) as Button
