class_name Economy
extends RefCounted
## Деньги, счета и история операций (docs/gameplay/economy.md): аренда по понедельникам,
## оплата руками в банке, просрочка — напоминание и пеня за каждый день.
##
## Чистые правила без сцен. Слушает начало дня автозагрузка `EconomyManager`, приложение банка
## только показывает и передаёт «оплатить». Деньги лежат в `GameState.money`, счета и история —
## в `GameState.economy_state()`. Числа — `balance.json`, `economy`.
##
## Проигрыша нет: неоплаченный счёт копит пеню и неделю за неделей просрочки; разговор с
## арендодателем и выселение — с диалогами (M3+).

const KIND_RENT: String = "rent"
## Сколько последних операций помнит банк.
const HISTORY_LIMIT: int = 100


# --- Деньги и история -----------------------------------------------------------

## Поступление (заказ, подработка). `label` — строка в истории банка.
static func earn(amount: int, label: String) -> void:
	if amount == 0:
		return
	GameState.add_money(amount)
	_record(amount, label)


## Списать деньги. Не хватает — ничего не списывается, false.
static func spend(amount: int, label: String) -> bool:
	if amount < 0 or not GameState.can_afford(amount):
		return false
	if amount > 0:
		GameState.add_money(-amount)
		_record(-amount, label)
	return true


## Изменение денег эффектом данных (квест, сцена): тоже строка в истории.
static func apply_delta(delta: int, label: String) -> void:
	if delta >= 0:
		earn(delta, label)
	else:
		GameState.add_money(delta)
		_record(delta, label)


## История: новые в конце, [{day, minute, amount, label}].
static func history() -> Array:
	return _state().get("history", []) as Array


# --- Счета ----------------------------------------------------------------------

static func bills() -> Array:
	return _state().get("bills", []) as Array


static func unpaid() -> Array:
	return bills().filter(func(b: Dictionary) -> bool: return not bool(b["paid"]))


static func bill(id: String) -> Dictionary:
	for b: Dictionary in bills():
		if str(b["id"]) == id:
			return b
	return {}


## Сколько стоит закрыть счёт сейчас: сумма плюс накопленная пеня.
static func total_of(b: Dictionary) -> int:
	return int(b["amount"]) + int(b["penalty"])


static func is_overdue(b: Dictionary, day: int = GameState.day) -> bool:
	return not bool(b["paid"]) and day > int(b["due_day"])


## Выставить счёт. Срок — `due_days` дней с выставления.
static func issue(kind: String, title: String, amount: int) -> Dictionary:
	var b: Dictionary = {
		"id": "%s_%d" % [kind, GameState.day],
		"kind": kind,
		"title": title,
		"amount": amount,
		"issued_day": GameState.day,
		"due_day": GameState.day + _num("rent_due_days", 3),
		"penalty": 0,
		"paid": false,
		"reminded": false,
	}
	_bills_mut().append(b)
	EventBus.bill_issued.emit(str(b["id"]))
	return b


## Оплатить счёт целиком (с пеней). Не хватает денег или счёт уже закрыт — false.
static func pay(id: String) -> bool:
	var b: Dictionary = bill(id)
	if b.is_empty() or bool(b["paid"]):
		return false
	if not spend(total_of(b), str(b["title"])):
		return false
	b["paid"] = true
	b["paid_day"] = GameState.day
	EventBus.bill_paid.emit(id)
	return true


## Начался день: в день аренды — новый счёт; у просроченных — пеня за день и (один раз)
## напоминание. Пеня начисляется со дня после срока.
static func on_day_started(day: int) -> void:
	for b: Dictionary in unpaid():
		if is_overdue(b, day):
			b["penalty"] = int(b["penalty"]) + _num("rent_penalty_per_day", 10)
			if not bool(b["reminded"]):
				b["reminded"] = true
				EventBus.bill_overdue.emit(str(b["id"]))
	if int(Clock.date_of(day)["weekday"]) == _num("rent_day_of_week", 1):
		issue(KIND_RENT, "Аренда квартиры", _num("rent_per_week", 200))


## Сколько недель счёт просрочен (0 — в срок). Пока только для банка; на этом счётчике потом
## встанут разговор с арендодателем и выселение.
static func overdue_weeks(b: Dictionary, day: int = GameState.day) -> int:
	if not is_overdue(b, day):
		return 0
	return (day - int(b["due_day"]) - 1) / 7 + 1


## Новая игра: стартовые деньги из баланса (без строки в истории — это не операция).
static func start_new_game() -> void:
	GameState.set_money(_num("start_money", 150))


# --- Внутреннее -----------------------------------------------------------------

static func _record(amount: int, label: String) -> void:
	var state: Dictionary = _state()
	if not state.has("history"):
		state["history"] = []
	var list: Array = state["history"]
	list.append({"day": GameState.day, "minute": GameState.minute, "amount": amount, "label": label})
	while list.size() > HISTORY_LIMIT:
		list.pop_front()


static func _bills_mut() -> Array:
	var state: Dictionary = _state()
	if not state.has("bills"):
		state["bills"] = []
	return state["bills"]


static func _state() -> Dictionary:
	return GameState.economy_state()


static func _num(key: String, fallback: int) -> int:
	var section: Dictionary = DataLoader.balance().get("economy", {}) as Dictionary
	return int(section.get(key, fallback))
