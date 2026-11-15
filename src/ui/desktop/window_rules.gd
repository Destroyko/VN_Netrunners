class_name WindowRules
extends RefCounted
## Правила окон рабочего стола без сцен (docs/tech/desktop-layout.md, «Окна»):
## куда можно перетащить окно и как оно меняет размер. Вынесено, чтобы проверять тестом.

## Сколько заголовка окна должно остаться на экране, чтобы окно было можно ухватить обратно.
const GRAB_MARGIN: float = 60.0
const TITLE_HEIGHT: float = 28.0


## Окно не уходит за границы целиком: за заголовок всегда можно взяться.
static func clamp_position(position: Vector2, size: Vector2, area: Vector2) -> Vector2:
	var x: float = clampf(position.x, GRAB_MARGIN - size.x, area.x - GRAB_MARGIN)
	var y: float = clampf(position.y, 0.0, maxf(area.y - TITLE_HEIGHT, 0.0))
	return Vector2(x, y)


## Новый размер при растягивании за угол: не меньше минимума окна и не больше рабочей области.
static func clamp_size(size: Vector2, minimum: Vector2, position: Vector2, area: Vector2) -> Vector2:
	var max_size: Vector2 = Vector2(maxf(area.x - position.x, minimum.x), maxf(area.y - position.y, minimum.y))
	return Vector2(clampf(size.x, minimum.x, max_size.x), clampf(size.y, minimum.y, max_size.y))


## Стартовое положение окна: каскадом, чтобы новые окна не лежали точно друг на друге.
static func cascade(index: int, size: Vector2, area: Vector2) -> Vector2:
	var step: float = 28.0
	var offset: float = step * float(index % 6)
	return clamp_position(Vector2(120.0 + offset, 40.0 + offset), size, area)
