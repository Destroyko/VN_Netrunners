extends GutTest
## Mailbox: доставка письма эффектом, прочитано, вложения на свой ПК, ответ один раз
## (docs/tech/quest-format.md).

const TEST_MAIL: String = "mail_test_order"


func before_each() -> void:
	GameState.reset()
	DataLoader.clear_cache()


func _uid() -> String:
	return str(Mailbox.inbox()[0]["uid"])


func test_send_message_effect_delivers_letter() -> void:
	assert_true(Effects.apply({"send_message": TEST_MAIL}))
	assert_eq(Mailbox.inbox().size(), 1)
	assert_eq(Mailbox.unread_count(), 1)


func test_unknown_letter_is_not_delivered() -> void:
	assert_false(Mailbox.deliver("mail_ghost"))
	assert_eq(Mailbox.inbox().size(), 0)
	assert_push_error_count(1)


func test_same_letter_can_come_twice() -> void:
	Mailbox.deliver(TEST_MAIL)
	Mailbox.deliver(TEST_MAIL)
	var inbox: Array = Mailbox.inbox()
	assert_eq(inbox.size(), 2)
	assert_ne(str(inbox[0]["uid"]), str(inbox[1]["uid"]))


func test_reading_marks_letter_read() -> void:
	Mailbox.deliver(TEST_MAIL)
	Mailbox.mark_read(_uid())
	assert_eq(Mailbox.unread_count(), 0)


func test_reply_applies_effects_once() -> void:
	Mailbox.deliver(TEST_MAIL)
	var replied: Dictionary = {"reply": ""}
	var spy := func(_uid: String, _id: String, reply_id: String) -> void: replied["reply"] = reply_id
	EventBus.mail_replied.connect(spy)
	assert_true(Mailbox.reply(_uid(), "accept"))
	EventBus.mail_replied.disconnect(spy)
	assert_true(GameState.has_flag("world.test_mail_accepted"))
	assert_eq(str(replied["reply"]), "accept", "квест узнает об ответе из шины")
	assert_false(Mailbox.reply(_uid(), "decline"), "ответить можно один раз")
	assert_eq(Mailbox.available_replies(_uid()).size(), 0)


func test_unknown_reply_is_rejected() -> void:
	Mailbox.deliver(TEST_MAIL)
	assert_false(Mailbox.reply(_uid(), "maybe"))


func test_attachment_is_saved_home_with_file_id() -> void:
	Mailbox.deliver(TEST_MAIL)
	var path: String = Mailbox.save_attachment(_uid(), 0)
	assert_eq(path, "/home/mail/instrukciya.txt")
	var home: Filesystem = Filesystem.for_node(Network.HOME_ID)
	assert_true(home.has_file(path))
	assert_true(home.has_file_id("file_test_instruction"), "условия квестов найдут файл по file_id")


func test_second_save_does_not_overwrite() -> void:
	Mailbox.deliver(TEST_MAIL)
	Mailbox.save_attachment(_uid(), 0)
	assert_eq(Mailbox.save_attachment(_uid(), 0), "/home/mail/instrukciya_2.txt")


func test_mail_is_saved_with_the_game() -> void:
	Mailbox.deliver(TEST_MAIL)
	Mailbox.reply(_uid(), "decline")
	var saved: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(saved)
	assert_eq(str(Mailbox.inbox()[0]["reply"]), "decline")


func test_validator_checks_letters() -> void:
	var v := Validator.new()
	v.validate_data({}, {}, {}, {}, {
		"mail_bad": {"id": "mail_bad", "from": "x", "subject": "y", "body": "z",
			"replies": [{"id": "a", "text": "A"}, {"id": "a", "text": "B", "effects": [{"send_message": "mail_none"}]}]},
		"oops": {"id": "oops"},
	})
	var text: String = "\n".join(v.errors)
	assert_string_contains(text, "два ответа")
	assert_string_contains(text, "несуществующее письмо")
	assert_string_contains(text, "должен начинаться с 'mail_'")
	assert_string_contains(text, "нет обязательного поля 'from'")
