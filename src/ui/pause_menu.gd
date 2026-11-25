class_name PauseMenu
extends Control
## Меню игры поверх комнаты (Esc или кнопка «Меню»): продолжить, сохранить, выйти в главное меню
## (плейтест M2, 17.11.2026: сохранение не место в «Пуске» ПК). Пока меню открыто, время стоит.
## Правил здесь нет: сохраняет `SaveSystem`.

const PAUSE_REASON: String = "menu"

signal main_menu_requested

var _status: Label


func _init() -> void:
	name = "PauseMenu"
	# Меню паузы накрывает экран: строка цели под ним не нужна.
	add_to_group(QuestTracker.COVER_GROUP)
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(240, 0)
	add_child(box)
	_button(box, "Continue", "Продолжить", close)
	_button(box, "Save", "Сохранить игру", save)
	_button(box, "MainMenu", "В главное меню", func() -> void:
		close()
		main_menu_requested.emit())
	_status = Label.new()
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)


func open() -> void:
	_status.text = ""
	show()
	Clock.pause(PAUSE_REASON)
	(find_child("Continue", true, false) as Button).grab_focus()


func close() -> void:
	hide()
	Clock.resume(PAUSE_REASON)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func save() -> void:
	var error: String = SaveSystem.save(SaveSystem.SLOT_MANUAL)
	_status.text = SaveSystem.result_text(error)


func status_text() -> String:
	return _status.text


func _button(box: Container, button_name: String, text: String, on_press: Callable) -> void:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.pressed.connect(on_press)
	box.add_child(button)
