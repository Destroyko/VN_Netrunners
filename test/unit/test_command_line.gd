extends GutTest
## CommandLine: разбор строки терминала (docs/tech/terminal-spec.md, «Разбор строки»).


func test_splits_on_spaces() -> void:
	assert_eq(CommandLine.parse("cat /home/a.txt"), PackedStringArray(["cat", "/home/a.txt"]))


func test_extra_spaces_are_ignored() -> void:
	assert_eq(CommandLine.parse("  cp   a   b  "), PackedStringArray(["cp", "a", "b"]))


func test_tab_separates_like_space() -> void:
	assert_eq(CommandLine.parse("ls\t/home"), PackedStringArray(["ls", "/home"]))


func test_quotes_keep_spaces_in_one_word() -> void:
	var words: PackedStringArray = CommandLine.parse("cat \"/home/мои файлы/заметка.txt\"")
	assert_eq(words.size(), 2)
	assert_eq(words[1], "/home/мои файлы/заметка.txt", "кавычки в слово не попадают")


func test_empty_line_has_no_words() -> void:
	assert_eq(CommandLine.parse("").size(), 0)
	assert_eq(CommandLine.parse("   ").size(), 0)


func test_unclosed_quote_runs_to_the_end() -> void:
	# Игрок ещё печатает: это не ошибка.
	var words: PackedStringArray = CommandLine.parse("cat \"/home/мои фай")
	assert_eq(words.size(), 2)
	assert_eq(words[1], "/home/мои фай")


func test_empty_quotes_make_an_empty_word() -> void:
	assert_eq(CommandLine.parse("mv a \"\""), PackedStringArray(["mv", "a", ""]))


func test_quote_inside_a_word_joins_parts() -> void:
	assert_eq(CommandLine.parse("cd /home/\"мои файлы\""), PackedStringArray(["cd", "/home/мои файлы"]))
