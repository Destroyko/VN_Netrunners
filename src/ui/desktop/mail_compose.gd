class_name MailCompose
extends VBoxContainer
## Новое письмо со своего ПК (docs/story/side-quests/first-job.md, заказ 4): кому — только из
## адресной книги (выпадающий список, чтобы не отправить не туда), тема, текст, вложение — файл
## со своего ПК. Правил здесь нет: «Отправить» — это `Mailbox.send`.

signal closed

var _to: OptionButton
var _subject: LineEdit
var _file: OptionButton
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
	_file = OptionButton.new()
	_file.name = "File"
	add_child(_row("Вложение:", _file))
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
	_file.clear()
	_file.add_item("(без вложения)")
	_file.set_item_metadata(0, "")
	for path: String in Filesystem.for_node(Network.HOME_ID).paths():
		if path.begins_with("/home/"):
			_file.add_item(path)
			_file.set_item_metadata(_file.item_count - 1, path)
	_subject.text = ""
	_body.text = ""
	_status.text = "" if _to.item_count > 0 else "Адресов пока нет"


## Выбрать адрес и вложение по значению — для тестов и для «переслать» в будущем.
func pick(address: String, path: String) -> void:
	for i: int in _to.item_count:
		if _to.get_item_text(i) == address:
			_to.select(i)
	for i: int in _file.item_count:
		if str(_file.get_item_metadata(i)) == path:
			_file.select(i)


func _on_send() -> void:
	if _to.selected < 0:
		_status.text = "Выберите адресата"
		return
	var file: String = str(_file.get_item_metadata(_file.selected)) if _file.selected >= 0 else ""
	if Mailbox.send(_to.get_item_text(_to.selected), _subject.text, _body.text, file):
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
