class_name TerminalHighlight
extends RefCounted
## Подсветка консоли (docs/tech/desktop-layout.md, «Окно терминала»): превращает строки терминала в
## BBCode с цветами — приглашение по частям, команда, ключи, пути, ошибки, успех, предупреждения.
## Только вид: команды и их ответы не меняются, решает всё `Terminal`. Чистый класс без сцен —
## проверяется тестом.
##
## Экран консоли тёмный во всех темах ПК, поэтому цвета — роли темы, подогнанные под тёмный фон:
## у светлой темы текст свой светлый, акценты — те же оттенки, что у окон.

## Слова, по которым строка ответа считается ошибкой, успехом, предупреждением или справкой.
const ERROR_MARKS: PackedStringArray = [
	"не найден", "нет такого", "нет таких", "недостаточно прав", "отклонён", "заблокирова", "прервано",
	"запрещ", "ошибка", "не удалось", "не установлен", "не работает", "нет подключения", "нет сервиса",
	"не указан", "невозможно",
]
const OK_MARKS: PackedStringArray = [
	"установлено", "подключено", "получен", "повышены", "удалено:", "передано", "заменено", "очищено",
	"сохранено", ": запущен",
]
const WARN_MARKS: PackedStringArray = ["трейс", "обнаружен", "(y/n)", "мониторинг", "внимание"]
const DIM_MARKS: PackedStringArray = ["использование:", "отменено", "пусто"]

var colors: Dictionary = {}


## Палитра консоли из темы `theme_id`: роли text, dim, host, path, command, flag, error, ok, warn, cursor,
## background.
static func palette(theme_id: String) -> Dictionary:
	var dark_theme: bool = GameTheme.color("panel", theme_id).get_luminance() < 0.4
	var accent: Color = GameTheme.color("accent", theme_id)
	var text: Color = GameTheme.color("text", theme_id) if dark_theme else Color("#D3D6DA")
	# У хакерской ОС экран с лёгким зелёным оттенком и текст чуть в зелень — свой характер, без кислоты.
	var background: Color = Color(0.035, 0.05, 0.04) if dark_theme else Color(0.03, 0.04, 0.05)
	if dark_theme:
		text = text.lerp(accent, 0.12)
	return {
		"background": background,
		"text": text,
		"dim": GameTheme.color("text_dim", theme_id),
		"host": GameTheme.color("ok", theme_id).lightened(0.15),
		"path": GameTheme.color("accent_alt", theme_id).lightened(0.3),
		"command": accent.lightened(0.15),
		"flag": GameTheme.color("text_dim", theme_id).lightened(0.15),
		"error": GameTheme.color("danger", theme_id).lightened(0.2),
		"ok": GameTheme.color("ok", theme_id).lightened(0.2),
		"warn": GameTheme.color("warn", theme_id).lightened(0.15),
		"root": GameTheme.color("danger", theme_id).lightened(0.2),
		"cursor": text,
	}


func _init(theme_id: String = "") -> void:
	colors = palette(theme_id if not theme_id.is_empty() else GameTheme.pc_theme_id())


## Приглашение: узел, путь и знак ($ — обычный вход, # — администратор), «адрес>» — соединение без
## входа, «пароль:» — запрос пароля.
func prompt(text: String) -> String:
	if text.ends_with("$ ") or text.ends_with("# "):
		var sigil: String = text.substr(text.length() - 2, 1)
		var body: String = text.substr(0, text.length() - 2)
		var colon: int = body.find(":")
		var host: String = body if colon < 0 else body.substr(0, colon)
		var path: String = "" if colon < 0 else body.substr(colon + 1)
		return "%s%s%s%s " % [
			_paint(host, "host"), _paint(":", "dim") if colon >= 0 else "", _paint(path, "path"),
			_paint(sigil, "root" if sigil == "#" else "dim"),
		]
	if text.ends_with("> "):
		return "%s%s " % [_paint(text.substr(0, text.length() - 2), "host"), _paint(">", "dim")]
	return _paint(text, "warn")


## Введённая команда: программа — своим цветом, ключи (-x) приглушённо, пути — цветом путей.
func command(line: String) -> String:
	var out: String = ""
	var word: String = ""
	var first: bool = true
	for i: int in line.length() + 1:
		var ch: String = line[i] if i < line.length() else " "
		if ch == " ":
			if not word.is_empty():
				out += _paint(word, _word_role(word, first))
				first = false
				word = ""
			if i < line.length():
				out += " "
		else:
			word += ch
	return out


## Строка ответа терминала целиком одним цветом по смыслу: ошибка, успех, предупреждение, справка.
func output(line: String) -> String:
	return _paint(line, role_of(line))


## Смысл строки ответа: "error", "ok", "warn", "dim", "path" (каталог в списке) или "text".
static func role_of(line: String) -> String:
	var low: String = line.to_lower()
	# Каталог в выводе ls — одно слово с «/» на конце: цветом путей, как в настоящей консоли.
	if line.ends_with("/") and not line.strip_edges().contains(" "):
		return "path"
	for mark: String in ERROR_MARKS:
		if low.contains(mark):
			return "error"
	for mark: String in WARN_MARKS:
		if low.contains(mark):
			return "warn"
	for mark: String in OK_MARKS:
		if low.contains(mark):
			return "ok"
	for mark: String in DIM_MARKS:
		if low.begins_with(mark):
			return "dim"
	return "text"


static func _word_role(word: String, first: bool) -> String:
	if first:
		return "command"
	if word.begins_with("-"):
		return "flag"
	if word.contains("/") or word.begins_with("~") or word.contains("."):
		return "path"
	return "text"


## Цветной кусок текста; квадратные скобки экранируются — вывод терминала не превратится в теги.
func _paint(text: String, role: String) -> String:
	if text.is_empty():
		return ""
	return "[color=#%s]%s[/color]" % [(colors.get(role, colors["text"]) as Color).to_html(false), escape(text)]


static func escape(text: String) -> String:
	return text.replace("[", "[lb]")
