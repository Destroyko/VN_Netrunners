extends CanvasLayer
## Окно инвентаря (`I`) поверх сцены квартиры и стола (docs/gameplay/inventory.md). Слева —
## инвентарь героя, справа — открытый контейнер (холодильник, шкаф), если герой у него. Слот —
## предмет; выбрал — его действия: съесть, переложить, переименовать, выбросить (с
## подтверждением). Предметы перетаскиваются между сетками и на системный блок в сцене.
##
## Правил здесь нет: всё делает `Inventory` (и `Room` для системного блока). Есть там же, где
## телефон (`PhoneOverlay.is_available`): в меню и настройках инвентаря нет.

const SLOT_SIZE: Vector2 = Vector2(84, 52)
const COLUMNS: int = 5

var panel: PanelContainer
var _grids: HBoxContainer
var _details: VBoxContainer
var _status: Label
## Открытый рядом контейнер ("" — только инвентарь героя).
var _other: String = ""
var _selected: String = ""
## Ждёт подтверждения «выбросить» (uid) или переименования.
var _confirm_discard: String = ""
var _renaming: String = ""


func _ready() -> void:
	layer = 39
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	panel.visible = false
	EventBus.inventory_changed.connect(func(_c: String) -> void: refresh())


func open(other: String = "") -> void:
	if not PhoneOverlay.in_game():
		return
	_other = other
	_selected = ""
	_status.text = ""
	panel.visible = true
	refresh()


func close() -> void:
	panel.visible = false
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


func refresh() -> void:
	if not panel.visible:
		return
	for child: Node in _grids.get_children():
		_grids.remove_child(child)
		child.queue_free()
	_grids.add_child(_grid(Inventory.HERO))
	if not _other.is_empty():
		_grids.add_child(_grid(_other))
	if not _selected.is_empty() and Inventory.find(_selected).is_empty():
		_selected = ""
	_fill_details()


# --- Сетка --------------------------------------------------------------------------------

func _grid(container: String) -> Control:
	var box := VBoxContainer.new()
	box.name = "Box_" + container
	var title := Label.new()
	title.text = "%s  %d / %d" % [Inventory.TITLES.get(container, container), Inventory.list(container).size(), Inventory.capacity(container)]
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(COLUMNS * (SLOT_SIZE.x + 4), 4 * (SLOT_SIZE.y + 4))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "Grid_" + container
	grid.columns = COLUMNS
	scroll.add_child(grid)
	# Бросить предмет на сетку — переложить сюда.
	box.set_drag_forwarding(Callable(), _can_drop.bind(container), _drop.bind(container))
	var items: Array = Inventory.list(container)
	for i: int in Inventory.capacity(container):
		var slot := Button.new()
		slot.name = "Slot_%d" % i
		slot.custom_minimum_size = SLOT_SIZE
		# Названия длинные («Лапша быстрого приготовления»): мелко и в две строки, до иконок.
		slot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		slot.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		slot.add_theme_font_size_override("font_size", 12)
		slot.set_drag_forwarding(Callable(), _can_drop.bind(container), _drop.bind(container))
		if i < items.size():
			var entry: Dictionary = items[i] as Dictionary
			var uid: String = str(entry["uid"])
			slot.text = Inventory.label_of(entry)
			slot.tooltip_text = "%s\n%s" % [Inventory.label_of(entry), Inventory.about(str(entry["kind"]))]
			slot.toggle_mode = true
			slot.button_pressed = uid == _selected
			slot.pressed.connect(select.bind(uid))
			slot.set_drag_forwarding(_drag.bind(uid, slot.text), _can_drop.bind(container), _drop.bind(container))
		else:
			slot.disabled = true
		grid.add_child(slot)
	return box


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
		return
	var found: Dictionary = Inventory.find(_selected)
	var entry: Dictionary = found["entry"] as Dictionary
	var kind: String = str(entry["kind"])
	var here: String = str(found["container"])
	var name_label := Label.new()
	name_label.text = Inventory.label_of(entry)
	_details.add_child(name_label)
	var row := HBoxContainer.new()
	row.name = "Actions"
	_details.add_child(row)
	if Inventory.is_food(kind) and Gates.is_open(Gates.HUNGER):
		_action(row, "Eat", "Съесть", func() -> void: Inventory.eat(_selected))
	# Переложить — в другой открытый контейнер (из инвентаря туда, оттуда — в инвентарь).
	var target: String = _other if here == Inventory.HERO else Inventory.HERO
	if not target.is_empty() and target != here and Inventory.accepts(target, kind):
		_action(row, "Move", "→ " + str(Inventory.TITLES.get(target, target)), move_to.bind(_selected, target))
	if not Inventory.is_food(kind):
		_action(row, "Rename", "Переименовать", func() -> void:
			_renaming = _selected
			_fill_details())
	var discard: Button = _action(row, "Discard", "Выбросить", func() -> void:
		_confirm_discard = _selected
		_fill_details())
	if Inventory.is_locked(entry):
		discard.disabled = true
		discard.tooltip_text = "Квестовый предмет: пока задача не закончена, не выбросить."
	if _confirm_discard == _selected:
		var confirm := HBoxContainer.new()
		confirm.name = "Confirm"
		_details.add_child(confirm)
		var ask := Label.new()
		ask.text = "Выбросить насовсем?"
		confirm.add_child(ask)
		_action(confirm, "Yes", "Да", func() -> void: _status.text = Inventory.discard(_selected))
		_action(confirm, "No", "Нет", func() -> void:
			_confirm_discard = ""
			_fill_details())
	if _renaming == _selected:
		var edit := LineEdit.new()
		edit.name = "NewName"
		edit.text = Inventory.label_of(entry)
		edit.custom_minimum_size = Vector2(220, 0)
		edit.text_submitted.connect(func(text: String) -> void:
			_renaming = ""
			Inventory.rename(_selected, text))
		_details.add_child(edit)
		edit.grab_focus.call_deferred()


func _action(parent: Control, action_name: String, text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.name = action_name
	button.text = text
	button.pressed.connect(on_press)
	parent.add_child(button)
	return button


# --- Ввод ---------------------------------------------------------------------------------

func _process(_delta: float) -> void:
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
	# Непрозрачная: сцена под окном не должна просвечивать сквозь слоты.
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#16181e")
	style.border_color = Color("#3a3f4b")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var title := Label.new()
	title.text = "Инвентарь (I)"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_button := Button.new()
	close_button.name = "Close"
	close_button.text = "×"
	close_button.flat = true
	close_button.pressed.connect(close)
	head.add_child(close_button)
	_grids = HBoxContainer.new()
	_grids.name = "Grids"
	_grids.add_theme_constant_override("separation", 16)
	column.add_child(_grids)
	_details = VBoxContainer.new()
	_details.name = "Details"
	column.add_child(_details)
	_status = Label.new()
	_status.name = "Status"
	_status.add_theme_color_override("font_color", Color("#ffcf5a"))
	column.add_child(_status)


# --- Для тестов --------------------------------------------------------------------------

func slot(container: String, index: int) -> Button:
	return panel.find_child("Grid_" + container, true, false).get_node_or_null("Slot_%d" % index) as Button


func detail(action_name: String) -> Button:
	return _details.find_child(action_name, true, false) as Button


func rename_field() -> LineEdit:
	return _details.find_child("NewName", true, false) as LineEdit


func status_text() -> String:
	return _status.text
