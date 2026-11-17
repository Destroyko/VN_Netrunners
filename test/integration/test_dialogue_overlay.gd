extends GutTest
## Окно диалогов поверх сцены: набор текста, клик во время набора — строка целиком, выборы
## кнопками, журнал по H (docs/tech/dialogue-format.md).

var overlay: CanvasLayer


func before_each() -> void:
	GameState.reset()
	DialogueManager.clear()
	Clock.reset_pauses()
	overlay = get_tree().root.get_node("DialogueOverlay") as CanvasLayer


func after_each() -> void:
	DialogueManager.clear()
	overlay.call("set_speed", AppSettings.DEFAULT_TEXT_SPEED)
	if bool(overlay.call("journal_visible")):
		overlay.call("toggle_journal")


func test_text_types_and_click_shows_whole_line() -> void:
	DialogueManager.request("dlg_test")
	overlay.call("set_speed", 10.0)
	overlay.call("show_node")
	assert_true(overlay.box.visible, "окно показано")
	assert_string_contains(str(overlay.call("speaker_text")), str(DataLoader.names()["name_roommate"]))
	assert_true(bool(overlay.call("is_typing")), "текст набирается постепенно")
	overlay.call("proceed")
	assert_false(bool(overlay.call("is_typing")), "клик во время набора — вся строка сразу")
	assert_eq(DialogueManager.current.node_id, "hello", "и не перескочил на следующую реплику")
	overlay.call("proceed")
	assert_eq(DialogueManager.current.node_id, "ask", "второй клик — дальше")


func test_instant_speed_shows_whole_line() -> void:
	DialogueManager.request("dlg_test")
	overlay.call("set_speed", 0.0)
	overlay.call("show_node")
	assert_false(bool(overlay.call("is_typing")))
	assert_string_contains(str(overlay.call("shown_text")), "новый жилец")


func test_choices_are_buttons() -> void:
	DialogueManager.request("dlg_test")
	overlay.call("set_speed", 0.0)
	DialogueManager.advance()
	var choice: Button = overlay.find_child("Choice_0", true, false) as Button
	assert_not_null(choice)
	assert_string_contains(str(overlay.call("shown_text")), "passhound", "термин в тексте")
	choice.emit_signal("pressed")
	assert_eq(DialogueManager.current.node_id, "more")


func test_box_hides_when_dialogue_ends() -> void:
	DialogueManager.request("dlg_test")
	DialogueManager.clear()
	assert_false(overlay.box.visible)


func test_journal_lists_lines() -> void:
	DialogueManager.request("dlg_test")
	DialogueManager.advance()
	DialogueManager.choose(1)
	overlay.call("toggle_journal")
	assert_true(bool(overlay.call("journal_visible")))
	var text: String = str(overlay.call("journal_text"))
	assert_string_contains(text, "новый жилец")
	assert_string_contains(text, "→ Не сейчас.", "выбор игрока отмечен стрелкой")
