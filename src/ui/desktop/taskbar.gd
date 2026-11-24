class_name Taskbar
extends PanelContainer
## Панель задач: слева «Пуск» и заметность, по центру кнопки окон, справа самочувствие, деньги, время
## и «Отойти от ПК» (docs/tech/desktop-layout.md, «Панель задач»; вид — docs/tech/desktop-ui-spec.md).
## Только читает GameState и слушает EventBus.

signal window_button_pressed(app_id: String)
signal menu_requested(action: String)
## Кнопка «Отойти от ПК» в правом краю панели — далеко от «Выключить» в «Пуске» (плейтест M2).
signal leave_requested

## «Пуск»: только то, что относится к компьютеру. Сохранение и выход из игры — в меню по Esc в
## комнате (плейтест M2, 17.11.2026). Программы и блокнот появятся здесь в M3.
const MENU_ITEMS: Dictionary = {
	"terminal": "Терминал", "reboot": "Перезагрузить", "shut_down": "Выключить",
}

## Высота панели и отступы — по шагу 4 px.
const HEIGHT: float = 48.0
const PAD: int = 12
const GAP: int = 8
const WINDOW_ICON: int = 18

## Тема ПК героя: та же, что у стола (`Desktop.theme_id`).
var theme_id: String = GameTheme.pc_theme_id()

var _time: Label
var _date: Label
var _money: Label
var _energy: ProgressBar
var _satiety: ProgressBar
var _heat: HeatBar
var _windows: HBoxContainer
var _buttons: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	add_theme_stylebox_override("panel", _bar_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP)
	add_child(row)

	# Боковые зоны равной ширины: кнопки окон остаются ровно по центру экрана.
	var left := HBoxContainer.new()
	left.add_theme_constant_override("separation", PAD)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var menu := MenuButton.new()
	menu.name = "Start"
	menu.text = "Пуск"
	menu.flat = false
	menu.focus_mode = Control.FOCUS_NONE
	menu.custom_minimum_size = Vector2(0, 32)
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_button(menu, true)
	var popup: PopupMenu = menu.get_popup()
	for action: String in MENU_ITEMS.keys():
		popup.add_item(str(MENU_ITEMS[action]))
		popup.set_item_metadata(popup.item_count - 1, action)
	popup.index_pressed.connect(func(index: int) -> void: menu_requested.emit(str(popup.get_item_metadata(index))))
	left.add_child(menu)
	_heat = HeatBar.new()
	_heat.theme_id = theme_id
	_heat.custom_minimum_size = Vector2(110, 10)
	_heat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(_heat)

	_windows = HBoxContainer.new()
	_windows.add_theme_constant_override("separation", 4)
	_windows.alignment = BoxContainer.ALIGNMENT_CENTER
	_windows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_windows.size_flags_stretch_ratio = 2.0
	row.add_child(_windows)

	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", PAD + 4)
	right.alignment = BoxContainer.ALIGNMENT_END
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)

	# Самочувствие — тонкие шкалы друг над другом: панель не растягивается в ширину.
	var needs := VBoxContainer.new()
	needs.add_theme_constant_override("separation", 4)
	needs.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(needs)
	_energy = _need_bar("Energy", "Энергия", GameTheme.color("ok", theme_id))
	needs.add_child(_energy)
	# Сытость показывается, только пока открыты ворота голода (docs/tech/gates.md).
	_satiety = _need_bar("Satiety", "Сытость", GameTheme.color("warn", theme_id))
	needs.add_child(_satiety)

	_money = Label.new()
	_money.name = "Money"
	_money.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(_money)

	# Время крупно, дата мелко под ним.
	var clock := VBoxContainer.new()
	clock.add_theme_constant_override("separation", -2)
	clock.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(clock)
	_time = Label.new()
	_time.name = "Time"
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time.add_theme_font_size_override("font_size", 16)
	clock.add_child(_time)
	_date = Label.new()
	_date.name = "Date"
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_date.add_theme_font_size_override("font_size", 11)
	_date.add_theme_color_override("font_color", GameTheme.color("text_dim", theme_id))
	clock.add_child(_date)

	var leave := Button.new()
	leave.name = "Leave"
	leave.tooltip_text = "Отойти от ПК (Esc)"
	leave.icon = GameTheme.icon("leave", theme_id)
	if leave.icon == null:
		leave.text = "Отойти"
	leave.expand_icon = true
	leave.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leave.custom_minimum_size = Vector2(40, 32)
	leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	leave.add_theme_constant_override("icon_max_width", 20)
	leave.focus_mode = Control.FOCUS_NONE
	_style_button(leave, true)
	leave.pressed.connect(func() -> void: leave_requested.emit())
	right.add_child(leave)


func _ready() -> void:
	EventBus.time_advanced.connect(func(_minute: int, _passed: int) -> void: refresh())
	EventBus.money_changed.connect(func(_money_now: int, _delta: int) -> void: refresh())
	EventBus.needs_changed.connect(refresh)
	EventBus.flag_changed.connect(func(flag: String, _value: bool) -> void:
		if flag == Gates.HUNGER:
			refresh())
	refresh()


func refresh() -> void:
	_time.text = "%02d:%02d" % [Clock.hour(), Clock.minute_of_hour()]
	_date.text = Clock.format_date()
	_money.text = "%d ₽" % GameState.money
	_energy.max_value = Needs.energy_max()
	_energy.value = Needs.energy()
	_energy.tooltip_text = "Энергия: %d / %d" % [int(Needs.energy()), int(Needs.energy_max())]
	_satiety.visible = Gates.is_open(Gates.HUNGER)
	_satiety.max_value = Needs.satiety_max()
	_satiety.value = Needs.satiety()
	_satiety.tooltip_text = "Сытость: %d / %d" % [int(Needs.satiety()), int(Needs.satiety_max())]


## Фон панели: свой тон, линия сверху, без скруглений — панель прилегает к краям экрана.
func _bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var panel: Color = GameTheme.color("panel", theme_id)
	var background: Color = GameTheme.color("background", theme_id)
	style.bg_color = background.lerp(panel, 0.5) if panel.get_luminance() < 0.4 else panel
	style.border_color = GameTheme.color("border", theme_id)
	style.border_width_top = 1
	style.content_margin_left = PAD
	style.content_margin_right = PAD
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


## Кнопка панели. `framed` — с подложкой («Пуск», «Отойти»); кнопка окна без подложки, а у окна в
## фокусе — тон плашки и полоса акцента снизу.
func _style_button(button: Button, framed: bool) -> void:
	var radius: int = int((GameTheme.load_theme(theme_id).get("shape", {}) as Dictionary).get("radius", 4))
	var raised: Color = GameTheme.color("panel_raised", theme_id)
	var accent: Color = GameTheme.color("accent", theme_id)
	var text: Color = GameTheme.color("text", theme_id)
	var bar: Color = _bar_style().bg_color
	var states: Dictionary = {
		"normal": bar.lerp(raised, 0.6) if framed else Color(0, 0, 0, 0),
		"hover": raised,
		"pressed": raised,
		"hover_pressed": raised,
		"disabled": Color(0, 0, 0, 0),
		"focus": Color(0, 0, 0, 0),
	}
	for state: String in states.keys():
		var box := StyleBoxFlat.new()
		box.bg_color = states[state] as Color
		box.set_corner_radius_all(radius)
		box.content_margin_left = PAD
		box.content_margin_right = PAD
		box.content_margin_top = 4
		box.content_margin_bottom = 4
		if state.begins_with("hover") or state == "pressed":
			box.bg_color = raised
		if (state == "pressed" or state == "hover_pressed") and not framed:
			box.border_color = accent
			box.border_width_bottom = 2
		button.add_theme_stylebox_override(state, box)
	for role: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(role, text)


## Тонкая шкала самочувствия в панели задач (за ПК телефон не показывается).
func _need_bar(bar_name: String, title: String, fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = bar_name
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(72, 6)
	bar.tooltip_text = title
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", style)
	# Свой тонкий фон: у фона шкалы из темы поля по 8 px, и шкала раздувается в высоту.
	var back := StyleBoxFlat.new()
	back.bg_color = GameTheme.color("background", theme_id).lerp(GameTheme.color("border", theme_id), 0.35)
	back.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", back)
	return bar


## Кнопка окна на панели: значок, заголовок и признак «окно сейчас в фокусе».
func set_window(app_id: String, title: String, focused: bool, minimized: bool, icon: Texture2D = null) -> void:
	var button: Button = _buttons.get(app_id) as Button
	if button == null:
		button = Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 36)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# Без expand_icon: с текстом растянутый значок получает нулевую ширину; размер задаёт icon_max_width.
		button.add_theme_constant_override("icon_max_width", WINDOW_ICON)
		button.add_theme_constant_override("h_separation", GAP)
		_style_button(button, false)
		button.pressed.connect(func() -> void: window_button_pressed.emit(app_id))
		_windows.add_child(button)
		_buttons[app_id] = button
	button.icon = icon
	button.text = title
	# Свёрнутое окно — блёклое: так видно, что оно убрано, без скобок вокруг названия.
	button.modulate = Color(1, 1, 1, 0.55 if minimized else 1.0)
	button.set_pressed_no_signal(focused and not minimized)


func remove_window(app_id: String) -> void:
	var button: Button = _buttons.get(app_id) as Button
	if button != null:
		button.queue_free()
		_buttons.erase(app_id)


func has_window_button(app_id: String) -> bool:
	return _buttons.has(app_id)
