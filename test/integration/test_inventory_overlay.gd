extends GutTest
## Окно инвентаря (`I`): слоты, действия с выбранным, переложить в открытый контейнер,
## выбросить с подтверждением, переименовать, вне игры его нет.

var holder: Control


func before_each() -> void:
	GameState.reset()
	Clock.reset_pauses()
	holder = Control.new()
	add_child_autofree(holder)
	PhoneOverlay.attach(holder)


func after_each() -> void:
	InventoryOverlay.close()
	PhoneOverlay.detach(holder)


func _press_i() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_I
	key.pressed = true
	InventoryOverlay._unhandled_input(key)


func test_i_opens_and_shows_slots() -> void:
	Inventory.add(Inventory.HERO, "food_noodles")
	_press_i()
	assert_true(InventoryOverlay.is_open())
	assert_eq(InventoryOverlay.slot(Inventory.HERO, 0).text, Shop.title_of("food_noodles"))
	assert_true(InventoryOverlay.slot(Inventory.HERO, 1).disabled, "пустой слот")
	_press_i()
	assert_false(InventoryOverlay.is_open())


func test_no_inventory_outside_the_game() -> void:
	PhoneOverlay.detach(holder)
	InventoryOverlay.open()
	assert_false(InventoryOverlay.is_open())


func test_eat_from_inventory() -> void:
	GameState.set_flag(Gates.HUNGER)
	Needs.set_satiety(10.0)
	var uid: String = Inventory.add(Inventory.HERO, "food_noodles")
	InventoryOverlay.open()
	InventoryOverlay.select(uid)
	InventoryOverlay.detail("Eat").emit_signal("pressed")
	assert_almost_eq(Needs.satiety(), 30.0, 0.5, "съел прямо из инвентаря")


func test_move_into_open_fridge() -> void:
	var uid: String = Inventory.add(Inventory.HERO, "food_noodles")
	InventoryOverlay.open(Inventory.FRIDGE)
	InventoryOverlay.select(uid)
	InventoryOverlay.detail("Move").emit_signal("pressed")
	assert_eq(Inventory.count("food_noodles", Inventory.FRIDGE), 1)
	assert_true(bool(InventoryOverlay._can_drop(Vector2.ZERO, {"inventory_uid": uid}, Inventory.HERO)), "обратно — перетаскиванием")


func test_discard_asks_first() -> void:
	Inventory.give("item_flash_backup")
	InventoryOverlay.open()
	InventoryOverlay.select(Inventory.first_uid("item_flash_backup"))
	InventoryOverlay.detail("Discard").emit_signal("pressed")
	assert_true(Inventory.has("item_flash_backup"), "сначала — вопрос")
	InventoryOverlay.detail("Yes").emit_signal("pressed")
	assert_false(Inventory.has("item_flash_backup"))


func test_rename_from_window() -> void:
	Inventory.give("item_flash_backup")
	var uid: String = Inventory.first_uid("item_flash_backup")
	InventoryOverlay.open()
	InventoryOverlay.select(uid)
	InventoryOverlay.detail("Rename").emit_signal("pressed")
	InventoryOverlay.rename_field().text_submitted.emit("резерв")
	assert_eq(InventoryOverlay.slot(Inventory.HERO, 0).text, "резерв")
