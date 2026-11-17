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


# --- Адресная книга и исходящие -------------------------------------------------

func test_contacts_learned_from_sender_and_letter() -> void:
	Mailbox.deliver(TEST_MAIL)
	assert_true(Mailbox.contacts().has("dispatch@example.local"), "отправитель — в адресной книге")
	Mailbox.deliver("mail_rent_reminder")
	assert_false(Mailbox.contacts().has("Домовладелец"), "имя без @ — не адрес")
	Effects.apply({"add_contact": "boss@client.local"})
	assert_true(Mailbox.contacts().has("boss@client.local"))


func test_send_only_to_known_address_with_existing_file() -> void:
	Mailbox.deliver(TEST_MAIL)
	assert_false(Mailbox.send("nobody@x.local", "t", "b"), "неизвестный адрес — не уходит")
	assert_false(Mailbox.send("dispatch@example.local", "t", "b", PackedStringArray(["/home/nope.txt"])))
	var path: String = Mailbox.save_attachment(_uid(), 0)
	var second: String = Mailbox.save_attachment(_uid(), 0)
	var got: Dictionary = {"ids": PackedStringArray()}
	var spy := func(_to: String, file_ids: PackedStringArray) -> void: got["ids"] = file_ids
	EventBus.mail_sent.connect(spy)
	assert_true(Mailbox.send("dispatch@example.local", "Отчёт", "Во вложении", PackedStringArray([path, second])))
	EventBus.mail_sent.disconnect(spy)
	assert_true((got["ids"] as PackedStringArray).has("file_test_instruction"))
	assert_eq((Mailbox.sent()[0]["files"] as Array).size(), 2, "несколько вложений")


func test_add_file_effect_puts_file_home() -> void:
	Effects.apply({"add_file": {"path": "/home/dnevnik/01.txt", "text": "Страница", "file_id": "file_page"}})
	var home: Filesystem = Filesystem.for_node(Network.HOME_ID)
	assert_true(home.has_file("/home/dnevnik/01.txt"))
	assert_eq(str(home.file_data("/home/dnevnik/01.txt").get("text", "")), "Страница")


func test_schedule_effect_fires_at_given_time() -> void:
	Clock.set_time(1, 20 * 60)
	Effects.apply({"schedule": {"delay_days": 1, "at": "09:00", "effects": [{"send_message": TEST_MAIL}]}})
	Clock.advance(12 * 60)  # 08:00 следующего дня
	assert_eq(Mailbox.inbox().size(), 0)
	Clock.advance(60)
	assert_eq(Mailbox.inbox().size(), 1, "письмо пришло ровно в 9:00")
	assert_eq(Schedule.pending().size(), 0)


# --- Ответить и лишние адреса (плейтест M2) --------------------------------------

func test_reply_draft_uses_sender_and_reply_subject() -> void:
	Mailbox.deliver("mail_job_1")
	var draft: Dictionary = Mailbox.reply_draft(_uid())
	assert_eq(str(draft["to"]), "dispatch@autsors.local")
	assert_eq(str(draft["subject"]), "Готово")
	Mailbox.deliver("mail_rent_reminder")
	assert_true(Mailbox.reply_draft(_uid()).is_empty(), "у домовладельца нет адреса — ответить некуда")


func test_forget_contact_effect() -> void:
	Mailbox.deliver("mail_job_4")
	assert_true(Mailbox.contacts().has("boss@firma.local"))
	Effects.apply({"forget_contact": "boss@firma.local"})
	assert_false(Mailbox.contacts().has("boss@firma.local"))

