class_name PuzzleValidator
extends RefCounted
## Проверка данных головоломок: словарь `data/puzzles/words_ru.json` и параметры уровней
## в `balance.json` (docs/tech/puzzles-spec.md).
##
## Вынесено из Validator отдельным файлом: один файл — одна ответственность.

const TIERS: PackedStringArray = ["common", "regular", "rare"]
## Русские буквы без ё: правило словаря — ё в словах нет (puzzles-spec.md).
const ALPHABET: String = "абвгдежзийклмнопрстуфхцчшщъыьэюя"

var errors: PackedStringArray = []
var warnings: PackedStringArray = []


func validate(words: Dictionary, balance: Dictionary) -> void:
	errors.clear()
	warnings.clear()
	if words.is_empty():
		errors.append("data/puzzles/words_ru.json не найден или пустой: «пароль» нечем загадывать")
		return

	var seen: Dictionary = {}
	for key: String in words.keys():
		if key.begins_with("_"):
			continue
		if not key.is_valid_int():
			errors.append("словарь: ключ '%s' должен быть длиной слова (число)" % key)
			continue
		_check_block(int(key), words[key] as Dictionary, seen)
	_check_levels(words, balance)


func _check_block(length: int, block: Dictionary, seen: Dictionary) -> void:
	for tier: String in block.keys():
		if not TIERS.has(tier):
			errors.append("словарь, длина %d: неизвестная градация '%s' (есть: %s)" % [length, tier, ", ".join(TIERS)])
			continue
		for word_variant: Variant in block[tier] as Array:
			var word: String = str(word_variant)
			var where: String = "словарь, длина %d, '%s'" % [length, word]
			if word.length() != length:
				errors.append("%s: длина %d, а нужна %d" % [where, word.length(), length])
			for index: int in word.length():
				if not ALPHABET.contains(word[index]):
					errors.append("%s: недопустимая буква '%s' (только а–я, без ё и дефисов)" % [where, word[index]])
					break
			var key: String = "%d:%s" % [length, word]
			if seen.has(key):
				errors.append("%s: повтор (уже есть в градации '%s')" % [where, seen[key]])
			seen[key] = tier


## Хватает ли слов для уровней: диапазон кандидатов не должен быть недостижим по определению.
func _check_levels(words: Dictionary, balance: Dictionary) -> void:
	var puzzles: Dictionary = balance.get("puzzles", {}) as Dictionary
	var levels: Dictionary = (puzzles.get("password", {}) as Dictionary).get("levels", {}) as Dictionary
	for level: String in levels.keys():
		var config: Dictionary = levels[level] as Dictionary
		var length: int = int(config.get("length", 0))
		var block: Dictionary = words.get(str(length), {}) as Dictionary
		var total: int = 0
		for tier: String in TIERS:
			total += (block.get(tier, []) as Array).size()
		var answers: int = 0
		for tier: Variant in config.get("tiers", []) as Array:
			answers += (block.get(str(tier), []) as Array).size()

		if answers == 0:
			errors.append("«пароль», уровень %s: в словаре нет слов длины %d из нужных градаций" % [level, length])
			continue
		var bounds: Array = config.get("candidates", [0, 0]) as Array
		# Без открытых букв кандидатов ровно столько, сколько слов: меньше нижней границы быть не может.
		if int(config.get("known", 0)) == 0 and total < int(bounds[0]):
			warnings.append(
				"«пароль», уровень %s: слов длины %d всего %d, а диапазон кандидатов начинается с %d"
				% [level, length, total, int(bounds[0])]
			)
