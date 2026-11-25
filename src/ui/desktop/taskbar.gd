class_name Taskbar
extends PanelContainer
## Панель задач: слева «Пуск», заметность и сразу за ними кнопки окон (как в Windows), справа
## самочувствие, деньги, время и «Отойти от ПК». Кнопки — во всю высоту панели (docs/tech/desktop-layout.md, «Панель задач»; вид — docs/tech/desktop-ui-spec.md).
## Только читает GameState и слушает EventBus.

signal window_button_pressed(app_id: String)
signal menu_requested(action: String)
## Кнопка «Отойти от ПК» в правом краю панели — далеко от «Выключить» в «Пуске» (плейтест M2).
signal leave_requested

## «Пуск»: только то, что относится к компьютеру. Сохранение и выход из игры — в меню по Esc в
## комнате (плейтест M2, 17.11.2026). Программы и блокнот появятся здесь в M3.
const MENU_ITEMS: Dictionary = {
	"terminal": "Терминал", "files": "Файлы", "reboot": "Перезагрузить", "shut_down": "Выключить",
}
## Значки пунктов «Пуска» и где проходит черта: действия питания — отдельной группой внизу.
## «Файлы» в «Пуске» всегда: даже если игрок удалил ярлыки со стола, проводник под рукой.
const MENU_ICONS: Dictionary = {"terminal": "terminal", "files": "files", "reboot": "reboot", "shut_down": "power"}
const MENU_POWER: PackedStringArray = ["reboot", "shut_down"]
const MENU_WIDTH: float = 240.0

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
var _start: Button
var _menu: PopupPanel


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	add_theme_stylebox_override("panel", _bar_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", PAD)
	add_child(row)
	var left := row
	_start = Button.new()
	_start.name = "Start"
	_start.text = "Пуск"
	_start.icon = GameTheme.icon("start", theme_id)
	_start.add_theme_constant_override("icon_max_width", 18)
	_start.toggle_mode = true
	_start.focus_mode = Control.FOCUS_NONE
	_start.custom_minimum_size = Vector2(0, HEIGHT - 1)
	_style_button(_start, true)
	_start.toggled.connect(func(on: bool) -> void:
		if on:
			open_start_menu()
		else:
			_menu.hide())
	left.add_child(_start)
	_build_menu()

	# Риск раскрытия: значок глаза и полоска делений, вместе — один элемент с подсказкой.
	var heat_box := HBoxContainer.new()
	heat_box.add_theme_constant_override("separation", 6)
	heat_box.tooltip_text = "Риск раскрытия"
	heat_box.mouse_filter = Control.MOUSE_FILTER_PASS
	left.add_child(heat_box)
	heat_box.add_child(_glyph("heat", 18))
	_heat = HeatBar.new()
	_heat.theme_id = theme_id
	_heat.custom_minimum_size = Vector2(110, 10)
	_heat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heat_box.add_child(_heat)

	# Кнопки окон — слева, сразу за шкалой; свободное место между ними и правой зоной.
	_windows = HBoxContainer.new()
	_windows.add_theme_constant_override("separation", 2)
	_windows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_windows)

	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", PAD + 4)
	row.add_child(right)

	# Самочувствие — тонкие шкалы друг над другом: панель не растягивается в ширину.
	var needs := VBoxContainer.new()
	needs.add_theme_constant_override("separation", 4)
	needs.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(needs)
	_energy = _need_bar("Energy", "Энергия", GameTheme.color("ok", theme_id))
	needs.add_child(_need_row("energy", _energy))
	# Сытость показывается, только пока открыты ворота голода (docs/tech/gates.md).
	_satiety = _need_bar("Satiety", "Сытость", GameTheme.color("warn", theme_id))
	needs.add_child(_need_row("food", _satiety))

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
	leave.custom_minimum_size = Vector2(48, HEIGHT - 1)
	leave.add_theme_constant_override("icon_max_width", 20)
	leave.focus_mode = Control.FOCUS_NONE
	_style_button(leave, true)
	leave.pressed.connect(func() -> void: leave_requested.emit())
	right.add_child(leave)


## «Пуск»: панель над кнопкой, пункты со значками, питание отдельной группой внизу.
func _build_menu() -> void:
	_menu = PopupPanel.new()
	_menu.name = "StartMenu"
	_menu.theme = GameTheme.build(theme_id)
	_menu.popup_hide.connect(func() -> void: _start.set_pressed_no_signal(false))
	add_child(_menu)
	var rows := VBoxContainer.new()
	rows.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	rows.add_theme_constant_override("separation", 2)
	_menu.add_child(rows)
	var power_started: bool = false
	for action: String in MENU_ITEMS.keys():
		if MENU_POWER.has(action) and not power_started:
			power_started = true
			rows.add_child(HSeparator.new())
		var item := Button.new()
		item.name = "Menu_" + action
		item.text = str(MENU_ITEMS[action])
		item.icon = GameTheme.icon(str(MENU_ICONS.get(action, "")), theme_id)
		item.theme_type_variation = "FlatButton"
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item.focus_mode = Control.FOCUS_NONE
		item.custom_minimum_size = Vector2(0, 36)
		item.add_theme_constant_override("icon_max_width", 20)
		item.add_theme_constant_override("h_separation", PAD)
		item.pressed.connect(func() -> void:
			_menu.hide()
			menu_requested.emit(action))
		rows.add_child(item)


## Открыть меню «Пуск» над кнопкой (щелчок по «Пуску», снимки, клавиша Win в будущем).
func open_start_menu() -> void:
	_start.set_pressed_no_signal(true)
	_menu.reset_size()
	var at: Vector2 = _start.get_screen_position() + Vector2(4, -_menu.size.y - 4)
	_menu.popup(Rect2i(Vector2i(at), _menu.size))


## Значок темы фиксированного размера (подписи шкал на панели).
func _glyph(icon_id: String, side: int) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = GameTheme.icon(icon_id, theme_id)
	rect.custom_minimum_size = Vector2(side, side)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Строка самочувствия: значок и тонкая шкала.
func _need_row(icon_id: String, bar: ProgressBar) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.tooltip_text = bar.tooltip_text
	row.add_child(_glyph(icon_id, 14))
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	return row


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
	# Прячется вся строка со значком, иначе значок висел бы без шкалы.
	(_satiety.get_parent() as Control).visible = _satiety.visible
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
	# Без полей: кнопки «Пуск», окон и «Отойти» во всю высоту панели и вплотную к краям экрана.
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 1
	style.content_margin_bottom = 0
	return style


## Кнопка панели во всю высоту, без скруглений. `framed` — с подложкой («Пуск», «Отойти»); кнопка
## окна без подложки, у окна в фокусе — тон плашки (полоску сверху рисует `TaskButton`).
func _style_button(button: Button, framed: bool) -> void:
	var raised: Color = GameTheme.color("panel_raised", theme_id)
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
		box.content_margin_left = PAD + 4
		box.content_margin_right = PAD + 4
		if state.begins_with("hover") or state == "pressed":
			box.bg_color = raised
		# У кнопки окна под мышью — полупрозрачный тон плашки, у окна в фокусе — полный.
		if state == "hover" and not framed:
			box.bg_color = Color(raised, 0.5)
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
	var button: TaskButton = _buttons.get(app_id) as TaskButton
	if button == null:
		button = TaskButton.new()
		button.name = "Task_" + app_id
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, HEIGHT - 1)
		button.focused_color = GameTheme.color("accent", theme_id)
		button.open_color = GameTheme.color("text_dim", theme_id)
		# Без expand_icon: с текстом растянутый значок получает нулевую ширину; размер задаёт icon_max_width.
		button.add_theme_constant_override("icon_max_width", WINDOW_ICON)
		button.add_theme_constant_override("h_separation", GAP)
		_style_button(button, false)
		button.pressed.connect(func() -> void: window_button_pressed.emit(app_id))
		_windows.add_child(button)
		_buttons[app_id] = button
	button.icon = icon
	button.text = title
	button.set_pressed_no_signal(focused and not minimized)
	var state: TaskButton.State = TaskButton.State.OPEN
	if minimized:
		state = TaskButton.State.MINIMIZED
	elif focused:
		state = TaskButton.State.FOCUSED
	button.set_state(state)


func remove_window(app_id: String) -> void:
	var button: TaskButton = _buttons.get(app_id) as TaskButton
	if button != null:
		button.queue_free()
		_buttons.erase(app_id)


func has_window_button(app_id: String) -> bool:
	return _buttons.has(app_id)
