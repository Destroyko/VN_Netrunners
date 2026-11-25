class_name MessagesApp
extends VBoxContainer
## Приложение «Сообщения» (docs/gameplay/messages.md) — в телефоне и на ПК, данные одни.
## Список чатов (непрочитанные — с числом) → переписка и кнопки ответа. Правил здесь нет:
## всё делает `Messenger`.
##
## В телефоне — одна колонка: список чатов или переписка. На ПК (`set_wide`) — как WhatsApp или
## Telegram на компьютере: слева чаты с последним сообщением, справа открытый чат.

const CHATS_WIDTH: float = 200.0
const PREVIEW_CHARS: int = 28

var _chats: VBoxContainer
var _body: HBoxContainer
var _back: Button
var _placeholder: Label
## Два столбца (ПК) или одна колонка (телефон).
var _wide: bool = false
var _thread_view: VBoxContainer
var _thread_title: Label
var _thread_lines: VBoxContainer
var _thread_scroll: ScrollContainer
var _replies: VBoxContainer
## Открытый чат ("" — список чатов).
var _contact: String = ""


func _init() -> void:
	name = "MessagesApp"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body = HBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	add_child(_body)
	_chats = VBoxContainer.new()
	_chats.name = "Chats"
	_chats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_chats)
	_thread_view = VBoxContainer.new()
	_thread_view.name = "Thread"
	_thread_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_thread_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_thread_view)
	_placeholder = Label.new()
	_placeholder.name = "Placeholder"
	_placeholder.text = "Выберите чат"
	_placeholder.theme_type_variation = "DimLabel"
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_placeholder.visible = false
	_body.add_child(_placeholder)
	var head := HBoxContainer.new()
	_thread_view.add_child(head)
	_back = Button.new()
	_back.name = "Back"
	_back.text = "‹ Чаты"
	_back.flat = true
	_back.pressed.connect(show_chats)
	head.add_child(_back)
	_thread_title = Label.new()
	_thread_title.name = "Title"
	_thread_title.add_theme_font_override("font", GameTheme.font("heading"))
	head.add_child(_thread_title)
	_thread_scroll = ScrollContainer.new()
	_thread_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_thread_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_thread_view.add_child(_thread_scroll)
	_thread_lines = VBoxContainer.new()
	_thread_lines.name = "Lines"
	_thread_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_thread_lines.add_theme_constant_override("separation", 6)
	_thread_scroll.add_child(_thread_lines)
	_replies = VBoxContainer.new()
	_replies.name = "Replies"
	_thread_view.add_child(_replies)


func _ready() -> void:
	EventBus.message_received.connect(func(_uid: String, _id: String) -> void: _refresh())
	_refresh()


## Вид для ПК: два столбца, чаты всегда видны слева.
func set_wide(on: bool) -> void:
	_wide = on
	_chats.size_flags_horizontal = Control.SIZE_FILL if on else Control.SIZE_EXPAND_FILL
	_chats.custom_minimum_size = Vector2(CHATS_WIDTH if on else 0.0, 0)
	_back.visible = not on
	if is_inside_tree():
		_refresh()


func is_wide() -> bool:
	return _wide


func current_chat() -> String:
	return _contact


## Список чатов: имя собеседника и число непрочитанных.
func show_chats() -> void:
	_contact = ""
	_refresh()


func open_chat(contact: String) -> void:
	_contact = contact
	Messenger.mark_read(contact)
	_refresh()


func _refresh() -> void:
	if _wide:
		# Два столбца: чаты всегда, справа — открытый чат или подсказка.
		_chats.visible = true
		_thread_view.visible = not _contact.is_empty()
		_placeholder.visible = _contact.is_empty()
		if not _contact.is_empty():
			Messenger.mark_read(_contact)
			_fill_thread()
		_fill_chats()
		return
	_placeholder.visible = false
	_chats.visible = _contact.is_empty()
	_thread_view.visible = not _contact.is_empty()
	if _contact.is_empty():
		_fill_chats()
	else:
		Messenger.mark_read(_contact)
		_fill_thread()


func _fill_chats() -> void:
	_clear(_chats)
	var contacts: PackedStringArray = Messenger.chats()
	if contacts.is_empty():
		var empty := Label.new()
		empty.name = "Empty"
		empty.text = "Сообщений нет."
		_chats.add_child(empty)
		return
	for contact: String in contacts:
		var button := Button.new()
		button.name = "Chat_" + contact
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var unread: int = Messenger.unread_count(contact)
		button.text = name_of(contact) + ("  (%d)" % unread if unread > 0 else "")
		if _wide:
			# На ПК под именем — начало последнего сообщения, как в мессенджерах; открытый чат выделен.
			button.text += "\n" + last_preview(contact)
			button.toggle_mode = true
			button.button_pressed = contact == _contact
			button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(open_chat.bind(contact))
		_chats.add_child(button)


func _fill_thread() -> void:
	_thread_title.text = name_of(_contact)
	_clear(_thread_lines)
	for entry: Dictionary in Messenger.thread(_contact):
		var mine: bool = str(entry.get("kind", "")) == Messenger.OUT
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mine else HORIZONTAL_ALIGNMENT_LEFT
		line.text = "%s\n%02d:%02d" % [Messenger.text_of(entry), int(entry.get("minute", 0)) / 60, int(entry.get("minute", 0)) % 60]
		if mine:
			line.theme_type_variation = "MineLabel"
		_thread_lines.add_child(line)
	_clear(_replies)
	var uid: String = Messenger.awaiting_reply(_contact)
	if not uid.is_empty():
		var replies: Array = Messenger.available_replies(uid)
		for i: int in replies.size():
			var reply: Dictionary = replies[i] as Dictionary
			var button := Button.new()
			button.name = "Reply_%d" % i
			button.text = DialogueText.with_names(str(reply.get("text", "")))
			button.pressed.connect(func() -> void:
				Messenger.reply(uid, str(reply.get("id", "")))
				_refresh())
			_replies.add_child(button)
	# Новые сообщения — внизу: прокрутить к концу, когда список пересоберётся.
	_scroll_to_end.call_deferred()


func _scroll_to_end() -> void:
	if is_inside_tree():
		_thread_scroll.scroll_vertical = int(_thread_scroll.get_v_scroll_bar().max_value)


## Начало последнего сообщения в чате — для списка чатов и уведомлений.
static func last_preview(contact: String) -> String:
	var items: Array = Messenger.thread(contact)
	if items.is_empty():
		return ""
	var entry: Dictionary = items[items.size() - 1] as Dictionary
	var text: String = Messenger.text_of(entry)
	if str(entry.get("kind", "")) == Messenger.OUT:
		text = "Вы: " + text
	return text if text.length() <= PREVIEW_CHARS else text.left(PREVIEW_CHARS - 1) + "…"


static func name_of(contact: String) -> String:
	var character: Dictionary = DataLoader.characters().get(contact, {}) as Dictionary
	return DialogueText.with_names(str(character.get("name", contact)))


func _clear(box: Node) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()


# --- Для тестов --------------------------------------------------------------------------

func thread_text() -> String:
	var lines: PackedStringArray = []
	for child: Node in _thread_lines.get_children():
		lines.append((child as Label).text)
	return "\n".join(lines)


func reply_button(index: int) -> Button:
	return _replies.get_node_or_null("Reply_%d" % index) as Button


func chat_button(contact: String) -> Button:
	return _chats.get_node_or_null("Chat_" + contact) as Button
