extends CanvasLayer
## Окно инвентаря (`I`) поверх сцены квартиры и стола (docs/gameplay/inventory.md). Слева —
## инвентарь героя, справа — открытый контейнер (холодильник, шкаф), если герой у него. Слот —
## предмет; выбрал — его действия: съесть, переложить, переименовать, выбросить (с
## подтверждением). Предметы перетаскиваются между сетками и на системный блок в сцене.
##
## Правил здесь нет: всё делает `Inventory` (и `Room` для системного блока). Есть там же, где
## телефон (`PhoneOverlay.is_available`): в меню и настройках инвентаря нет.
##
## Оформление — общая тема экранов (`GameTheme.current_id`), цвета только по ролям: окно не
## подстраивается под комнату и не спорит с темой ПК.

const SLOT_SIZE: Vector2 = Vector2(92, 52)
const COLUMNS: int = 5
## Зазор между слотами и сколько рядов видно без прокрутки (30 слотов — все 6 рядов сразу).
const SLOT_GAP: int = 4
const VISIBLE_ROWS: int = 6
const SLOT_FONT_SIZE: int = 12
## Высота панели выбранного предмета: окно не прыгает, когда выбор появляется и пропадает.
const DETAILS_MIN_HEIGHT: float = 112.0

var panel: PanelContainer
## «Системный блок» справа: открыт, когда инвентарь открыт у системника (`open(Inventory.PC)`).
var case_panel: PcCasePanel
var _grids: HBoxContainer
var _details: VBoxContainer
var _status: Label
## Открытый рядом контейнер ("" — только инвентарь героя).
var _other: String = ""
var _selected: String = ""
## Ждёт подтверждения «выбросить» (uid) или переименования.
var _confirm_discard: String = ""
var _renaming: String = ""
## Тема, которой нарисовано окно, и плашки слотов и опасных кнопок по её ролям.
var _theme_id: String = ""
var _styles: Dictionary = {}
## Меню правой кнопки по предмету («Вставить»).
var _slot_menu: PopupMenu


func _ready() -> void:
	layer = 39
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_apply_theme()
	panel.visible = false
	EventBus.inventory_changed.connect(func(_c: String) -> void: refresh())


func open(other: String = "") -> void:
	if not PhoneOverlay.in_game():
		return
	_apply_theme()
	# У системника рядом не сетка, а окно комплектующих (шаг 7.5).
	case_panel.visible = other == Inventory.PC
	_other = "" if other == Inventory.PC else other
	_selected = ""
	_status.text = ""
	panel.visible = true
	refresh()


func close() -> void:
	panel.visible = false
	case_panel.visible = false
	_other = ""
	_selected = ""
	_confirm_discard = ""
	_renaming = ""


func toggle() -> void:
	if panel.visible:
		close()
	else:
		open()


func is_open() -> bool:
	return panel.visible


func other_container() -> String:
	return _other


func is_case_open() -> bool:
	return panel.visible and case_panel.visible


func refresh() -> void:
	if not panel.visible:
		return
	for child: Node in _grids.get_children():
		_grids.remove_child(child)
		child.queue_free()
	_grids.add_child(_grid(Inventory.HERO))
	if not _other.is_empty():
		_grids.add_child(VSeparator.new())
		_grids.add_child(_grid(_other))
	if not _selected.is_empty() and Inventory.find(_selected).is_empty():
		_selected = ""
	_fill_details()
	case_panel.refresh()


# --- Сетка --------------------------------------------------------------------------------

func _grid(container: String) -> Control:
	var box := VBoxContainer.new()
	box.name = "Box_" + container
	box.add_theme_constant_override("separation", 8)
	var items: Array = Inventory.list(container)
	var capacity: int = Inventory.capacity(container)
	# Шапка колонки: название слева, заполненность справа; полный контейнер — цветом предупреждения.
	var head := HBoxContainer.new()
	head.name = "Head"
	box.add_child(head)
	var title := Label.new()
	title.name = "Title"
	title.text = str(Inventory.TITLES.get(container, container))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var count := Label.new()
	count.name = "Count"
	count.text = "%d / %d" % [items.size(), capacity]
	count.theme_type_variation = "WarnLabel" if items.size() >= capacity else "DimLabel"
	head.add_child(count)
	var rows: int = ceili(float(capacity) / COLUMNS)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(
		COLUMNS * SLOT_SIZE.x + (COLUMNS - 1) * SLOT_GAP + (12 if rows > VISIBLE_ROWS else 0),
		mini(rows, VISIBLE_ROWS) * (SLOT_SIZE.y + SLOT_GAP) - SLOT_GAP)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "Grid_" + container
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", SLOT_GAP)
	grid.add_theme_constant_override("v_separation", SLOT_GAP)
	scroll.add_child(grid)
	# Бросить предмет на сетку — переложить сюда.
	box.set_drag_forwarding(Callable(), _can_drop.bind(container), _drop.bind(container))
	for i: int in capacity:
		var slot := Button.new()
		slot.name = "Slot_%d" % i
		slot.custom_minimum_size = SLOT_SIZE
		slot.clip_text = true
		_style_slot(slot)
		slot.set_drag_forwarding(Callable(), _can_drop.bind(container), _drop.bind(container))
		if i < items.size():
			var entry: Dictionary = items[i] as Dictionary
			var uid: String = str(entry["uid"])
			slot.text = Inventory.label_of(entry)
			slot.add_child(_slot_caption(slot.text))
			slot.tooltip_text = "%s\n%s" % [Inventory.label_of(entry), Inventory.about(str(entry["kind"]))]
			slot.toggle_mode = true
			slot.button_pressed = uid == _selected
			slot.pressed.connect(select.bind(uid))
			slot.set_drag_forwarding(_drag.bind(uid, slot.text), _can_drop.bind(container), _drop.bind(container))
			slot.gui_input.connect(_on_slot_input.bind(uid))
		else:
			# Пустой слот — пустая ячейка: видно, сколько места осталось.
			slot.disabled = true
			slot.focus_mode = Control.FOCUS_NONE
		grid.add_child(slot)
	return box


## Подпись слота. Названия длинные («Лапша быстрого приготовления»), а у кнопки нет предела строк:
## перенесённый текст растягивал слот в высоту. Поэтому подпись рисует отдельная метка — мелко, не
## больше двух строк, с многоточием, — а текст кнопки остаётся названием предмета (по нему ищут
## тесты и подсказка), но невидим.
func _slot_caption(text: String) -> Label:
	var caption := Label.new()
	caption.name = "Caption"
	caption.text = text
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 3)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.max_lines_visible = 2
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.clip_text = true
	caption.add_theme_font_size_override("font_size", SLOT_FONT_SIZE)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return caption


## Слот: ячейка по ролям темы; выбранный (нажатый) — заливка плашки и рамка акцента.
func _style_slot(slot: Button) -> void:
	for role: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color",
			"font_focus_color", "font_disabled_color"]:
		slot.add_theme_color_override(role, Color(0, 0, 0, 0))
	slot.add_theme_stylebox_override("normal", _styles["slot"] as StyleBox)
	slot.add_theme_stylebox_override("hover", _styles["slot_hover"] as StyleBox)
	slot.add_theme_stylebox_override("pressed", _styles["slot_selected"] as StyleBox)
	slot.add_theme_stylebox_override("hover_pressed", _styles["slot_selected"] as StyleBox)
	slot.add_theme_stylebox_override("disabled", _styles["slot_empty"] as StyleBox)
	slot.add_theme_stylebox_override("focus", _styles["slot_focus"] as StyleBox)


func _drag(_at: Vector2, uid: String, text: String) -> Variant:
	var preview := Label.new()
	preview.text = text
	panel.set_drag_preview(preview)
	return {"inventory_uid": uid}


func _can_drop(_at: Vector2, data: Variant, container: String) -> bool:
	if not (data is Dictionary) or not (data as Dictionary).has("inventory_uid"):
		return false
	var found: Dictionary = Inventory.find(str((data as Dictionary)["inventory_uid"]))
	return not found.is_empty() and str(found["container"]) != container \
		and Inventory.accepts(container, str((found["entry"] as Dictionary)["kind"]))


func _drop(_at: Vector2, data: Variant, container: String) -> void:
	move_to(str((data as Dictionary)["inventory_uid"]), container)


## Правая кнопка по предмету: «Вставить», если рядом открыт системный блок и предмет подходит.
func _on_slot_input(event: InputEvent, uid: String) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT:
		return
	if not is_case_open() or not case_panel.can_insert({"inventory_uid": uid}):
		return
	_slot_menu.set_meta("uid", uid)
	_slot_menu.position = Vector2i(get_viewport().get_mouse_position())
	_slot_menu.popup()


## Переложить и сказать, если не вышло («Холодильник: заполнен»).
func move_to(uid: String, container: String) -> void:
	var error: String = Inventory.move(uid, container)
	_status.text = error


func select(uid: String) -> void:
	_selected = uid
	_confirm_discard = ""
	_renaming = ""
	_status.text = ""
	refresh()


# --- Действия с выбранным -----------------------------------------------------------------

func _fill_details() -> void:
	for child: Node in _details.get_children():
		_details.remove_child(child)
		child.queue_free()
	if _selected.is_empty():
		var hint := Label.new()
		hint.text = "Выберите предмет"
		hint.theme_type_variation = "DimLabel"
		_details.add_child(hint)
		return
	var found: Dictionary = Inventory.find(_selected)
	var entry: Dictionary = found["entry"] as Dictionary
	var kind: String = str(entry["kind"])
	var here: String = str(found["container"])
	var name_label := Label.new()
	name_label.name = "ItemName"
	name_label.text = Inventory.label_of(entry)
	name_label.theme_type_variation = "HeaderLabel"
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_details.add_child(name_label)
	var about_text: String = Inventory.about(kind)
	if Inventory.is_locked(entry):
		about_text += ("\n" if not about_text.is_empty() else "") + "Квестовый предмет."
	if not about_text.is_empty():
		var about := Label.new()
		about.name = "About"
		about.text = about_text
		about.theme_type_variation = "DimLabel"
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_details.add_child(about)
	var row := HBoxContainer.new()
	row.name = "Actions"
	row.add_theme_constant_override("separation", 8)
	_details.add_child(row)
	if Inventory.is_food(kind) and Gates.is_open(Gates.HUNGER):
		_action(row, "Eat", "Съесть", func() -> void: Inventory.eat(_selected))
	# Переложить — в другой открытый контейнер (из инвентаря туда, оттуда — в инвентарь).
	var target: String = _other if here == Inventory.HERO else Inventory.HERO
	if not target.is_empty() and target != here and Inventory.accepts(target, kind):
		_action(row, "Move", "→ " + str(Inventory.TITLES.get(target, target)), move_to.bind(_selected, target))
	if is_case_open() and case_panel.can_insert({"inventory_uid": _selected}):
		_action(row, "Insert", "Вставить", case_panel.insert.bind(_selected))
	if not Inventory.is_food(kind):
		_action(row, "Rename", "Переименовать", func() -> void:
			_renaming = _selected
			_confirm_discard = ""
			_fill_details())
	# Опасное действие — справа, отдельно от обычных, и цветом роли `danger`.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var discard: Button = _action(row, "Discard", "Выбросить", func() -> void:
		_confirm_discard = _selected
		_renaming = ""
		_fill_details())
	_style_danger(discard, false)
	if Inventory.is_locked(entry):
		discard.disabled = true
		discard.tooltip_text = "Квестовый предмет: пока задача не закончена, не выбросить."
	if _confirm_discard == _selected:
		var confirm := HBoxContainer.new()
		confirm.name = "Confirm"
		confirm.add_theme_constant_override("separation", 8)
		_details.add_child(confirm)
		var ask := Label.new()
		ask.text = "Выбросить насовсем?"
		ask.theme_type_variation = "DangerLabel"
		ask.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		confirm.add_child(ask)
		var yes: Button = _action(confirm, "Yes", "Да", func() -> void: _status.text = Inventory.discard(_selected))
		_style_danger(yes, true)
		_action(confirm, "No", "Нет", func() -> void:
			_confirm_discard = ""
			_fill_details())
	if _renaming == _selected:
		var rename_row := HBoxContainer.new()
		rename_row.name = "RenameRow"
		rename_row.add_theme_constant_override("separation", 8)
		_details.add_child(rename_row)
		var edit := LineEdit.new()
		edit.name = "NewName"
		edit.text = Inventory.label_of(entry)
		edit.placeholder_text = Inventory.name_of(kind)
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.text_submitted.connect(_rename)
		rename_row.add_child(edit)
		# Кнопка для мыши; Enter в поле делает то же.
		_action(rename_row, "RenameOk", "Сохранить", func() -> void: _rename(edit.text))
		edit.grab_focus.call_deferred()
		edit.select_all.call_deferred()


func _rename(text: String) -> void:
	_renaming = ""
	Inventory.rename(_selected, text)


func _action(parent: Control, action_name: String, text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.name = action_name
	button.text = text
	button.pressed.connect(on_press)
	parent.add_child(button)
	return button


## Опасная кнопка: рамка и подпись цветом `danger`, под мышью — заливка им же. `filled` — сразу
## залита (последний шаг: «Да» в подтверждении).
func _style_danger(button: Button, filled: bool) -> void:
	var danger: Color = GameTheme.color("danger", _theme_id)
	var on_danger: Color = GameTheme.color("text", _theme_id)
	button.add_theme_stylebox_override("normal", _styles["danger_filled" if filled else "danger"] as StyleBox)
	button.add_theme_stylebox_override("hover", _styles["danger_hover"] as StyleBox)
	button.add_theme_stylebox_override("pressed", _styles["danger_pressed"] as StyleBox)
	button.add_theme_stylebox_override("hover_pressed", _styles["danger_pressed"] as StyleBox)
	var idle: Color = on_danger if filled else danger
	button.add_theme_color_override("font_color", idle)
	button.add_theme_color_override("font_focus_color", idle)
	for role: String in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(role, on_danger)


# --- Ввод ---------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	# Пустая строка статуса не занимает места под карточкой; текст в неё пишут многие действия.
	_status.visible = not _status.text.is_empty()
	# Меню игры открылось или сцена ушла — окно закрывается.
	if panel.visible and not PhoneOverlay.in_game():
		close()


func _input(event: InputEvent) -> void:
	if panel.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_I:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or DialogueManager.is_active() or not PhoneOverlay.in_game():
		return
	get_viewport().set_input_as_handled()
	toggle()


func _build() -> void:
	panel = PanelContainer.new()
	panel.name = "Inventory"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var head := HBoxContainer.new()
	head.name = "Head"
	column.add_child(head)
	var title := Label.new()
	title.text = "Инвентарь (I)"
	title.theme_type_variation = "HeaderLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_button := Button.new()
	close_button.name = "Close"
	close_button.text = "×"
	close_button.theme_type_variation = "FlatButton"
	close_button.tooltip_text = "Закрыть (Esc)"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(32, 32)
	close_button.add_theme_font_size_override("font_size", 20)
	close_button.pressed.connect(close)
	head.add_child(close_button)
	column.add_child(HSeparator.new())
	_grids = HBoxContainer.new()
	_grids.name = "Grids"
	_grids.add_theme_constant_override("separation", 16)
	column.add_child(_grids)
	# Выбранный предмет — на карточке ниже сеток: название, описание, действия в один ряд.
	var card := PanelContainer.new()
	card.name = "DetailsCard"
	card.theme_type_variation = "CardPanel"
	card.custom_minimum_size = Vector2(0, DETAILS_MIN_HEIGHT)
	column.add_child(card)
	_details = VBoxContainer.new()
	_details.name = "Details"
	_details.add_theme_constant_override("separation", 8)
	card.add_child(_details)
	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = "WarnLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_slot_menu = PopupMenu.new()
	_slot_menu.name = "SlotMenu"
	_slot_menu.add_item("Вставить", 0)
	_slot_menu.id_pressed.connect(func(_id: int) -> void: case_panel.insert(str(_slot_menu.get_meta("uid", ""))))
	add_child(_slot_menu)
	# Окно системного блока — справа; закрыл его — закрылся и инвентарь.
	case_panel = PcCasePanel.new()
	case_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	case_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	case_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	case_panel.visible = false
	case_panel.close_requested.connect(close)
	case_panel.said.connect(func(text: String) -> void: _status.text = text)
	add_child(case_panel)


## Оформление по общей теме: окно непрозрачное (сцена не просвечивает сквозь слоты), рамка и
## скругление — из формы темы; плашки слотов и опасных кнопок — по ролям, общих в теме для них нет.
func _apply_theme() -> void:
	if _theme_id == GameTheme.current_id:
		return
	_theme_id = GameTheme.current_id
	var shape: Dictionary = GameTheme.load_theme(_theme_id).get("shape", {}) as Dictionary
	var radius: int = int(shape.get("radius", 4))
	var width: int = int(shape.get("border_width", 1))
	var background: Color = GameTheme.color("background", _theme_id)
	var panel_color: Color = GameTheme.color("panel", _theme_id)
	var raised: Color = GameTheme.color("panel_raised", _theme_id)
	var border: Color = GameTheme.color("border", _theme_id)
	var accent: Color = GameTheme.color("accent", _theme_id)
	var danger: Color = GameTheme.color("danger", _theme_id)
	panel.theme = GameTheme.build(_theme_id)

	var frame: StyleBoxFlat = _box(panel_color, border, width, radius + 2, 16)
	frame.shadow_color = Color(0, 0, 0, 0.35)
	frame.shadow_size = 12
	frame.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", frame)
	case_panel.theme = panel.theme
	case_panel.add_theme_stylebox_override("panel", frame)

	# Пустая ячейка — тон фона с бледной рамкой; занятая — чуть светлее панели; выбранная — плашка
	# и рамка акцента в два раза толще, чтобы выбор читался и без цвета.
	_styles = {
		"slot_empty": _box(background.lerp(panel_color, 0.35), border.lerp(panel_color, 0.55), width, radius, 4),
		"slot": _box(panel_color.lerp(raised, 0.45), border, width, radius, 4),
		"slot_hover": _box(raised, accent.lerp(border, 0.4), width, radius, 4),
		"slot_selected": _box(raised, accent, width + 1, radius, 4),
		"slot_focus": StyleBoxEmpty.new(),
		"danger": _box(panel_color.lerp(raised, 0.45), danger, width, radius, 12),
		"danger_filled": _box(danger.darkened(0.1), danger, width, radius, 12),
		"danger_hover": _box(danger, danger, width, radius, 12),
		"danger_pressed": _box(danger.darkened(0.2), danger.darkened(0.2), width, radius, 12),
	}
	for key: String in ["danger", "danger_filled", "danger_hover", "danger_pressed"]:
		var box: StyleBoxFlat = _styles[key] as StyleBoxFlat
		box.content_margin_top = 6
		box.content_margin_bottom = 6
	case_panel.apply_styles(_styles)
	refresh()


func _box(fill: Color, border: Color, width: int, radius: int, margin: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	return box


# --- Для тестов --------------------------------------------------------------------------

func slot(container: String, index: int) -> Button:
	return panel.find_child("Grid_" + container, true, false).get_node_or_null("Slot_%d" % index) as Button


func detail(action_name: String) -> Button:
	return _details.find_child(action_name, true, false) as Button


func rename_field() -> LineEdit:
	return _details.find_child("NewName", true, false) as LineEdit


func status_text() -> String:
	return _status.text
