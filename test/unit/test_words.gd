extends GutTest
## Словарь «пароля» (docs/tech/puzzles-spec.md, «Словарь»).


func before_each() -> void:
	DataLoader.clear_cache()


func test_dictionary_exists_for_both_lengths() -> void:
	assert_gt(Words.all(5).size(), 300, "пять букв: лёгкий и средний уровни")
	assert_gt(Words.all(7).size(), 200, "семь букв: «нетраннер»")


func test_every_word_has_the_right_length_and_alphabet() -> void:
	for length: int in [5, 7]:
		for word: String in Words.all(length):
			assert_eq(word.length(), length, "длина: " + word)
			assert_false(word.contains("ё"), "без ё: " + word)
			assert_eq(word, word.to_lower(), "строчные буквы: " + word)
			assert_true(word.strip_edges() == word and not word.contains(" ") and not word.contains("-"), "без пробелов и дефисов: " + word)


func test_no_word_repeats_across_tiers() -> void:
	for length: int in [5, 7]:
		var seen: Dictionary = {}
		for word: String in Words.all(length):
			assert_false(seen.has(word), "повтор: " + word)
			seen[word] = true


func test_answers_come_from_the_requested_tiers() -> void:
	var common: PackedStringArray = Words.answers(5, ["common"])
	var common_and_regular: PackedStringArray = Words.answers(5, ["common", "regular"])
	assert_lt(common.size(), common_and_regular.size())
	assert_lt(common_and_regular.size(), Words.all(5).size() + 1)
	for word: String in common:
		assert_eq(Words.tier_index(word), 0)


func test_has_and_tier_index() -> void:
	var word: String = Words.answers(5, ["common"])[0]
	assert_true(Words.has(word))
	assert_eq(Words.tier_index(word), 0)
	assert_false(Words.has("ццццц"))
	assert_eq(Words.tier_index("ццццц"), -1)


func test_unknown_length_is_empty() -> void:
	assert_eq(Words.all(3).size(), 0)
