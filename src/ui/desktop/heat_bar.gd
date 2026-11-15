class_name HeatBar
extends Control
## Полоска заметности: 10 делений без цифр, этап = два деления, этапы различаются цветом
## (docs/gameplay/heat.md, «Как игрок это видит»). Только читает `GameState.heat`.

const STAGE_COLORS: Array[Color] = [
	Color(0.35, 0.8, 0.45),
	Color(0.7, 0.85, 0.3),
	Color(0.95, 0.8, 0.25),
	Color(0.95, 0.5, 0.2),
	Color(0.9, 0.2, 0.2),
]
const EMPTY_COLOR: Color = Color(0.2, 0.22, 0.27)
const GAP: float = 2.0


func _init() -> void:
	custom_minimum_size = Vector2(120, 14)
	tooltip_text = "Риск раскрытия"


func _ready() -> void:
	EventBus.heat_changed.connect(func(_heat: int, _delta: int) -> void: queue_redraw())


## Цвет деления по его номеру (0–9): этап считаем по делению, а не по текущей заметности.
static func color_of_cell(index: int) -> Color:
	return STAGE_COLORS[clampi(index / 2, 0, STAGE_COLORS.size() - 1)]


func _draw() -> void:
	var filled: int = Heat.bar_cells(GameState.heat)
	var cell_width: float = (size.x - GAP * float(Heat.BAR_CELLS - 1)) / float(Heat.BAR_CELLS)
	for index: int in Heat.BAR_CELLS:
		var rect := Rect2(float(index) * (cell_width + GAP), 0.0, cell_width, size.y)
		draw_rect(rect, color_of_cell(index) if index < filled else EMPTY_COLOR)
