extends GutTest
## Перспектива экрана монитора (ScreenQuad): углы квадрата попадают в углы экрана на фоне,
## обратное преобразование возвращает точку назад.

const QUAD: PackedVector2Array = [Vector2(60, 190), Vector2(569, 130), Vector2(607, 388), Vector2(137, 531)]


func test_corners_land_on_the_screen_corners() -> void:
	var m: Basis = ScreenQuad.square_to_quad(QUAD)
	var square: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i: int in 4:
		var got: Vector2 = ScreenQuad.apply(m, square[i])
		assert_almost_eq(got.x, QUAD[i].x, 0.01)
		assert_almost_eq(got.y, QUAD[i].y, 0.01)


func test_inverse_brings_a_point_back() -> void:
	var m: Basis = ScreenQuad.square_to_quad(QUAD)
	var point: Vector2 = ScreenQuad.apply(m, Vector2(0.3, 0.7))
	var back: Vector2 = ScreenQuad.apply(m.inverse(), point)
	assert_almost_eq(back.x, 0.3, 0.0001)
	assert_almost_eq(back.y, 0.7, 0.0001)
