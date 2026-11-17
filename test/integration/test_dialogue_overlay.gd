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


## Настоящий клик мышью в точку экрана.
func _click(at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_viewport().push_input(event)


func test_mouse_click_on_text_goes_to_next_line() -> void:
	DialogueManager.request("dlg_test")
	overlay.call("set_speed", 0.0)
	overlay.call("show_node")
	await wait_process_frames(2)
	var text: Control = overlay.find_child("Text", true, false) as Control
	_click(text.get_global_rect().get_center())
	await wait_process_frames(1)
	assert_eq(DialogueManager.current.node_id, "ask", "клик мышью по тексту реплики — следующая реплика")


## Клик вне панели ловит прозрачная подложка на весь экран. Точкой экрана в тестах это не
## проверить — там поверх рисуется окно GUT, — поэтому событие отдаём подложке напрямую.
func test_click_outside_box_also_goes_on() -> void:
	DialogueManager.request("dlg_test")
	overlay.call("set_speed", 0.0)
	overlay.call("show_node")
	var catcher: Control = overlay.find_child("ClickCatcher", true, false) as Control
	assert_true(catcher.visible, "пока идёт диалог, подложка на месте")
	assert_eq(catcher.mouse_filter, Control.MOUSE_FILTER_STOP, "сцена под диалогом не кликается")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	catcher.gui_input.emit(event)
	assert_eq(DialogueManager.current.node_id, "ask", "клик в любом месте экрана — дальше")


func test_first_click_completes_line_second_goes_on() -> void:
	DialogueManager.request("dlg_test")
	overlay.call("set_speed", 5.0)
	overlay.call("show_node")
	await wait_process_frames(2)
	var text: Control = overlay.find_child("Text", true, false) as Control
	assert_true(bool(overlay.call("is_typing")))
	_click(text.get_global_rect().get_center())
	await wait_process_frames(1)
	assert_false(bool(overlay.call("is_typing")), "первый клик — строка целиком")
	assert_eq(DialogueManager.current.node_id, "hello")
	_click(text.get_global_rect().get_center())
	await wait_process_frames(1)
	assert_eq(DialogueManager.current.node_id, "ask", "второй клик — следующая реплика")
