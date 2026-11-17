class_name SystemNotice
extends PanelContainer
## Короткое сообщение системы ПК вверху стола: «Игра сохранена» и подобное. Это не мысль героя
## (те — `HeroThoughts`, внизу): система говорит сухо, как настоящая программа
## (docs/tech/terminal-spec.md, «Тон вывода»). Гаснет само, управление не блокирует.

const SHOW_SECONDS: float = 3.0

var _label: Label
var _timer: Timer


func _init() -> void:
	name = "SystemNotice"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	add_child(_label)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(hide)
	add_child(_timer)


func show_text(text: String) -> void:
	_label.text = text
	show()
	if is_inside_tree():
		_timer.start(SHOW_SECONDS)


func text() -> String:
	return _label.text
