class_name SceneCard
extends PanelContainer
## Карточка сцены, как в визуальных новеллах: слева вверху значок времени суток, фаза и время,
## под ними — где герой. Проявляется, когда герой пришёл в новое место или сменилась фаза суток
## (проснулся утром), держится несколько секунд и гаснет (решено разработчиком 25.11.2026).
##
## Правил здесь нет: фаза — `Clock.time_of_day()`, место — из данных локации.

## Сколько секунд карточка видна целиком, и сколько длятся проявление и угасание.
const HOLD_SECONDS: float = 3.5
const FADE_SECONDS: float = 0.4
const ICON_SIZE: float = 36.0
## Фаза суток → слово и значок (`assets/_source/icons/glyphs/time_*.svg`).
const PHASES: Dictionary = {
	"morning": {"word": "Утро", "icon": "time_morning"},
	"day": {"word": "День", "icon": "time_day"},
	"evening": {"word": "Вечер", "icon": "time_evening"},
	"night": {"word": "Ночь", "icon": "time_night"},
}
## В тестах и снимках карточка не гаснет сама, чтобы её можно было проверить.
static var animate: bool = true

var _icon: TextureRect
var _time: Label
var _place: Label
var _phase: String = ""
var _tween: Tween
var _theme_id: String = ""


func _init() -> void:
	name = "SceneCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	_time = Label.new()
	_time.name = "Clock"
	_time.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_time)
	_place = Label.new()
	_place.name = "Title"
	_place.add_theme_font_override("font", GameTheme.font("heading"))
	_place.add_theme_font_size_override("font_size", 20)
	_place.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_place)


## Оформление по теме общих экранов: полупрозрачная панель, текст и значок из ролей темы.
func use_theme(theme_id: String) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(GameTheme.color("background", theme_id), 0.78)
	style.border_color = Color(GameTheme.color("border", theme_id), 0.6)
	style.border_width_left = 3
	var radius: int = int((GameTheme.load_theme(theme_id).get("shape", {}) as Dictionary).get("radius", 4))
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)
	_time.add_theme_color_override("font_color", GameTheme.color("text_dim", theme_id))
	_place.add_theme_color_override("font_color", GameTheme.color("text", theme_id))
	_theme_id = theme_id


## Пришли в место: обновить текст и показать карточку.
func show_place(place: String) -> void:
	_place.text = place
	refresh_time()
	reveal()


## Обновить фазу и время. Сменилась фаза суток — карточка показывается снова.
func refresh_time() -> void:
	var phase: String = Clock.time_of_day()
	var info: Dictionary = PHASES.get(phase, PHASES["day"]) as Dictionary
	_time.text = "%s · %s" % [str(info["word"]), Clock.format_now()]
	var changed: bool = not _phase.is_empty() and phase != _phase
	if phase != _phase:
		_icon.texture = GameTheme.glyph(str(info["icon"]), _theme_id)
		_phase = phase
	if changed:
		reveal()


## Проявить, подержать и погасить. Повторный вызов продлевает показ.
func reveal() -> void:
	if _tween != null:
		_tween.kill()
	if not animate or not is_inside_tree():
		modulate.a = 1.0
		return
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_SECONDS)
	_tween.tween_interval(HOLD_SECONDS)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)


# --- Для тестов --------------------------------------------------------------------------

func time_text() -> String:
	return _time.text


func place_text() -> String:
	return _place.text


func phase() -> String:
	return _phase


func shown() -> bool:
	return modulate.a > 0.0
