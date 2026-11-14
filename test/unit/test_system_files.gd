extends GutTest
## SystemFiles: состояние своего ПК (docs/gameplay/hacking.md).

var pc: Filesystem


func before_each() -> void:
	GameState.reset()
	pc = Filesystem.new("node_home_pc", {
		"/home/readme.txt": {"text": "привет"},
		"/sys/x-server.sys": {"system": true},
		"/sys/net.sys": {"system": true},
		"/sys/theme.sys": {"system": true, "file_id": "theme_default"},
		"/log/access.log": {"log": true},
	})


# --- Что работает ------------------------------------------------------------

func test_healthy_pc() -> void:
	assert_true(SystemFiles.has_desktop(pc))
	assert_true(SystemFiles.has_network(pc))
	assert_false(SystemFiles.is_broken(pc))
	assert_eq(SystemFiles.boot_errors(pc).size(), 0, "жаловаться не на что")


func test_deleting_x_server_breaks_the_desktop() -> void:
	pc.erase_file(SystemFiles.FILE_X_SERVER)
	assert_true(SystemFiles.is_broken(pc))
	assert_false(SystemFiles.has_desktop(pc))
	assert_true(SystemFiles.has_network(pc), "сеть не при чём")

	var errors: PackedStringArray = SystemFiles.boot_errors(pc)
	assert_string_contains("\n".join(errors), "x-server.sys")
	assert_string_contains("\n".join(errors), "терминал доступен", "игрок должен видеть выход")


func test_deleting_net_keeps_the_desktop() -> void:
	# Машина работает, просто локально: это не «сломанный ПК».
	pc.erase_file(SystemFiles.FILE_NET)
	assert_false(SystemFiles.has_network(pc))
	assert_true(SystemFiles.has_desktop(pc))
	assert_false(SystemFiles.is_broken(pc))


func test_deleting_theme_breaks_nothing() -> void:
	# Безопасный эксперимент с системным файлом: оформление станет стандартным, и всё.
	pc.erase_file(SystemFiles.FILE_THEME)
	assert_false(SystemFiles.is_broken(pc))
	assert_eq(SystemFiles.missing(pc).size(), 0, "тема не входит в системный минимум")
	assert_eq(SystemFiles.theme_in_system(pc), "", "нет файла — стандартная тема")


func test_everything_missing() -> void:
	pc.remove("/sys", "*", true, true)
	assert_true(SystemFiles.is_broken(pc))
	assert_eq(SystemFiles.missing(pc).size(), 2, "x-server и net")


# --- Тема --------------------------------------------------------------------

func test_theme_applies_only_after_reboot() -> void:
	GameState.set_var(SystemFiles.VAR_APPLIED_THEME, "theme_default")
	pc.put_file(SystemFiles.FILE_THEME, {"system": true, "file_id": "theme_corp"})

	assert_eq(SystemFiles.applied_theme(), "theme_default", "пока применена старая")
	assert_true(SystemFiles.theme_pending(pc), "новая лежит в системе и ждёт")

	var result: Dictionary = SystemFiles.reboot(pc)
	assert_eq(SystemFiles.applied_theme(), "theme_corp")
	assert_true(bool(result["theme_changed"]))
	assert_false(SystemFiles.theme_pending(pc))


func test_reboot_without_changes_reports_nothing_new() -> void:
	SystemFiles.reboot(pc)
	var again: Dictionary = SystemFiles.reboot(pc)
	assert_false(bool(again["theme_changed"]))


func test_stolen_theme_keeps_its_id() -> void:
	# Темы — добыча: у разных машин файл называется одинаково, но это разные file_id.
	var target := Filesystem.new("node_office_server", {
		"/sys/theme.sys": {"system": true, "file_id": "theme_corp"},
	})
	# Своя тема на месте, значит сначала спросят — и только после ответа заменят.
	assert_true(
		target.copy_to(pc, "/sys", "theme.sys", SystemFiles.FILE_THEME, true).needs_confirm(),
		"молча свою тему не теряем"
	)
	assert_true(target.copy_to(pc, "/sys", "theme.sys", SystemFiles.FILE_THEME, true, true).is_ok())
	assert_eq(SystemFiles.theme_in_system(pc), "theme_corp", "id переехал с копией")


func test_deleting_own_theme_asks_first() -> void:
	# Та же потеря, что при копировании чужой темы поверх своей: спрашиваем и здесь.
	assert_true(pc.remove("/sys", "theme.sys", true).needs_confirm())
	assert_true(pc.has_file(SystemFiles.FILE_THEME), "коллекция цела, пока не ответил")


func test_reboot_reports_state() -> void:
	pc.erase_file(SystemFiles.FILE_X_SERVER)
	var result: Dictionary = SystemFiles.reboot(pc)
	assert_false(bool(result["desktop"]), "стол не собрался")
	assert_true(bool(result["network"]))
	assert_gt((result["errors"] as PackedStringArray).size(), 0)


# --- Восстановление ----------------------------------------------------------

func test_flashdrive_restores_system_files() -> void:
	pc.remove("/sys", "*", true, true)
	var restored: PackedStringArray = SystemFiles.restore_system(pc)
	assert_eq(restored.size(), 2)
	assert_false(SystemFiles.is_broken(pc), "ПК снова загружается")
	assert_true(SystemFiles.has_network(pc))


func test_flashdrive_does_not_touch_user_files() -> void:
	# Чинит только /sys — это её обещание игроку (docs/gameplay/hacking.md).
	pc.remove("/home", "readme.txt")
	pc.erase_file(SystemFiles.FILE_X_SERVER)
	SystemFiles.restore_system(pc)
	assert_false(pc.has_file("/home/readme.txt"), "пользовательские файлы не возвращаются")
	assert_true(pc.has_file("/sys/x-server.sys"))


func test_flashdrive_does_nothing_when_all_is_well() -> void:
	assert_eq(SystemFiles.restore_system(pc).size(), 0)


func test_flashdrive_does_not_restore_theme() -> void:
	# Тема — косметика: флешка ставит обычную ОС, а не возвращает украденное оформление.
	pc.erase_file(SystemFiles.FILE_THEME)
	SystemFiles.restore_system(pc)
	assert_false(pc.has_file(SystemFiles.FILE_THEME))
