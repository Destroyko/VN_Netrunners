class_name LetterTile
extends Button
## Плитка с буквой: либо в пуле внизу, либо в ячейке слова. Умеет тащиться мышью и принимать
## чужую плитку; сама ничего не решает — о перетаскивании и клике сообщает панели «пароль».

## Плитку бросили на эту: `from` — {kind, index}, `to_kind` / `to_index` — куда.
signal dropped(from: Dictionary, to_kind: String, to_index: int)

const KIND_POOL: String = "pool"
const KIND_SLOT: String = "slot"

var kind: String = KIND_POOL
var index: int = 0
var letter: String = ""
var locked: bool = false


func setup(tile_kind: String, tile_index: int, tile_letter: String, is_locked: bool) -> void:
	kind = tile_kind
	index = tile_index
	letter = tile_letter
	locked = is_locked
	text = tile_letter.to_upper()
	custom_minimum_size = Vector2(44, 48)
	focus_mode = Control.FOCUS_NONE
	if locked:
		disabled = true


func _get_drag_data(_at_position: Vector2) -> Variant:
	if letter.is_empty() or locked:
		return null
	var preview := Label.new()
	preview.text = letter.to_upper()
	preview.add_theme_font_size_override("font_size", 28)
	set_drag_preview(preview)
	return {"kind": kind, "index": index}


## Бросать можно только в ячейку слова; пул принимает плитки через `LetterZone`.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return kind == KIND_SLOT and not locked and data is Dictionary and (data as Dictionary).has("kind")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	dropped.emit(data as Dictionary, kind, index)
