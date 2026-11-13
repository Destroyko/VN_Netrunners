extends GutTest
## FsPath: разбор путей. Самая ошибкоёмкая часть файловой системы, поэтому отдельный файл.


func test_normalize_cleans_up_garbage() -> void:
	assert_eq(FsPath.normalize("/home//mail///a.txt"), "/home/mail/a.txt", "двойные слеши")
	assert_eq(FsPath.normalize("/home/./mail/a.txt"), "/home/mail/a.txt", "точка")
	assert_eq(FsPath.normalize("/home/mail/../a.txt"), "/home/a.txt", "две точки")
	assert_eq(FsPath.normalize("/home/"), "/home", "слеш на конце")
	assert_eq(FsPath.normalize("/"), "/", "корень")
	assert_eq(FsPath.normalize(""), "/", "пустой путь — корень")


func test_cannot_climb_above_root() -> void:
	# Как в настоящей оболочке: cd /.. оставляет в корне, а не ломает путь.
	assert_eq(FsPath.normalize("/.."), "/")
	assert_eq(FsPath.normalize("/home/../.."), "/")
	assert_eq(FsPath.normalize("/home/../../sys/x.sys"), "/sys/x.sys")


func test_resolve_uses_current_directory() -> void:
	assert_eq(FsPath.resolve("/home", "mail/a.txt"), "/home/mail/a.txt", "относительный путь")
	assert_eq(FsPath.resolve("/home/mail", ".."), "/home", "на уровень выше")
	assert_eq(FsPath.resolve("/home/mail", "/log"), "/log", "абсолютный заменяет целиком")
	assert_eq(FsPath.resolve("/home", ""), "/home", "пустой аргумент — остаёмся на месте")
	assert_eq(FsPath.resolve("/home", "  a.txt  "), "/home/a.txt", "пробелы обрезаются")


func test_valid_paths_are_inside_four_roots() -> void:
	for path: String in ["/home", "/log/access.log", "/sys/x-server.sys", "/prog/a.sh", "/"]:
		assert_true(FsPath.is_valid(path), "внутри корней: " + path)
	for path: String in ["/root/zametki.txt", "/etc/passwd", "/homework/a.txt"]:
		assert_false(FsPath.is_valid(path), "вне корней: " + path)


func test_root_of() -> void:
	assert_eq(FsPath.root_of("/home/mail/a.txt"), "/home")
	assert_eq(FsPath.root_of("/sys"), "/sys")
	assert_eq(FsPath.root_of("/nope/a.txt"), "", "вне корней — пусто")
	assert_eq(FsPath.root_of("/homework"), "", "похожее имя не считается /home")


func test_admin_roots() -> void:
	assert_true(FsPath.requires_admin("/sys/x-server.sys"))
	assert_true(FsPath.requires_admin("/prog/nightly.sh"))
	assert_false(FsPath.requires_admin("/home/a.txt"))
	assert_false(FsPath.requires_admin("/log/access.log"), "логи доступны гостю — это намеренно")


func test_parent_and_name() -> void:
	assert_eq(FsPath.parent("/home/mail/a.txt"), "/home/mail")
	assert_eq(FsPath.parent("/home"), "/")
	assert_eq(FsPath.parent("/"), "/")
	assert_eq(FsPath.name_of("/home/mail/a.txt"), "a.txt")
	assert_eq(FsPath.name_of("/home"), "home")


func test_direct_child() -> void:
	assert_true(FsPath.is_direct_child("/home/a.txt", "/home"))
	assert_false(FsPath.is_direct_child("/home/mail/a.txt", "/home"), "глубже — не прямой ребёнок")
	assert_true(FsPath.is_direct_child("/home/mail/a.txt", "/home/mail"))


func test_masks() -> void:
	assert_true(FsPath.has_mask("*"))
	assert_true(FsPath.has_mask("*.log"))
	assert_false(FsPath.has_mask("access.log"))
	assert_true(FsPath.matches_mask("access.log", "*"))
	assert_true(FsPath.matches_mask("access.log", "*.log"))
	assert_false(FsPath.matches_mask("access.txt", "*.log"))
	assert_true(FsPath.matches_mask("a.log", "?.log"))
