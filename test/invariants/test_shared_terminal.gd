extends "res://test/unit/terminal_fixture.gd"
## Один терминал на всех: консоль, окно «Файлы» своего ПК (`execute_local`) и «Блокнот»
## (`save_edit`) делят ждущий вопрос y/n и текущий узел (docs/tech/interactions.md, И-7, И-8;
## docs/issues.md: ISS-004, ISS-007, ISS-008).

const OpenIssue = preload("res://test/invariants/open_issue.gd")


# --- ISS-004: «Файлы» съедают вопрос консоли --------------------------------------------

func test_files_window_keeps_the_console_question() -> void:
	enter("node_training_pc")
	run("cp /home/zametka.txt")
	run("cp /home/zametka.txt")
	assert_true(t.has_question(), "консоль спросила «заменить?»")
	t.execute_local("rm /home/readme.txt")
	assert_true(t.has_question(), "вопрос консоли ждёт ответа и после действия в окне")
	assert_string_contains(t.last_question(), "заменить")


# --- ISS-007: вопрос окна «Файлы», отвеченный в консоли -------------------------------------

## Окно «Файлы» спросило про системный файл своего ПК. Игрок ответил «y» не в окне, а в консоли,
## где открыт сеанс с чужим узлом: команда должна остаться командой своего ПК (И-8).
func test_local_question_answered_in_console_stays_on_own_pc() -> void:
	enter_as_admin("node_office_server")
	t.execute_local("rm /sys/net.sys")
	assert_false(t.local_question().is_empty(), "системный файл — окно спрашивает")
	assert_false(t.has_question(), "вопрос окна — не вопрос консоли")
	run("y")
	assert_true(Filesystem.for_node("node_office_server").has_file("/sys/net.sys"), "чужой узел не тронут")
	assert_true(t.home_fs().has_file("/sys/net.sys"), "«y» в консоли — не ответ окну")
	t.answer_local(true)
	assert_false(t.home_fs().has_file("/sys/net.sys"), "ответ в окне удалил файл своего ПК")
	assert_true(Filesystem.for_node("node_office_server").has_file("/sys/net.sys"))
	assert_true(t.is_remote(), "соединение не оборвано саботажем")


# --- ISS-008: «Блокнот» своего ПК при открытом сеансе ---------------------------------------

func test_notepad_on_own_pc_saves_while_connected_elsewhere() -> void:
	run("edit /home/readme.txt")
	assert_eq(str(last.request.get("node", "")), Network.HOME_ID)
	enter("node_training_pc")
	var saved: TermResult = t.save_edit(Network.HOME_ID, "/home/readme.txt", "новый текст")
	assert_string_contains(saved.text(), "сохранено")
	assert_eq(str(t.home_fs().file_data("/home/readme.txt").get("text", "")), "новый текст")


## Обратный случай работает: файл чужого узла после обрыва не сохраняется.
func test_notepad_of_remote_file_refuses_after_dc() -> void:
	enter_as_admin("node_training_pc")
	run("edit /home/zametka.txt")
	var before: String = str(Filesystem.for_node("node_training_pc").file_data("/home/zametka.txt").get("text", ""))
	run("dc")
	var saved: TermResult = t.save_edit("node_training_pc", "/home/zametka.txt", "чужое")
	assert_string_contains(saved.text(), "не сохранены")
	assert_eq(str(Filesystem.for_node("node_training_pc").file_data("/home/zametka.txt").get("text", "")), before)


# --- ISS-008: «Блокнот» один и знает свой файл ----------------------------------------------

func test_file_open_in_notepad_is_busy() -> void:
	t.begin_edit(Network.HOME_ID, "/home/readme.txt")
	assert_string_contains(run("rm /home/readme.txt"), "занят: readme.txt")
	assert_true(t.home_fs().has_file("/home/readme.txt"))
	t.end_edit()
	run("rm /home/readme.txt")
	assert_false(t.home_fs().has_file("/home/readme.txt"), "закрыл «Блокнот» — файл свободен")


func test_notepad_waits_while_a_program_runs() -> void:
	learn_programs()
	enter("node_training_pc")
	Clock.configure({"real_seconds_per_minute": 4, "program_speedup": 3, "program_min_minutes": 2})
	Clock.start()
	run("rootstep")
	var saved: TermResult = t.save_edit(Network.HOME_ID, "/home/readme.txt", "новый текст")
	Clock.stop()
	Clock.reload_config()
	assert_eq(saved.text(), Terminal.BUSY_TEXT)
	assert_ne(str(t.home_fs().file_data("/home/readme.txt").get("text", "")), "новый текст")
