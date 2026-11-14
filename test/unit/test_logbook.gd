extends GutTest
## Logbook: записи в логах узла и их цена в заметности (docs/gameplay/heat.md).

## Веса задаём явно, чтобы тест не поехал, когда числа в balance.json покрутят на плейтесте.
const WEIGHTS: Dictionary = {
	Logbook.CATEGORY_SESSION: 1,
	Logbook.CATEGORY_ROOT: 4,
	Logbook.CATEGORY_FILE_DELETED: 3,
	Logbook.CATEGORY_FILE_CREATED: 3,
}

var log_book: Logbook


func before_each() -> void:
	log_book = Logbook.new("node_test", [], 200)


func _enter() -> void:
	log_book.append(Logbook.CATEGORY_SESSION, "вход с неизвестного адреса", 3, 14 * 60 + 30)


func _leave() -> void:
	log_book.append(Logbook.CATEGORY_SESSION, "сеанс закрыт", 3, 15 * 60)


# --- Запись и чтение ---------------------------------------------------------

func test_starts_empty() -> void:
	assert_true(log_book.is_empty())
	assert_eq(log_book.heat_weight(WEIGHTS), 0, "за чистый узел заметности нет")


func test_only_four_known_categories() -> void:
	# append с неизвестной категорией пишет ошибку в консоль и не добавляет запись.
	# Сам вызов здесь не делаем: движковая ошибка валит тест в GUT.
	assert_eq(Logbook.CATEGORIES.size(), 4)
	assert_true(Logbook.is_known_category(Logbook.CATEGORY_ROOT))
	assert_false(Logbook.is_known_category("file_read"), "у чтения записи нет вообще")
	assert_false(Logbook.is_known_category("опечатка"))


func test_lines_are_stamped_with_game_time() -> void:
	_enter()
	var lines: PackedStringArray = log_book.lines()
	assert_eq(lines.size(), 1)
	assert_string_contains(lines[0], "День 3, 14:30")
	assert_string_contains(lines[0], "вход с неизвестного адреса")


# --- Заметность по категориям ------------------------------------------------

func test_session_counts_once_for_enter_and_leave() -> void:
	# Главное правило: вход и выход — одна категория, значит 1, а не 1+1.
	_enter()
	_leave()
	assert_eq(log_book.count(), 2, "записей две")
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


# --- Чистка и ротация --------------------------------------------------------

func test_clear_removes_everything() -> void:
	_enter()
	log_book.append(Logbook.CATEGORY_ROOT, "смена уровня доступа", 3, 14 * 60 + 35)
	assert_eq(log_book.clear(), 2, "вернула число удалённых")
	assert_true(log_book.is_empty())
	assert_eq(log_book.heat_weight(WEIGHTS), 0, "почистил — не платишь")


func test_clear_removes_story_entries_too() -> void:
	# У сюжетных записей защита только от ротации, а не от игрока: свобода с файлами полная.
	log_book.append(Logbook.CATEGORY_SESSION, "кто-то пытался зайти", 2, 300, true)
	log_book.clear()
	assert_true(log_book.is_empty())


func test_rotation_keeps_the_newest() -> void:
	var small := Logbook.new("node_test", [], 3)
	for index: int in 5:
		small.append(Logbook.CATEGORY_SESSION, "запись %d" % index, 1, index)
	assert_eq(small.count(), 3, "хранятся последние три")
	assert_string_contains(small.lines()[0], "запись 2", "самые старые выброшены")


func test_rotation_never_evicts_story_entries() -> void:
	# Иначе зацепка пропала бы до того, как игрок её нашёл.
	var small := Logbook.new("node_test", [], 3)
	small.append(Logbook.CATEGORY_SESSION, "важное: кто-то был здесь", 1, 0, true)
	for index: int in 10:
		small.append(Logbook.CATEGORY_SESSION, "обычная %d" % index, 1, index + 1)
	var kept: String = "\n".join(small.lines())
	assert_string_contains(kept, "важное", "сюжетная запись на месте")
	assert_eq(small.count(), 3)


func test_rotation_stops_when_only_story_entries_left() -> void:
	# Защита от зацикливания: чистить нечего, пусть список чуть вырастет.
	var small := Logbook.new("node_test", [], 2)
	for index: int in 4:
		small.append(Logbook.CATEGORY_SESSION, "важное %d" % index, 1, index, true)
	assert_eq(small.count(), 4, "сюжетные не выбрасываются никогда")


# --- Состояние ---------------------------------------------------------------

func test_save_round_trip() -> void:
	_enter()
	log_book.append(Logbook.CATEGORY_ROOT, "смена уровня доступа", 3, 14 * 60 + 35)
	var saved: Dictionary = log_book.to_dict()

	var restored: Logbook = Logbook.from_dict("node_test", saved.duplicate(true))
	assert_eq(restored.count(), 2)
	assert_eq(restored.heat_weight(WEIGHTS), 5, "сеанс 1 + права 4")


func test_weights_come_from_balance() -> void:
	# Числа в коде только как запасные: правит их balance.json.
	var from_balance: Dictionary = Logbook.weights_from_balance()
	for category: String in Logbook.CATEGORIES:
		assert_true(from_balance.has(category), "вес задан в балансе: " + category)
	assert_gt(Logbook.max_entries_from_balance(), 0)
