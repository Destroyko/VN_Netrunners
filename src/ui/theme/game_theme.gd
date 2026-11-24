class_name GameTheme
extends RefCounted
## Темы оформления (docs/art/themes.md): тема — папка `data/themes/<id>/theme.json` (роли цветов, форма,
## цвета значков) и значки `assets/ui/icons/<id>/`. Темы MVP: `phone` (телефон, меню и комната), `standard`
## (обычный ПК), `hacker` (хакерская ОС). Игрок может скачать файл темы с чужого ПК и подменить свою (после
## перезагрузки тема ПК обновляется), поэтому тема выбирается данными: переменная `pc.theme` или по `pc.os`.
##
## Цвета берутся только через роли (`color`, `build`): тема целиком меняется сменой id. Шрифт один, вопрос
## шрифта открыт (docs/roadmap.md, шаг 6а).

const THEMES_DIR: String = "res://data/themes"
const ICONS_DIR: String = "res://assets/ui/icons"
const DEFAULT_ID: String = "phone"
## Переменная GameState: id темы ПК, подменённой игроком ("" — по `pc.os`).
const VAR_PC_THEME: String = "pc.theme"
const PC_THEME_BY_OS: Dictionary = {"normal": "standard", "hacker": "hacker"}
const DEFAULT_COLORS: Dictionary = {
	"background": "#1C1E23", "panel": "#2E3A55", "panel_raised": "#46587A", "border": "#6E7B88",
	"text": "#E6EAEF", "text_dim": "#8D929B", "accent": "#E87B2E", "accent_alt": "#3FB3C4",
	"ok": "#3E9E5C", "warn": "#F0C330", "danger": "#D8453C",
}

## Тема, которой сейчас рисуются общие экраны (меню, комната, телефон). Окна ПК берут тему ПК отдельно.
static var current_id: String = DEFAULT_ID


## Цвет роли в теме `theme_id` (по умолчанию — общая). Нет роли — белый, чтобы ошибка была видна.
static func color(role: String, theme_id: String = "") -> Color:
	var colors: Dictionary = load_theme(theme_id if not theme_id.is_empty() else current_id).get("colors", DEFAULT_COLORS) as Dictionary
	if colors.has(role):
		return Color(str(colors[role]))
	return Color.WHITE


## Id темы ПК героя: подмена игрока, иначе по ОС (`pc.os`).
static func pc_theme_id() -> String:
	var custom: String = str(GameState.get_var_or(VAR_PC_THEME, ""))
	if not custom.is_empty() and theme_exists(custom):
		return custom
	return str(PC_THEME_BY_OS.get(str(GameState.get_var_or("pc.os", "normal")), "standard"))


static func theme_exists(theme_id: String) -> bool:
	return FileAccess.file_exists(THEMES_DIR.path_join(theme_id).path_join("theme.json"))


## Значок приложения в теме (без плашки на ПК, на плашке у телефона). Нет файла — null.
static func icon(icon_id: String, theme_id: String = "") -> Texture2D:
	var id: String = theme_id if not theme_id.is_empty() else current_id
	var kind: String = "tile" if bool((load_theme(id).get("icons", {}) as Dictionary).get("tiles", false)) else "glyph"
	var path: String = ICONS_DIR.path_join(id).path_join(kind).path_join(icon_id + ".svg")
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func build(theme_id: String = "") -> Theme:
	var id: String = theme_id if not theme_id.is_empty() else current_id
	var theme := Theme.new()
	var text: Color = color("text", id)
	var dim: Color = color("text_dim", id)
	var accent: Color = color("accent", id)
	var background: Color = color("background", id)
	var panel: Color = color("panel", id)
	var raised: Color = color("panel_raised", id)
	var border: Color = color("border", id)

	theme.set_color("font_color", "Label", text)
	# Вариации подписи для приложений: второстепенный текст, заголовок письма или новости, предупреждение.
	theme.set_type_variation("DimLabel", "Label")
	theme.set_color("font_color", "DimLabel", dim)
	theme.set_type_variation("HeaderLabel", "Label")
	theme.set_color("font_color", "HeaderLabel", text)
	theme.set_font_size("font_size", "HeaderLabel", 18)
	theme.set_type_variation("WarnLabel", "Label")
	theme.set_color("font_color", "WarnLabel", color("warn", id))
	theme.set_type_variation("DangerLabel", "Label")
	theme.set_color("font_color", "DangerLabel", color("danger", id))
	# Заголовок раздела списка (задачи) и своя реплика в переписке.
	theme.set_type_variation("SectionLabel", "Label")
	theme.set_color("font_color", "SectionLabel", accent)
	theme.set_type_variation("MineLabel", "Label")
	theme.set_color("font_color", "MineLabel", color("accent_alt", id))
	for kind: String in ["Button", "CheckBox", "OptionButton", "MenuButton"]:
		theme.set_color("font_color", kind, text)
		theme.set_color("font_hover_color", kind, text.lightened(0.2) if text.get_luminance() > 0.5 else text.darkened(0.2))
		theme.set_color("font_pressed_color", kind, accent)
		theme.set_color("font_focus_color", kind, text)
		theme.set_color("font_disabled_color", kind, dim)
	for kind: String in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", kind, _box(panel, border, id))
		theme.set_stylebox("hover", kind, _box(raised, color("accent_alt", id), id))
		theme.set_stylebox("pressed", kind, _box(background, accent, id))
		theme.set_stylebox("disabled", kind, _box(background.lerp(panel, 0.4), border.darkened(0.1), id))
		theme.set_stylebox("focus", kind, _outline(accent, id))

	theme.set_stylebox("panel", "PanelContainer", _box(panel, border, id))
	theme.set_stylebox("panel", "Panel", _box(panel, border, id))

	theme.set_color("font_color", "LineEdit", text)
	theme.set_color("caret_color", "LineEdit", accent)
	theme.set_color("selection_color", "LineEdit", raised)
	theme.set_color("font_placeholder_color", "LineEdit", dim)
	theme.set_stylebox("normal", "LineEdit", _box(background, border, id))
	theme.set_stylebox("focus", "LineEdit", _box(background, accent, id))

	# Списки и текстовые поля внутри окон (почта, файлы, блокнот): тон вдавленной области, без серого по умолчанию.
	var inset: StyleBoxFlat = _box(background, border, id)
	inset.set_content_margin_all(6)
	theme.set_stylebox("panel", "ItemList", inset)
	theme.set_stylebox("focus", "ItemList", _outline(accent, id))
	theme.set_stylebox("selected", "ItemList", _box(raised, accent, id, 0))
	theme.set_stylebox("selected_focus", "ItemList", _box(raised, accent, id, 0))
	theme.set_stylebox("hovered", "ItemList", _box(panel, panel, id, 0))
	theme.set_color("font_color", "ItemList", text)
	theme.set_color("font_selected_color", "ItemList", text)
	theme.set_color("font_hovered_color", "ItemList", text)
	theme.set_constant("v_separation", "ItemList", 6)
	theme.set_stylebox("normal", "TextEdit", inset)
	theme.set_stylebox("read_only", "TextEdit", inset)
	theme.set_stylebox("focus", "TextEdit", _box(background, accent, id))
	theme.set_color("font_color", "TextEdit", text)
	theme.set_color("font_readonly_color", "TextEdit", text)
	theme.set_color("caret_color", "TextEdit", accent)
	theme.set_color("selection_color", "TextEdit", raised)

	theme.set_stylebox("background", "ProgressBar", _box(background, border, id))
	theme.set_stylebox("fill", "ProgressBar", _box(accent, accent, id, 0))
	theme.set_color("font_color", "ProgressBar", text)

	# «Пуск» и контекстные меню — в тоне панели, пункт под мышью — тон плашки.
	theme.set_stylebox("panel", "PopupMenu", _box(panel, border, id))
	theme.set_stylebox("hover", "PopupMenu", _box(raised, raised, id, 0))
	theme.set_color("font_color", "PopupMenu", text)
	theme.set_color("font_hover_color", "PopupMenu", text)
	theme.set_color("font_disabled_color", "PopupMenu", dim)
	theme.set_constant("v_separation", "PopupMenu", 8)

	theme.set_stylebox("panel", "TooltipPanel", _box(background, accent, id))
	theme.set_color("font_color", "TooltipLabel", text)
	return theme


## Прямоугольник с рамкой по форме темы.
static func _box(fill: Color, border: Color, theme_id: String, width: int = -1) -> StyleBoxFlat:
	var shape: Dictionary = load_theme(theme_id).get("shape", {}) as Dictionary
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(int(shape.get("border_width", 1)) if width < 0 else width)
	box.set_corner_radius_all(int(shape.get("radius", 4)))
	box.set_content_margin_all(float(shape.get("padding", 8)))
	return box


## Контур вокруг сфокусированной кнопки (клавиатура), без заливки.
static func _outline(border: Color, theme_id: String) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(int((load_theme(theme_id).get("shape", {}) as Dictionary).get("radius", 4)))
	return box


## Описание темы из данных ({} — такой нет).
static func load_theme(theme_id: String) -> Dictionary:
	var path: String = THEMES_DIR.path_join(theme_id).path_join("theme.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}
