class_name Locations
extends RefCounted
## Локации (docs/gameplay/locations.md): где сейчас герой, какие объекты видны и куда ведёт дверь.
## Чистые правила без сцен. Описания — `data/locations/*.json`; что делает объект, решает его
## `kind`: окно сцены показывает объекты и передаёт клики, сюда — только переходы.
##
## Сюжета здесь нет: какая дверь заперта и какой объект виден, говорят условия в данных
## (`requires`, `open_requires`), а не код.

const VAR_LOCATION: String = "location.current"
## Что умеет объект. Новый тип — сюда, в окно сцены и в locations.md.
const KINDS: PackedStringArray = ["monitor", "system_block", "bed", "container", "door", "turn", "look", "dialogue"]
## Переходы: `door` — дверь в другую комнату, `turn` — повернуться к другому кадру той же
## комнаты (стрелка у края экрана). Правило у них одно, разница — только в том, как нарисованы.
const PASSAGES: PackedStringArray = ["door", "turn"]
const DEFAULT_HOME: String = "loc_room_bed"
const TIME_DAY: String = "day"
const TIME_NIGHT: String = "night"
const DEFAULT_LOCKED_TEXT: String = "Заперто."


static func all() -> Dictionary:
	return DataLoader.locations()


## Где герой начинает игру и просыпается после вырубания (`balance.json`, `locations.home`).
static func home() -> String:
	return str(_balance().get("home", DEFAULT_HOME))


## Время суток для фона: день с `day_from` до `night_from` часов (`balance.json`, `locations`).
static func time_of_day(minute_of_day: int) -> String:
	var section: Dictionary = _balance()
	var hour: int = minute_of_day / 60
	var day_from: int = int(section.get("day_from", 7))
	var night_from: int = int(section.get("night_from", 21))
	return TIME_DAY if hour >= day_from and hour < night_from else TIME_NIGHT


## Путь к фону: `{time}` в пути из данных — день или ночь (`bg_<кадр>_<время>.png`,
## art/style-guide.md). Пустая строка — фона нет.
static func background_image(id: String, minute_of_day: int) -> String:
	var background: Dictionary = def_of(id).get("background", {}) as Dictionary
	return str(background.get("image", "")).replace("{time}", time_of_day(minute_of_day))


static func _balance() -> Dictionary:
	return DataLoader.balance().get("locations", {}) as Dictionary


## Текущая локация. Нет записи или локацию убрали из данных — дом: старый сейв не ломается.
static func current() -> String:
	var id: String = str(GameState.get_var_or(VAR_LOCATION, ""))
	return id if all().has(id) else home()


static func def_of(id: String) -> Dictionary:
	return all().get(id, {}) as Dictionary


## Объекты локации, которые сейчас видны (их `requires` выполнены), в порядке из данных.
static func objects(id: String) -> Array:
	var visible: Array = []
	for object_variant: Variant in def_of(id).get("objects", []) as Array:
		var object: Dictionary = object_variant as Dictionary
		if Conditions.check_all(object.get("requires", []) as Array):
			visible.append(object)
	return visible


## Видимый объект текущей локации по id ({} — нет такого или скрыт).
static func object(object_id: String) -> Dictionary:
	for object: Dictionary in objects(current()):
		if str(object.get("id", "")) == object_id:
			return object
	return {}


## Перейти в локацию. Внутри квартиры время не тратится: пара шагов — не дорога.
static func enter(id: String) -> bool:
	if not all().has(id):
		push_error("Locations: нет локации '%s'" % id)
		return false
	GameState.set_var(VAR_LOCATION, id)
	EventBus.location_entered.emit(id)
	return true


## Пройти через дверь (или повернуться к другому кадру) текущей локации. {ok, text}: заперто —
## `locked_text` из данных.
static func use_door(object_id: String) -> Dictionary:
	var door: Dictionary = object(object_id)
	if not PASSAGES.has(str(door.get("kind", ""))):
		return {"ok": false, "text": ""}
	if not Conditions.check_all(door.get("open_requires", []) as Array):
		return {"ok": false, "text": str(door.get("locked_text", DEFAULT_LOCKED_TEXT))}
	return {"ok": enter(str(door.get("to", ""))), "text": ""}


static func go_home() -> void:
	enter(home())
