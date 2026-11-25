class_name ScreenQuad
extends RefCounted
## Перспектива экрана монитора на фоне комнаты: четыре угла экрана (по часовой стрелке от левого
## верхнего) → преобразование квадрата 0..1 в этот четырёхугольник (гомография). Экран ПК
## (загрузка, установка) рисуется в свой буфер и натягивается на монитор шейдером по обратному
## преобразованию. Чистая математика — её проверяют тесты.


## Матрица «квадрат → четырёхугольник» (Хекберт): x = (a·u + b·v + c) / (g·u + h·v + 1).
## Столбцы Basis — столбцы матрицы, так её и ждёт шейдер (mat3).
static func square_to_quad(quad: PackedVector2Array) -> Basis:
	var p0: Vector2 = quad[0]
	var p1: Vector2 = quad[1]
	var p2: Vector2 = quad[2]
	var p3: Vector2 = quad[3]
	var d1: Vector2 = p1 - p2
	var d2: Vector2 = p3 - p2
	var d3: Vector2 = p0 - p1 + p2 - p3
	var g: float = 0.0
	var h: float = 0.0
	var det: float = d1.x * d2.y - d2.x * d1.y
	if not is_zero_approx(det) and not d3.is_zero_approx():
		g = (d3.x * d2.y - d2.x * d3.y) / det
		h = (d1.x * d3.y - d3.x * d1.y) / det
	var a: float = p1.x - p0.x + g * p1.x
	var b: float = p3.x - p0.x + h * p3.x
	var d: float = p1.y - p0.y + g * p1.y
	var e: float = p3.y - p0.y + h * p3.y
	return Basis(Vector3(a, d, g), Vector3(b, e, h), Vector3(p0.x, p0.y, 1.0))


## Точка квадрата (u, v) → точка экрана.
static func apply(m: Basis, point: Vector2) -> Vector2:
	var q: Vector3 = m * Vector3(point.x, point.y, 1.0)
	return Vector2(q.x, q.y) / q.z
