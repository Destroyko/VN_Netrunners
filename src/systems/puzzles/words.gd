class_name Words
extends RefCounted
## Словарь головоломки «пароль» (docs/tech/puzzles-spec.md): русские существительные,
## разложенные по длине и частоте — common / regular / rare. Файл — data/puzzles/words_ru.json.
##
## Загаданное слово берётся из градаций уровня, а проверка ввода — по всем словам этой длины:
## игрок не знает, из какой градации слово, и редкое слово не должно казаться ему опечаткой.

const TIERS: PackedStringArray = ["common", "regular", "rare"]


## Все слова длины `length`, от частых к редким.
static func all(length: int) -> PackedStringArray:
	return answers(length, TIERS)


## Слова длины `length` из указанных градаций.
static func answers(length: int, tiers: Array) -> PackedStringArray:
	var result: PackedStringArray = []
	var block: Dictionary = DataLoader.puzzle_words().get(str(length), {}) as Dictionary
	for tier: String in TIERS:
		if tiers.has(tier):
			for word: Variant in block.get(tier, []) as Array:
				result.append(str(word))
	return result


## Есть ли такое слово в словаре — опечатка не тратит попытку.
static func has(word: String) -> bool:
	return all(word.length()).has(word)


## Номер градации: 0 — частое, 1 — обычное, 2 — редкое; -1, если слова нет в словаре.
static func tier_index(word: String) -> int:
	var block: Dictionary = DataLoader.puzzle_words().get(str(word.length()), {}) as Dictionary
	for index: int in TIERS.size():
		if (block.get(TIERS[index], []) as Array).has(word):
			return index
	return -1
