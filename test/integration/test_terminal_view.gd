extends GutTest
## Окно терминала: ввод, вывод, панели, история, автодополнение, трейс.
## Правила терминала проверяют свои тесты; здесь — что окно их показывает и передаёт команды.

var desktop: Desktop
var view: TerminalView


func before_each() -> void:
	GameState.reset()
	Clock.set_time(1, 12 * 60)
	var scene: PackedScene = load(Screens.DESKTOP) as PackedScene
	desktop = scene.instantiate() as Desktop
	add_child_autofree(desktop)
	await wait_frames(2)
	view = desktop.open_app("terminal").body.get_child(0) as TerminalView
	await wait_frames(1)


func test_terminal_opens_with_a_prompt() -> void:
	assert_not_null(view)
	assert_string_contains(view.output_text(), "help")


func test_command_is_echoed_and_answered() -> void:
	view.submit("pwd")
	var text: String = view.output_text()
	assert_string_contains(text, "home:/home$ pwd")
	assert_string_contains(text, "/home")


func test_unknown_command_is_reported() -> void:
	view.submit("abracadabra")
	assert_string_contains(view.output_text(), "abracadabra")


func test_file_panel_lists_the_current_directory() -> void:
	var files: ItemList = view.find_children("*", "ItemList", true, false)[0] as ItemList
	assert_gt(files.item_count, 0, "в /home что-то лежит")


func test_clicking_a_file_inserts_its_name() -> void:
	var files: ItemList = view.find_children("*", "ItemList", true, false)[0] as ItemList
	files.item_selected.emit(0)
	assert_false(view.entry_text().is_empty())


func test_programs_panel_follows_installed_programs() -> void:
	var programs: ItemList = view.find_children("*", "ItemList", true, false)[1] as ItemList
	assert_eq(programs.item_count, 1, "пока ничего не установлено: одна строка «нет»")
	GameState.set_flag(Programs.flag_for("passhound"))
	view.submit("progs")
	assert_eq(programs.get_item_text(0), "passhound")


func test_question_is_shown_and_answered() -> void:
	view.submit("rm /sys/theme.sys")
	assert_string_contains(view.output_text(), "(y/n)")
	view.submit("n")
	assert_string_contains(view.output_text(), "отменено")


func test_clear_wipes_the_screen() -> void:
	view.submit("pwd")
	view.submit("clear")
	assert_false(view.output_text().contains("home:/home$ pwd"))


func test_trace_indicator_hidden_when_not_tracing() -> void:
	assert_false(view.trace_visible())


func test_closing_the_window_keeps_the_terminal_history() -> void:
	view.submit("pwd")
	desktop.window_of("terminal").close()
	await wait_frames(2)
	assert_eq(desktop.terminal.history(), PackedStringArray(["pwd"]))
