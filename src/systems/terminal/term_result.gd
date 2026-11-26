class_name TermResult
extends RefCounted
## Что терминал отвечает на одну команду: строки для вывода и, если нужно, просьба
## интерфейсу. Сам терминал ничего не рисует — он чистая логика (CLAUDE.md).

## Строки для вывода по порядку.
var lines: PackedStringArray = []
## Сколько игровых минут потрачено: терминал уже сдвинул часы, это для показа и тестов.
var minutes: int = 0
## Вопрос «y/n», на который ждём ответ. Пусто — вопроса нет.
var question: String = ""
## Просьба интерфейсу, не текст. Виды:
##   {"type": "progress", "title": ...} — показать полоску прогресса программы;
##   {"type": "puzzle", "kind": "password"|"matrix", "node": ..., "service": ...,
##    "difficulty": ..., "alert": ...} — открыть головоломку, ответ вернуть через
##    Terminal.finish_puzzle().
var request: Dictionary = {}
## Очистить экран (`clear`).
var clear_screen: bool = false


## Цвет отдельных строк, когда смысл не виден из текста (закрытая папка в `ls`): номер → роль.
var roles: Dictionary = {}


## Строка с заданной ролью: "error", "ok", "warn", "dim", "path".
func add_as(text: String, role: String) -> void:
	add(text)
	roles[lines.size() - 1] = role


func role_at(index: int) -> String:
	return str(roles.get(index, ""))


func add(text: String) -> void:
	lines.append(text)


func add_all(items: PackedStringArray) -> void:
	lines.append_array(items)


func asks() -> bool:
	return not question.is_empty()


func text() -> String:
	return "\n".join(lines)
