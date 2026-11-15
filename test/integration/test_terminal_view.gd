extends GutTest
## Окно терминала: заставка, ввод, вывод, история, автодополнение, трейс.
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


func test_terminal_opens_with_the_os_banner() -> void:
	assert_not_null(view)
	assert_string_contains(view.output_text(), "ядро", "заставка с версией ОС, как у настоящей консоли")
	assert_false(view.output_text().contains("help"), "без подсказок")


func test_command_is_echoed_and_answered() -> void:
	view.submit("pwd")
	var text: String = view.output_text()
	assert_string_contains(text, "home:/home$ pwd")
	assert_string_contains(text, "/home")


func test_unknown_command_is_reported() -> void:
	view.submit("abracadabra")
	assert_string_contains(view.output_text(), "abracadabra")


func test_terminal_is_a_single_screen_without_side_panels() -> void:
	assert_eq(view.find_children("*", "ItemList", true, false).size(), 0)


func test_entry_has_no_context_menu() -> void:
	assert_false(view.entry().context_menu_enabled)


func test_banner_follows_the_os_level() -> void:
	GameState.set_var(Terminal.VAR_OS, Terminal.OS_OLD)
	assert_string_contains("
".join(desktop.terminal.banner()), "i686")


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
