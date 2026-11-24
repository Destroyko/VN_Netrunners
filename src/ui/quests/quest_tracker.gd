class_name QuestTracker
extends PanelContainer
## Строка цели в правом верхнем углу (docs/gameplay/planner.md, «Как подаём»): название задачи, за
## которой следит игрок, и под ним одна текущая цель. Что дальше — не показываем: игрок не должен
## знать этапы наперёд. Клик открывает «Задачи» (`open_requested`: стол открывает окно, комната —
## телефон). Задача закончена — «выполнено», потом следующая.
##
## Строки нет, когда цели нет, во время диалога и под тем, что накрывает экран (меню паузы, затемнение
## вырубания): такие узлы входят в группу `COVER_GROUP`. Правил здесь нет: что показать, решает `Planner`.

signal open_requested

const MAX_WIDTH: float = 320.0
## Отступ строки от верхнего и правого края экрана.
const TOP_OFFSET: float = 72.0
const SIDE_OFFSET: float = 16.0
## Сколько секунд держится «выполнено», прежде чем строка перейдёт к следующей задаче.
const DONE_SECONDS: float = 4.0
## Группа узлов, которые накрывают экран: пока такой узел виден, строки цели нет.
const COVER_GROUP: String = "covers_goal_line"

var _title: Label
var _goal: Label
var _done_left: float = 0.0
var _style: StyleBoxFlat
var _hover_style: StyleBoxFlat
var _in_dialogue: bool = false
## Есть ли что показать (без учёта диалога и накрытия).
var _has_goal: bool = false


func _init() -> void:
	name = "QuestTracker"
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Открыть «Задачи»"
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.05, 0.06, 0.09, 0.78)
	_style.set_corner_radius_all(6)
	_style.content_margin_left = 12
	_style.content_margin_right = 12
	_style.content_margin_top = 6
	_style.content_margin_bottom = 6
	_hover_style = _style.duplicate() as StyleBoxFlat
	add_theme_stylebox_override("panel", _style)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rows)
	_title = Label.new()
	_title.name = "Title"
	_title.add_theme_font_size_override("font_size", 12)
	_title.add_theme_color_override("font_color", Color("#ffcf5a"))
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(_title)
	_goal = Label.new()
	_goal.name = "Goal"
	_goal.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_goal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(_goal)
	mouse_entered.connect(func() -> void: add_theme_stylebox_override("panel", _hover_style))
	mouse_exited.connect(func() -> void: add_theme_stylebox_override("panel", _style))


## Поставить строку в правый верхний угол экрана-хозяина.
func place_top_right() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = -SIDE_OFFSET
	offset_top = TOP_OFFSET


## Строка на экране в теме этого экрана: тон панели, рамка, название задачи цветом акцента.
func use_theme(theme_id: String) -> void:
	theme = GameTheme.build(theme_id)
	var radius: int = int((GameTheme.load_theme(theme_id).get("shape", {}) as Dictionary).get("radius", 4))
	var panel: Color = GameTheme.color("panel", theme_id)
	_style.bg_color = Color(panel, 0.94)
	_style.border_color = GameTheme.color("border", theme_id)
	_style.set_border_width_all(1)
	_style.set_corner_radius_all(radius + 1)
	_style.shadow_color = Color(0, 0, 0, 0.18)
	_style.shadow_size = 6
	_style.shadow_offset = Vector2(0, 2)
	_hover_style = _style.duplicate() as StyleBoxFlat
	_hover_style.bg_color = Color(GameTheme.color("panel_raised", theme_id), 0.96)
	_hover_style.border_color = GameTheme.color("accent", theme_id)
	add_theme_stylebox_override("panel", _style)
	_title.add_theme_color_override("font_color", GameTheme.color("accent", theme_id))
	_goal.add_theme_color_override("font_color", GameTheme.color("text", theme_id))
	refresh()


func _ready() -> void:
	EventBus.quest_stage_changed.connect(func(_q: String, _s: String) -> void: refresh())
	EventBus.task_tracked.connect(func(_q: String) -> void: refresh())
	EventBus.quest_objective_done.connect(func(_q: String, _k: String, _o: bool) -> void: refresh())
	EventBus.quest_completed.connect(_on_completed)
	EventBus.dialogue_started.connect(func(_id: String) -> void:
		_in_dialogue = true
		_apply_visibility())
	EventBus.dialogue_ended.connect(func(_id: String) -> void:
		_in_dialogue = false
		_apply_visibility())
	refresh()


func _process(delta: float) -> void:
	# Меню паузы и затемнение появляются и уходят сами: проверяем их каждый кадр, это дёшево.
	_apply_visibility()
	if _done_left <= 0.0:
		return
	_done_left -= delta
	if _done_left <= 0.0:
		refresh()


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		open_requested.emit()


## Закончилась задача из строки — показать «выполнено» (мини-квесты внутри неё — нет: их итог виден
## по следующей цели).
func _on_completed(id: String, _outcome: String) -> void:
	if Quests.definition(id).has("parent") or _title.text != Planner.title_of(id):
		refresh()
		return
	_goal.text = "выполнено"
	_done_left = DONE_SECONDS


func refresh() -> void:
	if _done_left > 0.0:
		return
	var id: String = Planner.tracked()
	_has_goal = not id.is_empty()
	if _has_goal:
		_title.text = Planner.title_of(id)
		_goal.text = current_goal(id)
	_fit_width()
	_apply_visibility()


## Текущая цель задачи: первая невыполненная обязательная, иначе первая невыполненная необязательная.
## Пусто — все видимые цели выполнены (ждём перехода к следующему этапу).
static func current_goal(id: String) -> String:
	var optional: String = ""
	for step: Dictionary in Planner.current_steps(id):
		if bool(step["done"]):
			continue
		if not bool(step["optional"]):
			return str(step["text"])
		if optional.is_empty():
			optional = str(step["text"])
	return optional


## Строка по ширине текста, но не шире `MAX_WIDTH` (длинное — с многоточием).
func _fit_width() -> void:
	var font: Font = get_theme_default_font()
	var wanted: float = 0.0
	if font != null:
		wanted = maxf(font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x,
			font.get_string_size(_goal.text, HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_default_font_size()).x)
	custom_minimum_size.x = clampf(wanted + 28.0, 160.0, MAX_WIDTH)
	_title.clip_text = true
	_goal.clip_text = true
	reset_size()


func _apply_visibility() -> void:
	var shown: bool = _has_goal and not _in_dialogue and not _covered()
	if visible != shown:
		visible = shown


func _covered() -> bool:
	if not is_inside_tree():
		return false
	for node: Node in get_tree().get_nodes_in_group(COVER_GROUP):
		var item: CanvasItem = node as CanvasItem
		if item != null and item.is_visible_in_tree():
			return true
	return false


# --- Для тестов --------------------------------------------------------------------------

func title_text() -> String:
	return _title.text if visible else ""


func goal_text() -> String:
	return _goal.text if visible else ""
