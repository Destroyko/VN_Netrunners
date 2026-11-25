class_name Logbook
extends RefCounted
## Следы игрока на узле. Каждое действие — отдельный текстовый файл в `/log/auth` или
## `/log/access`, а не строка в общем журнале.
##
## Почему файлы (решено 15.11.2026): игрок видит, что наследил, и чистка приносит
## удовольствие — это `rm *` в двух папках, а не удаление одного файла, в который он
## всё равно не заходил бы. Заодно источник правды один: записи лежат в файловой системе
## узла, а она уже в сейве, отдельного состояния у журнала нет.
##
## Правила — docs/gameplay/hacking.md и docs/gameplay/heat.md:
## - четыре категории: сеанс (вход и выход), права, удаление, запись файлов;
## - у чтения записи нет вообще — смотреть можно, трогать опасно;
## - заметность считается по КАТЕГОРИЯМ, а не по числу файлов: удалил два файла или двадцать —
##   цена одна. Какие категории остались, видно по файлам, которые лежат в /log;
## - ротация по последним N записям, сюжетные ротацией не вытесняются.
##
## Раскладка: `auth` — кто вошёл и с какими правами (сеанс, права), `access` — что тронули
## (удалено, записано). Записи из data/nodes («история до прихода игрока») категории не имеют
## и в заметность не входят.
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

const FOLDER_AUTH: String = "auth"
const FOLDER_ACCESS: String = "access"

## В какую папку ложится запись категории.
const FOLDER_OF: Dictionary = {
	CATEGORY_SESSION: FOLDER_AUTH,
	CATEGORY_ROOT: FOLDER_AUTH,
	CATEGORY_FILE_DELETED: FOLDER_ACCESS,
	CATEGORY_FILE_CREATED: FOLDER_ACCESS,
}

## Слово в имени файла по умолчанию: `d003_1430_session.txt`.
const SLUG_OF: Dictionary = {
	CATEGORY_SESSION: "session",
	CATEGORY_ROOT: "root",
	CATEGORY_FILE_DELETED: "delete",
	CATEGORY_FILE_CREATED: "write",
}

## Запасные значения, если в balance.json нет раздела. Числа — оттуда, не из кода.
const FALLBACK_WEIGHTS: Dictionary = {
	CATEGORY_SESSION: 1,
	CATEGORY_ROOT: 4,
	CATEGORY_FILE_DELETED: 3,
	CATEGORY_FILE_CREATED: 3,
}
const FALLBACK_MAX_ENTRIES: int = 200

var logs_path: String = "/log"
var max_entries: int = FALLBACK_MAX_ENTRIES

var _fs: Filesystem


func _init(filesystem: Filesystem, path: String = "/log", limit: int = 0) -> void:
	_fs = filesystem
	logs_path = path
	max_entries = limit if limit > 0 else max_entries_from_balance()


static func is_known_category(category: String) -> bool:
	return CATEGORIES.has(category)


# --- Запись -------------------------------------------------------------------

## Записать действие отдельным файлом. `story` — сюжетная запись: ротация её не вытеснит,
## иначе зацепка пропала бы до того, как игрок её нашёл. `slug` — слово в имени файла
## («login», «logout»), по умолчанию по категории. Возвращает путь или пустую строку.
func append(
	category: String, text: String, day: int, minute: int, story: bool = false, slug: String = ""
) -> String:
	if not is_known_category(category):
		push_error("Logbook: неизвестная категория записи '%s'" % category)
		return ""

	var folder: String = "%s/%s" % [logs_path, str(FOLDER_OF[category])]
	var word: String = slug if not slug.is_empty() else str(SLUG_OF[category])
	var path: String = _free_path(folder, day, minute, word)
	_fs.put_file(path, {
		"text": "[%s] %s" % [stamp(day, minute), text],
		"log": true,
		"log_category": category,
		"day": day,
		"minute": minute,
		"story": story,
	})
	_rotate()
	return path


## Имя вида `d003_1430_session.txt`; при совпадении (два действия в одну минуту) — `_2`, `_3`…
func _free_path(folder: String, day: int, minute: int, word: String) -> String:
	var base: String = "%s/d%03d_%02d%02d_%s" % [folder, day, minute / 60, minute % 60, word]
	var path: String = base + ".txt"
	var number: int = 2
	while _fs.has_file(path):
		path = "%s_%d.txt" % [base, number]
		number += 1
	return path


## Выбросить самые старые записи, кроме сюжетных.
func _rotate() -> void:
	var paths: PackedStringArray = entry_paths()
	while paths.size() > max_entries:
		var victim: String = ""
		for candidate: String in paths:
			if not bool(_fs.file_data(candidate).get("story", false)):
				victim = candidate
				break
		# Остались только сюжетные — дальше чистить нечего, пусть список чуть вырастет.
		if victim.is_empty():
			return
		_fs.erase_file(victim)
		paths.remove_at(paths.find(victim))


## Игрок почистил логи программой `logwipe`: убирает вообще всё в каталоге логов — и записи,
## и историю узла. Сюжетные записи тоже: защита у них только от ротации, а не от игрока
## (обещанная свобода с файлами, docs/gameplay/hacking.md). `rm *` руками делает то же
## через Filesystem, поэтому журнал отдельно «чистить» не нужно.
func clear() -> int:
	var removed: int = 0
	for path: String in _fs.paths():
		if path.begins_with(logs_path + "/"):
			_fs.erase_file(path)
			removed += 1
	return removed


# --- Чтение -------------------------------------------------------------------

## Пути записей игрока от старых к новым. Файлы без категории (история узла, всё, что
## игрок положил в /log сам) сюда не входят: подделать запись нельзя, а чужую историю
## чистить ради заметности не нужно.
func entry_paths() -> PackedStringArray:
	var found: Array = []
	for path: String in _fs.paths():
		if not path.begins_with(logs_path + "/"):
			continue
		var data: Dictionary = _fs.file_data(path)
		if is_known_category(str(data.get("log_category", ""))):
			found.append({"path": path, "day": int(data.get("day", 0)), "minute": int(data.get("minute", 0))})
	found.sort_custom(_older_first)

	var result: PackedStringArray = []
	for item: Dictionary in found:
		result.append(str(item["path"]))
	return result


static func _older_first(a: Dictionary, b: Dictionary) -> bool:
	if int(a["day"]) != int(b["day"]):
		return int(a["day"]) < int(b["day"])
	if int(a["minute"]) != int(b["minute"]):
		return int(a["minute"]) < int(b["minute"])
	return str(a["path"]) < str(b["path"])


func count() -> int:
	return entry_paths().size()


func is_empty() -> bool:
	return entry_paths().is_empty()


## Категории, которые в логе остались. По ним считается заметность.
func categories() -> PackedStringArray:
	var found: Dictionary = {}
	for path: String in entry_paths():
		found[str(_fs.file_data(path).get("log_category", ""))] = true
	var result: PackedStringArray = []
	for category: String in CATEGORIES:
		if found.has(category):
			result.append(category)
	return result


## Сколько заметности даст этот лог, если игрок уйдёт, не почистив.
## Сумма по категориям, а не по файлам.
func heat_weight(weights: Dictionary = {}) -> int:
	return _weight_of(categories(), weights)


## То же, но только за записи, за которые заметность ещё не начислена: следы прошлых визитов
## уже оплачены при прошлом отключении (ISS-014, решено 25.11.2026).
func unpaid_weight(weights: Dictionary = {}) -> int:
	var found: Dictionary = {}
	for path: String in entry_paths():
		var data: Dictionary = _fs.file_data(path)
		if not bool(data.get("paid", false)):
			found[str(data.get("log_category", ""))] = true
	var unpaid: PackedStringArray = []
	for category: String in CATEGORIES:
		if found.has(category):
			unpaid.append(category)
	return _weight_of(unpaid, weights)


## Заметность за записи начислена: следующий визит за них уже не платит.
func mark_paid() -> void:
	for path: String in entry_paths():
		var data: Dictionary = _fs.file_data(path)
		if not bool(data.get("paid", false)):
			data = data.duplicate()
			data["paid"] = true
			_fs.put_file(path, data)


func _weight_of(found: PackedStringArray, weights: Dictionary) -> int:
	var table: Dictionary = weights if not weights.is_empty() else weights_from_balance()
	var total: int = 0
	for category: String in found:
		total += int(table.get(category, 0))
	return total


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


# --- Узел в игре --------------------------------------------------------------

## Журнал узла в игре: поверх его файловой системы из состояния. Отдельного состояния нет —
## записи это файлы, поэтому в сейв они попадают вместе с остальным.
static func for_node(node_id: String) -> Logbook:
	var definition: Dictionary = DataLoader.nodes().get(node_id, {}) as Dictionary
	return Logbook.new(Filesystem.for_node(node_id), str(definition.get("logs_path", "/log")))
