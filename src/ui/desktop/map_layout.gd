class_name MapLayout
extends RefCounted
## Раскладка карты сети (docs/tech/desktop-layout.md, «Карта сети»): куда поставить квадратики.
## Чистая функция: на вход известные узлы и связи, на выход — позиции. Проверяется тестом.
##
## Каждая «связная группа» узлов — отдельный остров (network.md): внутри острова узлы идут
## колонками по расстоянию от первого, острова стоят друг под другом.

const CELL: Vector2 = Vector2(150, 80)
const MARGIN: Vector2 = Vector2(30, 30)


## `ids` — известные узлы (в стабильном порядке), `links` — словарь id → список соседей.
## Связь рисуется, только если известны оба конца. Возвращает {id: Vector2} и размер холста.
static func compute(ids: PackedStringArray, links: Dictionary) -> Dictionary:
	var known: Dictionary = {}
	for id: String in ids:
		known[id] = true

	var placed: Dictionary = {}
	var positions: Dictionary = {}
	var top_row: int = 0
	var max_column: int = 0
	for start: String in ids:
		if placed.has(start):
			continue
		var layers: Array = _layers(start, links, known, placed)
		var island_rows: int = 0
		for column: int in layers.size():
			var layer: PackedStringArray = layers[column] as PackedStringArray
			island_rows = maxi(island_rows, layer.size())
			for row: int in layer.size():
				positions[layer[row]] = MARGIN + Vector2(float(column), float(top_row + row)) * CELL
			max_column = maxi(max_column, column)
		top_row += maxi(island_rows, 1)
	var canvas: Vector2 = MARGIN * 2.0 + Vector2(float(max_column + 1), float(maxi(top_row, 1))) * CELL
	return {"positions": positions, "size": canvas}


## Рёбра между известными узлами, без дублей (a — b и b — a это одна линия).
static func edges(ids: PackedStringArray, links: Dictionary) -> Array[Array]:
	var known: Dictionary = {}
	for id: String in ids:
		known[id] = true
	var seen: Dictionary = {}
	var result: Array[Array] = []
	for id: String in ids:
		for other: Variant in links.get(id, []) as Array:
			var neighbour: String = str(other)
			if not known.has(neighbour):
				continue
			var key: String = id + "|" + neighbour if id < neighbour else neighbour + "|" + id
			if seen.has(key):
				continue
			seen[key] = true
			result.append([id, neighbour])
	return result


## Обход в ширину внутри острова: колонка = расстояние от стартового узла.
static func _layers(start: String, links: Dictionary, known: Dictionary, placed: Dictionary) -> Array:
	var layers: Array = []
	var frontier: PackedStringArray = [start]
	placed[start] = true
	while not frontier.is_empty():
		layers.append(frontier)
		var next: PackedStringArray = []
		for id: String in frontier:
			for other: Variant in links.get(id, []) as Array:
				var neighbour: String = str(other)
				if known.has(neighbour) and not placed.has(neighbour):
					placed[neighbour] = true
					next.append(neighbour)
		# Связь может быть записана только с одной стороны: смотрим и обратные ссылки.
		for id: String in known.keys():
			if placed.has(id):
				continue
			for other: Variant in links.get(id, []) as Array:
				if frontier.has(str(other)):
					placed[id] = true
					next.append(id)
					break
		next.sort()
		frontier = next
	return layers
