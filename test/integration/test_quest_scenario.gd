extends "res://test/unit/terminal_fixture.gd"
## Сценарий квеста целиком через настоящий терминал и почту: письмо с заданием → взлом → `cp`
## нужного файла → письмо с выбором → ответ → оплата (docs/tech/quest-format.md).


func test_quest_from_brief_to_payment() -> void:
	GameState.set_money(0)
	Effects.apply({"unlock_quest": "side_test_courier"})
	assert_eq(str(Mailbox.inbox()[0]["id"]), "mail_test_courier_brief", "задание пришло письмом")

	enter("node_training_pc")
	assert_eq(GameState.get_quest_stage("side_test_courier"), "collect", "вошёл на узел")
	run("cp /home/zametka.txt")
	assert_eq(GameState.get_quest_stage("side_test_courier"), "decide", "скопировал нужный файл")

	var letter: Dictionary = Mailbox.inbox()[0]
	assert_eq(str(letter["id"]), "mail_test_courier_decide")
	assert_true(Mailbox.reply(str(letter["uid"]), "send"))
	assert_true(GameState.is_quest_completed("side_test_courier"))
	assert_eq(GameState.money, 50)
	assert_eq(str(Economy.history()[-1]["label"]), "Перевод", "оплата видна в банке")
