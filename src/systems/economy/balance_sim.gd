class_name BalanceSim
extends RefCounted
## Симуляция баланса (docs/tech/testing.md, «Экономика и баланс»): простой «бот» проживает N
## игровых дней на настоящих правилах и автозагрузках и пишет отчёт — деньги, доход с заказов,
## еда, аренда, сытость, энергия. Нужен, чтобы подобрать первые числа `balance.json` не на бумаге.
##
## Бот нарочно простой и «честный середняк»: каждый день сдаёт пришедший заказ подработки, ест
## доставкой, когда проголодался, платит аренду, как только хватает денег, и спит ночью. Как
## именно он выполняет заказ (команды, сеть), не важно: важны деньги и время.
##
## Состояние игры сбрасывается: запускать в инструменте или тесте, не в живой игре.

const FOOD: String = "food_lunch"
const HUNGRY_BELOW: float = 60.0
const WAKE_AT: int = 7 * 60
const ORDER_AT: int = 9 * 60 + 30
const EVENING_AT: int = 19 * 60


## Прожить `days` дней. Возвращает {rows: [по дню], summary: PackedStringArray}.
static func run(days: int, seed_value: int = 1) -> Dictionary:
	GameState.reset()
	Clock.reload_config()
	Rng.set_seed(seed_value)
	var needs_was: bool = NeedsManager.always_on
	NeedsManager.always_on = true
	Economy.start_new_game()
	Clock.set_time(1, 0)
	EventBus.game_started.emit()

	var rows: Array = []
	for day: int in range(1, days + 1):
		var row: Dictionary = {"day": day, "date": Clock.format_date(day), "money_start": GameState.money,
			"income": 0, "food": 0, "rent": 0, "job": ""}
		_advance_to(ORDER_AT)
		_do_job(row)
		_eat(row)
		_pay(row)
		_advance_to(EVENING_AT)
		_eat(row)
		_pay(row)
		row["satiety"] = snappedf(Needs.satiety(), 0.1)
		row["energy"] = snappedf(Needs.energy(), 0.1)
		row["debt"] = _debt()
		Rest.sleep_until(WAKE_AT)
		row["money_end"] = GameState.money
		rows.append(row)

	NeedsManager.always_on = needs_was
	return {"rows": rows, "summary": _summary(rows)}


static func _advance_to(minute: int) -> void:
	if minute > GameState.minute:
		Clock.advance(minute - GameState.minute)


## Сдать пришедший заказ подработки: исход done (оплата и следующий заказ назавтра).
static func _do_job(row: Dictionary) -> void:
	for id: String in Quests.active():
		if id.begins_with("side_job_"):
			var before: int = GameState.money
			Quests.finish(id, Quests.OUTCOME_DONE)
			row["income"] = int(row["income"]) + GameState.money - before
			row["job"] = id
			return


## Проголодался — заказать обед, дождаться курьера, съесть.
static func _eat(row: Dictionary) -> void:
	if Needs.satiety() >= HUNGRY_BELOW:
		return
	var before: int = GameState.money
	if not Shop.order(FOOD):
		return
	row["food"] = int(row["food"]) + before - GameState.money
	Clock.advance(Shop.delivery_minutes())
	Inventory.eat(Inventory.first_uid(FOOD))


## Заплатить все счета, на которые хватает денег.
static func _pay(row: Dictionary) -> void:
	for b: Dictionary in Economy.unpaid():
		var before: int = GameState.money
		if Economy.pay(str(b["id"])):
			row["rent"] = int(row["rent"]) + before - GameState.money


static func _debt() -> int:
	var total: int = 0
	for b: Dictionary in Economy.unpaid():
		total += Economy.total_of(b)
	return total


static func _summary(rows: Array) -> PackedStringArray:
	var lines: PackedStringArray = []
	lines.append("День | Дата           | Утро ₽ | Заказ      | +Доход | −Еда | −Аренда | Вечер ₽ | Долг | Сыт  | Энерг")
	var income: int = 0
	var food: int = 0
	var rent: int = 0
	for r: Dictionary in rows:
		income += int(r["income"])
		food += int(r["food"])
		rent += int(r["rent"])
		lines.append("%4d | %-14s | %6d | %-10s | %6d | %4d | %7d | %7d | %4d | %4.0f | %5.0f" % [
			int(r["day"]), str(r["date"]), int(r["money_start"]), str(r["job"]).trim_prefix("side_"),
			int(r["income"]), int(r["food"]), int(r["rent"]), int(r["money_end"]), int(r["debt"]),
			float(r["satiety"]), float(r["energy"])])
	var last: Dictionary = rows[rows.size() - 1] if not rows.is_empty() else {}
	lines.append("")
	lines.append("Итого за %d дн.: доход %d, еда %d, аренда %d, на руках %d, долг %d." % [
		rows.size(), income, food, rent, int(last.get("money_end", 0)), int(last.get("debt", 0))])
	return lines
