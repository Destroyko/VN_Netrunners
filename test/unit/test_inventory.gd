extends GutTest
## Инвентарь и хранилища (docs/gameplay/inventory.md): экземпляры, слоты, что куда кладётся,
## съесть, переименовать, выбросить, квестовые вещи, гнездо ПК, сейв.

const FLASH: String = "item_flash_backup"


func before_each() -> void:
	GameState.reset()


func test_each_thing_is_its_own_slot() -> void:
	Inventory.add(Inventory.HERO, "food_noodles")
	Inventory.add(Inventory.HERO, "food_noodles")
	assert_eq(Inventory.list(Inventory.HERO).size(), 2)
	assert_eq(Inventory.free_slots(Inventory.HERO), 28, "30 слотов из balance.json")


func test_full_container_takes_nothing() -> void:
	for i: int in Inventory.capacity(Inventory.HERO):
		assert_false(Inventory.add(Inventory.HERO, "food_noodles").is_empty())
	assert_true(Inventory.add(Inventory.HERO, "food_noodles").is_empty(), "полон — не взять")


func test_what_goes_where() -> void:
	var noodles: String = Inventory.add(Inventory.HERO, "food_noodles")
	Inventory.give(FLASH)
	var flash: String = Inventory.first_uid(FLASH)
	assert_eq(Inventory.move(noodles, Inventory.STORAGE), Inventory.ERROR_WRONG, "еду — не в шкаф")
	assert_eq(Inventory.move(flash, Inventory.FRIDGE), Inventory.ERROR_WRONG, "флешку — не в холодильник")
	assert_eq(Inventory.move(noodles, Inventory.FRIDGE), "")
	assert_eq(Inventory.move(flash, Inventory.STORAGE), "")
	assert_eq(Inventory.list(Inventory.HERO).size(), 0)
	assert_true(Inventory.has(FLASH), "вещь в шкафу — всё ещё вещь героя")


func test_eat_from_fridge() -> void:
	Needs.set_satiety(10.0)
	var uid: String = Inventory.add(Inventory.FRIDGE, "food_noodles")
	assert_true(Inventory.eat(uid))
	assert_almost_eq(Needs.satiety(), 30.0, 0.5)
	assert_eq(Inventory.count("food_noodles"), 0)
	Inventory.give(FLASH)
	assert_false(Inventory.eat(Inventory.first_uid(FLASH)), "флешку не съесть")


func test_rename_and_label() -> void:
	Inventory.give(FLASH)
	var uid: String = Inventory.first_uid(FLASH)
	assert_true(Inventory.rename(uid, "  с системой "))
	assert_eq(Inventory.label_of(Inventory.find(uid)["entry"] as Dictionary), "с системой")


func test_quest_item_cannot_be_thrown_away_until_quest_ends() -> void:
	Effects.apply({"give_item": {"item": FLASH, "quest": "side_test_courier"}})
	var uid: String = Inventory.first_uid(FLASH)
	assert_eq(Inventory.discard(uid), Inventory.ERROR_QUEST)
	GameState.set_quest_completed("side_test_courier")
	assert_eq(Inventory.discard(uid), "", "квест закончен — можно")
	assert_false(Inventory.has(FLASH))


func test_story_give_ignores_full_inventory() -> void:
	for i: int in Inventory.capacity(Inventory.HERO):
		Inventory.add(Inventory.HERO, "food_noodles")
	assert_true(Inventory.give(FLASH), "сюжетная вещь не теряется из-за полного инвентаря")
	assert_true(Inventory.has(FLASH))


func test_pc_slot_holds_one_flash() -> void:
	Inventory.give(FLASH)
	Inventory.give(FLASH)
	var home: Filesystem = Filesystem.for_node(Network.HOME_ID)
	var first: Dictionary = Room.insert(Inventory.first_uid(FLASH), home)
	assert_true(bool(first["ok"]))
	var second: Dictionary = Room.insert(Inventory.first_uid(FLASH), home)
	assert_false(bool(second["ok"]), "гнездо одно")
	assert_string_contains("\n".join(second["lines"] as PackedStringArray), "уже стоит")
	assert_eq(Room.eject(), "")
	assert_eq(Inventory.count(FLASH, Inventory.HERO), 2)


func test_inventory_is_saved() -> void:
	Inventory.give(FLASH)
	Inventory.rename(Inventory.first_uid(FLASH), "моя")
	var saved: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(saved)
	assert_eq(Inventory.label_of(Inventory.list(Inventory.HERO)[0] as Dictionary), "моя")
