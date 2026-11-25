extends "res://test/unit/terminal_fixture.gd"
## `probe` слой за слоем (docs/issues.md: ISS-016; решено 25.11.2026): порты, мониторинг
## подключений, анализ действий — по минуте и своей полоске на слой. Ctrl+C прерывает,
## раскрытые слои узел помнит; защиту перенастроили — сканировать заново.

const NODE: String = "node_office_server"
const ADDRESS: String = "77.61.204.12"


func before_each() -> void:
	super.before_each()
	reveal(NODE)


func after_each() -> void:
	Clock.stop()
	Clock.reload_config()


func _layers() -> int:
	return NetCommands.probe_lines(Network.for_game().describe(NODE, t.now())).size()


func _running_clock() -> void:
	Clock.configure({"real_seconds_per_minute": 4, "program_speedup": 3, "program_min_minutes": 2})
	Clock.start()


func test_probe_takes_a_minute_per_layer() -> void:
	var before: int = t.now()
	var text: String = run("probe " + ADDRESS)
	assert_eq(t.now() - before, _layers(), "по минуте на слой")
	assert_string_contains(text, "мониторинг подключений: да, трейс")
	assert_string_contains(text, "-----", "разведка закончена чертой")
	assert_eq(Network.for_game().probe_layers(NODE), _layers())


func test_each_layer_has_its_own_bar_and_line() -> void:
	_running_clock()
	var got: Array = []
	t.job_finished.connect(func(r: TermResult) -> void: got.append(r.text()))
	run("probe " + ADDRESS)
	assert_true(t.has_job(), "первый слой — под полоской")
	assert_true(Clock.is_fast_forwarding())
	Clock.tick(2.0)
	assert_eq(got.size(), 1, "слой дошёл — его строка")
	assert_string_contains(str(got[0]), "порт")
	assert_true(t.has_job(), "следующий слой — своя полоска")


func test_ctrl_c_keeps_finished_layers_and_probe_resumes() -> void:
	_running_clock()
	var got: Array = []
	t.job_finished.connect(func(r: TermResult) -> void: got.append(r.text()))
	run("probe " + ADDRESS)
	while got.size() < 2:
		Clock.tick(0.25)
	t.cancel_job()
	var done: int = Network.for_game().probe_layers(NODE)
	assert_eq(done, 2, "два слоя дошли до конца")
	assert_false(t.has_job())
	Clock.stop()
	var before: int = t.now()
	run("probe " + ADDRESS)
	assert_eq(t.now() - before, _layers() - done, "повтор — с первого нераскрытого слоя")


func test_fully_scanned_node_answers_at_once() -> void:
	run("probe " + ADDRESS)
	var before: int = t.now()
	assert_string_contains(run("probe " + ADDRESS), "анализ подозрительных действий")
	assert_eq(t.now(), before, "всё раскрыто — ответ сразу")


func test_reconfigured_defense_is_scanned_again() -> void:
	run("probe " + ADDRESS)
	Network.for_game().raise_alert(NODE)
	assert_eq(Network.for_game().probe_layers(NODE), 0, "узел насторожился — защита перенастроена")
	var before: int = t.now()
	run("probe " + ADDRESS)
	assert_eq(t.now() - before, _layers())
