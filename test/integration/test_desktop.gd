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

func test_phone_shows_needs_at_the_pc() -> void:
	assert_true(PhoneOverlay.frame.visible, "за ПК телефон лежит в углу")
	assert_false(PhoneOverlay.is_open())
	var status: PhoneStatus = PhoneOverlay.status()
	assert_eq(status.energy_bar().value, 80.0)
	Needs.eat(10.0)
	assert_eq(status.satiety_bar().value, 80.0, "поел — строка состояния перечитала")
	assert_almost_eq(PhoneOverlay.frame.offset_bottom, -34.0, 0.5, "телефон над панелью задач")
	desktop.hide_pc()
	assert_false(PhoneOverlay.frame.visible, "отошёл от ПК — стол телефон отдал")


func test_messages_app_on_the_pc() -> void:
	var window: DesktopWindow = desktop.open_app("messenger")
	assert_not_null(window, "«Сообщения» на ПК — настоящее приложение")
	assert_not_null(window.find_child("MessagesApp", true, false))


func test_hero_thought_appears_on_warning() -> void:
	var thoughts: HeroThoughts = desktop.find_child("HeroThoughts", true, false) as HeroThoughts
	EventBus.need_warned.emit(Needs.EVENT_ENERGY_LOW)
	assert_true(thoughts.visible)
	assert_string_contains(thoughts.text(), "отдыхать")



# --- Банк (gameplay/economy.md) ---------------------------------------------------

func test_bank_shows_bill_and_pays_it() -> void:
	GameState.set_money(300)
	Economy.issue(Economy.KIND_RENT, "Аренда квартиры", 200)
	var window: DesktopWindow = desktop.open_app("bank")
	var bank: BankApp = window.find_child("BankApp", true, false) as BankApp
	assert_string_contains((bank.find_child("Balance", true, false) as Label).text, "300")
	var pay: Button = bank.find_child("Pay", true, false) as Button
	assert_false(pay.disabled)
	pay.emit_signal("pressed")
	assert_eq(GameState.money, 100)
	assert_null(bank.find_child("Pay", true, false), "оплаченный счёт ушёл из списка")
	assert_eq((bank.find_child("History", true, false) as ItemList).item_count, 1)


func test_bank_pay_button_disabled_without_money() -> void:
	GameState.set_money(50)
	Economy.issue(Economy.KIND_RENT, "Аренда квартиры", 200)
	var window: DesktopWindow = desktop.open_app("bank")
	var pay: Button = window.find_child("Pay", true, false) as Button
	assert_true(pay.disabled)


# --- Магазин (gameplay/needs.md) --------------------------------------------------

func test_shop_orders_and_eats() -> void:
	GameState.set_money(100)
	var window: DesktopWindow = desktop.open_app("shop")
	var shop: ShopApp = window.find_child("ShopApp", true, false) as ShopApp
	var order: Button = shop.find_child("Item_food_sandwich", true, false).find_child("Action", true, false) as Button
	order.emit_signal("pressed")
	assert_eq(GameState.money, 91)
	Clock.advance(40)
	var eat: Node = shop.find_child("Food_food_sandwich", true, false)
	assert_not_null(eat, "приехало — в запасе")
	(eat.find_child("Action", true, false) as Button).emit_signal("pressed")
	assert_eq(Shop.pantry().size(), 0)


# --- Почта ------------------------------------------------------------------------

func test_mail_app_reads_saves_and_replies() -> void:
	Mailbox.deliver("mail_test_order")
	var icon: Button = desktop.find_child("Icon_mail", true, false) as Button
	assert_eq(icon.text, "Почта (1)", "непрочитанное — на иконке")
	var window: DesktopWindow = desktop.open_app("mail")
	var mail: MailApp = window.find_child("MailApp", true, false) as MailApp
	mail.open(str(Mailbox.inbox()[0]["uid"]))
	assert_eq(icon.text, "Почта")
	assert_string_contains((mail.find_child("Body", true, false) as Label).text, "пробное")
	(mail.find_child("Save_0", true, false) as Button).emit_signal("pressed")
	assert_true(Filesystem.for_node(Network.HOME_ID).has_file("/home/mail/instrukciya.txt"))
	(mail.find_child("Reply_accept", true, false) as Button).emit_signal("pressed")
	assert_true(GameState.has_flag("world.test_mail_accepted"))
	assert_null(mail.find_child("Reply_decline", true, false), "после ответа кнопок нет")


func test_mail_compose_sends_to_known_address() -> void:
	Mailbox.deliver("mail_test_order")
	var path: String = Mailbox.save_attachment(str(Mailbox.inbox()[0]["uid"]), 0)
	var window: DesktopWindow = desktop.open_app("mail")
	var mail: MailApp = window.find_child("MailApp", true, false) as MailApp
	var compose: MailCompose = mail.show_compose()
	assert_eq((compose.find_child("To", true, false) as OptionButton).item_count, 1, "только известные адреса")
	compose.pick("dispatch@example.local")
	# Мини-проводник: открыть папку, выделить файл, «Прикрепить выбранные».
	(compose.find_child("Attach", true, false) as Button).emit_signal("pressed")
	var picker: HomeFilePicker = compose.picker()
	assert_true(picker.visible)
	picker.open_dir("/home/mail")
	picker.select_names(PackedStringArray(["instrukciya.txt"]))
	(picker.find_child("Choose", true, false) as Button).emit_signal("pressed")
	assert_eq(compose.attached(), PackedStringArray([path]))
	# Перетаскивание: то же, что бросить файл в письмо.
	assert_true(compose._can_drop_data(Vector2.ZERO, {HomeFilePicker.DRAG_KEY: PackedStringArray([path])}))
	compose._drop_data(Vector2.ZERO, {HomeFilePicker.DRAG_KEY: PackedStringArray([path])})
	assert_eq(compose.attached().size(), 1, "тот же файл второй раз не прикрепляется")
	(compose.find_child("Send", true, false) as Button).emit_signal("pressed")
	assert_eq(Mailbox.sent().size(), 1)
	assert_true((Mailbox.sent()[0]["file_ids"] as Array).has("file_test_instruction"))


func test_save_notice_is_a_system_message() -> void:
	SaveSystem.dir = "user://test_saves_desktop"
	desktop.save_game()
	var notice: SystemNotice = desktop.find_child("SystemNotice", true, false) as SystemNotice
	assert_true(notice.visible)
	assert_eq(notice.text(), "игра сохранена", "сообщение системы, не мысль героя")
	assert_false((desktop.find_child("HeroThoughts", true, false) as HeroThoughts).visible)
	SaveSystem.delete(SaveSystem.SLOT_MANUAL)
	SaveSystem.dir = SaveSystem.DEFAULT_DIR


func test_news_app_shows_feed_and_marks_read() -> void:
	News.publish("news_weather", 1)
	var icon: Button = desktop.find_child("Icon_news", true, false) as Button
	assert_eq(icon.text, "Новости (1)")
	var window: DesktopWindow = desktop.open_app("news")
	var app: NewsApp = window.find_child("NewsApp", true, false) as NewsApp
	app.open("news_weather")
	assert_eq(icon.text, "Новости")
	assert_string_contains((app.find_child("Body", true, false) as Label).text, "осадк")


# --- Отойти от ПК и вернуться (разработчик, 17.11.2026) ----------------------------

func test_hidden_pc_keeps_its_windows_and_is_silent() -> void:
	var window: DesktopWindow = desktop.open_app("terminal")
	desktop.terminal.execute("ls")
	var history_before: int = desktop.terminal.history().size()
	desktop.hide_pc()
	assert_false(desktop.visible, "стол спрятан")
	assert_false(Desktop.pc_sound_on(), "звук ПК заглушён — снаружи не слышно")
	assert_eq(Desktop.kept(), desktop, "стол сохранён, не уничтожен")
	desktop.show_pc()
	assert_true(desktop.visible)
	assert_true(Desktop.pc_sound_on())
	assert_true(is_instance_valid(window) and window.is_inside_tree(), "окно терминала на месте")
	assert_eq(desktop.terminal.history().size(), history_before, "история команд на месте")
	assert_null(Desktop.kept(), "вернулись — спрятанного больше нет")


func test_hidden_pc_ignores_pass_out() -> void:
	desktop.hide_pc()
	EventBus.passed_out.emit()
	assert_null(desktop.find_child("PassOutCurtain", true, false), "занавес покажет комната, не спрятанный стол")
	desktop.show_pc()


func test_discard_kept_frees_old_pc() -> void:
	desktop.hide_pc()
	Desktop.discard_kept()
	assert_null(Desktop.kept())
	await wait_frames(1)
	assert_false(is_instance_valid(desktop), "новая игра — стол прошлой уничтожен")


func test_stub_apps_are_grey() -> void:
	for app_id: String in ["work"]:
		var icon: Button = desktop.find_child("Icon_" + app_id, true, false) as Button
		assert_true(icon.disabled, "пустое приложение — серое: " + app_id)
		assert_null(desktop.open_app(app_id))


func test_answer_button_opens_filled_form() -> void:
	Mailbox.deliver("mail_job_1")
	var window: DesktopWindow = desktop.open_app("mail")
	var mail: MailApp = window.find_child("MailApp", true, false) as MailApp
	var uid: String = str(Mailbox.inbox()[0]["uid"])
	mail.open(uid)
	assert_true((mail.find_child("Answer", true, false) as Button).visible)
	var compose: MailCompose = mail.answer(uid)
	assert_eq((compose.find_child("Subject", true, false) as LineEdit).text, "Готово")
	(compose.find_child("Send", true, false) as Button).emit_signal("pressed")
	assert_eq(str(Mailbox.sent()[-1]["to"]), "dispatch@autsors.local")


func test_start_menu_has_only_pc_actions() -> void:
	assert_eq(Taskbar.MENU_ITEMS.keys(), ["terminal", "reboot", "shut_down"], "сохранения и выхода из игры в «Пуске» нет")


func test_leave_button_is_on_the_taskbar() -> void:
	var leave: Button = desktop.find_child("Leave", true, false) as Button
	assert_not_null(leave, "заметная кнопка «Отойти от ПК» справа")
	var asked: Dictionary = {"n": 0}
	for child: Node in desktop.find_children("*", "Taskbar", true, false):
		(child as Taskbar).leave_requested.connect(func() -> void: asked["n"] += 1)
	leave.emit_signal("pressed")
	assert_gt(int(asked["n"]), 0)

