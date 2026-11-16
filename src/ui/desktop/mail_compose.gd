class_name MailCompose
extends VBoxContainer
## Новое письмо со своего ПК (docs/story/side-quests/first-job.md, заказ 4): кому — только из
## адресной книги (выпадающий список, чтобы не отправить не туда), тема, текст, вложения —
## файлы со своего ПК: кнопкой «Прикрепить файлы» (мини-проводник, можно несколько) или
## перетаскиванием в письмо. Правил здесь нет: «Отправить» — это `Mailbox.send`.

signal closed

var _to: OptionButton
var _subject: LineEdit
var _attached: ItemList
var _picker: HomeFilePicker
var _files: PackedStringArray = []
var _body: TextEdit
var _status: Label


func _init() -> void:
	name = "MailCompose"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_to = OptionButton.new()
	_to.name = "To"
	add_child(_row("Кому:", _to))
	_subject = LineEdit.new()
	_subject.name = "Subject"
	_subject.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_row("Тема:", _subject))
	var attach_row := HBoxContainer.new()
	add_child(attach_row)
	var attach := Button.new()
	attach.name = "Attach"
	attach.text = "Прикрепить файлы"
	attach.pressed.connect(func() -> void: _picker.visible = not _picker.visible)
	attach_row.add_child(attach)
	var remove := Button.new()
	remove.name = "Detach"
	remove.text = "Убрать"
	remove.pressed.connect(_detach_selected)
	attach_row.add_child(remove)
	_attached = ItemList.new()
	_attached.name = "Attached"
	_attached.custom_minimum_size = Vector2(0, 48)
	_attached.select_mode = ItemList.SELECT_MULTI
	_attached.tooltip_text = "Перетащите сюда файлы"
	# Список сам ловит мышь, поэтому брошенное на него передаём письму явно.
	_attached.set_drag_forwarding(Callable(), _can_drop_data, _drop_data)
	add_child(_attached)
	_picker = HomeFilePicker.new()
	_picker.visible = false
	_picker.files_chosen.connect(func(paths: PackedStringArray) -> void:
		for path: String in paths:
			attach_file(path)
		_picker.visible = false)
	add_child(_picker)
	_body = TextEdit.new()
	_body.name = "Body"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_body)
	var buttons := HBoxContainer.new()
	add_child(buttons)
	var send := Button.new()
	send.name = "Send"
	send.text = "Отправить"
	send.pressed.connect(_on_send)
	buttons.add_child(send)
	var cancel := Button.new()
	cancel.name = "Cancel"
	cancel.text = "Отмена"
	cancel.pressed.connect(func() -> void: closed.emit())
	buttons.add_child(cancel)
	_status = Label.new()
	_status.name = "Status"
	add_child(_status)


## Заполнить списки заново: адреса и файлы могли появиться с прошлого раза.
func reset() -> void:
	_to.clear()
	for address: String in Mailbox.contacts():
		_to.add_item(address)
	_files.clear()
	_attached.clear()
	_picker.visible = false
	_subject.text = ""
	_body.text = ""
	_status.text = "" if _to.item_count > 0 else "Адресов пока нет"


## Выбрать адресата по значению — для тестов и для «переслать» в будущем.
func pick(address: String) -> void:
	for i: int in _to.item_count:
		if _to.get_item_text(i) == address:
			_to.select(i)


## Прикрепить файл своего ПК (одинаковый дважды не прикрепляется).
func attach_file(path: String) -> void:
	if _files.has(path):
		return
	_files.append(path)
	_attached.add_item(FsPath.name_of(path))
	_attached.set_item_tooltip(_attached.item_count - 1, path)


func attached() -> PackedStringArray:
	return _files


func picker() -> HomeFilePicker:
	return _picker


func _detach_selected() -> void:
	var picked: PackedInt32Array = _attached.get_selected_items()
	for i: int in range(picked.size() - 1, -1, -1):
		_files.remove_at(picked[i])
		_attached.remove_item(picked[i])


## Бросили в письмо свои файлы (из мини-проводника, позже — из окна «Файлы»).
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has(HomeFilePicker.DRAG_KEY)


func _drop_data(_at: Vector2, data: Variant) -> void:
	for path: String in (data as Dictionary)[HomeFilePicker.DRAG_KEY] as PackedStringArray:
		attach_file(path)


func _on_send() -> void:
	if _to.selected < 0:
		_status.text = "Выберите адресата"
		return
	if Mailbox.send(_to.get_item_text(_to.selected), _subject.text, _body.text, _files):
		_status.text = "Отправлено"
		closed.emit()
	else:
		_status.text = "Не отправлено"


func _row(caption: String, field: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(80, 0)
	row.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return row
