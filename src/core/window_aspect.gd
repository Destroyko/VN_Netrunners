class_name WindowAspect
extends RefCounted
## Рамка пропорций окна: тянуть можно свободно, но не до уродливых крайностей.
##
## Зачем: интерфейс живёт в пикселях и выдерживает любые пропорции (docs/tech/resolution.md),
## но сцены новеллы — 16:9, и окно шириной в полоску ломает и их, и раскладку рабочего стола.
## Поэтому разрешаем всё от 4:3 до 21:9, а за границами подгоняем.
##
## Чистая функция без узлов: её проверяют тесты, а применяет автозагрузка WindowGuard.

## 4:3 — самый «квадратный» монитор, который мы поддерживаем.
const MIN_ASPECT: float = 4.0 / 3.0
## Сверхширокие. Не 21/9 = 2.333: то, что продают как «21:9», на самом деле шире —
## 2560×1080 это 2.370, 3440×1440 это 2.389. Берём 2.4, чтобы оба проходили.
const MAX_ASPECT: float = 2.4


## Привести размер окна к допустимому: сначала минимум, потом пропорции.
## Лишнее отрезаем от той стороны, которую растянули, а не добавляем к другой:
## иначе окно вылезало бы за экран.
static func clamp_size(
	size: Vector2i,
	min_size: Vector2i,
	min_aspect: float = MIN_ASPECT,
	max_aspect: float = MAX_ASPECT
) -> Vector2i:
	var result: Vector2i = size.max(min_size)
	var aspect: float = float(result.x) / float(result.y)
	if aspect > max_aspect:
		result.x = roundi(float(result.y) * max_aspect)
	elif aspect < min_aspect:
		result.y = roundi(float(result.x) / min_aspect)
	# Минимум держится и после подгонки, потому что он сам лежит внутри рамки
	# (это проверяет тест).
	return result.max(min_size)


static func aspect_of(size: Vector2i) -> float:
	if size.y == 0:
		return 0.0
	return float(size.x) / float(size.y)


static func is_in_frame(size: Vector2i, min_aspect: float = MIN_ASPECT, max_aspect: float = MAX_ASPECT) -> bool:
	var aspect: float = aspect_of(size)
	return aspect >= min_aspect - 0.001 and aspect <= max_aspect + 0.001
