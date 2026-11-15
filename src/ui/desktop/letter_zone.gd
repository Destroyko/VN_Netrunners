class_name LetterZone
extends HFlowContainer
## Пул букв: сюда можно вернуть плитку из ячейки, перетащив её обратно.

signal returned(from: Dictionary)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and str((data as Dictionary).get("kind", "")) == LetterTile.KIND_SLOT


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	returned.emit(data as Dictionary)
