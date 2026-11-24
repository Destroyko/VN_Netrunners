class_name GameTheme
extends RefCounted
## Общая тема интерфейса: кнопки, панели, подписи, поля ввода, полоски, подсказки. Цвета и форма —
## `data/ui_theme.json` (роли цветов из палитры комнат). Тема ставится на корневое окно один раз при
## загрузке (`BootScreen`), и все экраны получают её сами; отдельные оформления окон, которые
## переопределяют цвета руками, постепенно переводятся на роли отсюда.
##
## Шрифт не меняется: вопрос шрифта ещё не решён (docs/roadmap.md, шаг 6а).

const DATA_PATH: String = "res://data/ui_theme.json"
const DEFAULT_COLORS: Dictionary = {
	"background": "#1C1E23", "panel": "#2E3A55", "panel_raised": "#46587A", "border": "#6E7B88",
	"text": "#E6EAEF", "text_dim": "#8D929B", "accent": "#E87B2E", "accent_alt": "#3FB3C4",
	"ok": "#3E9E5C", "warn": "#F0C330", "danger": "#D8453C",
}


## Цвет по роли («text», «accent»…). Нет роли — белый, чтобы ошибка в данных была видна на экране.
static func color(role: String) -> Color:
	var colors: Dictionary = _data().get("colors", DEFAULT_COLORS) as Dictionary
	if colors.has(role):
		return Color(str(colors[role]))
	return Color.WHITE


static func build() -> Theme:
	var theme := Theme.new()
	var text: Color = color("text")
	var dim: Color = color("text_dim")
	var accent: Color = color("accent")

	theme.set_color("font_color", "Label", text)
	for kind: String in ["Button", "CheckBox", "OptionButton", "MenuButton"]:
		theme.set_color("font_color", kind, text)
		theme.set_color("font_hover_color", kind, Color.WHITE)
		theme.set_color("font_pressed_color", kind, accent)
		theme.set_color("font_focus_color", kind, text)
		theme.set_color("font_disabled_color", kind, dim)
	for kind: String in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", kind, _box(color("panel"), color("border")))
		theme.set_stylebox("hover", kind, _box(color("panel_raised"), color("accent_alt")))
		theme.set_stylebox("pressed", kind, _box(color("background"), accent))
		theme.set_stylebox("disabled", kind, _box(color("background").lerp(color("panel"), 0.4), color("border").darkened(0.4)))
		theme.set_stylebox("focus", kind, _outline(accent))

	theme.set_stylebox("panel", "PanelContainer", _box(color("panel"), color("border")))
	theme.set_stylebox("panel", "Panel", _box(color("panel"), color("border")))

	theme.set_color("font_color", "LineEdit", text)
	theme.set_color("caret_color", "LineEdit", accent)
	theme.set_color("selection_color", "LineEdit", color("panel_raised"))
	theme.set_color("font_placeholder_color", "LineEdit", dim)
	theme.set_stylebox("normal", "LineEdit", _box(color("background"), color("border")))
	theme.set_stylebox("focus", "LineEdit", _box(color("background"), accent))

	theme.set_stylebox("background", "ProgressBar", _box(color("background"), color("border")))
	theme.set_stylebox("fill", "ProgressBar", _box(accent, accent, 0))
	theme.set_color("font_color", "ProgressBar", text)

	theme.set_stylebox("panel", "TooltipPanel", _box(color("background"), accent))
	theme.set_color("font_color", "TooltipLabel", text)
	return theme


## Прямоугольник с рамкой по форме из данных.
static func _box(fill: Color, border: Color, width: int = -1) -> StyleBoxFlat:
	var shape: Dictionary = _data().get("shape", {}) as Dictionary
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(int(shape.get("border_width", 1)) if width < 0 else width)
	box.set_corner_radius_all(int(shape.get("radius", 4)))
	box.set_content_margin_all(float(shape.get("padding", 8)))
	return box


## Контур вокруг сфокусированной кнопки (клавиатура), без заливки.
static func _outline(border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(int((_data().get("shape", {}) as Dictionary).get("radius", 4)))
	return box


static func _data() -> Dictionary:
	if not FileAccess.file_exists(DATA_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return parsed as Dictionary if parsed is Dictionary else {}
