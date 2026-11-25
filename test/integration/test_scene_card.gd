extends GutTest
## Карточка сцены (как в новеллах): значок и слово фазы суток, время, место; показывается при
## входе в место и при смене фазы суток.


func before_each() -> void:
	GameState.reset()
	SceneCard.animate = false


func after_each() -> void:
	SceneCard.animate = true


func _card() -> SceneCard:
	var card := SceneCard.new()
	card.use_theme(GameTheme.current_id)
	add_child_autofree(card)
	return card


func test_shows_phase_time_and_place() -> void:
	Clock.set_time(1, 20 * 60)
	var card: SceneCard = _card()
	card.show_place("Комната")
	assert_true(card.shown(), "пришёл в место — карточка видна")
	assert_eq(card.place_text(), "Комната")
	assert_string_contains(card.time_text(), "Вечер")
	assert_string_contains(card.time_text(), "20:00")
	assert_eq(card.phase(), "evening")


func test_every_phase_has_word_and_icon() -> void:
	for phase: String in SceneCard.PHASES.keys():
		var icon: String = str((SceneCard.PHASES[phase] as Dictionary)["icon"])
		assert_not_null(GameTheme.glyph(icon), "значок фазы есть: " + icon)


func test_phase_change_shows_card_again() -> void:
	Clock.set_time(1, 22 * 60)
	var card: SceneCard = _card()
	card.show_place("Комната")
	card.modulate.a = 0.0
	Clock.set_time(1, 22 * 60 + 30)
	card.refresh_time()
	assert_false(card.shown(), "та же фаза — карточка не мелькает")
	Clock.set_time(2, 9 * 60)
	card.refresh_time()
	assert_true(card.shown(), "проснулся утром — карточка снова видна")
	assert_string_contains(card.time_text(), "Утро")


func test_room_scene_has_card_top_left() -> void:
	Clock.set_time(1, 12 * 60)
	var room: Node = load(Screens.ROOM).instantiate()
	add_child_autofree(room)
	var card: SceneCard = room.call("scene_card") as SceneCard
	assert_not_null(card)
	assert_eq(card.place_text(), "Комната")
	assert_string_contains(str(room.call("clock_text")), "День")
