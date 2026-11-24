extends Node
## Снимок телефона в окне 1280×720 для проверки вёрстки:
##   godot --path . res://tools/shot_phone.tscn -- open|peek [приложение]
## SHOT_MAIL=<id письма> — доставить письмо; с приложением mail оно открывается (phone_open_mail_letter.png).
## Нужен обычный режим с окном (не --headless). Кладёт PNG в tools/out/.


func _ready() -> void:
	var root: Window = get_tree().root
	var mode: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "open"
	root.size = Vector2i(1280, 720)
	var back := ColorRect.new()
	back.color = Color("#5c4a3a")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	GameState.reset()
	var app: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else ""
	var letter: String = OS.get_environment("SHOT_MAIL")
	if not letter.is_empty():
		Mailbox.deliver("mail_test_order")
		Mailbox.deliver(letter)
	root.theme = GameTheme.build()
	await get_tree().process_frame
	PhoneOverlay.attach(back)
	if mode == "open":
		PhoneOverlay.open(app)
	for i: int in 4:
		await get_tree().process_frame
	var suffix: String = mode + ("_" + app if not app.is_empty() else "")
	root.get_texture().get_image().save_png("res://tools/out/phone_%s.png" % suffix)
	if app == "mail" and not letter.is_empty():
		var mail: MailApp = PhoneOverlay.find_child("MailApp", true, false) as MailApp
		mail.open(str(Mailbox.inbox()[0]["uid"]))
		for i: int in 4:
			await get_tree().process_frame
		root.get_texture().get_image().save_png("res://tools/out/phone_%s_letter.png" % suffix)
	print("saved ", suffix)
	get_tree().quit()
