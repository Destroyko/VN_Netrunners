extends GutTest
## Shop: доставка еды в инвентарь, еда и энергетик с откатом (docs/gameplay/needs.md,
## inventory.md).


func _eat(kind: String) -> bool:
	return Inventory.eat(Inventory.first_uid(kind))

func before_each() -> void:
	GameState.reset()
	Clock.reload_config()
	GameState.set_money(100)


func test_order_takes_money_and_goes_on_the_way() -> void:
	assert_true(Shop.order("food_sandwich"))
	assert_eq(GameState.money, 91)
	assert_eq(Shop.orders().size(), 1)
	assert_string_contains(str(Economy.history()[0]["label"]), "Сэндвич")


func test_cannot_order_without_money_or_unknown_item() -> void:
	GameState.set_money(3)
	assert_false(Shop.order("food_sandwich"))
	assert_false(Shop.order("food_ghost"))
	assert_eq(GameState.money, 3)
	assert_eq(Shop.orders().size(), 0)


func test_delivery_arrives_after_delivery_minutes() -> void:
	Shop.order("food_lunch")
	Clock.advance(39)
	assert_eq(Inventory.count("food_lunch"), 0)
	Clock.advance(1)
	assert_eq(Inventory.count("food_lunch", Inventory.HERO), 1, "курьер отдал пакет — в инвентаре")
	assert_eq(Shop.orders().size(), 0)


func test_eating_fills_satiety_and_takes_time() -> void:
	Shop.order("food_lunch")
	Clock.advance(40)
	Needs.set_satiety(10.0)
	var before: int = Clock.total_minutes()
	assert_true(_eat("food_lunch"))
	assert_almost_eq(Needs.satiety(), 65.0, 0.01)
	assert_eq(Clock.total_minutes() - before, 20, "обед — 20 минут")
	assert_false(_eat("food_lunch"), "съел — больше нет")


func test_each_portion_takes_a_slot() -> void:
	Shop.order("food_noodles")
	Shop.order("food_noodles")
	Clock.advance(40)
	assert_eq(Inventory.list(Inventory.HERO).size(), 2, "стопок нет: две лапши — два слота")
	_eat("food_noodles")
	assert_eq(Inventory.count("food_noodles"), 1)


func test_full_inventory_blocks_order() -> void:
	for i: int in Inventory.capacity(Inventory.HERO) - 1:
		Inventory.add(Inventory.HERO, "food_noodles")
	assert_true(Shop.order("food_noodles"), "последний слот — под заказ")
	assert_eq(Shop.order_error("food_noodles"), Shop.ERROR_FULL, "место занято заказом в пути")
	assert_false(Shop.order("food_noodles"))


func test_energy_drink_now_and_crash_later() -> void:
	NeedsManager.always_on = true
	Needs.set_satiety(50.0)
	Needs.set_energy(30.0)
	Shop.order("drink_energy")
	Clock.advance(40)
	var at_start: float = Needs.energy()
	_eat("drink_energy")
	assert_almost_eq(Needs.energy(), at_start + 10.0 - 2.0 / 60.0, 0.01, "+10 сразу (минута на банку)")
	Clock.advance(298)
	var before_crash: float = Needs.energy()
	Clock.advance(2)
	assert_lt(Needs.energy(), before_crash - 13.0, "через 5 часов — откат на 14")
	NeedsManager.always_on = false


func test_crash_can_knock_out() -> void:
	NeedsManager.always_on = true
	Needs.set_satiety(50.0)
	Needs.set_energy(5.0)
	Needs.drink_energy(10.0, 30.0, 60)
	var out: Dictionary = {"n": 0}
	var claim := func() -> void:
		out["n"] += 1
		NeedsManager.claim_pass_out()
	EventBus.passed_out.connect(claim)
	Clock.advance(61)
	await get_tree().process_frame
	EventBus.passed_out.disconnect(claim)
	NeedsManager.sleep_after_pass_out()
	NeedsManager.always_on = false
	assert_eq(int(out["n"]), 1, "откат энергетика довёл до нуля — вырубился")


func test_delivery_is_saved_with_the_game() -> void:
	Shop.order("food_noodles")
	var saved: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(saved)
	assert_eq(Shop.orders().size(), 1)
