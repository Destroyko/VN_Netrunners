class_name MaskButton
extends Button
## Кнопка, кликабельная только по форме предмета: силуэт берётся из маски (PNG с прозрачностью,
## `tools/blockout/room_masks.py`). Растянута на весь экран, поэтому у предметов с масками нет
## прямоугольников: курсор и подсветка появляются только над самим предметом, а за его краем клик
## проходит к тому, что лежит ниже. Правил игры здесь нет — только форма и подсветка.

## Насколько светлеет силуэт под курсором.
const GLOW_ALPHA: float = 0.22

## Растры масок по пути: строим один раз, перерисовка объектов их не пересчитывает.
static var _bitmaps: Dictionary = {}

var _mask: BitMap
var _glow: TextureRect


## Задать силуэт. Маска должна быть того же кадра, что фон (иначе форма разойдётся с картинкой).
func setup(texture: Texture2D, path: String = "") -> void:
	_mask = _bitmaps.get(path) as BitMap if not path.is_empty() else null
	if _mask == null:
		_mask = BitMap.new()
		_mask.create_from_image_alpha(texture.get_image(), 0.5)
		if not path.is_empty():
			_bitmaps[path] = _mask
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow = TextureRect.new()
	_glow.name = "Glow"
	_glow.texture = texture
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.modulate = Color(1, 1, 1, 0)
	add_child(_glow)
	mouse_entered.connect(func() -> void: _glow.modulate.a = GLOW_ALPHA)
	mouse_exited.connect(func() -> void: _glow.modulate.a = 0.0)


## Точка внутри предмета? Координаты кнопки пересчитываются в координаты маски.
func _has_point(point: Vector2) -> bool:
	if _mask == null:
		return true
	if size.x <= 0.0 or size.y <= 0.0:
		return false
	var mask_size: Vector2 = Vector2(_mask.get_size())
	var at := Vector2i((point / size * mask_size).floor())
	if at.x < 0 or at.y < 0 or at.x >= _mask.get_size().x or at.y >= _mask.get_size().y:
		return false
	return _mask.get_bitv(at)


## Подсвечена ли форма сейчас (для проверки в тестах).
func glow_alpha() -> float:
	return _glow.modulate.a if _glow != null else 0.0
