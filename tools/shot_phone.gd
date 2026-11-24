extends Node
## Снимок телефона в окне 1280×720 для проверки вёрстки:
##   godot --path . res://tools/shot_phone.tscn -- open|peek
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
	root.theme = GameTheme.build()
	await get_tree().process_frame
	PhoneOverlay.attach(back)
	if mode == "open":
		PhoneOverlay.open()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var image: Image = root.get_texture().get_image()
	image.save_png("res://tools/out/phone_%s.png" % mode)
	print("saved ", mode)
	get_tree().quit()
