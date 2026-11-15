class_name DesktopDropZone
extends ColorRect
## Фон рабочего стола игрока, на который можно бросить файл из трансляции чужого ПК:
## брошенный файл скачивается к себе (как `cp` с узла). Правил здесь нет — только сигнал.

signal remote_file_dropped(data: Dictionary)
## Правая кнопка по фону стола: меню «Вставить».
signal menu_requested(at_position: Vector2)


func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
		menu_requested.emit(click.position)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("remote_file")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	remote_file_dropped.emit(data as Dictionary)
