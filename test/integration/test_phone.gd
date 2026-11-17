extends GutTest
## Смартфон (docs/gameplay/devices.md): свёрнут в углу со строкой состояния, Q достаёт и убирает,
## приложения, меню игры его прячет, вне игры его нет.

var holder: Control


func before_each() -> void:
	GameState.reset()
	Clock.reset_pauses()
	DialogueManager.clear()
	holder = Control.new()
	add_child_autofree(holder)
	PhoneOverlay.attach(holder)


func after_each() -> void:
	PhoneOverlay.detach(holder)
	Clock.reset_pauses()


func _press_q() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_Q
	key.pressed = true
	PhoneOverlay._unhandled_input(key)


func test_phone_lies_folded_with_status() -> void:
	assert_true(PhoneOverlay.frame.visible)
	assert_false(PhoneOverlay.is_open())
	GameState.add_money(150)
	assert_eq(PhoneOverlay.status().money_text(), "%d ₽" % GameState.money, "деньги видно всегда")


func test_q_opens_and_closes() -> void:
	_press_q()
	assert_true(PhoneOverlay.is_open())
	assert_not_null(PhoneOverlay.app_node().find_child("App_messages", true, false), "домашний экран со значками")
	_press_q()
	assert_false(PhoneOverlay.is_open())


func test_no_phone_outside_the_game() -> void:
	PhoneOverlay.detach(holder)
	assert_false(PhoneOverlay.frame.visible, "в главном меню телефона нет")
	PhoneOverlay.open()
	assert_false(PhoneOverlay.is_open())


func test_pause_menu_hides_phone() -> void:
	PhoneOverlay.open()
	Clock.pause(PauseMenu.PAUSE_REASON)
	PhoneOverlay._process(0.0)
	assert_false(PhoneOverlay.frame.visible)
	assert_false(PhoneOverlay.is_open())
	Clock.resume(PauseMenu.PAUSE_REASON)
	PhoneOverlay._process(0.0)
	assert_true(PhoneOverlay.frame.visible, "меню закрыли — телефон снова в углу")


func test_no_phone_during_dialogue() -> void:
	DialogueManager.request("dlg_test")
	_press_q()
	assert_false(PhoneOverlay.is_open())


func test_unread_badge_and_messages_app() -> void:
	Messenger.deliver("msg_test")
	assert_string_contains(PhoneOverlay.status().unread_text(), "1", "непрочитанное видно в строке")
	PhoneOverlay.open("messages")
	var app: MessagesApp = PhoneOverlay.app_node() as MessagesApp
	assert_not_null(app.chat_button("roommate"))
	app.open_chat("roommate")
	assert_eq(Messenger.unread_count(), 0, "открыл чат — прочитано")
	assert_string_contains(app.thread_text(), "Ты дома?")
	app.reply_button(0).emit_signal("pressed")
	assert_string_contains(app.thread_text(), "Дома.")
	assert_string_contains(app.thread_text(), "после одиннадцати", "пришёл ответ на ответ")
	assert_null(app.reply_button(0), "ответить можно один раз")


func test_apps_from_pc_open_in_phone() -> void:
	for app: String in ["mail", "bank", "news", "shop"]:
		PhoneOverlay.open(app)
		assert_eq(PhoneOverlay.current_app(), app)
		assert_not_null(PhoneOverlay.app_node(), app)


func test_alarm_from_phone_only_sets_time() -> void:
	PhoneOverlay.open("alarm")
	var alarm: AlarmApp = PhoneOverlay.app_node() as AlarmApp
	assert_false((alarm.find_child("Sleep", true, false) as Button).visible, "спать — только у кровати")
	assert_false((alarm.find_child("Wait", true, false) as Button).visible)


func test_stub_apps_are_grey() -> void:
	PhoneOverlay.open()
	for id: String in ["tasks", "map"]:
		assert_true((PhoneOverlay.app_node().find_child("App_" + id, true, false) as Button).disabled, id)
