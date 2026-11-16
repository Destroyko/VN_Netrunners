extends "res://test/unit/terminal_fixture.gd"
## Первая подработка: цепочка заказов через настоящий терминал и почту
## (docs/story/side-quests/first-job.md). Проверяем ключевые заказы, не все шесть целиком.


func _start_job_chain() -> void:
	# День 1, 08:00 — как при «Новой игре»; триггер старта шлёт дневник и ставит заказ на 09:00.
	Clock.set_time(1, 8 * 60)
	EventBus.game_started.emit()
	Clock.advance(60)  # 09:00 — приходит первый заказ


func test_start_sends_diary_and_first_order() -> void:
	_start_job_chain()
	var home: Filesystem = Filesystem.for_node(Network.HOME_ID)
	assert_true(home.has_file("/home/dnevnik/01_nachalo.txt"), "дневник на месте")
	assert_true(Quests.is_active("side_job_1"), "первый заказ пришёл в 9:00")
	var ids: Array = Mailbox.inbox().map(func(e: Dictionary) -> String: return str(e["id"]))
	assert_true(ids.has("mail_job_1"), "письмо с заданием")
	assert_true(home.has_file("/home/job/programma.bin"), "файлы для разноски у героя")


func test_job1_put_on_four_pcs_pays_and_chains() -> void:
	_start_job_chain()
	GameState.set_money(0)
	for addr: String in ["203.0.113.11", "203.0.113.12", "203.0.113.13", "203.0.113.14"]:
		run("connect " + addr)
		run("put /home/job/programma.bin /home/work/programma.bin")
		run("dc")
	assert_true(GameState.is_quest_completed("side_job_1"), "все четыре ПК — заказ закрыт")
	assert_eq(GameState.money, 60, "оплата за заказ")
	# Следующий заказ запланирован на завтра 9:00.
	Clock.advance(24 * 60)
	assert_true(Quests.is_active("side_job_2"), "второй заказ пришёл на следующее утро")


func test_job2_delete_files() -> void:
	_start_job_chain()
	Effects.apply({"unlock_quest": "side_job_2"})
	run("connect 203.0.113.21")
	run("rm /home/lichnoe/foto_s_dachi.jpg")
	run("rm /home/lichnoe/spisok_del.txt")
	run("rm /home/work/staryj_otchet.doc")
	assert_true(GameState.is_quest_completed("side_job_2"), "комп подготовлен")


func test_job4_deliver_report_to_boss_by_mail() -> void:
	_start_job_chain()
	Effects.apply({"unlock_quest": "side_job_4"})
	assert_true(Mailbox.contacts().has("boss@firma.local"), "адрес босса — из письма коллеги")
	run("connect 203.0.113.41")
	run("cp /home/work/otchet_nedelya.doc")
	run("dc")
	# Отправить боссу со своего ПК: вложение — скачанный отчёт.
	var attachment: String = Terminal.DUMP_DIR + "/otchet_nedelya.doc"
	assert_true(t.home_fs().has_file(attachment), "отчёт скачан к себе")
	assert_true(Mailbox.send("boss@firma.local", "Отчёт", "Во вложении", PackedStringArray([attachment])))
	assert_true(GameState.is_quest_completed("side_job_4"), "отчёт доставлен — заказ закрыт")


func test_job6_choice_to_keep_copy() -> void:
	_start_job_chain()
	Effects.apply({"unlock_quest": "side_job_6"})
	run("connect 203.0.113.61")
	run("cp /home/work/proekt_itog.doc")
	run("rm /home/corp/baza_klientov.db")
	assert_eq(GameState.get_quest_stage("side_job_6"), "decide", "рабочий снят, корп удалён")
	var uid: String = ""
	for e: Dictionary in Mailbox.inbox():
		if str(e["id"]) == "mail_job_6_decide":
			uid = str(e["uid"])
	assert_true(Mailbox.reply(uid, "keep"))
	assert_true(GameState.is_quest_completed("side_job_6"))
	assert_true(GameState.has_flag("world.job6_kept"))
	assert_true(GameState.has_flag("story.first_job_done"))
