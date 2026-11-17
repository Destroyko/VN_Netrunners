class_name Shop
extends RefCounted
## Доставка еды (docs/gameplay/needs.md, «Что из этого в M2»): заказал — деньги списаны, через
## `shop.delivery_minutes` курьер отдаёт пакет — каждая порция ложится в инвентарь героя своим
## слотом (docs/gameplay/inventory.md). Инвентарь полон — не купить.
##
## Чистые правила без сцен. Ход часов передаёт сюда `EconomyManager`; приложение «Магазин» только
## показывает и передаёт «заказать». Съесть — `Inventory.eat`, а что даёт еда — `apply_food`.
## Заказы в пути — в `GameState.economy_state()`. Каталог — `data/shop.json`.

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


const ERROR_FULL: String = "инвентарь заполнен"
const ERROR_MONEY: String = "не хватает денег"


## Почему не заказать ("" — можно). Место считается с учётом заказов в пути: каждый займёт слот.
static func order_error(id: String) -> String:
	var def: Dictionary = item(id)
	if def.is_empty():
		return "нет такого товара"
	if Inventory.free_slots(Inventory.HERO) - orders().size() <= 0:
		return ERROR_FULL
	if GameState.money < int(def.get("price", 0)):
		return ERROR_MONEY
	return ""


## Заказать. Нельзя (`order_error`) — false, ничего не списано.
static func order(id: String) -> bool:
	if not order_error(id).is_empty():
		return false
	var def: Dictionary = item(id)
	if not Economy.spend(int(def.get("price", 0)), "Доставка: " + title_of(id)):
		return false
	_list("orders").append({"item": id, "arrive_at": Clock.total_minutes() + delivery_minutes()})
	EventBus.order_placed.emit(id)
	return true


## Заказы в пути: [{item, arrive_at}].
static func orders() -> Array:
	return _list("orders")


## Прошло время: всё, что приехало, — в инвентарь героя (место под заказ оставлено при заказе).
## Курьера слышно, но он не будит.
static func on_time_passed() -> void:
	var now: int = Clock.total_minutes()
	var waiting: Array = _list("orders")
	var arrived: Array = waiting.filter(func(o: Dictionary) -> bool: return int(o["arrive_at"]) <= now)
	if arrived.is_empty():
		return
	for o: Dictionary in arrived:
		waiting.erase(o)
		var id: String = str(o["item"])
		Inventory.add(Inventory.HERO, id, "", true)
		EventBus.order_delivered.emit(id)


## Что даёт еда: сытость (энергетик — энергия сразу и откат потом). Занимает `eat_minutes`
## игрового времени. Убрать порцию из контейнера — дело `Inventory.eat`.
static func apply_food(id: String) -> void:
	var def: Dictionary = item(id)
	Needs.eat(float(def.get("satiety", 0)))
	if float(def.get("energy", 0)) > 0.0:
		Needs.drink_energy(float(def["energy"]), float(def.get("crash", 0)), int(def.get("crash_after_minutes", 0)))
	EventBus.food_consumed.emit(id)
	Clock.advance(int(def.get("eat_minutes", 0)))


static func _list(key: String) -> Array:
	var state: Dictionary = GameState.economy_state()
	if not state.has(key):
		state[key] = []
	return state[key]
