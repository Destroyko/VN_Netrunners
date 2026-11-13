extends GutTest
## Filesystem: операции с файлами узла (docs/tech/terminal-spec.md).

var fs: Filesystem


func before_each() -> void:
	fs = Filesystem.new("node_test", {
		"/home/readme.txt": {"text": "привет"},
		"/home/mail/sosedka.txt": {"text": "адрес для тренировки"},
		"/home/photos/kot.jpg": {"size_kb": 1200},
		"/home/buh/dolgi.csv": {"size_kb": 120, "file_id": "file_evidence_dolgi"},
		"/sys/x-server.sys": {"system": true},
		"/prog/nightly.sh": {"text": "выгрузка"},
		"/log/access.log": {"log": true},
		"/log/auth.log": {"log": true},
	})


# --- Чтение ------------------------------------------------------------------

func test_cat_returns_text() -> void:
	var result: FsResult = fs.read("/home/readme.txt")
	assert_true(result.is_ok())
	assert_eq(result.text, "привет")


func test_cat_of_binary_says_what_it_is() -> void:
	# Картинку или базу читать нечего, но это не ошибка: игрок видит, что это за файл.
	var result: FsResult = fs.read("/home/photos/kot.jpg")
	assert_true(result.is_ok())
	assert_string_contains(result.text, "1200")


func test_cat_missing_file() -> void:
	var result: FsResult = fs.read("/home/net-takogo.txt")
	assert_false(result.is_ok())
	assert_eq(result.code, FsResult.Code.NOT_FOUND)
	assert_string_contains(result.message(), "нет такого файла")


func test_cat_of_directory_is_not_found_but_explains() -> void:
	var result: FsResult = fs.read("/home/mail")
	assert_eq(result.code, FsResult.Code.IS_A_DIR)


func test_guest_cannot_read_system_files() -> void:
	var denied: FsResult = fs.read("/sys/x-server.sys", false)
	assert_eq(denied.code, FsResult.Code.NO_PERMISSION)
	assert_string_contains(denied.message(), "администратора")
	assert_true(fs.read("/sys/x-server.sys", true).is_ok(), "администратору можно")


func test_guest_can_read_logs() -> void:
	# Намеренно: rootstep выдаёт группа, а чистить за собой надо с первого дня.
	assert_true(fs.read("/log/access.log", false).is_ok())


# --- ls ----------------------------------------------------------------------

func test_ls_root_shows_four_roots() -> void:
	var entries: Array[Dictionary] = fs.list("/")
	assert_eq(entries.size(), 4)
	var names: Array = []
	for entry: Dictionary in entries:
		names.append(entry["name"])
	assert_eq(names, ["home", "log", "sys", "prog"])


func test_ls_marks_locked_for_guest() -> void:
	for entry: Dictionary in fs.list("/", false):
		var expected: bool = str(entry["name"]) in ["sys", "prog"]
		assert_eq(bool(entry["locked"]), expected, "закрыт по правам: %s" % entry["name"])
	for entry: Dictionary in fs.list("/", true):
		assert_false(bool(entry["locked"]), "администратору открыто всё")


func test_ls_mixes_dirs_and_files() -> void:
	var entries: Array[Dictionary] = fs.list("/home")
	var names: Array = []
	for entry: Dictionary in entries:
		names.append(entry["name"])
	# Каталоги сверху по алфавиту, потом файлы.
	assert_eq(names, ["buh", "mail", "photos", "readme.txt"])
	assert_true(bool(entries[0]["is_dir"]))
	assert_false(bool(entries[3]["is_dir"]))


func test_ls_shows_system_flag() -> void:
	var entries: Array[Dictionary] = fs.list("/sys", true)
	assert_eq(entries.size(), 1)
	assert_true(bool(entries[0]["system"]), "системный файл помечен")


# --- cd ----------------------------------------------------------------------

func test_cd_into_dir_and_up() -> void:
	var into: FsResult = fs.change_dir("/home", "mail")
	assert_true(into.is_ok())
	assert_eq(into.path, "/home/mail")
	assert_eq(fs.change_dir("/home/mail", "..").path, "/home")


func test_cd_into_file_fails() -> void:
	assert_eq(fs.change_dir("/home", "readme.txt").code, FsResult.Code.NOT_A_DIR)


func test_cd_into_missing_dir_fails() -> void:
	assert_eq(fs.change_dir("/home", "net-takogo").code, FsResult.Code.NOT_FOUND)


func test_cd_outside_roots_fails() -> void:
	assert_eq(fs.change_dir("/home", "/root").code, FsResult.Code.BAD_PATH)


func test_guest_cannot_enter_sys() -> void:
	assert_eq(fs.change_dir("/", "sys", false).code, FsResult.Code.NO_PERMISSION)
	assert_true(fs.change_dir("/", "sys", true).is_ok())


# --- rm ----------------------------------------------------------------------

func test_rm_deletes_file() -> void:
	var result: FsResult = fs.remove("/home", "readme.txt")
	assert_true(result.is_ok())
	assert_false(fs.has_file("/home/readme.txt"))


func test_rm_system_file_is_allowed_without_warning() -> void:
	# Обещанная свобода: системный файл удаляется как любой другой (docs/gameplay/hacking.md).
	assert_true(fs.remove("/sys", "x-server.sys", true).is_ok())
	assert_false(fs.has_file("/sys/x-server.sys"), "ПК теперь сломан — так и задумано")


func test_rm_mask_clears_logs() -> void:
	var result: FsResult = fs.remove("/log", "*")
	assert_true(result.is_ok())
	assert_eq(result.paths.size(), 2, "удалились оба лога")
	assert_false(fs.has_file("/log/access.log"))
	assert_false(fs.has_file("/log/auth.log"))


func test_rm_mask_by_extension() -> void:
	fs.copy_to(fs, "/home", "readme.txt", "/log/readme.txt")
	var result: FsResult = fs.remove("/log", "*.log")
	assert_eq(result.paths.size(), 2, "только логи")
	assert_true(fs.has_file("/log/readme.txt"), "лишнее не тронуто")


func test_rm_mask_without_matches_reports_not_found() -> void:
	assert_eq(fs.remove("/home", "*.exe").code, FsResult.Code.NOT_FOUND)


func test_rm_does_not_touch_subdirectories() -> void:
	fs.remove("/home", "*")
	assert_false(fs.has_file("/home/readme.txt"), "файл в каталоге удалён")
	assert_true(fs.has_file("/home/mail/sosedka.txt"), "файл в подкаталоге цел")


func test_guest_cannot_delete_system_files() -> void:
	assert_eq(fs.remove("/sys", "x-server.sys", false).code, FsResult.Code.NO_PERMISSION)
	assert_true(fs.has_file("/sys/x-server.sys"))


# --- cp и mv -----------------------------------------------------------------

func test_copy_to_another_machine_keeps_file_id() -> void:
	# Главное в копировании: file_id переезжает, по нему квест найдёт файл у игрока.
	var home := Filesystem.new("node_home_pc", {"/home/dump/readme.txt": {"text": "я"}})
	var result: FsResult = fs.copy_to(home, "/home/buh", "dolgi.csv", "/home/dump")
	assert_true(result.is_ok(), result.message())
	assert_true(home.has_file("/home/dump/dolgi.csv"), "лёг внутрь каталога под своим именем")
	assert_true(home.has_file_id("file_evidence_dolgi"), "file_id переехал")
	assert_true(fs.has_file("/home/buh/dolgi.csv"), "исходник остался на месте")


func test_copy_under_new_name() -> void:
	var home := Filesystem.new("node_home_pc", {})
	assert_true(fs.copy_to(home, "/home/buh", "dolgi.csv", "/home/ulika.csv").is_ok())
	assert_true(home.has_file("/home/ulika.csv"))
	assert_true(home.has_file_id("file_evidence_dolgi"), "переименование не теряет id")


func test_copy_is_independent_from_source() -> void:
	var home := Filesystem.new("node_home_pc", {})
	fs.copy_to(home, "/home", "readme.txt", "/home/kopiya.txt")
	fs.remove("/home", "readme.txt")
	assert_true(home.has_file("/home/kopiya.txt"), "копия живёт своей жизнью")


func test_copy_over_existing_file_fails() -> void:
	var home := Filesystem.new("node_home_pc", {"/home/a.txt": {"text": "занято"}})
	assert_eq(
		fs.copy_to(home, "/home", "readme.txt", "/home/a.txt").code,
		FsResult.Code.ALREADY_EXISTS
	)


func test_guest_cannot_copy_from_sys() -> void:
	var home := Filesystem.new("node_home_pc", {})
	assert_eq(
		fs.copy_to(home, "/sys", "x-server.sys", "/home/x.sys", false).code,
		FsResult.Code.NO_PERMISSION
	)


func test_move_renames() -> void:
	assert_true(fs.move("/home", "readme.txt", "privet.txt").is_ok())
	assert_false(fs.has_file("/home/readme.txt"))
	assert_true(fs.has_file("/home/privet.txt"))


func test_move_into_directory() -> void:
	assert_true(fs.move("/home", "readme.txt", "mail").is_ok())
	assert_true(fs.has_file("/home/mail/readme.txt"))


func test_move_missing_file_fails() -> void:
	assert_eq(fs.move("/home", "net-takogo.txt", "a.txt").code, FsResult.Code.NOT_FOUND)


# --- mkdir -------------------------------------------------------------------

func test_mkdir_creates_empty_dir() -> void:
	assert_true(fs.make_dir("/home", "uliki").is_ok())
	assert_true(fs.has_dir("/home/uliki"), "пустой каталог не исчезает")


func test_mkdir_only_in_home() -> void:
	# Игрок раскладывает свою добычу, а не чинит чужую систему.
	assert_eq(fs.make_dir("/sys", "moe", true).code, FsResult.Code.NOT_WRITABLE)
	assert_eq(fs.make_dir("/log", "moe").code, FsResult.Code.NOT_WRITABLE)


func test_mkdir_twice_fails() -> void:
	fs.make_dir("/home", "dump")
	assert_eq(fs.make_dir("/home", "dump").code, FsResult.Code.ALREADY_EXISTS)


func test_mkdir_then_move_into_it() -> void:
	fs.make_dir("/home", "dump")
	assert_true(fs.move("/home", "readme.txt", "dump").is_ok())
	assert_true(fs.has_file("/home/dump/readme.txt"))


# --- Состояние ---------------------------------------------------------------

func test_from_node_copies_data() -> void:
	# Правки игрока не должны менять содержимое data/nodes: DataLoader кэширует разбор.
	var node: Dictionary = {"id": "node_x", "files": {"/home/a.txt": {"text": "из данных"}}}
	var built: Filesystem = Filesystem.from_node(node)
	built.remove("/home", "a.txt")
	assert_true((node["files"] as Dictionary).has("/home/a.txt"), "исходные данные целы")


func test_save_round_trip() -> void:
	fs.remove("/home", "readme.txt")
	fs.make_dir("/home", "dump")
	var saved: Dictionary = fs.to_dict()

	var restored: Filesystem = Filesystem.from_dict("node_test", saved.duplicate(true))
	assert_false(restored.has_file("/home/readme.txt"), "удаление сохранилось")
	assert_true(restored.has_dir("/home/dump"), "созданный каталог сохранился")
	assert_true(restored.has_file("/home/mail/sosedka.txt"), "остальное на месте")


func test_paths_are_sorted() -> void:
	var all: PackedStringArray = fs.paths()
	var sorted: PackedStringArray = all.duplicate()
	sorted.sort()
	assert_eq(all, sorted, "порядок устойчивый — иначе тесты и вывод ls прыгают")
