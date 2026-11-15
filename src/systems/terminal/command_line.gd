class_name CommandLine
extends RefCounted
## Разбор строки терминала на слова (docs/tech/terminal-spec.md, «Разбор строки»).
##
## Слова разделены пробелами; путь с пробелами берётся в двойные кавычки:
## `cat "/home/мои файлы/заметка.txt"`. Незакрытая кавычка не ошибка — слово просто
## идёт до конца строки: игрок ещё печатает.


static func parse(line: String) -> PackedStringArray:
	var words: PackedStringArray = []
	var current: String = ""
	var in_quotes: bool = false
	# Отдельный признак: пустые кавычки "" — тоже слово, пусть и пустое.
	var has_word: bool = false

	for index: int in line.length():
		var symbol: String = line[index]
		if symbol == "\"":
			in_quotes = not in_quotes
			has_word = true
		elif (symbol == " " or symbol == "\t") and not in_quotes:
			if has_word:
				words.append(current)
				current = ""
				has_word = false
		else:
			current += symbol
			has_word = true

	if has_word:
		words.append(current)
	return words
