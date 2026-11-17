extends "res://test/unit/terminal_fixture.gd"
## Первая подработка: цепочка заказов через настоящий терминал и почту
## (docs/story/side-quests/first-job.md). Проверяем ключевые заказы, не все шесть целиком.


func _start_job_chain() -> void:
	# День 1, 08:00 — как при «Новой игре»; триггер старта шлёт дневник и начинает неделю
	# подработки (side_first_job): первый заказ — в 09:00.
	Clock.set_time(1, 8 * 60)
	EventBus.game_started.emit()
	Clock.advance(60)  # 09:00 — приходит первый заказ
	_read_all_mail()


## Заказ начинается с «проверить почту»: адреса машин открываются, когда письмо прочитано.
func _read_all_mail() -> void:
	for e: Dictionary in Mailbox.inbox():
		Mailbox.mark_read(str(e["uid"]))


func _unlock(id: String) -> void:
	Effects.apply({"unlock_quest": id})
	_read_all_mail()


func test_start_sends_diary_and_first_order() -> void:
	_start_job_chain()
	var home: Filesystem = Filesystem.for_node(Network.HOME_ID)
	assert_true(home.has_file("/home/dnevnik/01_nachalo.txt"), "дневник на месте")
	assert_true(Quests.is_active("side_job_2"), "первым приходит «подготовить ПК», не «4 ПК подряд»")
	var ids: Array = Mailbox.inbox().map(func(e: Dictionary) -> String: return str(e["id"]))
	assert_true(ids.has("mail_job_2"), "письмо с заданием")


func test_job_order_two_three_one_four() -> void:
	var order: Array = []
	for stage: Dictionary in Quests.definition("side_first_job")["stages"] as Array:
		for objective: Dictionary in stage.get("objectives", []) as Array:
			if str(objective["type"]) == "complete_quest":
				order.append(str(objective["quest"]))
	assert_eq(order, ["side_job_2", "side_job_3", "side_job_1", "side_job_4", "side_job_5", "side_job_6"])


func test_order_waits_for_mail_to_be_read() -> void:
	Clock.set_time(1, 8 * 60)
	EventBus.game_started.emit()
	Clock.advance(60)
	assert_eq(GameState.get_quest_stage("side_job_2"), "mail", "сначала — проверить почту")
	_read_all_mail()
	assert_eq(GameState.get_quest_stage("side_job_2"), "do", "прочитал письмо — за работу")


func test_week_goes_on_next_morning() -> void:
	_start_job_chain()
	assert_eq(Planner.tracked(), "side_first_job", "в трекере — неделя, а не отдельный заказ")
	assert_eq(Planner.subtitle("side_first_job"), Planner.title_of("side_job_2"))
	run("connect 203.0.113.21")
	run("rm /home/lichnoe/foto_s_dachi.jpg")
	run("rm /home/lichnoe/spisok_del.txt")
	run("rm /home/work/staryj_otchet.doc")
	run("dc")
	_report()
	assert_true(GameState.is_quest_completed("side_job_2"))
	var steps: Array = Planner.current_steps("side_first_job")
	assert_string_contains(str(steps[0]["text"]), "утра", "между заказами — «дождаться утра»")
	Clock.advance(23 * 60)  # 08:00 следующего дня
	assert_false(Quests.is_active("side_job_3"), "раньше девяти заказа нет")
	Clock.advance(60)
	assert_true(Quests.is_active("side_job_3"), "утром — следующий заказ")
	assert_eq(str(Planner.current_steps("side_first_job")[0]["text"]), "Проверить почту")


func test_job1_files_come_as_attachments() -> void:
	_start_job_chain()
	_unlock("side_job_1")
	assert_false(Filesystem.for_node(Network.HOME_ID).has_file("/home/job/programma.bin"), "файлы сами на ПК не появляются")
	var letter: Dictionary = {}
	for e: Dictionary in Mailbox.inbox():
		if str(e["id"]) == "mail_job_1":
			letter = e
	assert_eq(Mailbox.save_attachment(str(letter["uid"]), 0), "/home/mail/programma.bin", "программа — вложением письма")


## Отписаться диспетчеру: заказ закрывается письмом «Готово».
func _report() -> void:
	assert_true(Mailbox.send("dispatch@autsors.local", "Готово", "", PackedStringArray()))


## Сохранить вложения письма заказа к себе (в /home/mail).
func _save_job1_attachments() -> void:
	for e: Dictionary in Mailbox.inbox():
		if str(e["id"]) == "mail_job_1":
			Mailbox.save_attachment(str(e["uid"]), 0)
			Mailbox.save_attachment(str(e["uid"]), 1)


func test_job1_put_on_four_pcs_pays_and_chains() -> void:
	_start_job_chain()
	_unlock("side_job_1")
	_save_job1_attachments()
	GameState.set_money(0)
	for addr: String in ["203.0.113.11", "203.0.113.12", "203.0.113.13", "203.0.113.14"]:
		run("connect " + addr)
		var text: String = run("put /home/mail/*.* /home/work/")
		assert_string_contains(text, "programma.bin  40 КБ  100%", "отчёт о передаче")
		assert_string_contains(text, "instrukciya.txt", "маска унесла и инструкцию")
		assert_string_contains(text, "передано файлов:", "итог по пачке")
		run("dc")
	assert_false(GameState.is_quest_completed("side_job_1"), "работа сделана, но ещё не отписался")
	assert_eq(GameState.get_quest_stage("side_job_1"), "report")
	_report()
	assert_true(GameState.is_quest_completed("side_job_1"), "отписался — заказ закрыт")
	assert_eq(GameState.money, 60, "оплата за заказ")
	var ids: Array = Mailbox.inbox().map(func(e: Dictionary) -> String: return str(e["id"]))
	assert_true(ids.has("mail_job_done"), "заказчик ответил: принято, на сегодня всё")


func test_job2_delete_files() -> void:
	_start_job_chain()
	run("connect 203.0.113.21")
	run("rm /home/lichnoe/foto_s_dachi.jpg")
	run("rm /home/lichnoe/spisok_del.txt")
	run("rm /home/work/staryj_otchet.doc")
	_report()
	assert_true(GameState.is_quest_completed("side_job_2"), "комп подготовлен и отписался")


func test_job4_deliver_report_to_boss_by_mail() -> void:
	_start_job_chain()
	_unlock("side_job_4")
	assert_true(Mailbox.contacts().has("boss@firma.local"), "адрес босса — из письма коллеги")
	run("connect 203.0.113.41")
	run("cp /home/work/otchet_nedelya.doc")
	run("dc")
	# Отправить боссу со своего ПК: вложение — скачанный отчёт.
	var attachment: String = Terminal.DUMP_DIR + "/otchet_nedelya.doc"
	assert_true(t.home_fs().has_file(attachment), "отчёт скачан к себе")
	assert_true(Mailbox.send("boss@firma.local", "Отчёт", "Во вложении", PackedStringArray([attachment])))
	assert_true(GameState.is_quest_completed("side_job_4"), "отчёт доставлен — заказ закрыт")
	assert_false(Mailbox.contacts().has("boss@firma.local"), "босс клиента больше не нужен — из адресной книги убран")
	assert_false(Mailbox.contacts().has("kolleg@firma.local"))


func test_job6_hidden_copy_shows_only_after_done() -> void:
	_start_job_chain()
	_unlock("side_job_6")
	var said: Dictionary = {"text": ""}
	var spy := func(text: String) -> void: said["text"] = text
	EventBus.hero_thought.connect(spy)
	run("connect 203.0.113.61")
	EventBus.hero_thought.disconnect(spy)
	assert_string_contains(str(said["text"]), "одним глазком", "намёк — мысль вслух при первом входе")
	var keys: Array = Quests.visible_objectives("side_job_6").map(func(o: Dictionary) -> String: return str(o["key"]))
	assert_false(keys.has("p0"), "скрытая цель не видна, пока не сделана")
	run("cp /home/corp/baza_klientov.db")
	keys = Quests.visible_objectives("side_job_6").map(func(o: Dictionary) -> String: return str(o["key"]))
	assert_true(keys.has("p0"), "сделал — появилась в чекпоинтах")
	assert_true(GameState.has_flag("world.job6_kept"))


func test_job6_closes_by_deleting_without_choice() -> void:
	_start_job_chain()
	_unlock("side_job_6")
	run("connect 203.0.113.61")
	run("cp /home/work/proekt_itog.doc")
	run("rm /home/corp/baza_klientov.db")
	_report()
	assert_true(GameState.is_quest_completed("side_job_6"), "выбора нет: удалил и отписался — заказ закрыт")
	assert_false(GameState.has_flag("world.job6_kept"), "не копировал — скрытая цель не сделана")
	assert_true(GameState.has_flag("story.first_job_done"))


func test_job_machines_keep_no_logs_under_cover() -> void:
	_start_job_chain()
	_unlock("side_job_1")
	_save_job1_attachments()
	assert_true(GameState.has_flag("gate.cover"), "на подработке за героем подчищают")
	run("connect 203.0.113.11")
	run("put /home/mail/programma.bin /home/work/programma.bin")
	run("dc")
	assert_true(Logbook.for_node("node_job1_pc_a").is_empty(), "записей о герое в логе клиента нет")
