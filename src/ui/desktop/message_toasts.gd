class_name MessageToasts
extends VBoxContainer
## Всплывающие уведомления о сообщениях на рабочем столе, как в Windows: справа внизу над часами
## (docs/gameplay/devices.md, «Мессенджер на ПК»). Показываются, когда окно «Сообщения» закрыто,
## свёрнуто или не в фокусе; держатся несколько секунд; клик открывает чат.
##
## Правил здесь нет: что пришло — `Messenger`, открыто ли окно — спрашивает стол (`is_reading`).

## Клик по уведомлению: открыть мессенджер на этом чате.
signal chat_requested(contact: String)

## Сколько секунд держится уведомление (разработчик: 5–10).
const SECONDS: float = 7.0
const WIDTH: float = 300.0
## Больше — старые уходят: стопка не закрывает стол.
const MAX_SHOWN: int = 3

## Читает ли игрок сейчас сообщения (окно открыто и в фокусе) — тогда уведомлять не нужно.
var is_reading: Callable
var theme_id: String = ""


func _init() -> void:
	name = "MessageToasts"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(WIDTH, 0)


func _ready() -> void:
	EventBus.message_received.connect(func(uid: String, _id: String) -> void: on_message(uid))


func on_message(uid: String) -> void:
	if is_reading.is_valid() and bool(is_reading.call()):
		return
	var entry: Dictionary = Messenger.entry(uid)
	if entry.is_empty():
		return
	var contact: String = Messenger.contact_of(entry)
	add_child(_toast(contact, MessagesApp.name_of(contact), Messenger.text_of(entry)))
	while get_child_count() > MAX_SHOWN:
		var oldest: Node = get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	# Звук уведомления — шаг 17 M3 (звука в игре пока нет): событие для будущего плеера.
	EventBus.notification_shown.emit("message")


## Убрать все уведомления (игрок открыл мессенджер).
func clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()


func count() -> int:
	return get_child_count()


func _toast(contact: String, title: String, text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Toast_" + contact
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.tooltip_text = "Открыть чат"
	var style := StyleBoxFlat.new()
	style.bg_color = GameTheme.color("panel", theme_id)
	style.border_color = GameTheme.color("accent", theme_id)
	style.border_width_left = 3
	style.set_corner_radius_all(int((GameTheme.load_theme(theme_id).get("shape", {}) as Dictionary).get("radius", 4)))
	style.set_content_margin_all(10)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 6
	panel.add_theme_stylebox_override("panel", style)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rows)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(head)
	var icon := TextureRect.new()
	icon.texture = GameTheme.icon("messenger", theme_id)
	icon.custom_minimum_size = Vector2(18, 18)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(icon)
	var name_label := Label.new()
	name_label.name = "From"
	name_label.text = title
	name_label.add_theme_font_override("font", GameTheme.font("heading"))
	name_label.add_theme_color_override("font_color", GameTheme.color("text", theme_id))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(name_label)
	var body := Label.new()
	body.name = "Text"
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.max_lines_visible = 3
	body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_theme_color_override("font_color", GameTheme.color("text_dim", theme_id))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(body)
	panel.gui_input.connect(func(event: InputEvent) -> void:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			chat_requested.emit(contact))
	# Уходит сам через несколько секунд. Таймер — ребёнок панели: исчезает вместе с ней и не
	# срабатывает на уже убранной.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = SECONDS
	timer.autostart = true
	timer.timeout.connect(panel.queue_free)
	panel.add_child(timer)
	return panel


## Для тестов: нажать на уведомление.
func click(index: int) -> void:
	var panel: Control = get_child(index) as Control
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	panel.gui_input.emit(event)
