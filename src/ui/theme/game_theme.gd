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
## Разобранные описания и собранные Theme по id: окна пересобирают оформление при каждой смене фокуса,
## а файл темы во время игры не меняется.
static var _loaded: Dictionary = {}
static var _built: Dictionary = {}


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


## Значок без плашки в любой теме (мелкие значки в списках и кнопках, где плашка лишняя). Нет — null.
static func glyph(icon_id: String, theme_id: String = "") -> Texture2D:
	var id: String = theme_id if not theme_id.is_empty() else current_id
	var path: String = ICONS_DIR.path_join(id).path_join("glyph").path_join(icon_id + ".svg")
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func build(theme_id: String = "") -> Theme:
	var id: String = theme_id if not theme_id.is_empty() else current_id
	if _built.has(id):
		return _built[id] as Theme
	var theme: Theme = _make(id)
	_built[id] = theme
	return theme


static func _make(id: String) -> Theme:
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
	theme.set_type_variation("SmallLabel", "Label")
	theme.set_color("font_color", "SmallLabel", dim)
	theme.set_font_size("font_size", "SmallLabel", 12)
	theme.set_color("default_color", "RichTextLabel", text)
	var dark: bool = panel.get_luminance() < 0.4
	for kind: String in ["Button", "CheckBox", "CheckButton", "OptionButton", "MenuButton"]:
		theme.set_color("font_color", kind, text)
		theme.set_color("font_hover_color", kind, text)
		theme.set_color("font_pressed_color", kind, text)
		theme.set_color("font_hover_pressed_color", kind, text)
		theme.set_color("font_focus_color", kind, text)
		theme.set_color("font_disabled_color", kind, dim)
		theme.set_constant("h_separation", kind, 8)
	# Кнопка: заливка чуть выше тона панели, под мышью — тон плашки и рамка акцента, нажатая — темнее.
	var button_fill: Color = panel.lerp(raised, 0.45) if dark else panel.lerp(Color.WHITE, 0.5)
	for kind: String in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", kind, _control_box(button_fill, border, id))
		theme.set_stylebox("hover", kind, _control_box(raised, accent, id))
		theme.set_stylebox("pressed", kind, _control_box(raised.darkened(0.08), accent, id))
		theme.set_stylebox("hover_pressed", kind, _control_box(raised.darkened(0.08), accent, id))
		theme.set_stylebox("disabled", kind, _control_box(panel, border.lerp(panel, 0.5), id))
		theme.set_stylebox("focus", kind, _outline(accent, id))
	# Главное действие окна («Написать», «Оплатить», «Отправить»): заливка акцентом.
	var on_accent: Color = Color.WHITE if accent.get_luminance() < 0.6 else background
	theme.set_type_variation("AccentButton", "Button")
	theme.set_stylebox("normal", "AccentButton", _control_box(accent, accent, id))
	theme.set_stylebox("hover", "AccentButton", _control_box(accent.lightened(0.1), accent.lightened(0.1), id))
	theme.set_stylebox("pressed", "AccentButton", _control_box(accent.darkened(0.12), accent.darkened(0.12), id))
	theme.set_stylebox("hover_pressed", "AccentButton", _control_box(accent.darkened(0.12), accent.darkened(0.12), id))
	theme.set_stylebox("disabled", "AccentButton", _control_box(accent.lerp(panel, 0.6), accent.lerp(panel, 0.6), id))
	for role: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(role, "AccentButton", on_accent)
	theme.set_color("font_disabled_color", "AccentButton", on_accent.lerp(panel, 0.4))
	# Кнопка без подложки (значки стола, пункты меню): фон появляется только под мышью.
	theme.set_type_variation("FlatButton", "Button")
	var clear := StyleBoxEmpty.new()
	clear.set_content_margin_all(6)
	theme.set_stylebox("normal", "FlatButton", clear)
	theme.set_stylebox("focus", "FlatButton", StyleBoxEmpty.new())
	theme.set_stylebox("disabled", "FlatButton", clear)
	theme.set_stylebox("hover", "FlatButton", _control_box(Color(raised, 0.6), Color(raised, 0.0), id, 6))
	theme.set_stylebox("pressed", "FlatButton", _control_box(raised, raised, id, 6))
	theme.set_stylebox("hover_pressed", "FlatButton", _control_box(raised, raised, id, 6))

	# Флажки — свои значки по цветам темы, без стандартных из Godot.
	for kind: String in ["CheckBox", "CheckButton"]:
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			var none := StyleBoxEmpty.new()
			none.set_content_margin_all(4)
			theme.set_stylebox(state, kind, none)
	theme.set_icon("unchecked", "CheckBox", _svg_icon(
		'<rect x="1.5" y="1.5" width="15" height="15" rx="3" fill="%s" stroke="%s" stroke-width="1.5"/>' % [_hex(background), _hex(border)]))
	theme.set_icon("checked", "CheckBox", _svg_icon(
		'<rect x="1.5" y="1.5" width="15" height="15" rx="3" fill="%s" stroke="%s" stroke-width="1.5"/>' % [_hex(accent), _hex(accent)]
		+ '<path d="M5 9.5 L8 12.5 L13 6" fill="none" stroke="%s" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>' % _hex(on_accent)))
	theme.set_icon("radio_unchecked", "CheckBox", _svg_icon(
		'<circle cx="9" cy="9" r="7.5" fill="%s" stroke="%s" stroke-width="1.5"/>' % [_hex(background), _hex(border)]))
	theme.set_icon("radio_checked", "CheckBox", _svg_icon(
		'<circle cx="9" cy="9" r="7.5" fill="%s" stroke="%s" stroke-width="1.5"/><circle cx="9" cy="9" r="3.5" fill="%s"/>' % [_hex(background), _hex(accent), _hex(accent)]))
	theme.set_icon("unchecked_disabled", "CheckBox", theme.get_icon("unchecked", "CheckBox"))
	theme.set_icon("checked_disabled", "CheckBox", theme.get_icon("checked", "CheckBox"))
	theme.set_icon("arrow", "OptionButton", _svg_icon(
		'<path d="M5 7 L9 11 L13 7" fill="none" stroke="%s" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>' % _hex(dim)))

	# Полосы прокрутки — тонкие, ползунок цвета рамки, под мышью темнее, при перетаскивании акцент.
	for kind: String in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0, 0, 0, 0)
		track.set_content_margin_all(2)
		theme.set_stylebox("scroll", kind, track)
		theme.set_stylebox("scroll_focus", kind, track)
		theme.set_stylebox("grabber", kind, _pill(border))
		theme.set_stylebox("grabber_highlight", kind, _pill(dim))
		theme.set_stylebox("grabber_pressed", kind, _pill(accent))
		for icon: String in ["increment", "decrement", "increment_highlight", "decrement_highlight", "increment_pressed", "decrement_pressed"]:
			theme.set_icon(icon, kind, _svg_icon("", 2))
	var line := StyleBoxLine.new()
	line.color = border.lerp(panel, 0.3)
	line.thickness = 1
	theme.set_stylebox("separator", "HSeparator", line)
	theme.set_constant("separation", "HSeparator", 9)
	var vline := StyleBoxLine.new()
	vline.color = line.color
	vline.vertical = true
	theme.set_stylebox("separator", "VSeparator", vline)
	theme.set_constant("separation", "VSeparator", 9)

	theme.set_stylebox("panel", "PanelContainer", _box(panel, border, id))
	theme.set_stylebox("panel", "Panel", _box(panel, border, id))

	theme.set_color("font_color", "LineEdit", text)
	theme.set_color("caret_color", "LineEdit", accent)
	theme.set_color("selection_color", "LineEdit", raised)
	theme.set_color("font_placeholder_color", "LineEdit", dim)
	var field: Color = background if dark else panel.lerp(Color.WHITE, 0.6)
	theme.set_stylebox("normal", "LineEdit", _control_box(field, border, id, 8))
	theme.set_stylebox("focus", "LineEdit", _control_box(field, accent, id, 8))
	theme.set_stylebox("read_only", "LineEdit", _control_box(panel, border, id, 8))

	# Списки и текстовые поля внутри окон (почта, файлы, блокнот): тон вдавленной области, без серого по умолчанию.
	var inset: StyleBoxFlat = _box(field, border.lerp(panel, 0.3), id)
	inset.set_content_margin_all(6)
	theme.set_stylebox("panel", "ItemList", inset)
	theme.set_stylebox("focus", "ItemList", _outline(accent, id))
	theme.set_stylebox("selected", "ItemList", _control_box(raised, raised, id, 6))
	theme.set_stylebox("selected_focus", "ItemList", _control_box(raised, raised, id, 6))
	theme.set_stylebox("hovered", "ItemList", _control_box(Color(raised, 0.45), Color(raised, 0.0), id, 6))
	theme.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	theme.set_color("guide_color", "ItemList", Color(0, 0, 0, 0))
	theme.set_color("font_color", "ItemList", text)
	theme.set_color("font_selected_color", "ItemList", text)
	theme.set_color("font_hovered_color", "ItemList", text)
	theme.set_constant("v_separation", "ItemList", 6)
	theme.set_stylebox("normal", "TextEdit", inset)
	theme.set_stylebox("panel", "Tree", inset)
	# Карточка внутри окна (баланс в банке): тон поля, поля по сетке.
	var card: StyleBoxFlat = _box(field, border.lerp(panel, 0.3), id)
	card.set_content_margin_all(12)
	theme.set_type_variation("CardPanel", "PanelContainer")
	theme.set_stylebox("panel", "CardPanel", card)
	theme.set_color("font_color", "Tree", text)
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
	var popup: StyleBoxFlat = _box(panel, border, id)
	popup.set_content_margin_all(6)
	popup.shadow_color = Color(0, 0, 0, 0.3 if dark else 0.15)
	popup.shadow_size = 8
	popup.shadow_offset = Vector2(0, 3)
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_stylebox("panel", "PopupPanel", popup)
	theme.set_stylebox("hover", "PopupMenu", _control_box(raised, raised, id, 6))
	theme.set_stylebox("separator", "PopupMenu", line)
	theme.set_constant("item_start_padding", "PopupMenu", 10)
	theme.set_constant("item_end_padding", "PopupMenu", 16)
	theme.set_color("font_color", "PopupMenu", text)
	theme.set_color("font_hover_color", "PopupMenu", text)
	theme.set_color("font_disabled_color", "PopupMenu", dim)
	theme.set_constant("v_separation", "PopupMenu", 8)

	# Подсказка — тёмная плашка на светлой теме и наоборот, как в привычных ОС.
	var tip: StyleBoxFlat = _box(background if dark else text, background if dark else text, id)
	tip.content_margin_left = 8
	tip.content_margin_right = 8
	tip.content_margin_top = 4
	tip.content_margin_bottom = 4
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", text if dark else background)
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


## Плашка элемента управления: форма темы, поля по сетке (по бокам `horizontal`, сверху и снизу 6).
static func _control_box(fill: Color, border: Color, theme_id: String, horizontal: float = 12.0) -> StyleBoxFlat:
	var box: StyleBoxFlat = _box(fill, border, theme_id)
	box.content_margin_left = horizontal
	box.content_margin_right = horizontal
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


## Ползунок полосы прокрутки: скруглённая «таблетка».
static func _pill(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(3)
	box.set_content_margin_all(3)
	return box


## Мелкий значок интерфейса из SVG-разметки (`size`×`size` единиц).
static func _svg_icon(shapes: String, size: int = 18) -> Texture2D:
	var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>' % [
		size, size, size, size, shapes]
	var image := Image.new()
	image.load_svg_from_string(svg, 1.0)
	return ImageTexture.create_from_image(image)


static func _hex(value: Color) -> String:
	return "#" + value.to_html(false)


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
	if _loaded.has(theme_id):
		return _loaded[theme_id] as Dictionary
	var path: String = THEMES_DIR.path_join(theme_id).path_join("theme.json")
	var result: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		result = parsed as Dictionary if parsed is Dictionary else {}
	_loaded[theme_id] = result
	return result
