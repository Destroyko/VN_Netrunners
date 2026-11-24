extends GutTest
## Ворота механик среза (src/core/gates.gd, docs/tech/gates.md): по умолчанию закрыты и механику
## прячут, открытые — возвращают её. Сюжет здесь не нужен: ворота открывает сам тест.


func before_each() -> void:
	GameState.reset()
	Clock.reload_config()
	NeedsManager.always_on = true


func test_gates_are_closed_by_default() -> void:
	for gate: String in [Gates.HUNGER, Gates.SHOP, Gates.NEWS, Gates.AUTOCRACK]:
		assert_false(Gates.is_open(gate), "закрыты: " + gate)


func test_hunger_gate_freezes_satiety_and_hides_the_band() -> void:
	Needs.set_satiety(10.0)
	assert_eq(Needs.band(), Needs.BAND_NORMAL, "голод спрятан: даже при нуле сытости полоса обычная")
	Clock.advance(5 * 60)
	assert_eq(Needs.satiety(), 10.0, "сытость не тает")
	GameState.set_flag(Gates.HUNGER)
	assert_eq(Needs.band(), Needs.BAND_HUNGRY, "ворота открыты — голод работает")
	Clock.advance(5 * 60)
	assert_lt(Needs.satiety(), 10.0)


func test_hidden_apps_have_no_icon_until_the_gate_opens() -> void:
	for id: String in ["news", "shop"]:
		var app: Dictionary = Desktop.app_definition(id)
		assert_false(Desktop.is_shown(app), "скрыто: " + id)
		assert_false(Desktop.is_available(app))
	GameState.set_flag(Gates.NEWS)
	assert_true(Desktop.is_shown(Desktop.app_definition("news")))
	assert_false(Desktop.is_shown(Desktop.app_definition("shop")), "магазин за своими воротами")
	GameState.set_flag(Gates.SHOP)
	assert_true(Desktop.is_available(Desktop.app_definition("shop")))
