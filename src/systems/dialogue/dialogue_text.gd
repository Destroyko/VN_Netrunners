class_name DialogueText
extends RefCounted
## Текст реплики для экрана (docs/tech/dialogue-format.md): подстановка имён `{name_*}` и
## термины `[[id]]` / `[[id|текст]]` — выделены цветом и показывают подсказку из глоссария.
##
## Чистые правила: на вход строка из данных, на выход BBCode для RichTextLabel. Ссылка термина —
## `[url=term:<id>]`, окно по наведению показывает `hint(id)`.

const TERM_COLOR: String = "#9fd4ff"
const TERM_PREFIX: String = "term:"


## Подставить имена из `data/names.json`. Неизвестная подстановка остаётся как есть — видно ошибку.
static func with_names(text: String) -> String:
	var result: String = text
	var names: Dictionary = DataLoader.names()
	for key: String in names.keys():
		if key.begins_with("_"):
			continue
		result = result.replace("{%s}" % key, str(names[key]))
	return result


## Текст для окна: имена подставлены, термины — цветные ссылки, остальной BBCode экранирован.
## `term_color` — цвет терминов; окно передаёт цвет роли своей темы.
static func to_bbcode(text: String, term_color: String = TERM_COLOR) -> String:
	var source: String = with_names(text).replace("[", "\u0001").replace("]", "\u0002")
	var out: String = ""
	var rest: String = source
	while true:
		var open: int = rest.find("\u0001\u0001")
		if open < 0:
			break
		var close: int = rest.find("\u0002\u0002", open)
		if close < 0:
			break
		out += _escape(rest.substr(0, open))
		var inner: String = rest.substr(open + 2, close - open - 2)
		var parts: PackedStringArray = inner.split("|", true, 1)
		var id: String = parts[0].strip_edges()
		var label: String = parts[1] if parts.size() > 1 else title(id)
		out += "[color=%s][url=%s%s]%s[/url][/color]" % [term_color, TERM_PREFIX, id, _escape(label)]
		rest = rest.substr(close + 2)
	return out + _escape(rest)


## Текст без разметки — для журнала и тестов: «[[passhound]]» → «passhound».
static func plain(text: String) -> String:
	var source: String = with_names(text)
	var regex := RegEx.create_from_string("\\[\\[([^\\]|]+)(\\|([^\\]]*))?\\]\\]")
	var out: String = ""
	var from: int = 0
	for m: RegExMatch in regex.search_all(source):
		out += source.substr(from, m.get_start() - from)
		out += m.get_string(3) if m.get_string(2) != "" else title(m.get_string(1).strip_edges())
		from = m.get_end()
	return out + source.substr(from)


static func title(id: String) -> String:
	var entry: Dictionary = DataLoader.glossary().get(id, {}) as Dictionary
	return with_names(str(entry.get("title", id)))


static func hint(id: String) -> String:
	var entry: Dictionary = DataLoader.glossary().get(id, {}) as Dictionary
	return with_names(str(entry.get("hint", "")))


## Все термины в тексте — для валидатора.
static func terms(text: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var regex := RegEx.create_from_string("\\[\\[([^\\]|]+)(\\|[^\\]]*)?\\]\\]")
	for m: RegExMatch in regex.search_all(text):
		found.append(m.get_string(1).strip_edges())
	return found


## Квадратные скобки в обычном тексте — не разметка: показываем их как есть.
static func _escape(text: String) -> String:
	return text.replace("\u0001", "[lb]").replace("\u0002", "[rb]")
