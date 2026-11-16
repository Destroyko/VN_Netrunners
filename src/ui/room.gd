extends Control
## Комната героя — заглушка M1 (арты — M3). Только показывает текст и передаёт клики в `Room`:
## правил игры здесь нет (docs/gameplay/hacking.md, «Комната»).
##
## Клик по монитору: рабочий стол или аварийный экран. Клик по системному блоку: что внутри.
## Предмет из инвентаря подключается к системному блоку кнопкой под ним. Кровать: будильник и
## «спать» или «подождать» — правила сна в `Rest` (docs/gameplay/needs.md).

@onready var _output: Label = $Rows/Output
@onready var _inventory: VBoxContainer = $Rows/Inventory
@onready var _clock: Label = $Rows/Clock
@onready var _bed_panel: HBoxContainer = $Rows/BedPanel


func _ready() -> void:
	$Rows/Monitor.pressed.connect(_on_monitor)
	$Rows/SystemBlock.pressed.connect(_on_system_block)
	$Rows/Menu.pressed.connect(_on_menu)
	$Rows/Bed.pressed.connect(_on_bed)
	$Rows/BedPanel/Sleep.pressed.connect(_on_rest.bind(Rest.MODE_SLEEP))
	$Rows/BedPanel/Wait.pressed.connect(_on_rest.bind(Rest.MODE_WAIT))
	EventBus.time_advanced.connect(func(_minute: int, _passed: int) -> void: _refresh_clock())
	_refresh_clock()
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


## Кровать: показать будильник (по умолчанию из баланса) с выбором «спать» или «подождать».
func _on_bed() -> void:
	var alarm: int = Rest.default_alarm()
	$Rows/BedPanel/Hour.value = alarm / 60
	$Rows/BedPanel/Minute.value = alarm % 60
	_bed_panel.visible = true


func _on_rest(mode: String) -> void:
	_bed_panel.visible = false
	var alarm: int = int($Rows/BedPanel/Hour.value) * 60 + int($Rows/BedPanel/Minute.value)
	var report: Dictionary = Rest.pass_time(Rest.minutes_until(alarm), mode)
	var reason: String = str(report["interrupted"])
	_output.text = Clock.format_now() if reason.is_empty() else "%s — %s" % [Clock.format_now(), reason]


func _refresh_clock() -> void:
	_clock.text = Clock.format_now()


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
