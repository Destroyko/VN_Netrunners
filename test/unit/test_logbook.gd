extends GutTest
## Logbook: следы игрока — отдельные файлы в /log/auth и /log/access, и их цена в заметности
## (docs/gameplay/heat.md, docs/gameplay/hacking.md).

## Веса задаём явно, чтобы тест не поехал, когда числа в balance.json покрутят на плейтесте.
const WEIGHTS: Dictionary = {
	Logbook.CATEGORY_SESSION: 1,
	Logbook.CATEGORY_ROOT: 4,
	Logbook.CATEGORY_FILE_DELETED: 3,
	Logbook.CATEGORY_FILE_CREATED: 3,
}

var fs: Filesystem
var log_book: Logbook


func before_each() -> void:
	# В узле уже есть история «до прихода игрока»: она категории не имеет.
	fs = Filesystem.new("node_test", {
		"/home/readme.txt": {"text": "привет"},
		"/log/auth/old_01_session.txt": {"text": "старый вход хозяина", "log": true},
	})
	log_book = Logbook.new(fs, "/log", 200)


func _enter() -> void:
	log_book.append(Logbook.CATEGORY_SESSION, "вход с неизвестного адреса", 3, 14 * 60 + 30, false, "login")


func _leave() -> void:
	log_book.append(Logbook.CATEGORY_SESSION, "сеанс закрыт", 3, 15 * 60, false, "logout")


# --- Запись и чтение ---------------------------------------------------------

func test_starts_empty_even_with_old_history() -> void:
	assert_true(log_book.is_empty(), "история узла следом игрока не считается")
	assert_eq(log_book.heat_weight(WEIGHTS), 0, "за чистый узел заметности нет")


func test_only_four_known_categories() -> void:
	# append с неизвестной категорией пишет ошибку в консоль и ничего не создаёт.
	# Сам вызов здесь не делаем: движковая ошибка валит тест в GUT.
	assert_eq(Logbook.CATEGORIES.size(), 4)
	assert_true(Logbook.is_known_category(Logbook.CATEGORY_ROOT))
	assert_false(Logbook.is_known_category("file_read"), "у чтения записи нет вообще")
	assert_false(Logbook.is_known_category("опечатка"))


func test_every_action_is_its_own_file() -> void:
	_enter()
	_leave()
	assert_true(fs.has_file("/log/auth/d003_1430_login.txt"))
	assert_true(fs.has_file("/log/auth/d003_1500_logout.txt"))
	assert_eq(log_book.count(), 2)


func test_auth_and_access_folders() -> void:
	_enter()
	log_book.append(Logbook.CATEGORY_ROOT, "смена уровня доступа", 3, 14 * 60 + 35)
	log_book.append(Logbook.CATEGORY_FILE_DELETED, "удалён файл", 3, 14 * 60 + 40)
	log_book.append(Logbook.CATEGORY_FILE_CREATED, "записан файл", 3, 14 * 60 + 45)
	assert_true(fs.has_file("/log/auth/d003_1435_root.txt"), "права — к входам")
	assert_true(fs.has_file("/log/access/d003_1440_delete.txt"), "что тронули — в access")
	assert_true(fs.has_file("/log/access/d003_1445_write.txt"))


func test_entry_is_readable_and_stamped_with_game_time() -> void:
	_enter()
	var result: FsResult = fs.read("/log/auth/d003_1430_login.txt")
	assert_true(result.is_ok(), "гость читает логи")
	assert_string_contains(result.text, "День 3, 14:30")
	assert_string_contains(result.text, "вход с неизвестного адреса")


func test_two_actions_in_the_same_minute_do_not_overwrite() -> void:
	for index: int in 3:
		log_book.append(Logbook.CATEGORY_FILE_DELETED, "файл %d" % index, 3, 600)
	assert_eq(log_book.count(), 3, "три действия — три файла")
	assert_true(fs.has_file("/log/access/d003_1000_delete.txt"))
	assert_true(fs.has_file("/log/access/d003_1000_delete_2.txt"))
	assert_true(fs.has_file("/log/access/d003_1000_delete_3.txt"))


func test_entries_are_listed_oldest_first() -> void:
	log_book.append(Logbook.CATEGORY_FILE_DELETED, "позже", 4, 10)
	log_book.append(Logbook.CATEGORY_FILE_DELETED, "раньше", 2, 500)
	var paths: PackedStringArray = log_book.entry_paths()
	assert_string_contains(paths[0], "d002")
	assert_string_contains(paths[1], "d004")


func test_logs_in_another_folder() -> void:
	# У узла из data/nodes каталог логов может быть не /log (logs_path).
	var other := Logbook.new(fs, "/sys/log", 200)
	other.append(Logbook.CATEGORY_SESSION, "вход", 1, 0)
	assert_true(fs.has_file("/sys/log/auth/d001_0000_session.txt"))
	assert_eq(log_book.count(), 0, "чужой каталог не смешивается")


# --- Заметность по категориям ------------------------------------------------

func test_session_counts_once_for_enter_and_leave() -> void:
	# Главное правило: вход и выход — одна категория, значит 1, а не 1+1.
	_enter()
	_leave()
	assert_eq(log_book.count(), 2, "файлов два")
	assert_eq(log_book.heat_weight(WEIGHTS), 1, "а категория одна")


func test_many_deletions_cost_the_same_as_one() -> void:
	# Иначе игра наказывала бы за выполнение задания «найди и удали файлы».
	_enter()
	log_book.append(Logbook.CATEGORY_FILE_DELETED, "файл удалён", 3, 14 * 60 + 40)
	var after_one: int = log_book.heat_weight(WEIGHTS)
	for index: int in 19:
		log_book.append(Logbook.CATEGORY_FILE_DELETED, "файл удалён", 3, 14 * 60 + 41 + index)
	assert_eq(log_book.heat_weight(WEIGHTS), after_one, "двадцать удалений стоят как одно")


func test_categories_add_up() -> void:
	_enter()
	log_book.append(Logbook.CATEGORY_ROOT, "смена уровня доступа", 3, 14 * 60 + 35)
	log_book.append(Logbook.CATEGORY_FILE_DELETED, "файл удалён", 3, 14 * 60 + 40)
	log_book.append(Logbook.CATEGORY_FILE_CREATED, "записан новый файл", 3, 14 * 60 + 45)
	_leave()
	assert_eq(log_book.heat_weight(WEIGHTS), 11, "сеанс 1 + права 4 + удаление 3 + запись 3")


func test_ceiling_is_eleven() -> void:
	# Потолок за взлом предсказуем — это нужно для массовых операций поздней игры.
	var total: int = 0
	for category: String in Logbook.CATEGORIES:
		total += int(WEIGHTS[category])
	assert_eq(total, 11)


func test_root_costs_more_than_deleting() -> void:
	# Обычный пользователь прав себе не повышает: это самое чёткое доказательство взлома.
	assert_gt(int(WEIGHTS[Logbook.CATEGORY_ROOT]), int(WEIGHTS[Logbook.CATEGORY_FILE_DELETED]))


func test_categories_are_ordered_and_unique() -> void:
	log_book.append(Logbook.CATEGORY_FILE_DELETED, "файл удалён", 1, 0)
	_enter()
	log_book.append(Logbook.CATEGORY_FILE_DELETED, "ещё файл", 1, 10)
	assert_eq(
		log_book.categories(),
		PackedStringArray([Logbook.CATEGORY_SESSION, Logbook.CATEGORY_FILE_DELETED]),
		"порядок устойчивый, повторов нет"
	)


# --- Чистка руками -----------------------------------------------------------

func test_cleaning_by_hand_lowers_the_weight() -> void:
	# То, ради чего всё затевалось: чистка — это настоящие команды в двух папках.
	_enter()
	log_book.append(Logbook.CATEGORY_ROOT, "смена уровня доступа", 3, 14 * 60 + 35)
	log_book.append(Logbook.CATEGORY_FILE_DELETED, "файл удалён", 3, 14 * 60 + 40)
	assert_eq(log_book.heat_weight(WEIGHTS), 8)

	fs.remove("/log/access", "*")
	assert_eq(log_book.heat_weight(WEIGHTS), 5, "убрали access — осталось сеанс и права")
	fs.remove("/log/auth", "d003*")
	assert_eq(log_book.heat_weight(WEIGHTS), 0, "почистил — не платишь")


func test_exit_record_survives_cleaning() -> void:
	# Запись о выходе пишется уже после чистки: бесследно уйти нельзя (hacking.md).
	_enter()
	fs.remove("/log/auth", "d003*")
	_leave()
	assert_eq(log_book.heat_weight(WEIGHTS), 1)
	assert_true(fs.has_file("/log/auth/d003_1500_logout.txt"), "папка пересоздалась сама")


func test_clear_removes_everything_in_the_log_folder() -> void:
	_enter()
	log_book.append(Logbook.CATEGORY_ROOT, "смена уровня доступа", 3, 14 * 60 + 35)
	assert_eq(log_book.clear(), 3, "две записи и старая история")
	assert_true(log_book.is_empty())
	assert_false(fs.has_file("/log/auth/old_01_session.txt"), "logwipe чистит каталог целиком")
	assert_true(fs.has_file("/home/readme.txt"), "остальное не тронуто")


func test_clear_removes_story_entries_too() -> void:
	# У сюжетных записей защита только от ротации, а не от игрока: свобода с файлами полная.
	log_book.append(Logbook.CATEGORY_SESSION, "кто-то пытался зайти", 2, 300, true)
	log_book.clear()
	assert_true(log_book.is_empty())


func test_player_cannot_forge_a_log_entry() -> void:
	# Файл без категории — просто файл: цену в заметности он не добавляет.
	fs.put_file("/log/auth/fake.txt", {"text": "подделка", "log": true})
	fs.put_file("/log/auth/fake2.txt", {"text": "ещё одна"})
	assert_eq(log_book.heat_weight(WEIGHTS), 0)


func test_moving_an_entry_out_of_the_log_folder_removes_its_weight() -> void:
	_enter()
	fs.move("/", "/log/auth/d003_1430_login.txt", "/home/spasennoe.txt")
	assert_eq(log_book.heat_weight(WEIGHTS), 0, "запись вынесена: в /log её нет")


# --- Ротация -----------------------------------------------------------------

func test_rotation_keeps_the_newest() -> void:
	var small := Logbook.new(fs, "/log", 3)
	for index: int in 5:
		small.append(Logbook.CATEGORY_SESSION, "запись %d" % index, 1, index)
	assert_eq(small.count(), 3, "хранятся последние три")
	assert_false(fs.has_file("/log/auth/d001_0000_session.txt"), "самые старые выброшены")
	assert_true(fs.has_file("/log/auth/d001_0004_session.txt"))


func test_rotation_does_not_touch_old_node_history() -> void:
	var small := Logbook.new(fs, "/log", 1)
	for index: int in 3:
		small.append(Logbook.CATEGORY_SESSION, "запись %d" % index, 1, index)
	assert_true(fs.has_file("/log/auth/old_01_session.txt"), "история узла не вытесняется")


func test_rotation_never_evicts_story_entries() -> void:
	# Иначе зацепка пропала бы до того, как игрок её нашёл.
	var small := Logbook.new(fs, "/log", 3)
	small.append(Logbook.CATEGORY_SESSION, "важное: кто-то был здесь", 1, 0, true)
	for index: int in 10:
		small.append(Logbook.CATEGORY_SESSION, "обычная %d" % index, 1, index + 1)
	assert_true(fs.has_file("/log/auth/d001_0000_session.txt"), "сюжетная запись на месте")
	assert_eq(small.count(), 3)


func test_rotation_stops_when_only_story_entries_left() -> void:
	# Защита от зацикливания: чистить нечего, пусть список чуть вырастет.
	var small := Logbook.new(fs, "/log", 2)
	for index: int in 4:
		small.append(Logbook.CATEGORY_SESSION, "важное %d" % index, 1, index, true)
	assert_eq(small.count(), 4, "сюжетные не выбрасываются никогда")


# --- Состояние ---------------------------------------------------------------

func test_entries_survive_save_and_load() -> void:
	# Отдельного состояния у журнала нет: записи — файлы, а файлы уже в сейве.
	GameState.reset()
	var log_book_in_game: Logbook = Logbook.for_node("node_training_pc")
	log_book_in_game.append(Logbook.CATEGORY_ROOT, "смена уровня доступа", 3, 600)

	var saved: Dictionary = GameState.to_dict()
	GameState.reset()
	assert_eq(Logbook.for_node("node_training_pc").count(), 0, "после сброса записей нет")
	GameState.from_dict(saved)

	var restored: Logbook = Logbook.for_node("node_training_pc")
	assert_eq(restored.count(), 1)
	assert_eq(restored.heat_weight(WEIGHTS), 4)


func test_game_node_keeps_its_history() -> void:
	GameState.reset()
	var in_game: Logbook = Logbook.for_node("node_office_server")
	assert_true(Filesystem.for_node("node_office_server").has_file("/log/auth/old_01_session.txt"))
	assert_eq(in_game.heat_weight(WEIGHTS), 0, "история до игрока — не следы игрока")


func test_weights_come_from_balance() -> void:
	# Числа в коде только как запасные: правит их balance.json.
	var from_balance: Dictionary = Logbook.weights_from_balance()
	for category: String in Logbook.CATEGORIES:
		assert_true(from_balance.has(category), "вес задан в балансе: " + category)
	assert_gt(Logbook.max_entries_from_balance(), 0)
