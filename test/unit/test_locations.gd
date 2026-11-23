extends GutTest
## Локации (docs/gameplay/locations.md): где герой, видимость объектов по условиям, двери,
## цель visit_location, эффект move_to, проверка данных.


func before_each() -> void:
	GameState.reset()


func test_hero_starts_at_home() -> void:
	assert_eq(Locations.current(), "loc_room", "начинает игру в комнате")
	assert_eq(Locations.home(), "loc_room", "дом — из balance.json")


func test_unknown_location_in_save_falls_back_home() -> void:
	GameState.set_var(Locations.VAR_LOCATION, "loc_gone")
	assert_eq(Locations.current(), "loc_room", "локацию убрали из данных — сейв не ломается")


func test_door_moves_hero_and_tells_the_bus() -> void:
	watch_signals(EventBus)
	var result: Dictionary = Locations.use_door("to_desk")
	assert_true(bool(result["ok"]), "подойти к ПК — переход к другому кадру комнаты")
	assert_eq(Locations.current(), "loc_room_desk")
	assert_signal_emitted_with_parameters(EventBus, "location_entered", ["loc_room_desk"])
	assert_true(bool(Locations.use_door("turn_back")["ok"]), "отойти — тот же переход")
	assert_true(bool(Locations.use_door("door_corridor")["ok"]))
	assert_eq(str(GameState.to_dict()["vars"].get(Locations.VAR_LOCATION, "")), "loc_corridor", "место — в сейве")


func test_door_of_another_location_is_not_usable() -> void:
	assert_false(bool(Locations.use_door("door_kitchen")["ok"]), "дверь на кухню — в коридоре, не в комнате")
	assert_eq(Locations.current(), "loc_room")


func test_object_visibility_and_locked_door_follow_conditions() -> void:
	var def: Dictionary = {"id": "loc_t", "title": "T", "objects": [
		{"id": "secret", "kind": "look", "text": "!", "rect": [0, 0, 0.1, 0.1], "requires": [{"flag": "world.t_seen"}]},
		{"id": "door", "kind": "door", "to": "loc_room_desk", "rect": [0, 0, 0.1, 0.1],
			"open_requires": [{"flag": "world.t_key"}], "locked_text": "Закрыто на ключ."},
	]}
	DataLoader.locations()["loc_t"] = def
	GameState.set_var(Locations.VAR_LOCATION, "loc_t")
	assert_eq(Locations.objects("loc_t").size(), 1, "скрытый объект не виден")
	GameState.set_flag("world.t_seen")
	assert_eq(Locations.objects("loc_t").size(), 2)
	var locked: Dictionary = Locations.use_door("door")
	assert_false(bool(locked["ok"]))
	assert_eq(str(locked["text"]), "Закрыто на ключ.")
	GameState.set_flag("world.t_key")
	assert_true(bool(Locations.use_door("door")["ok"]))
	assert_eq(Locations.current(), "loc_room_desk")
	DataLoader.clear_cache()


func test_time_of_day_has_four_parts() -> void:
	assert_eq(Locations.time_of_day(3 * 60), Locations.TIME_NIGHT)
	assert_eq(Locations.time_of_day(9 * 60), Locations.TIME_MORNING)
	assert_eq(Locations.time_of_day(12 * 60), Locations.TIME_DAY)
	assert_eq(Locations.time_of_day(19 * 60), Locations.TIME_EVENING)
	assert_eq(Locations.time_of_day(23 * 60), Locations.TIME_NIGHT)


func test_background_follows_time_of_day() -> void:
	assert_eq(Locations.background_image("loc_kitchen", 12 * 60), "res://assets/backgrounds/bg_kitchen_day.png")
	assert_eq(Locations.background_image("loc_kitchen", 19 * 60), "res://assets/backgrounds/bg_kitchen_evening.png")
	assert_eq(Locations.background_image("loc_kitchen", 23 * 60), "res://assets/backgrounds/bg_kitchen_night.png")


func test_background_follows_pc_state() -> void:
	assert_eq(Locations.background_image("loc_room", 12 * 60, true), "res://assets/backgrounds/bg_room_main_day_pc_on.png")
	assert_eq(Locations.background_image("loc_room", 23 * 60, false), "res://assets/backgrounds/bg_room_main_night_pc_off.png")
	assert_eq(Locations.background_image("loc_room_desk", 19 * 60, true), "res://assets/backgrounds/bg_room_pc_evening_pc_on.png")


func test_morning_background_uses_day_picture() -> void:
	# картинок на утро пока нет: подставляется день (`background_alias` в balance.json)
	assert_eq(Locations.background_image("loc_kitchen", 9 * 60), "res://assets/backgrounds/bg_kitchen_day.png")


func test_visit_location_objective() -> void:
	var objective: Dictionary = {"type": "visit_location", "location": "loc_kitchen"}
	assert_true(QuestObjectives.matches(objective, {"event": "location_entered", "location": "loc_kitchen"}))
	assert_false(QuestObjectives.matches(objective, {"event": "location_entered", "location": "loc_hall"}))


func test_debug_go_command() -> void:
	assert_string_contains(DebugCommands.run("go loc_kitchen"), "loc_kitchen")
	assert_eq(Locations.current(), "loc_kitchen")
	assert_string_contains(DebugCommands.run("go loc_nope"), "нет такой локации")
	assert_push_error_count(1)


func test_move_to_effect() -> void:
	assert_true(Effects.apply({"move_to": "loc_kitchen"}))
	assert_eq(Locations.current(), "loc_kitchen")


func test_validator_catches_broken_locations() -> void:
	var v := LocationValidator.new()
	v.validate({
		"room_x": {"id": "room_x", "objects": [
			{"id": "a", "kind": "teleport", "rect": [0, 0, 0.1, 0.1]},
			{"id": "a", "kind": "door", "to": "loc_nowhere", "rect": [0.9, 0, 0.2, 0.1]},
			{"id": "b", "kind": "look", "rect": [0, 0]},
			{"id": "c", "kind": "dialogue", "dialogue": "dlg_ghost", "rect": [0, 0, 0.1, 0.1]},
		]},
	}, DataLoader.dialogues())
	var text: String = "\n".join(v.errors)
	assert_string_contains(text, "должен начинаться с 'loc_'")
	assert_string_contains(text, "нет title")
	assert_string_contains(text, "неизвестный kind")
	assert_string_contains(text, "повторяющийся id")
	assert_string_contains(text, "несуществующую локацию")
	assert_string_contains(text, "выходит за экран")
	assert_string_contains(text, "четыре числа")
	assert_string_contains(text, "у look нет text")
	assert_string_contains(text, "нет диалога")


func test_real_locations_are_valid() -> void:
	var v := LocationValidator.new()
	v.validate(DataLoader.locations(), DataLoader.dialogues())
	assert_eq(v.errors.size(), 0, "\n".join(v.errors))
