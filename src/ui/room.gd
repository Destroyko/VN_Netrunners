extends Control
## Комната героя — заглушка M1 (арты — M3). Только показывает текст и передаёт клики в `Room`:
## правил игры здесь нет (docs/gameplay/hacking.md, «Комната»).
##
## Клик по монитору: рабочий стол или аварийный экран. Клик по системному блоку: что внутри.
## Предмет из инвентаря подключается к системному блоку кнопкой под ним.

@onready var _output: Label = $Rows/Output
@onready var _inventory: VBoxContainer = $Rows/Inventory


func _ready() -> void:
	$Rows/Monitor.pressed.connect(_on_monitor)
	$Rows/SystemBlock.pressed.connect(_on_system_block)
	$Rows/Menu.pressed.connect(_on_menu)
	EventBus.system_restored.connect(func(_paths: PackedStringArray, _os: bool) -> void: _refresh_inventory())
	_refresh_inventory()
	_output.text = "Твоя комната."
	$Rows/Monitor.grab_focus()


func _on_monitor() -> void:
	var report: Dictionary = Room.monitor(Filesystem.for_node(Network.HOME_ID))
	if bool(report["desktop"]):
		get_tree().change_scene_to_file(Screens.DESKTOP)
		return
	_show(report["lines"] as PackedStringArray)


func _on_system_block() -> void:
	_show(Room.hardware())


func _on_item(item_id: String) -> void:
	var report: Dictionary = Room.use_item(item_id, Filesystem.for_node(Network.HOME_ID))
	_show(report["lines"] as PackedStringArray)


func _on_menu() -> void:
	get_tree().change_scene_to_file(Screens.MAIN_MENU)


func _show(lines: PackedStringArray) -> void:
	_output.text = "\n".join(lines)


## По кнопке на каждый предмет героя: нажатие подключает его к системному блоку.
func _refresh_inventory() -> void:
	for child: Node in _inventory.get_children():
		child.queue_free()
	for id: String in Inventory.items():
		var button := Button.new()
		button.text = "Подключить к системному блоку: " + Inventory.name_of(id)
		button.tooltip_text = Inventory.about(id)
		button.pressed.connect(_on_item.bind(id))
		_inventory.add_child(button)
