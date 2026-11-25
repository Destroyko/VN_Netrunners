class_name SaveSystem
extends RefCounted
## Сохранения (docs/tech/architecture.md, «Сохранения»): сейв = сериализованный `GameState` +
## снимок `Rng` + версия формата. Слоты — файлы в `user://saves/`: `auto` (автосейв) и ручные.
##
## Чистые правила без сцен; кнопки меню и стола только зовут их, автосейв — `SaveManager`.
##
## Что НЕ сохраняется — то, что живёт в интерфейсе: открытые окна, история терминала, открытая
## головоломка, буфер проводника. После загрузки игрок в комнате, стол собирается заново, а
## живое подключение к чужому узлу сброшено (как `dc` без записи в лог): иначе после загрузки
## «соединение» висело бы без терминала. Трейс на узле при этом остаётся (он живёт на узле).
##
## Запись атомарная: сначала во временный файл, потом переименование — оборванная запись не
## портит прежний сейв.

const SLOT_AUTO: String = "auto"
const SLOT_MANUAL: String = "manual"
const DEFAULT_DIR: String = "user://saves"

## Каталог сейвов. Тесты подменяют его, чтобы не трогать настоящие сохранения.
static var dir: String = DEFAULT_DIR


static func path_of(slot: String) -> String:
	return dir.path_join("%s.json" % slot)


static func exists(slot: String) -> bool:
	return FileAccess.file_exists(path_of(slot))


## Сохранить текущую игру в слот. Возвращает "" или текст ошибки.
## Сохранить нельзя, пока идёт полоска программы (ISS-003, И-21): её живое состояние в сейв не
## попадает, а мир посреди неё был бы несогласован. Долгие программы — фоновые задачи с сейвом.
const BUSY_ERROR: String = "идёт программа"


## Что сказать игроку после сохранения.
static func result_text(error: String) -> String:
	if error.is_empty():
		return "игра сохранена"
	if error == BUSY_ERROR:
		return "сохранить нельзя: идёт программа"
	return "ошибка сохранения: " + error


static func can_save() -> bool:
	return not Clock.is_fast_forwarding()


static func save(slot: String) -> String:
	if not can_save():
		return BUSY_ERROR
	if not DirAccess.dir_exists_absolute(dir):
		var made: int = DirAccess.make_dir_recursive_absolute(dir)
		if made != OK:
			return "не удалось создать каталог сейвов (%d)" % made
	var data: Dictionary = {
		"meta": {
			"slot": slot,
			"day": GameState.day,
			"minute": GameState.minute,
			"date": Clock.format_now(),
			"money": GameState.money,
			"saved_at": int(Time.get_unix_time_from_system()),
		},
		"state": GameState.to_dict(),
		"rng": Rng.snapshot(),
	}
	var tmp: String = path_of(slot) + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return "не удалось записать сейв (%d)" % FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if FileAccess.file_exists(path_of(slot)):
		DirAccess.remove_absolute(path_of(slot))
	var moved: int = DirAccess.rename_absolute(tmp, path_of(slot))
	if moved != OK:
		return "не удалось сохранить сейв (%d)" % moved
	EventBus.game_saved.emit(slot)
	return ""


## Прочитать сейв, не применяя: {ok, data, error}. Битый файл или версия из будущего — ok=false.
static func read(slot: String) -> Dictionary:
	if not exists(slot):
		return {"ok": false, "data": {}, "error": "сейва нет"}
	var text: String = FileAccess.get_file_as_string(path_of(slot))
	var json := JSON.new()
	if text.is_empty() or json.parse(text) != OK or not (json.data is Dictionary):
		return {"ok": false, "data": {}, "error": "сейв повреждён"}
	var data: Dictionary = json.data as Dictionary
	if not (data.get("state") is Dictionary):
		return {"ok": false, "data": {}, "error": "в сейве нет состояния игры"}
	var migrated: Dictionary = SaveMigrations.migrate(data["state"] as Dictionary)
	if not bool(migrated["ok"]):
		return {"ok": false, "data": {}, "error": str(migrated["error"])}
	data["state"] = migrated["state"]
	return {"ok": true, "data": data, "error": ""}


## Загрузить сейв в игру. Возвращает "" или текст ошибки; при ошибке текущая игра не тронута.
static func load_slot(slot: String) -> String:
	var got: Dictionary = read(slot)
	if not bool(got["ok"]):
		return str(got["error"])
	var data: Dictionary = got["data"]
	GameState.from_dict(data["state"] as Dictionary)
	Rng.restore(data.get("rng", {}) as Dictionary)
	# Живое подключение сбрасываем: терминала, к которому оно относилось, больше нет.
	var network: Dictionary = GameState.network_state()
	if network.has("session"):
		network["session"] = {}
	Clock.reset_pauses()
	EventBus.game_loaded.emit(slot)
	return ""


## Сейвы, новые сверху: [{slot, meta}]. Битые пропускаются.
static func list() -> Array:
	var found: Array = []
	if not DirAccess.dir_exists_absolute(dir):
		return found
	for name: String in DirAccess.get_files_at(dir):
		if not name.ends_with(".json"):
			continue
		var slot: String = name.get_basename()
		var got: Dictionary = read(slot)
		if bool(got["ok"]):
			found.append({"slot": slot, "meta": (got["data"] as Dictionary).get("meta", {})})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int((a["meta"] as Dictionary).get("saved_at", 0)) > int((b["meta"] as Dictionary).get("saved_at", 0)))
	return found


## Самый свежий слот ("" — сейвов нет). Его загружает «Продолжить».
static func latest() -> String:
	var all: Array = list()
	return str((all[0] as Dictionary)["slot"]) if not all.is_empty() else ""


static func delete(slot: String) -> void:
	if exists(slot):
		DirAccess.remove_absolute(path_of(slot))
