class_name HeroThoughts
extends PanelContainer
## Мысль героя внизу стола: «скоро пора отдыхать», «надо бы поесть»
## (docs/gameplay/needs.md, «Предупреждение»). Не блокирует управление и сама гаснет.
## Тексты — `data/needs.json`.

const SHOW_SECONDS: float = 6.0

var _label: Label
var _timer: Timer


func _init() -> void:
	name = "HeroThoughts"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	add_child(_label)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(hide)
	add_child(_timer)


func _ready() -> void:
	EventBus.need_warned.connect(func(kind: String) -> void: say(thought(kind)))
	EventBus.order_delivered.connect(func(_id: String) -> void: say(thought("delivered")))
	EventBus.hero_thought.connect(say)


static func thought(kind: String) -> String:
	return str((DataLoader.needs().get("thoughts", {}) as Dictionary).get(kind, ""))


func say(text: String) -> void:
	if text.is_empty():
		return
	_label.text = text
	show()
	if is_inside_tree():
		_timer.start(SHOW_SECONDS)


func text() -> String:
	return _label.text
