class_name MailApp
extends HBoxContainer
## Приложение «Почта» (docs/gameplay/mail.md): слева «Написать», папки «Входящие» и «Отправленные» и
## список писем (значок, отправитель, время, тема), справа письмо с прокруткой, вложения
## «Сохранить к себе», кнопки ответа и «Удалить». На узком экране (телефон) — то список, то письмо
## с кнопкой «Назад». Правил здесь нет: всё делает `Mailbox`, в том числе можно ли удалить письмо.

const FOLDER_INBOX: String = "inbox"
const FOLDER_SENT: String = "sent"
## Уже этой ширины — одна колонка: список или письмо (телефон).
const NARROW_WIDTH: float = 560.0
const LIST_WIDTH: float = 250.0
const ROW_HEIGHT: float = 52.0

var _folder: String = FOLDER_INBOX
var _theme_id: String = ""
var _narrow: bool = false

var _side: VBoxContainer
var _rows: VBoxContainer
var _empty: Label
var _folder_buttons: Dictionary = {}
var _row_group := ButtonGroup.new()

var _reader: VBoxContainer
var _letter: VBoxContainer
var _placeholder: Label
var _back: Button
var _from: Label
var _subject: Label
var _body: Label
var _attachments: VBoxContainer
var _replies: HFlowContainer
var _answer: Button
var _delete: Button
var _status: Label
var _compose: MailCompose

## Открытое письмо: uid входящего или номер отправленного ("sent:<n>"); "" — ничего не открыто.
var _open_uid: String = ""


func _init() -> void:
	name = "MailApp"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	_build_side()
	_build_reader()
	_compose = MailCompose.new()
	_compose.visible = false
	_compose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_compose.closed.connect(func() -> void:
		_compose.visible = false
		_layout())
	add_child(_compose)
	resized.connect(_layout)


func _build_side() -> void:
	_side = VBoxContainer.new()
	_side.name = "Side"
	_side.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	_side.add_theme_constant_override("separation", 8)
	add_child(_side)
	var write := Button.new()
	write.name = "Write"
	write.text = "Написать"
	write.theme_type_variation = "AccentButton"
	# Компактная кнопка в углу панели, а не полоса во всю колонку.
	write.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	write.pressed.connect(show_compose)
	_side.add_child(write)

	# Папки — две кнопки-вкладки, выбранная подсвечена.
	var folders := HBoxContainer.new()
	folders.add_theme_constant_override("separation", 4)
	_side.add_child(folders)
	var group := ButtonGroup.new()
	for folder: String in [FOLDER_INBOX, FOLDER_SENT]:
		var tab := Button.new()
		tab.name = "Folder_" + folder
		tab.toggle_mode = true
		tab.button_group = group
		tab.theme_type_variation = "FlatButton"
		tab.focus_mode = Control.FOCUS_NONE
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.add_theme_constant_override("icon_max_width", 16)
		tab.button_pressed = folder == _folder
		tab.pressed.connect(show_folder.bind(folder))
		folders.add_child(tab)
		_folder_buttons[folder] = tab

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side.add_child(scroll)
	var list_box := VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)
	_rows = VBoxContainer.new()
	_rows.name = "Letters"
	_rows.add_theme_constant_override("separation", 2)
	list_box.add_child(_rows)
	_empty = Label.new()
	_empty.name = "Empty"
	_empty.theme_type_variation = "DimLabel"
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Пусто — одна надпись по центру области списка (читалка справа при этом молчит).
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_box.add_child(_empty)


func _build_reader() -> void:
	_reader = VBoxContainer.new()
	_reader.name = "Reader"
	_reader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reader.add_theme_constant_override("separation", 8)
	add_child(_reader)
	_placeholder = Label.new()
	_placeholder.name = "Placeholder"
	_placeholder.theme_type_variation = "DimLabel"
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_reader.add_child(_placeholder)

	_letter = VBoxContainer.new()
	_letter.name = "Letter"
	_letter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_letter.add_theme_constant_override("separation", 6)
	_reader.add_child(_letter)

	# Панель действий над письмом: «Назад» (узкий экран), «Ответить», «Удалить».
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	_letter.add_child(actions)
	_back = Button.new()
	_back.name = "Back"
	_back.text = "← Назад"
	_back.theme_type_variation = "FlatButton"
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(close_letter)
	actions.add_child(_back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	# «Ответить» — своё письмо отправителю: тема уже стоит, можно приложить файлы.
	_answer = Button.new()
	_answer.name = "Answer"
	_answer.text = "Ответить"
	_answer.visible = false
	_answer.focus_mode = Control.FOCUS_NONE
	_answer.pressed.connect(func() -> void: answer(_open_uid))
	actions.add_child(_answer)
	_delete = Button.new()
	_delete.name = "Delete"
	_delete.text = "Удалить"
	_delete.focus_mode = Control.FOCUS_NONE
	_delete.pressed.connect(func() -> void: delete_open())
	actions.add_child(_delete)

	_subject = Label.new()
	_subject.name = "Subject"
	_subject.theme_type_variation = "HeaderLabel"
	_subject.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_letter.add_child(_subject)
	_from = Label.new()
	_from.name = "From"
	_from.theme_type_variation = "DimLabel"
	_from.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_from.clip_text = true
	_letter.add_child(_from)
	_letter.add_child(HSeparator.new())

	# Тело письма прокручивается: длинное письмо не раздувает окно, слова переносятся.
	var scroll := ScrollContainer.new()
	scroll.name = "BodyScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_letter.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	_body = Label.new()
	_body.name = "Body"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(1, 0)
	column.add_child(_body)
	_attachments = VBoxContainer.new()
	_attachments.name = "Attachments"
	column.add_child(_attachments)
	_replies = HFlowContainer.new()
	_replies.name = "Replies"
	_replies.add_theme_constant_override("h_separation", 6)
	_replies.add_theme_constant_override("v_separation", 6)
	column.add_child(_replies)
	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = "DimLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)


func _ready() -> void:
	_theme_id = _host_theme()
	for folder: String in _folder_buttons.keys():
		(_folder_buttons[folder] as Button).icon = GameTheme.glyph("inbox" if folder == FOLDER_INBOX else "mail_sent", _theme_id)
	_delete.icon = GameTheme.glyph("trash", _theme_id)
	_delete.add_theme_constant_override("icon_max_width", 16)
	EventBus.mail_received.connect(func(_uid: String, _id: String) -> void: refresh())
	EventBus.mail_sent.connect(func(_to: String, _files: PackedStringArray) -> void: refresh())
	# Задача закончилась — письмо её задания можно удалить: кнопка оживает.
	EventBus.quest_completed.connect(func(_id: String, _outcome: String) -> void: _refresh_actions())
	refresh()
	_layout()


## Тема того, кто показывает почту: окно стола (своё или чужого узла) или общая (телефон).
func _host_theme() -> String:
	var node: Node = get_parent()
	while node != null:
		if node is DesktopWindow:
			return (node as DesktopWindow).theme_id
		node = node.get_parent()
	return GameTheme.current_id


# --- Список ---------------------------------------------------------------------------

func show_folder(folder: String) -> void:
	_folder = folder
	_mark_folder()
	_open_uid = ""
	refresh()


## Подсветить вкладку текущей папки (без сигнала группа кнопок другую сама не отжимает).
func _mark_folder() -> void:
	for folder: String in _folder_buttons.keys():
		(_folder_buttons[folder] as Button).set_pressed_no_signal(folder == _folder)


func refresh() -> void:
	var unread: int = Mailbox.unread_count()
	(_folder_buttons[FOLDER_INBOX] as Button).text = "Входящие" + (" (%d)" % unread if unread > 0 else "")
	(_folder_buttons[FOLDER_SENT] as Button).text = "Отправленные"
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if _folder == FOLDER_INBOX:
		for e: Dictionary in Mailbox.inbox():
			var def: Dictionary = Mailbox.definition(str(e["id"]))
			var icon: String = "mail_read" if bool(e["read"]) else "mail_unread"
			_rows.add_child(_letter_row(str(e["uid"]), icon, str(def.get("from", "")), str(def.get("subject", "")),
				int(e["day"]), int(e["minute"]), not bool(e["read"])))
	else:
		var sent: Array = Mailbox.sent()
		for i: int in range(sent.size() - 1, -1, -1):
			var s: Dictionary = sent[i]
			_rows.add_child(_letter_row("sent:%d" % i, "mail_sent", "Кому: " + str(s["to"]), str(s["subject"]),
				int(s["day"]), int(s["minute"]), false))
	_empty.visible = _rows.get_child_count() == 0
	_empty.text = "Писем нет
Новые письма появятся здесь" if _folder == FOLDER_INBOX 		else "Отправленных нет
Письма, которые вы отправите, появятся здесь"
	_placeholder.text = "Выберите письмо слева" if _rows.get_child_count() > 0 else ""
	if _open_uid.is_empty() or (_folder == FOLDER_INBOX and Mailbox.entry(_open_uid).is_empty()):
		_open_uid = ""
	_layout()


## Строка письма: значок состояния, отправитель и время, ниже тема. Непрочитанное — ярче.
func _letter_row(uid: String, icon_id: String, who: String, subject: String, day: int, minute: int, fresh: bool) -> Button:
	var row := Button.new()
	row.name = "Letter_" + uid.replace(":", "_").replace("#", "_").replace("@", "_")
	row.toggle_mode = true
	row.button_group = _row_group
	row.theme_type_variation = "FlatButton"
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.tooltip_text = "%s\n%s" % [subject, who]
	row.set_pressed_no_signal(uid == _open_uid)
	row.pressed.connect(func() -> void:
		if uid.begins_with("sent:"):
			open_sent(int(uid.get_slice(":", 1)))
		else:
			open(uid))
	var line := HBoxContainer.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 8
	line.offset_right = -8
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var mark := TextureRect.new()
	mark.texture = GameTheme.glyph(icon_id, _theme_id)
	mark.custom_minimum_size = Vector2(20, 20)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(mark)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(text)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(top)
	var sender := _row_label(who, "" if fresh else "DimLabel")
	sender.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sender)
	var time: Label = _row_label(_when(day, minute), "SmallLabel")
	# Время не обрезается: обрезается отправитель слева от него.
	time.clip_text = false
	time.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	top.add_child(time)
	text.add_child(_row_label(subject, "" if fresh else "DimLabel"))
	return row


func _row_label(text: String, variation: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Когда пришло: сегодня — время, раньше — дата.
static func _when(day: int, minute: int) -> String:
	if day == GameState.day:
		return "%02d:%02d" % [minute / 60, minute % 60]
	return Clock.format_date(day).get_slice(", ", 1)


# --- Письмо ---------------------------------------------------------------------------

## Открыть входящее письмо: прочитано, видны вложения, ответы и «Удалить».
func open(uid: String) -> void:
	_compose.visible = false
	if _folder != FOLDER_INBOX:
		_folder = FOLDER_INBOX
		_mark_folder()
	_open_uid = uid
	Mailbox.mark_read(uid)
	var e: Dictionary = Mailbox.entry(uid)
	var def: Dictionary = Mailbox.definition(str(e["id"]))
	_from.text = "%s  ·  %s" % [str(def.get("from", "")), Clock.format_date(int(e["day"]))]
	_subject.text = str(def.get("subject", ""))
	_body.text = str(def.get("body", ""))
	_status.text = ""
	_clear(_attachments)
	var files: Array = def.get("attachments", []) as Array
	for i: int in files.size():
		var button := Button.new()
		button.name = "Save_%d" % i
		button.text = "Сохранить к себе: %s" % str((files[i] as Dictionary).get("name", ""))
		button.icon = GameTheme.glyph("attach", _theme_id)
		button.add_theme_constant_override("icon_max_width", 16)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(func() -> void:
			var path: String = Mailbox.save_attachment(uid, i)
			_status.text = "сохранено: " + path if not path.is_empty() else "")
		_attachments.add_child(button)
	_clear(_replies)
	if not str(e["reply"]).is_empty():
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
	_refresh_actions()


## Открыть отправленное письмо по номеру в `Mailbox.sent()`.
func open_sent(index: int) -> void:
	_compose.visible = false
	var s: Dictionary = Mailbox.sent()[index]
	_open_uid = "sent:%d" % index
	_from.text = "Кому: %s  ·  %s" % [str(s["to"]), Clock.format_date(int(s["day"]))]
	_subject.text = str(s["subject"])
	_body.text = str(s["body"])
	_status.text = ""
	_clear(_attachments)
	for file: Variant in s.get("files", []) as Array:
		var label := Label.new()
		label.text = "Вложение: " + str(file).get_file()
		label.theme_type_variation = "DimLabel"
		_attachments.add_child(label)
	_clear(_replies)
	refresh()
	_refresh_actions()


## «Ответить» и «Удалить» по открытому письму; нельзя удалить — кнопка неактивна, причина в подсказке.
func _refresh_actions() -> void:
	if _open_uid.is_empty():
		return
	var sent: bool = _open_uid.begins_with("sent:")
	_answer.visible = not sent and not Mailbox.reply_draft(_open_uid).is_empty()
	var block: String = "" if sent else Mailbox.delete_block(_open_uid)
	_delete.disabled = not block.is_empty()
	_delete.tooltip_text = "Удалить письмо" if block.is_empty() else "Нельзя удалить: " + block


## Удалить открытое письмо (правило — в `Mailbox`). Удалилось — читалка пустеет.
func delete_open() -> bool:
	var done: bool = false
	if _open_uid.begins_with("sent:"):
		done = Mailbox.delete_sent(int(_open_uid.get_slice(":", 1)))
	else:
		done = Mailbox.delete(_open_uid)
	if done:
		_open_uid = ""
		refresh()
	return done


func close_letter() -> void:
	_open_uid = ""
	refresh()


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
	_compose.visible = true
	_layout()
	return _compose


## Что видно: на широком окне — список и письмо (или форма); на узком — что-то одно.
func _layout() -> void:
	_narrow = size.x > 0.0 and size.x < NARROW_WIDTH
	var reading: bool = not _open_uid.is_empty()
	var composing: bool = _compose.visible
	_side.visible = not _narrow or (not reading and not composing)
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _narrow else Control.SIZE_FILL
	_reader.visible = not composing and (not _narrow or reading)
	_placeholder.visible = not reading
	_letter.visible = reading
	_back.visible = _narrow


func _clear(box: Container) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
