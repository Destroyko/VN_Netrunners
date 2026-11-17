class_name AlarmApp
extends VBoxContainer
## Приложение «Будильник» (docs/gameplay/time.md, «Ждать и спать»): время пробуждения и «Спать»
## или «Подождать». Открывает его объект в мире — кровать даёт оба действия, скамейка (позже) —
## только «Подождать». Открыт просто из телефона — только посмотреть и поставить время.
## Правил здесь нет: время проматывает `Rest`.

signal rested(mode: String)

var _hour: SpinBox
var _minute: SpinBox
var _sleep: Button
var _wait: Button
var _hint: Label


func _init() -> void:
	name = "AlarmApp"
	add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.name = "Alarm"
	add_child(row)
	var label := Label.new()
	label.text = "Будильник:"
	row.add_child(label)
	_hour = SpinBox.new()
	_hour.name = "Hour"
	_hour.max_value = 23
	row.add_child(_hour)
	_minute = SpinBox.new()
	_minute.name = "Minute"
	_minute.max_value = 55
	_minute.step = 5
	row.add_child(_minute)
	_sleep = Button.new()
	_sleep.name = "Sleep"
	_sleep.text = "Спать"
	_sleep.pressed.connect(_rest.bind(Rest.MODE_SLEEP))
	add_child(_sleep)
	_wait = Button.new()
	_wait.name = "Wait"
	_wait.text = "Подождать"
	_wait.pressed.connect(_rest.bind(Rest.MODE_WAIT))
	add_child(_wait)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = "Будильник включается перед сном."
	add_child(_hint)
	var alarm: int = Rest.default_alarm()
	set_alarm(alarm / 60, alarm % 60)
	set_modes([])


## Какие действия доступны: [] — только время, кровать — сон и ожидание.
func set_modes(modes: PackedStringArray) -> void:
	_sleep.visible = modes.has(Rest.MODE_SLEEP)
	_wait.visible = modes.has(Rest.MODE_WAIT)
	_hint.visible = modes.is_empty()


func set_alarm(hour: int, minute: int) -> void:
	_hour.value = hour
	_minute.value = minute


func _rest(mode: String) -> void:
	var alarm: int = int(_hour.value) * 60 + int(_minute.value)
	Rest.pass_time(Rest.minutes_until(alarm), mode)
	rested.emit(mode)
