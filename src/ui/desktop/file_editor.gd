class_name FileEditor
extends VBoxContainer
## «Блокнот» для команды `edit` (docs/tech/terminal-spec.md): текст файла можно изменить и
## сохранить. Правил здесь нет: что разрешено и что попадёт в лог узла, решает терминал
## (`Terminal.save_edit`), окно только отдаёт текст.

signal saved(text: String)
signal cancelled

var _text: TextEdit
var _original: String = ""


func setup(request: Dictionary) -> void:
	name = "FileEditor"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_original = str(request.get("text", ""))
	var where := Label.new()
	where.name = "Path"
	where.text = str(request.get("path", ""))
	where.theme_type_variation = "DimLabel"
	where.add_theme_font_override("font", GameTheme.font("mono"))
	add_child(where)
	_text = TextEdit.new()
	_text.name = "Text"
	_text.text = _original
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.add_theme_font_override("font", GameTheme.font("mono"))
	add_child(_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	add_child(row)
	var cancel := Button.new()
	cancel.name = "Cancel"
	cancel.text = "Отмена"
	cancel.pressed.connect(func() -> void: cancelled.emit())
	row.add_child(cancel)
	var save := Button.new()
	save.name = "Save"
	save.text = "Сохранить"
	save.pressed.connect(func() -> void: saved.emit(_text.text))
	row.add_child(save)


func _ready() -> void:
	_text.grab_focus.call_deferred()


## Для тестов: подменить текст, как будто игрок напечатал.
func set_text(text: String) -> void:
	_text.text = text


func is_changed() -> bool:
	return _text.text != _original
