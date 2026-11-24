class_name Taskbar
extends PanelContainer
## Панель задач: меню, время, деньги, заметность, кнопки открытых окон
## (docs/tech/desktop-layout.md, «Панель задач»). Только читает GameState и слушает EventBus.

signal window_button_pressed(app_id: String)
signal menu_requested(action: String)
## Кнопка «Отойти от ПК» справа на панели — заметная и далеко от «Выключить» (плейтест M2).
signal leave_requested

## «Пуск»: только то, что относится к компьютеру. Сохранение и выход из игры — в меню по Esc в
## комнате (плейтест M2, 17.11.2026). Программы и блокнот появятся здесь в M3.
const MENU_ITEMS: Dictionary = {
	"terminal": "Терминал", "reboot": "Перезагрузить", "shut_down": "Выключить",
}

var _time: Label
var _money: Label
var _energy: ProgressBar
var _satiety: ProgressBar
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
	_energy = _need_bar("Energy", "Энергия", GameTheme.color("ok"))
	row.add_child(_energy)
	# Сытость показывается, только пока открыты ворота голода (docs/tech/gates.md).
	_satiety = _need_bar("Satiety", "Сытость", GameTheme.color("warn"))
	row.add_child(_satiety)
	_heat = HeatBar.new()
	_heat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_heat)

	_windows = HBoxContainer.new()
	_windows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_windows)

	var leave := Button.new()
	leave.name = "Leave"
	leave.text = "Отойти от ПК (Esc)"
	leave.focus_mode = Control.FOCUS_NONE
	leave.pressed.connect(func() -> void: leave_requested.emit())
	row.add_child(leave)


func _ready() -> void:
	EventBus.time_advanced.connect(func(_minute: int, _passed: int) -> void: refresh())
	EventBus.money_changed.connect(func(_money_now: int, _delta: int) -> void: refresh())
	EventBus.needs_changed.connect(refresh)
	EventBus.flag_changed.connect(func(flag: String, _value: bool) -> void:
		if flag == Gates.HUNGER:
			refresh())
	refresh()


func refresh() -> void:
	_time.text = Clock.format_now()
	_money.text = "%d ₽" % GameState.money
	_energy.max_value = Needs.energy_max()
	_energy.value = Needs.energy()
	_energy.tooltip_text = "Энергия: %d / %d" % [int(Needs.energy()), int(Needs.energy_max())]
	_satiety.visible = Gates.is_open(Gates.HUNGER)
	_satiety.max_value = Needs.satiety_max()
	_satiety.value = Needs.satiety()
	_satiety.tooltip_text = "Сытость: %d / %d" % [int(Needs.satiety()), int(Needs.satiety_max())]


## Тонкая шкала самочувствия в панели задач (за ПК телефон не показывается).
func _need_bar(bar_name: String, title: String, fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = bar_name
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(70, 8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.tooltip_text = title
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	bar.add_theme_stylebox_override("fill", style)
	return bar


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
