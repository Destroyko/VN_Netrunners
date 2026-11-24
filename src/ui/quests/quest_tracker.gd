class_name QuestTracker
extends PanelContainer
## Трекер в правом верхнем углу экрана (плейтест M2: «не видно, что делать»): задача, за которой
## следит игрок, её идущий мини-квест и текущие шаги. Задача закончена — «выполнено», потом
## следующая. Правил здесь нет: что показать, решает `Planner`.

const WIDTH: float = 300.0
## Сколько секунд держится «выполнено», прежде чем трекер перейдёт к следующей задаче.
const DONE_SECONDS: float = 4.0

var _title: Label
var _subtitle: Label
var _steps: VBoxContainer
var _done_left: float = 0.0
var _style: StyleBoxFlat
## Цвет выполненного шага: у плашки комнаты свой, у плашки на столе — из темы ОС.
var _done_color: Color = Color("#7d8590")


func _init() -> void:
	name = "QuestTracker"
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.05, 0.06, 0.09, 0.72)
	_style.set_corner_radius_all(6)
	_style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", _style)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rows)
	_title = Label.new()
	_title.name = "Title"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_color_override("font_color", Color("#ffcf5a"))
	rows.add_child(_title)
	_subtitle = Label.new()
	_subtitle.name = "Subtitle"
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_color_override("font_color", Color("#aab0bb"))
	rows.add_child(_subtitle)
	_steps = VBoxContainer.new()
	_steps.name = "Steps"
	_steps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(_steps)


## Плашка на рабочем столе ПК — в теме ОС, как уведомление системы: тон панели, рамка, заголовок
## цветом акцента. В комнате остаётся тёмная полупрозрачная плашка поверх кадра.
func use_theme(theme_id: String) -> void:
	theme = GameTheme.build(theme_id)
	var radius: int = int((GameTheme.load_theme(theme_id).get("shape", {}) as Dictionary).get("radius", 4))
	_style.bg_color = Color(GameTheme.color("panel", theme_id), 0.96)
	_style.border_color = GameTheme.color("border", theme_id)
	_style.set_border_width_all(1)
	_style.set_corner_radius_all(radius + 1)
	_style.content_margin_left = 14
	_style.content_margin_right = 12
	_style.content_margin_top = 10
	_style.content_margin_bottom = 10
	_style.shadow_color = Color(0, 0, 0, 0.18)
	_style.shadow_size = 6
	_style.shadow_offset = Vector2(0, 2)
	_title.add_theme_color_override("font_color", GameTheme.color("accent", theme_id))
	_subtitle.add_theme_color_override("font_color", GameTheme.color("text_dim", theme_id))
	_done_color = GameTheme.color("text_dim", theme_id)
	refresh()


func _ready() -> void:
	EventBus.quest_stage_changed.connect(func(_q: String, _s: String) -> void: refresh())
	EventBus.task_tracked.connect(func(_q: String) -> void: refresh())
	EventBus.quest_objective_done.connect(func(_q: String, _k: String, _o: bool) -> void: refresh())
	EventBus.quest_completed.connect(_on_completed)
	refresh()


func _process(delta: float) -> void:
	if _done_left <= 0.0:
		return
	_done_left -= delta
	if _done_left <= 0.0:
		refresh()


## Закончилась задача из трекера — показать «выполнено» (мини-квесты внутри неё — нет: их итог
## виден по шагам).
func _on_completed(id: String, _outcome: String) -> void:
	if Quests.definition(id).has("parent") or _title.text != Planner.title_of(id):
		refresh()
		return
	_subtitle.text = "выполнено"
	_clear_steps()
	_done_left = DONE_SECONDS


func refresh() -> void:
	if _done_left > 0.0:
		return
	var id: String = Planner.tracked()
	visible = not id.is_empty()
	if id.is_empty():
		return
	_title.text = Planner.title_of(id)
	_subtitle.text = Planner.subtitle(id)
	_subtitle.visible = not _subtitle.text.is_empty()
	_clear_steps()
	for step: Dictionary in Planner.current_steps(id):
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var mark: String = "✓" if bool(step["done"]) else "•"
		line.text = "%s %s%s" % [mark, str(step["text"]), " (необязательно)" if bool(step["optional"]) else ""]
		if bool(step["done"]):
			line.add_theme_color_override("font_color", _done_color)
		_steps.add_child(line)


func _clear_steps() -> void:
	for child: Node in _steps.get_children():
		_steps.remove_child(child)
		child.queue_free()


# --- Для тестов --------------------------------------------------------------------------

func title_text() -> String:
	return _title.text if visible else ""


func subtitle_text() -> String:
	return _subtitle.text


func steps_text() -> String:
	var lines: PackedStringArray = []
	for child: Node in _steps.get_children():
		lines.append((child as Label).text)
	return "\n".join(lines)
