class_name PhoneStatus
extends HBoxContainer
## Строка состояния телефона: время, энергия, сытость, деньги, непрочитанное. Видна всегда —
## свёрнутый телефон лежит в углу экрана (плейтест M2: самочувствие видно не только за ПК).
## Только читает `Needs`, `GameState`, `Mailbox`, `Messenger` и слушает шину.

const BAR_WIDTH: float = 56.0

var _time: Label
var _energy: ProgressBar
var _satiety: ProgressBar
var _money: Label
var _unread: Label


func _init() -> void:
	name = "Status"
	add_theme_constant_override("separation", 8)
	_time = _label("Time")
	_energy = _bar("Energy", "Энергия", Color("#7fd36b"))
	_satiety = _bar("Satiety", "Сытость", Color("#e8a24a"))
	_money = _label("Money")
	_money.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_unread = _label("Unread")
	_unread.add_theme_color_override("font_color", Color("#ffcf5a"))


func _ready() -> void:
	EventBus.time_advanced.connect(func(_m: int, _p: int) -> void: refresh())
	EventBus.needs_changed.connect(refresh)
	EventBus.flag_changed.connect(func(flag: String, _value: bool) -> void:
		if flag == Gates.HUNGER:
			refresh())
	EventBus.money_changed.connect(func(_money_now: int, _delta: int) -> void: refresh())
	for sig: Signal in [EventBus.mail_received, EventBus.message_received]:
		sig.connect(func(_uid: String, _id: String) -> void: refresh())
	EventBus.mail_read.connect(func(_uid: String, _id: String) -> void: refresh())
	EventBus.messages_read.connect(func(_contact: String) -> void: refresh())
	refresh()


func refresh() -> void:
	_time.text = "%02d:%02d" % [Clock.hour(), Clock.minute_of_hour()]
	_energy.max_value = Needs.energy_max()
	_energy.value = Needs.energy()
	_energy.tooltip_text = "Энергия: %d / %d" % [int(Needs.energy()), int(Needs.energy_max())]
	_satiety.visible = Gates.is_open(Gates.HUNGER)
	_satiety.max_value = Needs.satiety_max()
	_satiety.value = Needs.satiety()
	_satiety.tooltip_text = "Сытость: %d / %d" % [int(Needs.satiety()), int(Needs.satiety_max())]
	_money.text = "%d ₽" % GameState.money
	var unread: int = unread_total()
	_unread.text = "● %d" % unread if unread > 0 else ""


static func unread_total() -> int:
	return Mailbox.unread_count() + Messenger.unread_count()


func _label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(label)
	return label


## Полоска с буквой: текст на полоске не помещается, полное число — во всплывающей подсказке.
func _bar(node_name: String, caption: String, color: Color) -> ProgressBar:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(box)
	var letter := Label.new()
	letter.text = caption.left(1)
	box.add_child(letter)
	var bar := ProgressBar.new()
	bar.name = node_name
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(BAR_WIDTH, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	# Цвет — чтобы полоска читалась на тёмном телефоне: светлая серая сливалась с фоном.
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.12)
	back.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", back)
	box.add_child(bar)
	return bar


# --- Для тестов --------------------------------------------------------------------------

func energy_bar() -> ProgressBar:
	return _energy


func satiety_bar() -> ProgressBar:
	return _satiety


func money_text() -> String:
	return _money.text


func unread_text() -> String:
	return _unread.text
