class_name MessagesApp
extends VBoxContainer
## Приложение «Сообщения» (docs/gameplay/messages.md) — в телефоне и на ПК, данные одни.
## Список чатов (непрочитанные — с числом) → переписка и кнопки ответа. Правил здесь нет:
## всё делает `Messenger`.

var _chats: VBoxContainer
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
	_chats = VBoxContainer.new()
	_chats.name = "Chats"
	add_child(_chats)
	_thread_view = VBoxContainer.new()
	_thread_view.name = "Thread"
	_thread_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_thread_view)
	var head := HBoxContainer.new()
	_thread_view.add_child(head)
	var back := Button.new()
	back.name = "Back"
	back.text = "‹ Чаты"
	back.flat = true
	back.pressed.connect(show_chats)
	head.add_child(back)
	_thread_title = Label.new()
	_thread_title.name = "Title"
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


## Список чатов: имя собеседника и число непрочитанных.
func show_chats() -> void:
	_contact = ""
	_refresh()


func open_chat(contact: String) -> void:
	_contact = contact
	Messenger.mark_read(contact)
	_refresh()


func _refresh() -> void:
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
			line.add_theme_color_override("font_color", Color("#9fd4ff"))
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
