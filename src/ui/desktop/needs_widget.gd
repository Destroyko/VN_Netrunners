class_name NeedsWidget
extends PanelContainer
## Виджет «энергия и сытость» на рабочем столе (docs/tech/desktop-layout.md: состояние тела —
## не на панели задач). Закрывается крестиком. Только читает `Needs` и слушает шину.
##
## Ширина фиксированная: когда объём энергии начнёт расти (M4), полоска будет расти внутри этой
## ширины до потолка, а не вылезать за окно (gameplay/needs.md, «Прокачка»).

const WIDTH: float = 200.0

var _energy: ProgressBar
var _satiety: ProgressBar


func _init() -> void:
	name = "NeedsWidget"
	custom_minimum_size = Vector2(WIDTH, 0)
	var rows := VBoxContainer.new()
	add_child(rows)
	var head := HBoxContainer.new()
	rows.add_child(head)
	var title := Label.new()
	title.text = "Самочувствие"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.name = "Close"
	close.text = "×"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide)
	head.add_child(close)
	_energy = _bar(rows, "Энергия")
	_satiety = _bar(rows, "Сытость")


func _ready() -> void:
	EventBus.time_advanced.connect(func(_m: int, _p: int) -> void: refresh())
	EventBus.needs_changed.connect(refresh)
	refresh()


func refresh() -> void:
	_energy.max_value = Needs.energy_max()
	_energy.value = Needs.energy()
	_satiety.max_value = Needs.satiety_max()
	_satiety.value = Needs.satiety()


func energy_bar() -> ProgressBar:
	return _energy


func satiety_bar() -> ProgressBar:
	return _satiety


func _bar(parent: Container, caption: String) -> ProgressBar:
	var label := Label.new()
	label.text = caption
	parent.add_child(label)
	var bar := ProgressBar.new()
	bar.name = caption
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(WIDTH - 16, 10)
	parent.add_child(bar)
	return bar
