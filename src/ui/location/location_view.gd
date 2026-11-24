extends Control
## Сцена локации (docs/gameplay/locations.md): фон и объекты под клик из `data/locations/`.
## Правил здесь нет — только показ и передача кликов: переходы в `Locations`, ПК в `Room` и
## `PcPower`, сон в `Rest`, предметы в `Inventory`.
##
## Что делает объект, решает его `kind`:
## - `monitor` — сразу за компьютер (если включён), без лишнего шага (плейтест M2);
## - `system_block` — панель (питание, железо, вставить / вынуть флешку) и инвентарь слева:
##   флешку можно перетащить из инвентаря прямо на системный блок (inventory.md);
## - `bed` — телефон с будильником: «спать» или «подождать» (docs/gameplay/time.md);
## - `container` — инвентарь и рядом содержимое контейнера (холодильник, шкаф);
## - `door` — сразу в другую локацию (или «заперто»); `turn` — то же, но это поворот к другому
##   кадру комнаты: рисуется стрелкой у края экрана; `back` — то же, полоса внизу экрана с подписью
##   («В коридор», «Отойти от ПК»);
## - `look` — текст в строке внизу; `dialogue` — диалог новеллы.
##
## Арта пока нет: фон — цвет из данных, объект — полупрозрачная плашка с подписью. Появится
## картинка по пути из данных — встанет сама, код менять не нужно.

const PANEL_KINDS: PackedStringArray = ["system_block"]

var _background: ColorRect
var _background_art: TextureRect
var _objects: Control
var _title: Label
var _clock: Label
var _menu: Button
var _output: Label
var _panel: PanelContainer
var _actions: VBoxContainer
var _pause: PauseMenu
## Объект, чья панель действий открыта ("" — никакой).
var _selected: String = ""
## Какие объекты сейчас нарисованы: перестраиваем, только если набор изменился.
var _shown_ids: PackedStringArray = []
## Какой фон показан: меняем, только когда сменилось время суток или локация.
var _shown_background: String = ""


func _ready() -> void:
	_build()
	_pause = PauseMenu.new()
	_pause.main_menu_requested.connect(_on_menu)
	add_child(_pause)
	_menu.pressed.connect(_pause.open)
	PhoneOverlay.attach(self)
	# Сон и ожидание идут из будильника в телефоне; итог — строкой внизу.
	EventBus.rested.connect(_on_rested)
	EventBus.location_entered.connect(func(_id: String) -> void: _show_location())
	# Условия объектов могли измениться (флаг, этап квеста, конец диалога) — перепроверить видимость.
	EventBus.flag_changed.connect(func(_flag: String, _value: bool) -> void: _refresh_objects())
	EventBus.quest_stage_changed.connect(func(_q: String, _s: String) -> void: _refresh_objects())
	EventBus.dialogue_ended.connect(func(_id: String) -> void: _refresh_objects())
	EventBus.time_advanced.connect(func(_minute_now: int, _passed: int) -> void:
		_refresh_clock()
		_refresh_background())
	EventBus.need_warned.connect(func(kind: String) -> void: _output.text = HeroThoughts.thought(kind))
	# Герой дома — курьера слышит в любой комнате квартиры, а не только за ПК.
	EventBus.order_delivered.connect(func(_id: String) -> void: _output.text = HeroThoughts.thought("delivered"))
	EventBus.hero_thought.connect(func(text: String) -> void: _output.text = text)
	EventBus.passed_out.connect(_on_passed_out)
	EventBus.inventory_changed.connect(func(_c: String) -> void: _refresh_panel())
	EventBus.system_restored.connect(func(_paths: PackedStringArray, _os: bool) -> void: _refresh_panel())
	EventBus.pc_power_changed.connect(func(_on: bool) -> void:
		_refresh_panel()
		_refresh_background())
	_show_location()
	_refresh_clock()
	_show_wake()


# --- Показ -------------------------------------------------------------------------------

func _show_location() -> void:
	var id: String = Locations.current()
	var def: Dictionary = Locations.def_of(id)
	_title.text = str(def.get("title", id))
	var background: Dictionary = def.get("background", {}) as Dictionary
	_background.color = Color(str(background.get("color", "#1f2433")))
	_shown_background = "-"
	_refresh_background()
	_shown_ids = []
	_close_panel()
	_refresh_objects()


## Фон по времени суток. Картинки нет — остаётся цвет из данных.
func _refresh_background() -> void:
	var image: String = Locations.background_image(Locations.current(), GameState.minute, PcPower.is_on())
	if image == _shown_background:
		return
	_shown_background = image
	var has_art: bool = not image.is_empty() and ResourceLoader.exists(image)
	_background_art.visible = has_art
	_background_art.texture = load(image) as Texture2D if has_art else null


func background_path() -> String:
	return _shown_background


## Перерисовать объекты, если изменился набор видимых.
func _refresh_objects() -> void:
	var visible_objects: Array = Locations.objects(Locations.current())
	var ids: PackedStringArray = []
	for object: Dictionary in visible_objects:
		ids.append(str(object.get("id", "")))
	if ids == _shown_ids:
		return
	_shown_ids = ids
	if not _selected.is_empty() and not ids.has(_selected):
		_close_panel()
	for child: Node in _objects.get_children():
		_objects.remove_child(child)
		child.queue_free()
	for object: Dictionary in visible_objects:
		_objects.add_child(_object_button(object))


func _object_button(object: Dictionary) -> Button:
	var id: String = str(object.get("id", ""))
	var rect: Array = object.get("rect", [0, 0, 0.1, 0.1]) as Array
	var mask: String = str(object.get("mask", ""))
	var masked: bool = not mask.is_empty() and ResourceLoader.exists(mask)
	var button: Button = MaskButton.new() if masked else Button.new()
	button.name = "Obj_" + id
	button.tooltip_text = str(object.get("title", id))
	var image: String = str(object.get("image", ""))
	if not masked:
		# Доли экрана → якоря: сцена тянется под любой размер окна.
		button.anchor_left = float(rect[0])
		button.anchor_top = float(rect[1])
		button.anchor_right = float(rect[0]) + float(rect[2])
		button.anchor_bottom = float(rect[1]) + float(rect[3])
	if masked:
		# Точная форма по маске из Blender: кнопка на весь экран, клик и подсветка — по силуэту,
		# подпись — всплывающей подсказкой у курсора.
		(button as MaskButton).setup(load(mask) as Texture2D, mask)
	elif not image.is_empty() and ResourceLoader.exists(image):
		button.flat = true
		var art := TextureRect.new()
		art.texture = load(image) as Texture2D
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(art)
	elif str(object.get("kind", "")) == "back":
		# «Назад» — полоса внизу экрана, подпись из данных.
		button.text = str(object.get("title", id))
		var bar := StyleBoxFlat.new()
		bar.bg_color = Color(0, 0, 0, 0.45)
		bar.border_color = Color(1, 1, 1, 0.18)
		bar.border_width_top = 1
		button.add_theme_stylebox_override("normal", bar)
		var bar_hover := bar.duplicate() as StyleBoxFlat
		bar_hover.bg_color = Color(0.12, 0.14, 0.2, 0.7)
		bar_hover.border_color = Color(1, 1, 1, 0.5)
		button.add_theme_stylebox_override("hover", bar_hover)
		button.add_theme_stylebox_override("pressed", bar_hover)
	elif str(object.get("kind", "")) == "turn":
		# Поворот к другому кадру — стрелка у края, подпись во всплывающей подсказке.
		button.flat = true
		button.text = "‹" if float(rect[0]) + float(rect[2]) / 2.0 < 0.5 else "›"
		button.add_theme_font_size_override("font_size", 48)
	else:
		# Заглушка без арта: полупрозрачная плашка с подписью.
		button.text = str(object.get("title", id))
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1, 1, 1, 0.06)
		style.border_color = Color(1, 1, 1, 0.25)
		style.set_border_width_all(1)
		button.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate() as StyleBoxFlat
		hover.bg_color = Color(1, 1, 1, 0.16)
		hover.border_color = Color(1, 1, 1, 0.6)
		button.add_theme_stylebox_override("hover", hover)
	if str(object.get("kind", "")) == "system_block":
		# Флешку из инвентаря можно бросить прямо на системный блок — она вставляется.
		button.set_drag_forwarding(Callable(), _can_drop_on_pc, _drop_on_pc)
	button.pressed.connect(click.bind(id))
	return button


func _can_drop_on_pc(_at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or not (data as Dictionary).has("inventory_uid"):
		return false
	var found: Dictionary = Inventory.find(str((data as Dictionary)["inventory_uid"]))
	return not found.is_empty() and Inventory.accepts(Inventory.PC, str((found["entry"] as Dictionary)["kind"]))


func _drop_on_pc(_at: Vector2, data: Variant) -> void:
	insert(str((data as Dictionary)["inventory_uid"]))


## Вставить носитель в системный блок (перетащил или «Вставить»).
func insert(uid: String) -> void:
	var report: Dictionary = Room.insert(uid, Filesystem.for_node(Network.HOME_ID))
	_show(report["lines"] as PackedStringArray)
	_refresh_panel()


# --- Клики -------------------------------------------------------------------------------

## Клик по объекту текущей локации.
func click(object_id: String) -> void:
	var object: Dictionary = Locations.object(object_id)
	if object.is_empty():
		return
	var kind: String = str(object.get("kind", ""))
	if PANEL_KINDS.has(kind):
		if _selected == object_id and _panel.visible:
			_close_panel()
			return
		_selected = object_id
		_refresh_panel()
		# У системного блока слева открывается инвентарь — флешку тащить оттуда.
		InventoryOverlay.open()
		return
	_close_panel()
	match kind:
		"monitor":
			if PcPower.is_on():
				_on_sit()
			else:
				_output.text = "Экран чёрный: компьютер выключен."
		"door", "turn", "back":
			var result: Dictionary = Locations.use_door(object_id)
			if not bool(result["ok"]):
				_output.text = str(result["text"])
		"look":
			_output.text = str(object.get("text", ""))
		"dialogue":
			DialogueManager.request(str(object.get("dialogue", "")))
		"bed":
			PhoneOverlay.open_alarm(PackedStringArray([Rest.MODE_SLEEP, Rest.MODE_WAIT]))
		"container":
			InventoryOverlay.open(str(object.get("container", "")))


## Наполнить панель действий выбранного объекта (или обновить уже открытую).
func _refresh_panel() -> void:
	if _selected.is_empty():
		return
	var object: Dictionary = Locations.object(_selected)
	if object.is_empty():
		_close_panel()
		return
	for child: Node in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	match str(object.get("kind", "")):
		"system_block":
			_action("Act_power", "Выключить компьютер" if PcPower.is_on() else "Включить компьютер", _on_power)
			_action("Act_hardware", "Осмотреть железо", func() -> void: _show(Room.hardware()))
			var plugged: Dictionary = Room.inserted()
			if not plugged.is_empty():
				_action("Act_eject", "Вынуть: " + Inventory.label_of(plugged), func() -> void: _show(PackedStringArray([Room.eject()])))
			for id: String in Inventory.items():
				if not Inventory.accepts(Inventory.PC, id):
					continue
				var button: Button = _action("Act_item_" + id, "Вставить: " + Inventory.name_of(id), func() -> void: insert(Inventory.first_uid(id)))
				button.tooltip_text = Inventory.about(id)
	_panel.visible = true
	_place_panel(object)


func _action(action_name: String, text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.name = action_name
	button.text = text
	button.pressed.connect(on_press)
	_actions.add_child(button)
	return button


## Панель — сбоку от объекта, внутри экрана.
func _place_panel(object: Dictionary) -> void:
	var rect: Array = object.get("rect", [0, 0, 0, 0]) as Array
	_panel.reset_size()
	var screen: Vector2 = size
	var right: float = (float(rect[0]) + float(rect[2])) * screen.x + 8.0
	var left: float = float(rect[0]) * screen.x - _panel.size.x - 8.0
	var x: float = right if right + _panel.size.x <= screen.x or left < 0.0 else left
	var y: float = clampf(float(rect[1]) * screen.y, 0.0, maxf(0.0, screen.y - _panel.size.y))
	_panel.position = Vector2(clampf(x, 0.0, maxf(0.0, screen.x - _panel.size.x)), y)


func _close_panel() -> void:
	_selected = ""
	_panel.visible = false


func _on_background_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		_close_panel()


# --- Действия ----------------------------------------------------------------------------

## Сесть за ПК: рабочий стол или аварийный экран, если система сломана.
func _on_sit() -> void:
	var report: Dictionary = Room.monitor(Filesystem.for_node(Network.HOME_ID))
	if bool(report["desktop"]):
		Desktop.enter_pc(get_tree())
		return
	_show(report["lines"] as PackedStringArray)


func _on_rested(_mode: String, _minutes: int, interrupted: String) -> void:
	_output.text = Clock.format_now() if interrupted.is_empty() else "%s — %s" % [Clock.format_now(), interrupted]


func _exit_tree() -> void:
	PhoneOverlay.detach(self)


## Питание ПК. Выключение закрывает и спрятанный стол — это уже не «отошёл», а выключил
## (docs/gameplay/hacking.md, «Питание ПК»).
func _on_power() -> void:
	if PcPower.is_on():
		PcPower.shut_down()
		Desktop.discard_kept()
		_output.text = "Компьютер выключен."
	else:
		var report: Dictionary = PcPower.power_on()
		var errors: PackedStringArray = report.get("errors", PackedStringArray()) as PackedStringArray
		_output.text = "Компьютер включён." if errors.is_empty() else "Компьютер включён, но при загрузке ошибки."
	_refresh_panel()


## Вырубился здесь: тот же занавес; просыпается герой у себя, на кровати — в какой бы комнате
## квартиры ни упал («еле добрался до кровати», docs/gameplay/needs.md).
func _on_passed_out() -> void:
	NeedsManager.claim_pass_out()
	_close_panel()
	var curtain := PassOutCurtain.new()
	add_child(curtain)
	curtain.finished.connect(func() -> void:
		NeedsManager.sleep_after_pass_out()
		_show_wake(curtain))
	curtain.play_falling_asleep()


## После вырубания картинка проявляется из черноты. Время пробуждения герой вслух не называет —
## его видно на часах.
func _show_wake(curtain: PassOutCurtain = null) -> void:
	if not bool(GameState.get_var_or(Needs.VAR_WOKE_AFTER_PASS_OUT, false)):
		return
	GameState.set_var(Needs.VAR_WOKE_AFTER_PASS_OUT, false)
	if Locations.current() != Locations.home():
		Locations.go_home()
	if curtain == null:
		curtain = PassOutCurtain.new()
		add_child(curtain)
	curtain.play_waking_up()


func _refresh_clock() -> void:
	_clock.text = Clock.format_now()


## Esc: сначала закрывает панель действий, потом — меню игры.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _panel.visible:
		_close_panel()
	else:
		_pause.toggle()


func pause_menu() -> PauseMenu:
	return _pause


func _on_menu() -> void:
	get_tree().change_scene_to_file(Screens.MAIN_MENU)


func _show(lines: PackedStringArray) -> void:
	_output.text = "\n".join(lines)


# --- Сборка ------------------------------------------------------------------------------

func _build() -> void:
	_background = ColorRect.new()
	_background.name = "Background"
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.gui_input.connect(_on_background_input)
	add_child(_background)
	_background_art = TextureRect.new()
	_background_art.name = "BackgroundArt"
	_background_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_background_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background_art)
	_objects = Control.new()
	_objects.name = "Objects"
	_objects.set_anchors_preset(Control.PRESET_FULL_RECT)
	_objects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_objects)

	var top := HBoxContainer.new()
	top.name = "Top"
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_title = Label.new()
	_title.name = "Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	_clock = Label.new()
	_clock.name = "Clock"
	top.add_child(_clock)
	_menu = Button.new()
	_menu.name = "Menu"
	_menu.text = "Меню (Esc)"
	top.add_child(_menu)

	_output = Label.new()
	_output.name = "Output"
	_output.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_output.offset_top = -96
	_output.offset_left = 16
	# Справа внизу лежит свёрнутый телефон — текст до него не доходит.
	_output.offset_right = -PhoneOverlay.WIDTH - 2 * PhoneOverlay.MARGIN
	_output.offset_bottom = -12
	_output.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_output.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_output.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_output)

	# Трекер задачи — в правом верхнем углу, под часами.
	var tracker := QuestTracker.new()
	tracker.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	tracker.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tracker.offset_top = 48
	add_child(tracker)

	_panel = PanelContainer.new()
	_panel.name = "ActionPanel"
	_panel.visible = false
	add_child(_panel)
	_actions = VBoxContainer.new()
	_actions.name = "Actions"
	_panel.add_child(_actions)


# --- Для тестов --------------------------------------------------------------------------

func object_button(object_id: String) -> Button:
	return _objects.get_node_or_null("Obj_" + object_id) as Button


func action(action_name: String) -> Node:
	return _actions.get_node_or_null(action_name)


func actions_shown() -> bool:
	return _panel.visible


func output_text() -> String:
	return _output.text


func clock_text() -> String:
	return _clock.text


func title_text() -> String:
	return _title.text
