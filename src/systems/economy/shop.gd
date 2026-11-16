class_name Shop
extends RefCounted
## Доставка еды (docs/gameplay/needs.md, «Что из этого в M2»): заказал — деньги списаны, через
## `shop.delivery_minutes` пакет у двери и лежит в запасе; съел — сытость (энергетик — энергия
## сразу и откат потом).
##
## Чистые правила без сцен. Ход часов передаёт сюда `EconomyManager`; приложение «Магазин» и
## кухня в комнате только показывают и передают «заказать» и «съесть». Заказы в пути и запас —
## в `GameState.economy_state()` (сейв их помнит). Каталог — `data/shop.json`.

const DEFAULT_DELIVERY: int = 40


static func catalog() -> Dictionary:
	return DataLoader.shop().get("items", {}) as Dictionary


static func item(id: String) -> Dictionary:
	return catalog().get(id, {}) as Dictionary


static func title_of(id: String) -> String:
	return str(item(id).get("title", id))


static func delivery_minutes() -> int:
	var section: Dictionary = DataLoader.balance().get("shop", {}) as Dictionary
	return int(section.get("delivery_minutes", DEFAULT_DELIVERY))


## Заказать. Нет такого товара или не хватает денег — false, ничего не списано.
static func order(id: String) -> bool:
	var def: Dictionary = item(id)
	if def.is_empty():
		return false
	if not Economy.spend(int(def.get("price", 0)), "Доставка: " + title_of(id)):
		return false
	_list("orders").append({"item": id, "arrive_at": Clock.total_minutes() + delivery_minutes()})
	EventBus.order_placed.emit(id)
	return true


## Заказы в пути: [{item, arrive_at}].
static func orders() -> Array:
	return _list("orders")


## Запас дома: {id: сколько}.
static func pantry() -> Dictionary:
	var state: Dictionary = GameState.economy_state()
	if not state.has("pantry"):
		state["pantry"] = {}
	return state["pantry"]


## Прошло время: всё, что приехало, — в запас. Курьер оставляет пакет у двери и не будит.
static func on_time_passed() -> void:
	var now: int = Clock.total_minutes()
	var waiting: Array = _list("orders")
	var arrived: Array = waiting.filter(func(o: Dictionary) -> bool: return int(o["arrive_at"]) <= now)
	if arrived.is_empty():
		return
	for o: Dictionary in arrived:
		waiting.erase(o)
		var id: String = str(o["item"])
		pantry()[id] = int(pantry().get(id, 0)) + 1
		EventBus.order_delivered.emit(id)


## Съесть или выпить из запаса. Занимает `eat_minutes` игрового времени. Нет в запасе — false.
static func consume(id: String) -> bool:
	var count: int = int(pantry().get(id, 0))
	if count <= 0:
		return false
	if count == 1:
		pantry().erase(id)
	else:
		pantry()[id] = count - 1
	var def: Dictionary = item(id)
	Needs.eat(float(def.get("satiety", 0)))
	if float(def.get("energy", 0)) > 0.0:
		Needs.drink_energy(float(def["energy"]), float(def.get("crash", 0)), int(def.get("crash_after_minutes", 0)))
	EventBus.food_consumed.emit(id)
	Clock.advance(int(def.get("eat_minutes", 0)))
	return true


static func _list(key: String) -> Array:
	var state: Dictionary = GameState.economy_state()
	if not state.has(key):
		state[key] = []
	return state[key]
