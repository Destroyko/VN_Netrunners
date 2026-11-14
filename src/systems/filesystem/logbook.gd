class_name Logbook
extends RefCounted
## Логи одного узла: что игрок там делал и чем это пахнет для заметности.
##
## Правила — docs/gameplay/hacking.md и docs/gameplay/heat.md:
## - записи четырёх категорий: сеанс (вход и выход), права, удаление, запись файлов;
## - у чтения записи нет вообще — смотреть можно, трогать опасно;
## - заметность считается по КАТЕГОРИЯМ, а не по числу записей: удалил два файла или
##   двадцать — цена одна. Иначе игра наказывала бы за выполнение задания, где надо
##   удалить несколько файлов;
## - ротация по последним N записям, сюжетные ротацией не вытесняются.
##
## Чистая логика: ни Clock, ни EventBus. Время записи передаёт вызывающий (терминал),
## заметность начисляет система heat — здесь только сумма весов.

const CATEGORY_SESSION: String = "session"
const CATEGORY_ROOT: String = "root"
const CATEGORY_FILE_DELETED: String = "file_deleted"
const CATEGORY_FILE_CREATED: String = "file_created"

const CATEGORIES: PackedStringArray = [
	CATEGORY_SESSION,
	CATEGORY_ROOT,
	CATEGORY_FILE_DELETED,
	CATEGORY_FILE_CREATED,
]

## Запасные значения, если в balance.json нет раздела. Числа — оттуда, не из кода.
const FALLBACK_WEIGHTS: Dictionary = {
	CATEGORY_SESSION: 1,
	CATEGORY_ROOT: 4,
	CATEGORY_FILE_DELETED: 3,
	CATEGORY_FILE_CREATED: 3,
}
const FALLBACK_MAX_ENTRIES: int = 200

var node_id: String = ""
var max_entries: int = FALLBACK_MAX_ENTRIES

## Записи по порядку: {category, text, day, minute, story}.
var _entries: Array = []


func _init(for_node: String = "", entries: Array = [], limit: int = 0) -> void:
	node_id = for_node
	_entries = entries
	max_entries = limit if limit > 0 else max_entries_from_balance()


# --- Запись -------------------------------------------------------------------

## Добавить запись. `story` — сюжетная: ротация её не вытеснит, иначе зацепка пропала бы
## до того, как игрок её нашёл.
static func is_known_category(category: String) -> bool:
	return CATEGORIES.has(category)


func append(category: String, text: String, day: int, minute: int, story: bool = false) -> void:
	if not is_known_category(category):
		push_error("Logbook: неизвестная категория записи '%s'" % category)
		return
	_entries.append({
		"category": category,
		"text": text,
		"day": day,
		"minute": minute,
		"story": story,
	})
	_rotate()


## Выбросить старые записи, кроме сюжетных.
func _rotate() -> void:
	while _entries.size() > max_entries:
		var victim: int = -1
		for index: int in _entries.size():
			if not bool((_entries[index] as Dictionary).get("story", false)):
				victim = index
				break
		# Остались только сюжетные — дальше чистить нечего, пусть список чуть вырастет.
		if victim < 0:
			return
		_entries.remove_at(victim)


## Игрок почистил логи: `rm *` в /log или `logwipe`.
## Сюжетные записи тоже удаляются — защита у них только от ротации, а не от игрока
## (обещанная свобода с файлами, docs/gameplay/hacking.md).
func clear() -> int:
	var removed: int = _entries.size()
	_entries.clear()
	return removed


# --- Чтение -------------------------------------------------------------------

func count() -> int:
	return _entries.size()


func is_empty() -> bool:
	return _entries.is_empty()


func entries() -> Array:
	return _entries.duplicate(true)


## Категории, которые в логе есть. По ним считается заметность.
func categories() -> PackedStringArray:
	var found: Dictionary = {}
	for entry: Variant in _entries:
		found[str((entry as Dictionary).get("category", ""))] = true
	var result: PackedStringArray = []
	for category: String in CATEGORIES:
		if found.has(category):
			result.append(category)
	return result


## Сколько заметности даст этот лог, если игрок уйдёт, не почистив.
## Сумма по категориям, а не по записям.
func heat_weight(weights: Dictionary = {}) -> int:
	var table: Dictionary = weights if not weights.is_empty() else weights_from_balance()
	var total: int = 0
	for category: String in categories():
		total += int(table.get(category, 0))
	return total


## Содержимое файла лога для `cat`: по строке на запись.
func lines() -> PackedStringArray:
	var result: PackedStringArray = []
	for entry: Variant in _entries:
		var data: Dictionary = entry as Dictionary
		result.append("[%s] %s" % [stamp(int(data["day"]), int(data["minute"])), str(data["text"])])
	return result


static func stamp(day: int, minute: int) -> String:
	return "День %d, %02d:%02d" % [day, minute / 60, minute % 60]


# --- Числа из баланса ---------------------------------------------------------

static func weights_from_balance() -> Dictionary:
	var heat: Dictionary = DataLoader.balance().get("heat", {}) as Dictionary
	var weights: Dictionary = heat.get("log_weights", {}) as Dictionary
	return weights if not weights.is_empty() else FALLBACK_WEIGHTS


static func max_entries_from_balance() -> int:
	var logs: Dictionary = DataLoader.balance().get("logs", {}) as Dictionary
	return int(logs.get("max_entries", FALLBACK_MAX_ENTRIES))


# --- Состояние ----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"entries": _entries}


static func from_dict(for_node: String, data: Dictionary) -> Logbook:
	return Logbook.new(for_node, data.get("entries", []) as Array)


## Лог узла в игре: берётся из состояния, при первом обращении создаётся пустым.
## Записи должны попадать в сейв — иначе после загрузки узел забудет, что игрок там был.
static func for_node(node_id: String) -> Logbook:
	if not GameState.has_logbook(node_id):
		GameState.set_logbook_state(node_id, {"entries": []})
	return from_dict(node_id, GameState.logbook_state(node_id))
