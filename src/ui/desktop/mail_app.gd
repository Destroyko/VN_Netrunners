class_name MailApp
extends HBoxContainer
## Приложение «Почта»: слева входящие (непрочитанные — с точкой), справа письмо, вложения с
## «Сохранить к себе» и кнопки ответа; «Написать» — новое письмо со своего ПК (`MailCompose`).
## Правил здесь нет: всё делает `Mailbox`.

var _list: ItemList
var _from: Label
var _subject: Label
var _body: Label
var _attachments: VBoxContainer
var _replies: HBoxContainer
var _status: Label
var _uids: PackedStringArray = []
var _open_uid: String = ""
var _reader: VBoxContainer
var _compose: MailCompose


func _init() -> void:
	name = "MailApp"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := VBoxContainer.new()
	add_child(left)
	var write := Button.new()
	write.name = "Write"
	write.text = "Написать"
	write.pressed.connect(show_compose)
	left.add_child(write)
	_list = ItemList.new()
	_list.name = "Inbox"
	_list.custom_minimum_size = Vector2(180, 0)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(index: int) -> void: open(_uids[index]))
	left.add_child(_list)
	var right := VBoxContainer.new()
	_reader = right
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	_compose = MailCompose.new()
	_compose.visible = false
	_compose.closed.connect(func() -> void:
		_compose.visible = false
		_reader.visible = true)
	add_child(_compose)
	_from = Label.new()
	right.add_child(_from)
	_subject = Label.new()
	_subject.add_theme_color_override("font_color", Color(0.9, 0.92, 0.6))
	right.add_child(_subject)
	_body = Label.new()
	_body.name = "Body"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_body)
	_attachments = VBoxContainer.new()
	_attachments.name = "Attachments"
	right.add_child(_attachments)
	_replies = HBoxContainer.new()
	_replies.name = "Replies"
	right.add_child(_replies)
	_status = Label.new()
	_status.name = "Status"
	right.add_child(_status)


func _ready() -> void:
	EventBus.mail_received.connect(func(_uid: String, _id: String) -> void: refresh())
	refresh()


func refresh() -> void:
	_list.clear()
	_uids.clear()
	for e: Dictionary in Mailbox.inbox():
		var def: Dictionary = Mailbox.definition(str(e["id"]))
		var mark: String = "" if bool(e["read"]) else "● "
		_list.add_item("%s%s" % [mark, str(def.get("subject", ""))])
		_uids.append(str(e["uid"]))
	if _open_uid.is_empty() and _uids.is_empty():
		_body.text = "Писем нет"


## Новое письмо вместо читалки.
func show_compose() -> MailCompose:
	_compose.reset()
	_reader.visible = false
	_compose.visible = true
	return _compose


## Открыть письмо: прочитано, видны вложения и ответы.
func open(uid: String) -> void:
	_compose.visible = false
	_reader.visible = true
	_open_uid = uid
	Mailbox.mark_read(uid)
	var e: Dictionary = Mailbox.entry(uid)
	var def: Dictionary = Mailbox.definition(str(e["id"]))
	_from.text = "От: %s   %s" % [str(def.get("from", "")), Clock.format_date(int(e["day"]))]
	_subject.text = str(def.get("subject", ""))
	_body.text = str(def.get("body", ""))
	_status.text = ""
	_clear(_attachments)
	var files: Array = def.get("attachments", []) as Array
	for i: int in files.size():
		var button := Button.new()
		button.name = "Save_%d" % i
		button.text = "Сохранить к себе: %s" % str((files[i] as Dictionary).get("name", ""))
		button.pressed.connect(func() -> void:
			var path: String = Mailbox.save_attachment(uid, i)
			_status.text = "сохранено: " + path if not path.is_empty() else "")
		_attachments.add_child(button)
	_clear(_replies)
	var replied: String = str(e["reply"])
	if not replied.is_empty():
		_status.text = "Отвечено"
	for r: Dictionary in Mailbox.available_replies(uid):
		var reply := Button.new()
		reply.name = "Reply_" + str(r["id"])
		reply.text = str(r["text"])
		reply.pressed.connect(func() -> void:
			Mailbox.reply(uid, str(r["id"]))
			open(uid))
		_replies.add_child(reply)
	refresh()


func _clear(box: Container) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
