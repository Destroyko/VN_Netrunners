extends GutTest
## Почта на стыке с удалением писем и повторной доставкой (docs/tech/interactions.md;
## docs/issues.md: ISS-012, ISS-013). У доставленного письма свой `uid`; цель `read_mail` ищет
## письмо по `id`.

const OpenIssue = preload("res://test/invariants/open_issue.gd")


func before_each() -> void:
	GameState.reset()
	DataLoader.clear_cache()


func _uids() -> Array:
	return Mailbox.inbox().map(func(e: Dictionary) -> String: return str(e["uid"]))


func test_uids_stay_unique_after_delete() -> void:
	Mailbox.deliver("mail_rent_reminder")
	Mailbox.deliver("mail_test_long")
	assert_true(Mailbox.delete(str(_uids()[0])), "письмо без ответов и квеста удаляется")
	Mailbox.deliver("mail_test_long")
	var uids: Array = _uids()
	assert_eq(uids.size(), 2)
	assert_ne(uids[0], uids[1], "у каждого доставленного письма свой uid")
	# Одинаковый uid — ответ и «прочитано» уходят первому письму с ним, второе недостижимо.
	Mailbox.mark_read(str(uids[0]))
	assert_false(bool((Mailbox.inbox()[1] as Dictionary)["read"]), "прочитано только открытое письмо")


## Повторная доставка того же письма (шаблоны radiant): цель «прочитать письмо» нового этапа
## не закрывается прочитанной старой копией.
func test_read_mail_objective_ignores_an_old_read_copy() -> void:
	Mailbox.deliver("mail_job_1")
	Mailbox.mark_read(str(_uids()[0]))
	assert_true(Quests.start("side_job_1"))
	assert_eq(GameState.get_quest_stage("side_job_1"), "mail", "новое письмо ещё не прочитано")



func test_uid_carries_number_and_day() -> void:
	Mailbox.deliver("mail_rent_reminder")
	assert_eq(str(_uids()[0]), "mail_rent_reminder#1@d%d" % GameState.day)


## Письмо прочитали раньше, чем начался этап «прочитать», — цель закрыта (софтлока нет).
func test_read_mail_objective_counts_a_copy_read_in_advance() -> void:
	Mailbox.deliver("mail_test_long")
	Mailbox.mark_read(str(_uids()[0]))
	assert_true(QuestObjectives.satisfied({"type": "read_mail", "mail": "mail_test_long"}, 1))
