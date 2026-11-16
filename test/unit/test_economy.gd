extends GutTest
## Economy: деньги и история, аренда по понедельникам, оплата руками, просрочка с пеней
## (docs/gameplay/economy.md).

const DAY: int = 24 * 60

var _overdue: Array[String] = []


func before_each() -> void:
	GameState.reset()
	Clock.reload_config()
	_overdue.clear()
	EventBus.bill_overdue.connect(_on_overdue)


func after_each() -> void:
	EventBus.bill_overdue.disconnect(_on_overdue)


func _on_overdue(id: String) -> void:
	_overdue.append(id)


## Перейти к началу дня `day` (день 1 — четверг, 2 апреля).
func _go_to_day(day: int) -> void:
	Clock.advance((day - GameState.day) * DAY - GameState.minute)


# --- Деньги и история -----------------------------------------------------------

func test_new_game_starts_with_money_from_balance() -> void:
	Economy.start_new_game()
	assert_eq(GameState.money, 150)
	assert_eq(Economy.history().size(), 0, "стартовые деньги — не операция")


func test_earn_and_spend_are_recorded() -> void:
	Economy.earn(300, "Заказ")
	assert_true(Economy.spend(120, "Доставка"))
	assert_eq(GameState.money, 180)
	var h: Array = Economy.history()
	assert_eq(h.size(), 2)
	assert_eq(int(h[1]["amount"]), -120)
	assert_eq(str(h[1]["label"]), "Доставка")


func test_cannot_spend_more_than_you_have() -> void:
	GameState.set_money(50)
	assert_false(Economy.spend(60, "Что-то"))
	assert_eq(GameState.money, 50)
	assert_eq(Economy.history().size(), 0)


func test_money_effect_goes_to_history() -> void:
	Effects.apply({"money": 500})
	assert_eq(GameState.money, 500)
	assert_eq(str(Economy.history()[0]["label"]), "Перевод")


# --- Аренда ---------------------------------------------------------------------

func test_first_rent_comes_on_monday_the_fifth_day() -> void:
	_go_to_day(4)
	assert_eq(Economy.bills().size(), 0, "чт, пт, сб, вс — без аренды")
	_go_to_day(5)
	var open: Array = Economy.unpaid()
	assert_eq(open.size(), 1)
	assert_eq(int(open[0]["amount"]), 200)
	assert_eq(int(open[0]["due_day"]), 8, "срок — три дня")


func test_rent_is_not_taken_by_itself() -> void:
	GameState.set_money(1000)
	_go_to_day(5)
	assert_eq(GameState.money, 1000, "платят руками в банке")


func test_paying_rent_closes_the_bill() -> void:
	GameState.set_money(250)
	_go_to_day(5)
	var id: String = str(Economy.unpaid()[0]["id"])
	assert_true(Economy.pay(id))
	assert_eq(GameState.money, 50)
	assert_eq(Economy.unpaid().size(), 0)
	assert_false(Economy.pay(id), "второй раз не платится")


func test_cannot_pay_without_money() -> void:
	GameState.set_money(100)
	_go_to_day(5)
	var id: String = str(Economy.unpaid()[0]["id"])
	assert_false(Economy.pay(id))
	assert_eq(GameState.money, 100)


func test_rent_comes_every_monday() -> void:
	_go_to_day(19)
	assert_eq(Economy.bills().size(), 3, "дни 5, 12, 19")


# --- Просрочка ------------------------------------------------------------------

func test_overdue_brings_one_reminder_and_daily_penalty() -> void:
	_go_to_day(8)
	var b: Dictionary = Economy.unpaid()[0]
	assert_false(Economy.is_overdue(b), "в день срока ещё не просрочено")
	assert_eq(_overdue.size(), 0)
	_go_to_day(9)
	assert_eq(int(b["penalty"]), 10)
	assert_eq(_overdue.size(), 1)
	_go_to_day(11)
	assert_eq(int(b["penalty"]), 30, "пеня за каждый день")
	assert_eq(_overdue.size(), 1, "напоминание одно")
	assert_eq(Economy.total_of(b), 230)


func test_paying_overdue_includes_penalty() -> void:
	GameState.set_money(1000)
	_go_to_day(10)
	var b: Dictionary = Economy.bill("rent_5")
	assert_true(Economy.pay("rent_5"))
	assert_eq(GameState.money, 1000 - 220)
	_go_to_day(12)
	assert_eq(int(b["penalty"]), 20, "оплаченный счёт пеню больше не копит")


func test_overdue_weeks_counter() -> void:
	_go_to_day(9)
	var b: Dictionary = Economy.bill("rent_5")
	assert_eq(Economy.overdue_weeks(b), 1)
	assert_eq(Economy.overdue_weeks(b, 15), 1)
	assert_eq(Economy.overdue_weeks(b, 16), 2)


func test_economy_is_saved_with_the_game() -> void:
	_go_to_day(5)
	var saved: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(saved)
	assert_eq(Economy.unpaid().size(), 1)


func test_old_save_without_economy_loads_empty() -> void:
	var saved: Dictionary = GameState.to_dict()
	saved.erase("economy")
	GameState.from_dict(saved)
	assert_eq(Economy.bills().size(), 0)
