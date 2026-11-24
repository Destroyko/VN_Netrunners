class_name LoginForm
extends VBoxContainer
## Форма входа по паролю (docs/gameplay/hacking.md, «Пароль после перехвата»): адрес узла,
## поле пароля, «Войти». Правил нет: введённое отдаётся в `submit`, тот отвечает пустой строкой
## (вошли) или текстом ошибки. Позже станет экраном входа проводника.

var _field: LineEdit
var _note: Label
var _submit: Callable


## `submit(text) -> String`: пусто — вход удался, иначе — что показать под полем.
static func create(address: String, submit: Callable) -> LoginForm:
	var form := LoginForm.new()
	form._submit = submit
	form._build(address)
	return form


func _build(address: String) -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var host := Label.new()
	host.text = address
	host.add_theme_font_override("font", PasswordPanel._mono())
	add_child(host)
	var label := Label.new()
	label.text = "Пароль"
	add_child(label)
	_field = LineEdit.new()
	_field.secret = true
	_field.context_menu_enabled = false
	_field.text_submitted.connect(func(_text: String) -> void: try_login())
	add_child(_field)
	_note = Label.new()
	_note.theme_type_variation = "DangerLabel"
	add_child(_note)
	var button := Button.new()
	button.name = "Enter"
	button.text = "Войти"
	button.pressed.connect(try_login)
	add_child(button)
	_field.ready.connect(_field.grab_focus)


func try_login() -> void:
	var text: String = _field.text
	_field.clear()
	if text.strip_edges().is_empty():
		return
	_note.text = str(_submit.call(text))


func field() -> LineEdit:
	return _field


func note_text() -> String:
	return _note.text
