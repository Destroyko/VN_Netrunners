extends GutTest
## Общее для тестов окон на рабочем столе: чистое состояние, анимации выключены, итог окна
## головоломки, поиск куска в дампе.

var _gained: int = -1


func before_each() -> void:
	GameState.reset()
	MatrixPanel.animate = false
	DumpPanel.animate = false
	_gained = -1


func _on_finished(gained: int) -> void:
	_gained = gained


func _dump_spot(panel: DumpPanel) -> Vector2i:
	# Ищет текущий кусок на экране: (строка экрана, столбец) или (-1, -1).
	var piece: PackedInt32Array = panel.puzzle.current_target()
	var rows: Array[int] = panel.puzzle.visible_rows()
	for row: int in rows.size():
		var symbols: PackedInt32Array = panel.puzzle.row_symbols(rows[row])
		for at: int in panel.puzzle.width - piece.size() + 1:
			if symbols.slice(at, at + piece.size()) == piece:
				return Vector2i(row, at)
	return Vector2i(-1, -1)
