extends Control
## Комната героя — заглушка M1 (арты — M3). Только показывает текст и передаёт клики в `Room`:
## правил игры здесь нет (docs/gameplay/hacking.md, «Комната»).
##
## Объект выбирают — под ним появляются его действия (разработчик, 17.11.2026; с графикой это
## будет клик по спрайту монитора или системного блока):
## - монитор: сразу за компьютер (если включён) — других действий у него нет;
## - системный блок: включить / выключить, осмотреть железо, подключить предмет из инвентаря.
## Кровать: будильник и «спать» или «подождать» — правила сна в `Rest` (docs/gameplay/needs.md).

const OBJECT_MONITOR: String = "monitor"
const OBJECT_SYSTEM_BLOCK: String = "system_block"

@onready var _output: Label = $Rows/Output
@onready var _actions: VBoxContainer = $Rows/Actions
## Какой объект выбран: его действия показаны под ним ("" — ничего).
var _selected: String = ""
@onready var _clock: Label = $Rows/Clock
@onready var _bed_panel: HBoxContainer = $Rows/BedPanel
@onready var _kitchen: VBoxContainer = $Rows/Kitchen


func _ready() -> void:
	$Rows/Monitor.pressed.connect(select_object.bind(OBJECT_MONITOR))
	$Rows/SystemBlock.pressed.connect(select_object.bind(OBJECT_SYSTEM_BLOCK))
	$Rows/Menu.pressed.connect(_on_menu)
	$Rows/Bed.pressed.connect(_on_bed)
	$Rows/BedPanel/Sleep.pressed.connect(_on_rest.bind(Rest.MODE_SLEEP))
	$Rows/BedPanel/Wait.pressed.connect(_on_rest.bind(Rest.MODE_WAIT))
	EventBus.time_advanced.connect(func(_minute: int, _passed: int) -> void: _refresh_clock())
	EventBus.need_warned.connect(func(kind: String) -> void: _output.text = HeroThoughts.thought(kind))
	# Герой дома — курьера слышит здесь же, а не только за ПК.
	EventBus.order_delivered.connect(func(_id: String) -> void: _output.text = HeroThoughts.thought("delivered"))
	EventBus.hero_thought.connect(func(text: String) -> void: _output.text = text)
	EventBus.passed_out.connect(_on_passed_out)
	for sig: Signal in [EventBus.order_delivered, EventBus.food_consumed]:
		sig.connect(func(_id: String) -> void: _refresh_kitchen())
	_refresh_kitchen()
	_refresh_clock()
	EventBus.system_restored.connect(func(_paths: PackedStringArray, _os: bool) -> void: _refresh_actions())
	_output.text = "Твоя комната."
	_show_wake()
	$Rows/Monitor.grab_focus()


## Выбрать объект комнаты: под ним — его действия. Повторный выбор того же — список обновляется.
func select_object(object: String) -> void:
	if object == OBJECT_MONITOR:
		# У монитора одно действие — сесть за компьютер, поэтому без лишнего шага (плейтест M2).
		_selected = ""
		_refresh_actions()
		if PcPower.is_on():
			_on_sit()
		else:
			_output.text = "Экран чёрный: компьютер выключен."
		return
	_selected = object
	_output.text = "Системный блок."
	_refresh_actions()


func _refresh_actions() -> void:
	for child: Node in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	match _selected:
		OBJECT_SYSTEM_BLOCK:
			_power_action()
			_action("Act_hardware", "Осмотреть железо", func() -> void: _show(Room.hardware()))
			for id: String in Inventory.items():
				var button: Button = _action("Act_item_" + id, "Подключить: " + Inventory.name_of(id), _on_item.bind(id))
				button.tooltip_text = Inventory.about(id)


func _action(action_name: String, text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.name = action_name
	button.text = text
	button.pressed.connect(on_press)
	_actions.add_child(button)
	return button


func _power_action() -> void:
	_action("Act_power", "Выключить компьютер" if PcPower.is_on() else "Включить компьютер", _on_power)


## Сесть за ПК: рабочий стол или аварийный экран, если система сломана.
func _on_sit() -> void:
	var report: Dictionary = Room.monitor(Filesystem.for_node(Network.HOME_ID))
	if bool(report["desktop"]):
		Desktop.enter_pc(get_tree())
		return
	_show(report["lines"] as PackedStringArray)


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


## Вырубился прямо в комнате: тот же занавес, только сцена не меняется.
func _on_passed_out() -> void:
	NeedsManager.claim_pass_out()
	var curtain := PassOutCurtain.new()
	add_child(curtain)
	curtain.finished.connect(func() -> void:
		NeedsManager.sleep_after_pass_out()
		_show_wake(curtain))
	curtain.play_falling_asleep()


## После вырубания картинка проявляется из черноты уже здесь. Время пробуждения герой вслух не
## называет — его видно на часах.
func _show_wake(curtain: PassOutCurtain = null) -> void:
	if not bool(GameState.get_var_or(Needs.VAR_WOKE_AFTER_PASS_OUT, false)):
		return
	GameState.set_var(Needs.VAR_WOKE_AFTER_PASS_OUT, false)
	if curtain == null:
		curtain = PassOutCurtain.new()
		add_child(curtain)
	curtain.play_waking_up()


## Кухня: по кнопке на каждую еду из запаса (что привезла доставка). Съесть — `Shop.consume`.
func _refresh_kitchen() -> void:
	for child: Node in _kitchen.get_children():
		_kitchen.remove_child(child)
		child.queue_free()
	var pantry: Dictionary = Shop.pantry()
	for id: String in pantry.keys():
		var button := Button.new()
		button.name = "Eat_" + id
		button.text = "Поесть: %s × %d" % [Shop.title_of(id), int(pantry[id])]
		button.pressed.connect(func() -> void: Shop.consume(id))
		_kitchen.add_child(button)


## Питание ПК: включить или выключить. Выключение закрывает и спрятанный стол — это уже не
## «отошёл», а выключил (docs/gameplay/hacking.md, «Питание ПК»).
func _on_power() -> void:
	if PcPower.is_on():
		PcPower.shut_down()
		Desktop.discard_kept()
		_output.text = "Компьютер выключен."
	else:
		var report: Dictionary = PcPower.power_on()
		var errors: PackedStringArray = report.get("errors", PackedStringArray()) as PackedStringArray
		_output.text = "Компьютер включён." if errors.is_empty() else "Компьютер включён, но при загрузке ошибки."
	_refresh_actions()


func _refresh_clock() -> void:
	_clock.text = Clock.format_now()


func _on_menu() -> void:
	get_tree().change_scene_to_file(Screens.MAIN_MENU)


func _show(lines: PackedStringArray) -> void:
	_output.text = "\n".join(lines)
