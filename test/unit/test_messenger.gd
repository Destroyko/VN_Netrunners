extends GutTest
## Мессенджер (docs/gameplay/messages.md): доставка эффектом, чаты, непрочитанное, ответ
## вариантом с эффектами, сейв, проверка данных. Сообщения — msg_test, msg_test_after.


func before_each() -> void:
	GameState.reset()


func test_message_arrives_by_effect() -> void:
	watch_signals(EventBus)
	assert_true(Effects.apply({"send_text": "msg_test"}))
	assert_signal_emitted(EventBus, "message_received")
	assert_eq(Messenger.chats(), PackedStringArray(["roommate"]))
	assert_eq(Messenger.unread_count(), 1)
	assert_eq(Messenger.unread_count("roommate"), 1)
	var entry: Dictionary = Messenger.thread("roommate")[0] as Dictionary
	assert_string_contains(Messenger.text_of(entry), str(DataLoader.names()["name_roommate"]), "имена подставлены")


func test_opening_chat_reads_it() -> void:
	Messenger.deliver("msg_test")
	Messenger.mark_read("roommate")
	assert_eq(Messenger.unread_count(), 0)


func test_reply_goes_into_thread_and_applies_effects() -> void:
	Messenger.deliver("msg_test")
	var uid: String = Messenger.awaiting_reply("roommate")
	assert_false(uid.is_empty(), "на сообщение можно ответить")
	watch_signals(EventBus)
	assert_true(Messenger.reply(uid, "yes"))
	assert_signal_emitted_with_parameters(EventBus, "message_replied", [uid, "msg_test", "yes"])
	var thread: Array = Messenger.thread("roommate")
	assert_eq(thread.size(), 3, "сообщение, ответ героя, ответ на ответ")
	assert_eq(Messenger.text_of(thread[1] as Dictionary), "Дома.")
	assert_eq(str((thread[2] as Dictionary)["id"]), "msg_test_after")
	assert_false(Messenger.reply(uid, "no"), "отвечают один раз")
	assert_eq(Messenger.awaiting_reply("roommate"), "")


func test_reply_effects_change_state() -> void:
	Messenger.deliver("msg_test")
	Messenger.reply(Messenger.awaiting_reply("roommate"), "no")
	assert_eq(int(GameState.get_var_or("rep.roommate", 0)), -1)


func test_chat_with_latest_message_comes_first() -> void:
	DataLoader.messages()
	Messenger.deliver("msg_test")
	var log: Array = GameState.get_var_or(Messenger.VAR_LOG, []) as Array
	log.append({"kind": Messenger.IN, "uid": "x#9", "id": "msg_test", "from": "mother", "day": 1, "minute": 0, "read": false, "reply": ""})
	assert_eq(Messenger.chats()[0], "mother")


func test_log_is_saved() -> void:
	Messenger.deliver("msg_test")
	var saved: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(saved)
	assert_eq(Messenger.unread_count(), 1, "переписка — в сейве")


func test_unknown_message_is_refused() -> void:
	assert_false(Messenger.deliver("msg_ghost"))
	assert_push_error_count(1)


func test_validator_catches_broken_messages() -> void:
	var v := Validator.new()
	v._validate_text_message("bad", {"id": "bad", "from": "ghost", "replies": [{"id": "a"}, {"id": "a", "text": "x"}]}, DataLoader.characters())
	var text: String = "\n".join(v.errors)
	assert_string_contains(text, "должен начинаться с 'msg_'")
	assert_string_contains(text, "неизвестный отправитель")
	assert_string_contains(text, "нужны id и text")
	assert_string_contains(text, "два ответа")
