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
const KINDS: PackedStringArray = ["monitor", "system_block", "bed", "container", "door", "turn", "back", "look", "dialogue"]
## Переходы: `door` — дверь в другую комнату, `turn` — повернуться к другому кадру той же
## комнаты (стрелка у края экрана), `back` — «назад» полосой внизу экрана (из комнаты в коридор,
## от ПК в комнату). Правило у них одно, разница — только в том, как нарисованы.
const PASSAGES: PackedStringArray = ["door", "turn", "back"]
const DEFAULT_HOME: String = "loc_room"
const TIME_MORNING: String = "morning"
const TIME_DAY: String = "day"
const TIME_EVENING: String = "evening"
const TIME_NIGHT: String = "night"
## Границы времени суток по умолчанию (минуты от начала дня), если в данных их нет.
const DEFAULT_BOUNDS: Dictionary = {"morning": 360, "day": 660, "evening": 1080, "night": 1320}
const DEFAULT_LOCKED_TEXT: String = "Заперто."


static func all() -> Dictionary:
	return DataLoader.locations()


## Где герой начинает игру и просыпается после вырубания (`balance.json`, `locations.home`).
static func home() -> String:
	return str(_balance().get("home", DEFAULT_HOME))


## Время суток для фона: ночь, утро, день, вечер, ночь — по тем же границам, что у `Clock`
## (`balance.json`, `clock.time_of_day_bounds`). Картинок на утро пока нет: `background_alias`
## в данных подставляет вместо него день.
static func time_of_day(minute_of_day: int) -> String:
	var clock: Dictionary = DataLoader.balance().get("clock", {}) as Dictionary
	var bounds: Dictionary = clock.get("time_of_day_bounds", DEFAULT_BOUNDS) as Dictionary
	var m: int = minute_of_day
	if m < int(bounds.get("morning", DEFAULT_BOUNDS["morning"])):
		return TIME_NIGHT
	if m < int(bounds.get("day", DEFAULT_BOUNDS["day"])):
		return TIME_MORNING
	if m < int(bounds.get("evening", DEFAULT_BOUNDS["evening"])):
		return TIME_DAY
	if m < int(bounds.get("night", DEFAULT_BOUNDS["night"])):
		return TIME_EVENING
	return TIME_NIGHT


## Путь к фону: `{time}` в пути из данных — утро, день, вечер или ночь, `{pc}` — `on` или `off`
## по состоянию компьютера (`bg_room_main_day_pc_on.png`, art/style-guide.md). Пустая строка —
## фона нет.
static func background_image(id: String, minute_of_day: int, pc_on: bool = false) -> String:
	var background: Dictionary = def_of(id).get("background", {}) as Dictionary
	var time: String = time_of_day(minute_of_day)
	var aliases: Dictionary = _balance().get("background_alias", {}) as Dictionary
	return str(background.get("image", "")).replace("{time}", str(aliases.get(time, time))).replace("{pc}", "on" if pc_on else "off")


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
