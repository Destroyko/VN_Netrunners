extends GutTest
## Quests и Triggers: квест из JSON целиком — старт, цели по событиям шины, необязательная цель,
## выбор ответом на письмо, срок и исходы; триггеры по событиям (docs/tech/quest-format.md).
## Квест — пробный `side_test_courier` из data/quests/side.

const QUEST: String = "side_test_courier"
const NODE: String = "node_training_pc"
const DAY: int = 24 * 60


func before_each() -> void:
	GameState.reset()
	Clock.reload_config()


func _mail_ids() -> Array:
	return Mailbox.inbox().map(func(e: Dictionary) -> String: return str(e["id"]))


func _reach_decide() -> void:
	Quests.start(QUEST)
	EventBus.node_connected.emit(NODE)
	EventBus.file_copied.emit(NODE, "/home/zametka.txt")


# --- Старт ----------------------------------------------------------------------

func test_unlock_quest_effect_starts_first_stage_and_sends_brief() -> void:
	assert_true(Effects.apply({"unlock_quest": QUEST}))
	assert_true(Quests.is_active(QUEST))
	assert_eq(GameState.get_quest_stage(QUEST), "get_in")
	assert_true(_mail_ids().has("mail_test_courier_brief"), "эффект этапа: письмо с заданием")


func test_quest_starts_once() -> void:
	assert_true(Quests.start(QUEST))
	assert_false(Quests.start(QUEST))


# --- Цели -----------------------------------------------------------------------

func test_objectives_close_by_bus_events() -> void:
	Quests.start(QUEST)
	EventBus.node_connected.emit("node_home_router")
	assert_eq(GameState.get_quest_stage(QUEST), "get_in", "не тот узел")
	EventBus.node_connected.emit(NODE)
	assert_eq(GameState.get_quest_stage(QUEST), "collect")
	EventBus.file_copied.emit(NODE, "/home/privet.txt")
	assert_eq(GameState.get_quest_stage(QUEST), "collect", "не тот файл")
	EventBus.file_copied.emit(NODE, "/home/zametka.txt")
	assert_eq(GameState.get_quest_stage(QUEST), "decide")
	assert_true(_mail_ids().has("mail_test_courier_decide"))


func test_optional_wipe_logs_pays_bonus_only_when_clean() -> void:
	Quests.start(QUEST)
	EventBus.node_connected.emit(NODE)
	GameState.set_money(0)
	var book: Logbook = Logbook.for_node(NODE)
	book.append(Logbook.CATEGORY_FILE_DELETED, "удалён x", 1, 600, false, "x")
	EventBus.node_disconnected.emit(NODE)
	assert_eq(GameState.money, 0, "наследил — бонуса нет")
	assert_false(Quests.is_done(QUEST, "p0"))
	Logbook.for_node(NODE).clear()
	book = Logbook.for_node(NODE)
	book.append(Logbook.CATEGORY_SESSION, "выход", 1, 610, false, "logout")
	EventBus.node_disconnected.emit(NODE)
	assert_true(Quests.is_done(QUEST, "p0"), "почистил — осталась только запись о сеансе")
	assert_eq(GameState.money, 10, "бонус из on_done")


# --- Выбор и исходы -------------------------------------------------------------

func test_choice_by_mail_reply_finishes_with_outcome() -> void:
	_reach_decide()
	GameState.set_money(0)
	var uid: String = str(Mailbox.inbox()[0]["uid"])
	assert_true(Mailbox.reply(uid, "send"))
	assert_true(GameState.is_quest_completed(QUEST))
	assert_eq(GameState.money, 50, "исход done — оплата")


func test_other_choice_leads_to_other_outcome() -> void:
	_reach_decide()
	assert_true(Quests.choose(QUEST, "keep"))
	assert_true(GameState.has_flag("world.test_courier_kept"))


func test_choice_is_only_possible_on_its_stage() -> void:
	Quests.start(QUEST)
	assert_false(Quests.choose(QUEST, "send"), "до этапа выбора — нельзя")
	assert_false(Quests.choose(QUEST, "nonsense"))


# --- Срок -----------------------------------------------------------------------

func test_deadline_expires_into_expired_outcome() -> void:
	Quests.start(QUEST)
	assert_eq(Quests.due_day(QUEST), 3)
	Clock.advance(3 * DAY - GameState.minute - 1)
	assert_true(Quests.is_active(QUEST), "весь третий день — ещё в срок")
	Clock.advance(1)
	assert_false(Quests.is_active(QUEST))
	assert_true(GameState.has_flag("world.test_courier_expired"))


func test_finished_quest_ignores_events() -> void:
	_reach_decide()
	Quests.choose(QUEST, "send")
	var money: int = GameState.money
	EventBus.node_disconnected.emit(NODE)
	Clock.advance(5 * DAY)
	assert_eq(GameState.money, money, "законченный квест больше ничего не платит")


func test_quest_progress_is_saved() -> void:
	Quests.start(QUEST)
	EventBus.node_connected.emit(NODE)
	var saved: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(saved)
	assert_eq(GameState.get_quest_stage(QUEST), "collect")


func test_schedule_news_effect_queues_for_morning() -> void:
	Effects.apply({"schedule_news": {"id": "news_x", "delay_days": 2}})
	var queue: Array = GameState.get_var_or(Effects.VAR_NEWS_QUEUE, []) as Array
	assert_eq(queue.size(), 1)
	assert_eq(int(queue[0]["day"]), 3)


# --- Цели «по состоянию» --------------------------------------------------------

func test_deliver_objective_closes_by_sent_letter() -> void:
	var objective: Dictionary = {"type": "deliver", "what": "file_test_instruction", "to": "dispatch@example.local"}
	var sent := {"event": "mail_sent", "to": "dispatch@example.local", "file_id": "file_test_instruction"}
	assert_true(QuestObjectives.matches(objective, sent))
	sent["to"] = "boss@client.local"
	assert_false(QuestObjectives.matches(objective, sent), "не тому")


func test_file_at_objective_checks_path_on_node() -> void:
	var objective: Dictionary = {"type": "file_at", "node": "node_training_pc", "path": "/home/zametka.txt"}
	assert_true(QuestObjectives.satisfied(objective))
	objective["path"] = "/home/nope.txt"
	assert_false(QuestObjectives.satisfied(objective))


# --- Триггеры -------------------------------------------------------------------

func test_rent_reminder_letter_comes_on_overdue() -> void:
	Clock.advance(9 * DAY - GameState.minute - (GameState.day - 1) * DAY)
	assert_true(_mail_ids().has("mail_rent_reminder"), "аренда просрочена — письмо домовладельца")


func test_once_trigger_fires_only_once_and_checks_requires() -> void:
	var list: Dictionary = {
		"trigger_a": {"id": "trigger_a", "on": "day_started", "once": true, "effects": [{"money": 5}]},
		"trigger_b": {"id": "trigger_b", "on": "day_started", "requires": [{"flag": "world.never"}], "effects": [{"money": 100}]},
	}
	GameState.set_money(0)
	assert_eq(Triggers.fire("day_started", list), PackedStringArray(["trigger_a"]))
	assert_eq(Triggers.fire("day_started", list).size(), 0, "once — один раз")
	assert_eq(GameState.money, 5)


func test_quest_console_commands() -> void:
	assert_string_contains(DebugCommands.run("quest start " + QUEST), "начат")
	assert_string_contains(DebugCommands.run("quest"), "этап get_in")
	assert_string_contains(DebugCommands.run("quest choose %s send" % QUEST), "нет")
