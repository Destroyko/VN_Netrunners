class_name FileList
extends ItemList
## Список файлов проводника, из которого файл можно утащить мышью. Что тащится, решает
## проводник (`drag_source(index) -> Variant`, null — тащить нечего).

var drag_source: Callable


func _get_drag_data(at_position: Vector2) -> Variant:
	var index: int = get_item_at_position(at_position, true)
	if index < 0 or not drag_source.is_valid():
		return null
	var data: Variant = drag_source.call(index)
	if data == null:
		return null
	var preview := Label.new()
	preview.text = get_item_text(index)
	set_drag_preview(preview)
	return data
