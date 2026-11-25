class_name PcCasePanel
extends PanelContainer
## Окно «Системный блок» справа от инвентаря (шаг 7.5, эскиз разработчика 25.11.2026): гнездо USB
## и слоты комплектующих. Флешку тащат из инвентаря в гнездо (гнездо подсвечивается, пока
## тащишь подходящее), обратно — в сетку инвентаря; правая кнопка по гнезду — «Вынуть». Слоты
## комплектующих видны, но пока не работают — железа в игре ещё нет. Внизу — питание ПК.
##
## Правил здесь нет: вставить и вынуть — `Room`, питание — `PcPower`. Окно живёт внутри
## `InventoryOverlay`: закрыл одно — закрылись оба.

## Слоты комплектующих по эскизу: пока недоступны. Последний — секрет на будущее.
const MODULES: PackedStringArray = [
	"Материнская плата", "Процессор", "Видеокарта",
	"Оперативная память", "Оперативная память", "Оперативная память", "Оперативная память",
	"Жёсткий диск", "Сетевая карта", "???",
]
const MODULE_COLUMNS: int = 4
const MENU_EJECT: int = 0

## Закрыть окно (оно закрывает и инвентарь).
signal close_requested
## Что сказать игроку (вставлено, вынуто, ПК выключен) — строка статуса инвентаря.
signal said(text: String)

var _usb: Button
var _power: Button
var _menu: PopupMenu
var _styles: Dictionary = {}
var _dragging_fit: bool = false


func _ready() -> void:
	name = "PcCase"
	_build()
	EventBus.inventory_changed.connect(func(_c: String) -> void: refresh())
	EventBus.pc_power_changed.connect(func(_on: bool) -> void: refresh())


## Плашки слотов — из инвентаря, чтобы оба окна были одной породы.
func apply_styles(styles: Dictionary) -> void:
	_styles = styles
	refresh()


func refresh() -> void:
	if _usb == null:
		return
	var plugged: Dictionary = Room.inserted()
	_usb.text = Inventory.label_of(plugged) if not plugged.is_empty() else ""
	(_usb.get_node("Caption") as Label).text = _usb.text
	_usb.tooltip_text = "%s\n%s" % [_usb.text, Inventory.about(str(plugged["kind"]))] if not plugged.is_empty() \
		else "Гнездо USB: перетащи сюда флешку из инвентаря"
	_power.text = "Выключить компьютер" if PcPower.is_on() else "Включить компьютер"
	_paint_usb()


func usb_slot() -> Button:
	return _usb


func power_button() -> Button:
	return _power


# --- Гнездо USB ------------------------------------------------------------------------------

func _paint_usb() -> void:
	if _styles.is_empty():
		return
	var plugged: bool = not Room.inserted().is_empty()
	var normal: StyleBox = _styles["slot_selected" if _dragging_fit else ("slot" if plugged else "slot_empty")] as StyleBox
	for state: String in ["normal", "disabled"]:
		_usb.add_theme_stylebox_override(state, normal)
	_usb.add_theme_stylebox_override("hover", _styles["slot_hover"] as StyleBox)
	_usb.add_theme_stylebox_override("pressed", normal)
	_usb.add_theme_stylebox_override("focus", _styles["slot_focus"] as StyleBox)
	for module: Node in find_child("Modules", true, false).get_children():
		(module as Button).add_theme_stylebox_override("disabled", _styles["slot_empty"] as StyleBox)
		(module.get_node("Caption") as Label).theme_type_variation = "DimLabel"


## Пока тащат подходящий носитель — гнездо подсвечено: видно, куда бросить.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_dragging_fit = can_insert(get_viewport().gui_get_drag_data())
		_paint_usb()
	elif what == NOTIFICATION_DRAG_END:
		_dragging_fit = false
		_paint_usb()


func can_insert(data: Variant) -> bool:
	if not (data is Dictionary) or not (data as Dictionary).has("inventory_uid"):
		return false
	var found: Dictionary = Inventory.find(str((data as Dictionary)["inventory_uid"]))
	return not found.is_empty() and str(found["container"]) != Inventory.PC \
		and Inventory.accepts(Inventory.PC, str((found["entry"] as Dictionary)["kind"])) \
		and Room.inserted().is_empty()


func insert(uid: String) -> void:
	var report: Dictionary = Room.insert(uid, Filesystem.for_node(Network.HOME_ID))
	said.emit("\n".join(report["lines"] as PackedStringArray))


func eject() -> void:
	var error: String = Room.eject()
	said.emit(error)


func _drag_usb(_at: Vector2) -> Variant:
	var plugged: Dictionary = Room.inserted()
	if plugged.is_empty():
		return null
	var preview := Label.new()
	preview.text = Inventory.label_of(plugged)
	set_drag_preview(preview)
	return {"inventory_uid": str(plugged["uid"])}


func _on_usb_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT or Room.inserted().is_empty():
		return
	_menu.position = Vector2i(get_viewport().get_mouse_position())
	_menu.popup()


# --- Питание ----------------------------------------------------------------------------------

## Выключить — по-настоящему (стол закрыт, соединение оборвано). Включить — загрузка под
## полоской; с флешкой в гнезде — установка системы. Экран загрузки покажет её сам.
func _on_power() -> void:
	if PcPower.is_on():
		PcPower.shut_down()
		Desktop.discard_kept()
		said.emit("Компьютер выключен.")
		return
	var report: Dictionary = PcPower.power_on()
	if bool(report.get("pending", false)):
		close_requested.emit()
		return
	if bool(report.get("installed", false)):
		said.emit("Система установлена с флешки.")
	else:
		said.emit("Компьютер включён.")


# --- Сборка -----------------------------------------------------------------------------------

func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var title := Label.new()
	title.text = "Системный блок"
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
	close_button.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close_button)
	column.add_child(HSeparator.new())

	column.add_child(_section("USB"))
	_usb = _slot("Slot_usb", "")
	_usb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_usb.set_drag_forwarding(_drag_usb, func(_at: Vector2, data: Variant) -> bool: return can_insert(data),
		func(_at: Vector2, data: Variant) -> void: insert(str((data as Dictionary)["inventory_uid"])))
	_usb.gui_input.connect(_on_usb_input)
	column.add_child(_usb)
	_menu = PopupMenu.new()
	_menu.name = "UsbMenu"
	_menu.add_item("Вынуть", MENU_EJECT)
	_menu.id_pressed.connect(func(_id: int) -> void: eject())
	add_child(_menu)

	column.add_child(_section("Комплектующие"))
	var grid := GridContainer.new()
	grid.name = "Modules"
	grid.columns = MODULE_COLUMNS
	grid.add_theme_constant_override("h_separation", InventoryOverlay.SLOT_GAP)
	grid.add_theme_constant_override("v_separation", InventoryOverlay.SLOT_GAP)
	column.add_child(grid)
	for i: int in MODULES.size():
		var module: Button = _slot("Module_%d" % i, MODULES[i])
		# Железа в игре пока нет: слот виден, но недоступен.
		module.disabled = true
		module.tooltip_text = "Неизвестное устройство" if MODULES[i] == "???" else "%s: пока недоступно" % MODULES[i]
		grid.add_child(module)

	column.add_child(HSeparator.new())
	_power = Button.new()
	_power.name = "Power"
	_power.pressed.connect(_on_power)
	column.add_child(_power)


func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "DimLabel"
	return label


func _slot(slot_name: String, caption: String) -> Button:
	var slot := Button.new()
	slot.name = slot_name
	slot.custom_minimum_size = InventoryOverlay.SLOT_SIZE
	slot.clip_text = true
	slot.focus_mode = Control.FOCUS_NONE
	var label := Label.new()
	label.name = "Caption"
	label.text = caption
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.max_lines_visible = 2
	label.add_theme_font_size_override("font_size", InventoryOverlay.SLOT_FONT_SIZE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(label)
	# Текст кнопки — для подсказки и тестов, виден только подписью.
	slot.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	slot.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	slot.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
	slot.add_theme_color_override("font_disabled_color", Color(0, 0, 0, 0))
	return slot
