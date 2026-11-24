class_name HeatBar
extends Control
## Полоска заметности: 10 делений без цифр, этап = два деления, этапы различаются цветом
## (docs/gameplay/heat.md, «Как игрок это видит»). Только читает `GameState.heat`.
## Цвета — роли темы (`ok` → `warn` → `danger`), чтобы шкала жила в палитре ОС.

## Цвета этапов по умолчанию (без темы), для тестов и мест вне окон ПК.
const STAGE_COLORS: Array[Color] = [
	Color(0.35, 0.8, 0.45),
	Color(0.7, 0.85, 0.3),
	Color(0.95, 0.8, 0.25),
	Color(0.95, 0.5, 0.2),
	Color(0.9, 0.2, 0.2),
]
const GAP: float = 3.0

## Тема, в цветах которой рисуется шкала ("" — цвета по умолчанию).
var theme_id: String = "":
	set(value):
		theme_id = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(120, 12)
	tooltip_text = "Риск раскрытия"


func _ready() -> void:
	EventBus.heat_changed.connect(func(_heat: int, _delta: int) -> void: queue_redraw())


## Цвет деления по его номеру (0–9): этап считаем по делению, а не по текущей заметности.
static func color_of_cell(index: int, for_theme: String = "") -> Color:
	var stage: int = clampi(index / 2, 0, STAGE_COLORS.size() - 1)
	if for_theme.is_empty():
		return STAGE_COLORS[stage]
	var ok: Color = GameTheme.color("ok", for_theme)
	var warn: Color = GameTheme.color("warn", for_theme)
	var danger: Color = GameTheme.color("danger", for_theme)
	var themed: Array[Color] = [ok, ok.lerp(warn, 0.5), warn, warn.lerp(danger, 0.5), danger]
	return themed[stage]


func _draw() -> void:
	var filled: int = Heat.bar_cells(GameState.heat)
	var empty: Color = GameTheme.color("background", theme_id) if not theme_id.is_empty() else Color(0.2, 0.22, 0.27)
	if not theme_id.is_empty():
		empty = empty.lerp(GameTheme.color("border", theme_id), 0.45)
	var cell_width: float = (size.x - GAP * float(Heat.BAR_CELLS - 1)) / float(Heat.BAR_CELLS)
	for index: int in Heat.BAR_CELLS:
		var rect := Rect2(float(index) * (cell_width + GAP), 0.0, cell_width, size.y)
		draw_rect(rect, color_of_cell(index, theme_id) if index < filled else empty)
