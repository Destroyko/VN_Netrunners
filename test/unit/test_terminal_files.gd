extends "res://test/unit/terminal_fixture.gd"
## Terminal: команды файлов, вопросы «y/n», время и перезагрузка (docs/tech/terminal-spec.md).


# --- Разбор и служебные команды ----------------------------------------------

func test_empty_line_does_nothing() -> void:
	assert_eq(run(""), "")
	assert_eq(run("   "), "")
	assert_eq(t.history().size(), 0, "пустое в историю не идёт")


func test_unknown_command_is_reported_without_hints() -> void:
	assert_eq(run("foo"), "команда не найдена: foo")


func test_command_case_is_ignored() -> void:
	assert_eq(run("PWD"), "/home")


func test_help_lists_commands() -> void:
	var text: String = run("help")
	for name: String in ["ls", "cat", "cp", "put", "rm", "connect", "dc", "reboot"]:
		assert_string_contains(text, name)
	assert_false(text.contains("passhound"), "программ нет — в справке их нет")


func test_help_lists_installed_programs() -> void:
	GameState.set_flag(Programs.flag_for("passhound"))
	assert_string_contains(run("help"), "passhound")


func test_help_about_one_command() -> void:
	var text: String = run("help cat")
	assert_string_contains(text, "cat <файл>")
	assert_string_contains(run("help foo"), "команда не найдена")


func test_clear_asks_the_interface_to_clear() -> void:
	run("clear")
	assert_true(last.clear_screen)


func test_history_remembers_commands_not_answers() -> void:
	run("pwd")
	run("ls")
	assert_string_contains(run("history"), "pwd")
	assert_eq(t.history().size(), 3, "history тоже команда")


func test_history_is_limited_to_fifty() -> void:
	for index: int in 60:
		run("pwd")
	assert_eq(t.history().size(), Terminal.HISTORY_LIMIT)


func test_prompt_at_home() -> void:
	assert_eq(t.prompt(), "home:/home$ ")


# --- ls, cd, pwd: бесплатные ---------------------------------------------------

func test_ls_shows_dirs_first_with_slash() -> void:
	var lines: PackedStringArray = run("ls").split("\n")
	assert_true(lines[0].begins_with("ПРАВА") and lines[0].ends_with("ИМЯ"), "таблица, как ls -l")
	assert_true(lines[1].begins_with("drwx") and lines[1].ends_with("/"), "папки первыми, со слешем")
	assert_true(Array(lines).any(func(l: String) -> bool: return l.ends_with("  mail/")))
	assert_true(Array(lines).any(func(l: String) -> bool: return l.ends_with("readme.txt") and l.begins_with("-rw-r--r--") and l.contains("1 КБ")), str(lines))


func test_navigation_is_free_of_time() -> void:
	var before: int = minute()
	run("cd mail")
	run("ls")
	run("pwd")
	assert_eq(minute(), before, "pwd, ls и cd времени не стоят")


func test_cd_moves_and_prompt_follows() -> void:
	run("cd mail")
	assert_eq(run("pwd"), "/home/mail")
	assert_eq(t.prompt(), "home:/home/mail$ ")
	run("cd ..")
	assert_eq(run("pwd"), "/home")
	run("cd /")
	assert_eq(run("pwd"), "/")


func test_cd_to_missing_dir() -> void:
	assert_string_contains(run("cd net-takogo"), "файл не найден")


func test_cd_into_a_file() -> void:
	assert_string_contains(run("cd readme.txt"), "это не каталог")


func test_root_listing_shows_four_roots() -> void:
	var text: String = run("ls /")
	for root: String in ["home/", "log/", "sys/", "prog/"]:
		assert_string_contains(text, root)
	assert_string_contains(text, "[sys]", "системный каталог помечен")


func test_own_pc_gives_full_rights() -> void:
	# Примеры из спецификации: `home:/sys$ rm x-server.sys` — на своей машине права полные.
	run("cd /sys")
	assert_eq(run("pwd"), "/sys")
	assert_string_contains(run("ls"), "x-server.sys")
	assert_eq(t.prompt(), "home:/sys$ ", "дома всегда $")


func test_ls_marks_system_files() -> void:
	run("cd /sys")
	assert_string_contains(run("ls"), "[sys]")


# --- cat ---------------------------------------------------------------------

func test_cat_prints_text_and_costs_a_minute() -> void:
	var before: int = minute()
	assert_string_contains(run("cat readme.txt"), "Старая ОС")
	assert_eq(minute(), before + 1)
	assert_eq(last.minutes, 1)


func test_cat_emits_file_read() -> void:
	run("cat readme.txt")
	assert_signal_emitted(EventBus, "file_read")


func test_cat_of_missing_file() -> void:
	var before: int = minute()
	assert_string_contains(run("cat net.txt"), "файл не найден")
	assert_eq(minute(), before, "ошибка времени не стоит")


func test_cat_without_argument_shows_usage() -> void:
	assert_string_contains(run("cat"), "help cat")


func test_quoted_path_with_spaces() -> void:
	t.home_fs().put_file("/home/мои файлы/заметка.txt", {"text": "секрет"})
	assert_eq(run("cat \"/home/мои файлы/заметка.txt\""), "секрет")


# --- cp, mv, mkdir дома -------------------------------------------------------

func test_cp_copies_at_home() -> void:
	assert_string_contains(run("cp readme.txt copy.txt"), "copy.txt", "копия — строкой отчёта")
	assert_true(t.home_fs().has_file("/home/copy.txt"))
	assert_true(t.home_fs().has_file("/home/readme.txt"), "оригинал на месте")


func test_cp_needs_two_arguments_at_home() -> void:
	assert_string_contains(run("cp readme.txt"), "help cp")


func test_cp_over_existing_asks_first() -> void:
	run("cp readme.txt copy.txt")
	var text: String = run("cp mail/archive.txt copy.txt")
	assert_string_contains(text, "заменить? (y/n)")
	assert_true(last.asks())
	assert_true(t.has_question())
	assert_string_contains(str(t.home_fs().file_data("/home/copy.txt").get("text", "")), "Старая ОС", "пока не ответил — прежний")


func test_answer_yes_replaces() -> void:
	run("cp readme.txt copy.txt")
	run("cp mail/archive.txt copy.txt")
	var text: String = run("y")
	assert_string_contains(text, "заменено")
	assert_false(t.has_question())
	assert_string_contains(str(t.home_fs().file_data("/home/copy.txt").get("text", "")), "Архив писем")


func test_answer_no_cancels() -> void:
	run("cp readme.txt copy.txt")
	run("cp mail/archive.txt copy.txt")
	assert_eq(run("n"), "отменено")
	assert_string_contains(str(t.home_fs().file_data("/home/copy.txt").get("text", "")), "Старая ОС")


func test_russian_answers_work() -> void:
	run("cp readme.txt copy.txt")
	run("cp mail/archive.txt copy.txt")
	run("да")
	assert_string_contains(str(t.home_fs().file_data("/home/copy.txt").get("text", "")), "Архив писем")


func test_another_command_cancels_the_question() -> void:
	run("cp readme.txt copy.txt")
	run("cp mail/archive.txt copy.txt")
	assert_eq(run("pwd"), "/home", "другая команда выполняется как обычно")
	assert_false(t.has_question())
	assert_eq(run("y"), "команда не найдена: y", "старый вопрос уже закрыт")


func test_mv_renames() -> void:
	run("mv readme.txt moe.txt")
	assert_false(t.home_fs().has_file("/home/readme.txt"))
	assert_true(t.home_fs().has_file("/home/moe.txt"))


func test_mkdir_in_home_only() -> void:
	assert_eq(run("mkdir nowaya"), "")
	assert_true(t.home_fs().has_dir("/home/nowaya"))
	assert_string_contains(run("mkdir /sys/moe"), "сюда нельзя писать")


# --- rm и подтверждение для системных файлов ----------------------------------

func test_rm_ordinary_file_does_not_ask() -> void:
	assert_string_contains(run("rm readme.txt"), "удалено: 1")
	assert_false(t.has_question())
	assert_false(t.home_fs().has_file("/home/readme.txt"))
	assert_signal_emitted(EventBus, "file_deleted")


func test_rm_system_file_asks_and_does_not_explain() -> void:
	var text: String = run("rm /sys/x-server.sys")
	assert_eq(text, "вы действительно хотите удалить системный файл x-server.sys? (y/n)")
	assert_true(t.home_fs().has_file("/sys/x-server.sys"), "до ответа файл на месте")


func test_rm_system_file_after_yes_breaks_the_desktop() -> void:
	run("rm /sys/x-server.sys")
	run("y")
	assert_false(t.home_fs().has_file("/sys/x-server.sys"))
	assert_true(SystemFiles.is_broken(t.home_fs()), "ПК сломан — так и задумано")


func test_rm_mask_over_system_files_asks_once() -> void:
	var text: String = run("rm /sys/*")
	assert_string_contains(text, "системные файлы")
	run("y")
	assert_false(t.home_fs().has_file("/sys/net.sys"))


func test_rm_costs_a_minute() -> void:
	var before: int = minute()
	run("rm readme.txt")
	assert_eq(minute(), before + 1)


func test_rm_at_home_leaves_no_log_entries() -> void:
	# Логи своего ПК — для чужой активности; собственные команды в них не пишутся.
	run("rm readme.txt")
	assert_eq(logbook(Network.HOME_ID).count(), 0)


# --- Перезагрузка -----------------------------------------------------------

func test_reboot_applies_the_theme_and_takes_time() -> void:
	t.home_fs().put_file("/sys/theme.sys", {"system": true, "file_id": "theme_corp"})
	var before: int = minute()
	var text: String = run("reboot")
	assert_string_contains(text, "применена тема: theme_corp")
	var pc: Dictionary = DataLoader.balance().get("pc", {}) as Dictionary
	assert_eq(minute(), before + int(pc["shutdown_minutes"]) + int(pc["boot_minutes"]), "выключение + загрузка")


func test_reboot_with_broken_desktop_reports_errors() -> void:
	run("rm /sys/x-server.sys")
	run("y")
	assert_string_contains(run("reboot"), "x-server.sys")


func test_reboot_is_refused_on_a_remote_machine() -> void:
	enter("node_husband_pc")
	Clock.set_time(1, 19 * 60)
	enter("node_husband_pc")
	assert_string_contains(run("reboot"), "только на своём ПК")


# --- Маски и вопрос о замене (плейтест M2) ----------------------------------------

func test_cp_with_mask_copies_all_matching_files() -> void:
	t.home_fs().put_file("/home/src/a.txt", {"text": "a"})
	t.home_fs().put_file("/home/src/b.txt", {"text": "b"})
	t.home_fs().put_file("/home/src/c.jpg", {"size_kb": 3})
	var text: String = run("cp /home/src/*.txt /home/dst")
	assert_true(t.home_fs().has_file("/home/dst/a.txt"))
	assert_true(t.home_fs().has_file("/home/dst/b.txt"))
	assert_false(t.home_fs().has_file("/home/dst/c.jpg"), "маска *.txt — только текстовые")
	assert_string_contains(text, "передано файлов: 2 из 2")


func test_mask_replace_asks_once_for_the_whole_batch() -> void:
	t.home_fs().put_file("/home/src/a.txt", {"text": "a"})
	t.home_fs().put_file("/home/src/b.txt", {"text": "b"})
	run("cp /home/src/*.* /home/dst")
	var text: String = run("cp /home/src/*.* /home/dst")
	assert_eq(text.count("заменить?"), 1, "один вопрос на всю пачку")
	assert_string_contains(run("y"), "заменено")


func test_mask_with_no_matches() -> void:
	assert_string_contains(run("cp /home/*.zzz /home/dst"), "файлы не найдены")


func test_cp_copies_a_whole_folder() -> void:
	t.home_fs().put_file("/home/src/a.txt", {"text": "a"})
	t.home_fs().put_file("/home/src/deep/b.txt", {"text": "b"})
	var text: String = run("cp -r /home/src /home/dst")
	assert_true(t.home_fs().has_file("/home/dst/src/a.txt"), "папка целиком, флаг -r не мешает")
	assert_true(t.home_fs().has_file("/home/dst/src/deep/b.txt"), "и вложенные папки")
	assert_string_contains(text, "передано файлов: 2 из 2")

