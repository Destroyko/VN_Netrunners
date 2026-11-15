class_name BugReport
extends RefCounted
## Правила журнала сессии и снимков «здесь баг» (docs/tech/testing.md, «Отчёт об ошибке»):
## как называются папки и как выглядят строки журнала. Чистые функции — проверяются тестами,
## а файлы пишет `SessionLog`.

## Папка внутри проекта: так снимок сразу виден тому, кто чинит, без копирования в чат.
const PROJECT_DIR: String = "res://bugreports"
## Запасная папка, если проект только для чтения (экспортированная сборка).
const USER_DIR: String = "user://bugreports"
const SESSIONS_SUBDIR: String = "sessions"


## Имя по времени: «2026-11-15_21-04-37». Сортировка по имени = сортировка по времени,
## поэтому последний снимок — последний по алфавиту.
static func stamp(time: Dictionary) -> String:
	return "%04d-%02d-%02d_%02d-%02d-%02d" % [
		int(time.get("year", 0)), int(time.get("month", 0)), int(time.get("day", 0)),
		int(time.get("hour", 0)), int(time.get("minute", 0)), int(time.get("second", 0)),
	]


## Строка журнала: реальное время от запуска, игровое время, вид записи, текст.
## «+0012.345 [д1 10:04] term   home:/home$ scan»
static func line(elapsed_ms: int, game_day: int, game_minute: int, kind: String, text: String) -> String:
	return "+%08.3f [д%d %02d:%02d] %-7s %s" % [
		elapsed_ms / 1000.0, game_day, game_minute / 60, game_minute % 60, kind, text,
	]


## Аргументы сигнала в одну строку: словари и массивы — коротким JSON.
static func describe_args(args: Array) -> String:
	var parts: PackedStringArray = []
	for value: Variant in args:
		if value is Dictionary or value is Array:
			parts.append(JSON.stringify(value))
		else:
			parts.append(str(value))
	return ", ".join(parts)


## Последняя папка снимка среди имён (без журналов сессий); пусто — снимков нет.
static func latest(names: PackedStringArray) -> String:
	var best: String = ""
	for name: String in names:
		if name == SESSIONS_SUBDIR or name.begins_with("."):
			continue
		if name > best:
			best = name
	return best
