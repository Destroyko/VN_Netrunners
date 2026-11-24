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
var _answer: Button
var _status: Label
var _uids: PackedStringArray = []
var _open_uid: String = ""
var _reader: VBoxContainer
## Пока письмо не открыто: подсказка по центру читалки вместо пустого места.
var _placeholder: Label
var _letter: Array[Control] = []
var _compose: MailCompose


func _init() -> void:
	name = "MailApp"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	var write := Button.new()
	write.name = "Write"
	write.text = "Написать"
	write.theme_type_variation = "AccentButton"
	write.pressed.connect(show_compose)
	left.add_child(write)
	_list = ItemList.new()
	_list.name = "Inbox"
	_list.custom_minimum_size = Vector2(220, 0)
	# Длинная тема — с многоточием; отправитель — в подсказке строки.
	_list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	_placeholder = Label.new()
	_placeholder.name = "Placeholder"
	_placeholder.theme_type_variation = "DimLabel"
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_placeholder)
	_subject = Label.new()
	_subject.theme_type_variation = "HeaderLabel"
	_subject.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_subject)
	_from = Label.new()
	_from.theme_type_variation = "DimLabel"
	right.add_child(_from)
	var rule := HSeparator.new()
	right.add_child(rule)
	_letter.append_array([_subject, _from, rule])
	_body = Label.new()
	_body.name = "Body"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_body)
	_letter.append(_body)
	_attachments = VBoxContainer.new()
	_attachments.name = "Attachments"
	right.add_child(_attachments)
	_replies = HBoxContainer.new()
	_replies.name = "Replies"
	right.add_child(_replies)
	# «Ответить» — своё письмо отправителю: тема уже стоит, можно приложить файлы.
	_answer = Button.new()
	_answer.name = "Answer"
	_answer.text = "Ответить"
	_answer.visible = false
	_answer.pressed.connect(func() -> void: answer(_open_uid))
	right.add_child(_answer)
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
		_list.set_item_tooltip(_list.item_count - 1, "%s\n%s" % [str(def.get("subject", "")), str(def.get("from", ""))])
		_uids.append(str(e["uid"]))
	_placeholder.text = "Писем нет" if _uids.is_empty() else "Выберите письмо слева"
	_show_letter(not _open_uid.is_empty())


## Читалка: письмо или подсказка по центру.
func _show_letter(shown: bool) -> void:
	_placeholder.visible = not shown
	for part: Control in _letter:
		part.visible = shown


## Ответить на письмо: форма с адресом отправителя и темой («Готово» или «Re: …»).
func answer(uid: String) -> MailCompose:
	var draft: Dictionary = Mailbox.reply_draft(uid)
	if draft.is_empty():
		return null
	var compose: MailCompose = show_compose()
	compose.prefill(str(draft["to"]), str(draft["subject"]))
	return compose


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
	_from.text = "%s  ·  %s" % [str(def.get("from", "")), Clock.format_date(int(e["day"]))]
	_subject.text = str(def.get("subject", ""))
	_body.text = str(def.get("body", ""))
	_answer.visible = not Mailbox.reply_draft(uid).is_empty()
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
