extends GutTest
## Рабочий стол: окна, панель задач, шкала заметности (docs/tech/desktop-layout.md).
## Правила окон проверяем отдельно (WindowRules), сцену — собирая её headless.

var desktop: Desktop


func before_each() -> void:
	GameState.reset()
	var scene: PackedScene = load(Screens.DESKTOP) as PackedScene
	desktop = scene.instantiate() as Desktop
	add_child_autofree(desktop)
	await wait_frames(2)


# --- Правила окон --------------------------------------------------------------

func test_window_cannot_leave_the_screen_entirely() -> void:
	var area := Vector2(1280, 720)
	var size := Vector2(400, 300)
	var far: Vector2 = WindowRules.clamp_position(Vector2(5000, 5000), size, area)
	assert_lt(far.x, area.x, "за правым краем остаётся полоска заголовка")
	assert_lt(far.y, area.y)
	var lost: Vector2 = WindowRules.clamp_position(Vector2(-5000, -5000), size, area)
	assert_gt(lost.x + size.x, 0.0, "за левым краем тоже можно ухватить")
	assert_eq(lost.y, 0.0, "выше верхнего края не уходит")


func test_resize_respects_minimum_and_area() -> void:
	var area := Vector2(800, 600)
	var minimum := Vector2(300, 200)
	assert_eq(WindowRules.clamp_size(Vector2(10, 10), minimum, Vector2.ZERO, area), minimum)
	assert_eq(WindowRules.clamp_size(Vector2(5000, 5000), minimum, Vector2(100, 100), area), Vector2(700, 500))


func test_new_windows_cascade() -> void:
	var area := Vector2(1280, 720)
	var first: Vector2 = WindowRules.cascade(0, Vector2(400, 300), area)
	var second: Vector2 = WindowRules.cascade(1, Vector2(400, 300), area)
	assert_ne(first, second)


# --- Стол ----------------------------------------------------------------------

func test_every_app_has_an_icon() -> void:
	for app: Dictionary in Desktop.APPS:
		assert_not_null(desktop.find_child("Icon_" + str(app["id"]), true, false), str(app["id"]))


func test_group_site_is_gray_until_the_gate_opens() -> void:
	var icon: Button = desktop.find_child("Icon_group", true, false) as Button
	assert_true(icon.disabled)
	assert_null(desktop.open_app("group"), "закрытое приложение не открывается")


func test_opening_an_app_makes_one_focused_window() -> void:
	var window: DesktopWindow = desktop.open_app("files")
	assert_not_null(window)
	assert_true(window.is_focused)
	assert_eq(desktop.open_windows().size(), 1)


func test_second_launch_raises_the_same_window() -> void:
	var first: DesktopWindow = desktop.open_app("files")
	desktop.open_app("mail")
	var again: DesktopWindow = desktop.open_app("files")
	assert_eq(again, first, "одно окно на приложение")
	assert_eq(desktop.open_windows().size(), 2)
	assert_true(first.is_focused)


func test_focus_moves_between_windows() -> void:
	var files: DesktopWindow = desktop.open_app("files")
	var mail: DesktopWindow = desktop.open_app("mail")
	assert_true(mail.is_focused)
	assert_false(files.is_focused)
	desktop.focus(files)
	assert_true(files.is_focused)
	assert_false(mail.is_focused)


func test_minimized_window_comes_back_from_the_icon() -> void:
	var window: DesktopWindow = desktop.open_app("files")
	window.minimize()
	assert_false(window.visible)
	desktop.open_app("files")
	assert_true(window.visible)
	assert_false(window.is_minimized)


func test_closing_a_window_forgets_it_and_keeps_its_geometry() -> void:
	var window: DesktopWindow = desktop.open_app("files")
	window.position = Vector2(300, 200)
	window.close()
	await wait_frames(2)
	assert_null(desktop.window_of("files"))
	var again: DesktopWindow = desktop.open_app("files")
	assert_eq(again.position, Vector2(300, 200), "положение запомнилось")


func test_maximize_and_restore() -> void:
	var window: DesktopWindow = desktop.open_app("files")
	var before: Rect2 = Rect2(window.position, window.size)
	window.toggle_maximize()
	assert_true(window.is_maximized)
	assert_eq(window.position, Vector2.ZERO)
	window.toggle_maximize()
	assert_eq(Rect2(window.position, window.size), before)


# --- Панель задач ---------------------------------------------------------------

func test_taskbar_has_a_button_per_open_window() -> void:
	desktop.open_app("files")
	var found: Taskbar = null
	for child: Node in desktop.find_children("*", "Taskbar", true, false):
		found = child as Taskbar
	assert_not_null(found)
	assert_true(found.has_window_button("files"))


func test_heat_bar_colors_follow_stages() -> void:
	assert_eq(HeatBar.color_of_cell(0), HeatBar.color_of_cell(1), "этап = два деления")
	assert_ne(HeatBar.color_of_cell(1), HeatBar.color_of_cell(2))
	assert_eq(HeatBar.color_of_cell(9), HeatBar.STAGE_COLORS[4])


# --- Самочувствие и мысли героя (gameplay/needs.md) -------------------------------------

func test_needs_widget_shows_bars_and_closes() -> void:
	var widget: NeedsWidget = desktop.find_child("NeedsWidget", true, false) as NeedsWidget
	assert_not_null(widget)
	assert_eq(widget.energy_bar().value, 80.0)
	Needs.eat(10.0)
	assert_eq(widget.satiety_bar().value, 80.0, "поел — виджет перечитал")
	(widget.find_child("Close", true, false) as Button).emit_signal("pressed")
	assert_false(widget.visible)


func test_hero_thought_appears_on_warning() -> void:
	var thoughts: HeroThoughts = desktop.find_child("HeroThoughts", true, false) as HeroThoughts
	EventBus.need_warned.emit(Needs.EVENT_ENERGY_LOW)
	assert_true(thoughts.visible)
	assert_string_contains(thoughts.text(), "отдыхать")

