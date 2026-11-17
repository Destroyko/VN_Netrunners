class_name Inventory
extends RefCounted
## Инвентарь и хранилища (docs/gameplay/inventory.md): предметы — экземпляры со своим uid в
## контейнерах. Инвентарь героя, хранилище в комнате, холодильник, гнездо ПК — одно понятие:
## список предметов со своим лимитом и правилом «что можно положить». Переложить, съесть,
## выбросить — операции над экземпляром.
##
## Чистые правила без сцен. Состояние — `GameState.inventory_state()` (в сейве с v2).
## Описания: вещи — `data/items.json`, еда и напитки — каталог магазина `data/shop.json`.
## Сюжет выдаёт вещи эффектом `give_item` (`"item_x"` или `{"item": "item_x", "quest": "…"}` —
## квестовую нельзя выбросить, пока квест не завершён).

const ID_PREFIX: String = "item_"

const HERO: String = "hero"
const STORAGE: String = "room_storage"
const FRIDGE: String = "fridge"
## Гнездо ПК: вставленная флешка. Одна за раз.
const PC: String = "pc_usb"
const CONTAINERS: PackedStringArray = [HERO, STORAGE, FRIDGE, PC]
## Названия контейнеров для игрока.
const TITLES: Dictionary = {HERO: "Инвентарь", STORAGE: "Шкаф", FRIDGE: "Холодильник", PC: "Системный блок"}
const DEFAULT_SLOTS: Dictionary = {HERO: 30, STORAGE: 50, FRIDGE: 30, PC: 1}

## Виды вещей из items.json. Еда — отдельная категория (`food`), её виды — товары магазина.
const KIND_RESTORE: String = "restore"  # резервный носитель
const KINDS: PackedStringArray = [KIND_RESTORE]
const CATEGORY_FOOD: String = "food"

const ERROR_FULL: String = "заполнен"
const ERROR_WRONG: String = "сюда это не положить"
const ERROR_QUEST: String = "квестовый предмет"


# --- Описания -----------------------------------------------------------------------------

static func definitions() -> Dictionary:
	var result: Dictionary = {}
	var data: Dictionary = DataLoader.items()
	for id: String in data.keys():
		if not id.begins_with("_") and data[id] is Dictionary:
			result[id] = data[id]
	return result


## Вещь из items.json или еда из каталога магазина.
static func is_item(kind: String) -> bool:
	return definitions().has(kind) or not Shop.item(kind).is_empty()


static func is_food(kind: String) -> bool:
	return not Shop.item(kind).is_empty()


static func name_of(kind: String) -> String:
	if is_food(kind):
		return Shop.title_of(kind)
	return str((definitions().get(kind, {}) as Dictionary).get("name", kind))


static func about(kind: String) -> String:
	if is_food(kind):
		var def: Dictionary = Shop.item(kind)
		return "Сытость +%d" % int(def.get("satiety", 0)) + (", энергия +%d" % int(def["energy"]) if def.has("energy") else "")
	return str((definitions().get(kind, {}) as Dictionary).get("about", ""))


## Вид вещи (`restore`…) или `food`.
static func kind_of(kind: String) -> String:
	if is_food(kind):
		return CATEGORY_FOOD
	return str((definitions().get(kind, {}) as Dictionary).get("kind", ""))


## Подпись экземпляра: своё имя (переименовал) или имя вида.
static func label_of(entry: Dictionary) -> String:
	var label: String = str(entry.get("label", ""))
	return label if not label.is_empty() else name_of(str(entry.get("kind", "")))


# --- Контейнеры ---------------------------------------------------------------------------

static func capacity(container: String) -> int:
	var slots: Dictionary = (DataLoader.balance().get("inventory", {}) as Dictionary).get("slots", {}) as Dictionary
	return int(slots.get(container, DEFAULT_SLOTS.get(container, 0)))


## Можно ли положить вид в контейнер: холодильник — только еда, шкаф — всё, кроме еды, гнездо ПК —
## только носители.
static func accepts(container: String, kind: String) -> bool:
	match container:
		FRIDGE:
			return is_food(kind)
		STORAGE:
			return not is_food(kind)
		PC:
			return kind_of(kind) == KIND_RESTORE
	return CONTAINERS.has(container)


static func list(container: String) -> Array:
	var all: Dictionary = _containers()
	if not all.has(container):
		all[container] = []
	return all[container] as Array


static func free_slots(container: String) -> int:
	return capacity(container) - list(container).size()


## Положить новый экземпляр. Не помещается или не принимает — "". `force` — сверх лимита (сюжетная
## выдача: квестовый предмет не должен потеряться из-за полного инвентаря).
static func add(container: String, kind: String, quest: String = "", force: bool = false) -> String:
	if not is_item(kind) or not accepts(container, kind):
		return ""
	if free_slots(container) <= 0 and not force:
		return ""
	var state: Dictionary = GameState.inventory_state()
	var next: int = int(state.get("next", 1))
	state["next"] = next + 1
	var entry: Dictionary = {"uid": "it_%d" % next, "kind": kind, "label": "", "quest": quest}
	list(container).append(entry)
	EventBus.inventory_changed.emit(container)
	return str(entry["uid"])


## Где лежит экземпляр: {container, entry} или {}.
static func find(uid: String) -> Dictionary:
	for container: String in _containers().keys():
		for entry: Dictionary in _containers()[container] as Array:
			if str(entry.get("uid", "")) == uid:
				return {"container": container, "entry": entry}
	return {}


## Переложить в другой контейнер. "" — получилось, иначе причина для игрока.
static func move(uid: String, to: String) -> String:
	var found: Dictionary = find(uid)
	if found.is_empty():
		return ERROR_WRONG
	var from: String = str(found["container"])
	if from == to:
		return ""
	var entry: Dictionary = found["entry"] as Dictionary
	if not accepts(to, str(entry["kind"])):
		return ERROR_WRONG
	if free_slots(to) <= 0:
		return "%s: %s" % [TITLES.get(to, to), ERROR_FULL]
	list(from).erase(entry)
	list(to).append(entry)
	EventBus.inventory_changed.emit(from)
	EventBus.inventory_changed.emit(to)
	return ""


## Выбросить насовсем. Квестовый, пока квест не завершён, — нельзя.
static func discard(uid: String) -> String:
	var found: Dictionary = find(uid)
	if found.is_empty():
		return ERROR_WRONG
	if is_locked(found["entry"] as Dictionary):
		return ERROR_QUEST
	list(str(found["container"])).erase(found["entry"])
	EventBus.inventory_changed.emit(str(found["container"]))
	return ""


static func is_locked(entry: Dictionary) -> bool:
	var quest: String = str(entry.get("quest", ""))
	return not quest.is_empty() and not GameState.is_quest_completed(quest)


static func rename(uid: String, label: String) -> bool:
	var found: Dictionary = find(uid)
	if found.is_empty():
		return false
	(found["entry"] as Dictionary)["label"] = label.strip_edges()
	EventBus.inventory_changed.emit(str(found["container"]))
	return true


## Съесть или выпить экземпляр еды — откуда угодно (инвентарь, холодильник).
static func eat(uid: String) -> bool:
	var found: Dictionary = find(uid)
	if found.is_empty() or not is_food(str((found["entry"] as Dictionary)["kind"])):
		return false
	var kind: String = str((found["entry"] as Dictionary)["kind"])
	list(str(found["container"])).erase(found["entry"])
	EventBus.inventory_changed.emit(str(found["container"]))
	Shop.apply_food(kind)
	return true


# --- Совместимость со старым API (эффекты give_item / take_item, условие has_item) ---------

## Есть ли у героя такая вещь — в любом его контейнере (инвентарь, шкаф, холодильник, гнездо ПК).
static func has(kind: String) -> bool:
	return count(kind) > 0


static func count(kind: String, container: String = "") -> int:
	var total: int = 0
	for c: String in _containers().keys():
		if not container.is_empty() and c != container:
			continue
		for entry: Dictionary in _containers()[c] as Array:
			if str(entry.get("kind", "")) == kind:
				total += 1
	return total


## Выдать вещь герою (сюжет). Инвентарь полон — всё равно выдаётся: сюжетная вещь не теряется.
static func give(kind: String, quest: String = "") -> bool:
	if not is_item(kind):
		push_error("Inventory: неизвестный предмет '%s'" % kind)
		return false
	return not add(HERO, kind, quest, true).is_empty()


## Забрать вещь (сюжет): первый экземпляр, где бы он ни лежал. Квестовость не мешает — забирает
## сам сюжет.
static func take(kind: String) -> bool:
	for container: String in _containers().keys():
		for entry: Dictionary in _containers()[container] as Array:
			if str(entry.get("kind", "")) == kind:
				(_containers()[container] as Array).erase(entry)
				EventBus.inventory_changed.emit(container)
				return true
	return false


## Вещи (не еда) в инвентаре героя — виды, без повторов, по порядку.
static func items() -> PackedStringArray:
	var result: PackedStringArray = []
	for entry: Dictionary in list(HERO):
		var kind: String = str(entry["kind"])
		if not is_food(kind) and not result.has(kind):
			result.append(kind)
	result.sort()
	return result


## Первый экземпляр вида в контейнере ("" — нет).
static func first_uid(kind: String, container: String = HERO) -> String:
	for entry: Dictionary in list(container):
		if str(entry["kind"]) == kind:
			return str(entry["uid"])
	return ""


static func _containers() -> Dictionary:
	var state: Dictionary = GameState.inventory_state()
	if not state.has("containers"):
		state["containers"] = {}
	return state["containers"] as Dictionary
