extends GutTest
## Диалоги (docs/tech/dialogue-format.md): разметка текста, ход диалога, выборы и развилки,
## время на паузе, журнал, цель квеста «поговорить», проверка данных. Диалог — dlg_test.


func before_each() -> void:
	GameState.reset()
	DialogueManager.clear()
	Clock.reset_pauses()


func after_each() -> void:
	DialogueManager.clear()


# --- Текст ------------------------------------------------------------------------

func test_names_are_substituted() -> void:
	assert_eq(DialogueText.with_names("Я {name_roommate}."), "Я %s." % str(DataLoader.names()["name_roommate"]))


func test_terms_become_links_with_hint() -> void:
	var bb: String = DialogueText.to_bbcode("Запусти [[passhound]] на порт.")
	assert_string_contains(bb, "[url=term:passhound]passhound[/url]")
	assert_string_contains(DialogueText.hint("passhound"), "дамп")
	assert_eq(DialogueText.plain("Запусти [[passhound|программу]]."), "Запусти программу.")


func test_plain_square_brackets_are_not_markup() -> void:
	var bb: String = DialogueText.to_bbcode("Файл [важно].")
	assert_false(bb.contains("[важно]"), "скобки экранированы, а не приняты за тег")
	assert_eq(DialogueText.plain("Файл [важно]."), "Файл [важно].")


# --- Ход диалога ----------------------------------------------------------------------

func test_dialogue_runs_through_choice_to_end() -> void:
	assert_true(Effects.apply({"start_dialogue": "dlg_test"}))
	assert_true(DialogueManager.is_active())
	assert_true(Clock.is_paused(), "в диалоге время стоит")
	assert_eq(DialogueManager.current.node_id, "hello")
	DialogueManager.advance()
	assert_eq(DialogueManager.current.node_id, "ask")
	DialogueManager.advance()
	assert_eq(DialogueManager.current.node_id, "ask", "у узла с выборами клик не продвигает")
	assert_true(DialogueManager.choose(0))
	assert_eq(DialogueManager.current.node_id, "more")
	assert_true(GameState.has_flag("world.test_dialogue_more"), "эффект узла")
	DialogueManager.advance()  # bye
	DialogueManager.advance()  # narr
	DialogueManager.advance()  # конец
	assert_false(DialogueManager.is_active())
	assert_false(Clock.is_paused(), "диалог кончился — время пошло")


func test_choice_effects_apply() -> void:
	DialogueManager.request("dlg_test")
	DialogueManager.advance()
	DialogueManager.choose(1)
	assert_eq(int(GameState.get_var_or("rep.roommate", 0)), -1)


func test_hidden_choice_needs_its_condition() -> void:
	var run := DialogueRun.new()
	run._def = {"start": "a", "nodes": {"a": {"text": "?", "choices": [
		{"text": "всегда", "next": "a"}, {"text": "по флагу", "next": "a", "requires": [{"flag": "world.x"}]}]}}}
	run._enter("a")
	assert_eq(run.choices().size(), 1)
	GameState.set_flag("world.x")
	assert_eq(run.choices().size(), 2)


func test_branch_picks_first_matching() -> void:
	var run := DialogueRun.new()
	run._def = {"start": "b", "nodes": {
		"b": {"branch": [{"requires": [{"flag": "world.y"}], "next": "yes"}, {"next": "no"}]},
		"yes": {"text": "да", "end": true}, "no": {"text": "нет", "end": true}}}
	run._enter("b")
	assert_eq(run.node_id, "no")
	GameState.set_flag("world.y")
	run._enter("b")
	assert_eq(run.node_id, "yes")


func test_second_dialogue_waits_in_queue() -> void:
	DialogueManager.request("dlg_test")
	DialogueManager.request("dlg_test")
	for i: int in 3:
		DialogueManager.advance()
	DialogueManager.choose(1)
	DialogueManager.advance()
	DialogueManager.advance()
	assert_true(DialogueManager.is_active(), "первый кончился — начался следующий из очереди")
	assert_eq(DialogueManager.current.node_id, "hello")


func test_journal_keeps_lines_and_choices() -> void:
	DialogueManager.request("dlg_test")
	DialogueManager.advance()
	DialogueManager.choose(1)
	var journal: Array = DialogueRun.journal()
	assert_eq(str(journal[0]["speaker"]), "roommate")
	assert_true(bool(journal[2]["choice"]), "выбор игрока — в журнале")
	assert_false(str(journal[1]["text"]).contains("[["), "разметки в журнале нет")
	var saved: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(saved)
	assert_eq(DialogueRun.journal().size(), journal.size(), "журнал — в сейве")


func test_unknown_dialogue_is_refused() -> void:
	assert_false(DialogueManager.request("dlg_ghost"))
	assert_push_error_count(1)


# --- Квест «поговорить» ---------------------------------------------------------------

func test_talk_objective_closes_when_dialogue_ends() -> void:
	var objective: Dictionary = {"type": "talk", "dialogue": "dlg_test"}
	assert_true(QuestObjectives.matches(objective, {"event": "dialogue_ended", "dialogue": "dlg_test"}))
	assert_false(QuestObjectives.matches(objective, {"event": "dialogue_ended", "dialogue": "dlg_other"}))


# --- Проверка данных -------------------------------------------------------------------

func test_validator_catches_broken_dialogues() -> void:
	var v := DialogueValidator.new()
	v.validate({
		"dlg_bad": {"id": "dlg_bad", "start": "a", "nodes": {
			"a": {"speaker": "ghost", "emotion": "smirk", "text": "[[nope]]", "next": "zzz"},
			"b": {"text": "два выхода", "next": "a", "end": true},
		}},
		"talk_x": {"id": "talk_x", "start": "q", "nodes": {}},
	}, DataLoader.characters(), DataLoader.glossary())
	var text: String = "\n".join(v.errors)
	assert_string_contains(text, "неизвестный говорящий")
	assert_string_contains(text, "неизвестная эмоция")
	assert_string_contains(text, "несуществующий узел 'zzz'")
	assert_string_contains(text, "ровно одно")
	assert_string_contains(text, "термина 'nope'")
	assert_string_contains(text, "должен начинаться с 'dlg_'")
	assert_string_contains("\n".join(v.warnings), "недостижим")


func test_real_dialogues_are_valid() -> void:
	var v := DialogueValidator.new()
	v.validate(DataLoader.dialogues(), DataLoader.characters(), DataLoader.glossary())
	assert_eq(v.errors.size(), 0, "\n".join(v.errors))


# --- Настройки ------------------------------------------------------------------------

func test_text_speed_is_saved_in_settings() -> void:
	var path: String = "user://test_settings_text.cfg"
	var settings := AppSettings.new()
	settings.text_speed = 80.0
	settings.save_to(path)
	var loaded := AppSettings.new()
	loaded.load_from(path)
	assert_eq(loaded.text_speed, 80.0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
