extends GutTest
## Темы разговора с персонажем (заготовка): видны по условиям, одноразовая — один раз.


func before_each() -> void:
	GameState.reset()
	DialogueManager.clear()


func _ids() -> Array:
	return CharacterTopics.available("roommate").map(func(t: Dictionary) -> String: return str(t["id"]))


func test_topics_follow_conditions_and_once() -> void:
	assert_eq(_ids(), ["smalltalk"], "тема о пробежке закрыта, пока квест её не открыл")
	GameState.set_flag("quest.example.ask_run")
	assert_eq(_ids(), ["smalltalk", "run"])
	assert_true(CharacterTopics.choose("roommate", "run"), "тема начинает свой диалог")
	assert_eq(_ids(), ["smalltalk"], "одноразовая — больше не видна")
	assert_false(CharacterTopics.choose("roommate", "run"))
