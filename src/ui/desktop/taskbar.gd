class_name Taskbar
extends PanelContainer
## Панель задач: меню, время, деньги, заметность, кнопки открытых окон
## (docs/tech/desktop-layout.md, «Панель задач»). Только читает GameState и слушает EventBus.

signal window_button_pressed(app_id: String)
signal menu_requested(action: String)

const MENU_ITEMS: Dictionary = {
	"save_game": "Сохранить игру", "back_to_room": "В комнату",
	"reboot": "Перезагрузить", "shut_down": "Выключить", "main_menu": "В главное меню",
}

var _time: Label
var _money: Label
var _heat: HeatBar
var _windows: HBoxContainer
var _buttons: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(0, 34)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)

	var menu := MenuButton.new()
	menu.text = "☰"
	menu.flat = true
	var popup: PopupMenu = menu.get_popup()
	for action: String in MENU_ITEMS.keys():
		popup.add_item(str(MENU_ITEMS[action]))
		popup.set_item_metadata(popup.item_count - 1, action)
	popup.index_pressed.connect(func(index: int) -> void: menu_requested.emit(str(popup.get_item_metadata(index))))
	row.add_child(menu)

	_time = Label.new()
	row.add_child(_time)
	_money = Label.new()
	row.add_child(_money)
	_heat = HeatBar.new()
	_heat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_heat)

	_windows = HBoxContainer.new()
	_windows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_windows)


func _ready() -> void:
	EventBus.time_advanced.connect(func(_minute: int, _passed: int) -> void: refresh())
	EventBus.money_changed.connect(func(_money_now: int, _delta: int) -> void: refresh())
	refresh()


func refresh() -> void:
	_time.text = Clock.format_now()
	_money.text = "%d ₽" % GameState.money


## Кнопка окна на панели: заголовок и признак «окно сейчас в фокусе».
func set_window(app_id: String, title: String, focused: bool, minimized: bool) -> void:
	var button: Button = _buttons.get(app_id) as Button
	if button == null:
		button = Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: window_button_pressed.emit(app_id))
		_windows.add_child(button)
		_buttons[app_id] = button
	button.text = ("(%s)" if minimized else "%s") % title
	button.set_pressed_no_signal(focused and not minimized)


func remove_window(app_id: String) -> void:
	var button: Button = _buttons.get(app_id) as Button
	if button != null:
		button.queue_free()
		_buttons.erase(app_id)


func has_window_button(app_id: String) -> bool:
	return _buttons.has(app_id)
