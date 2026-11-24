extends Node
## Снимок рабочего стола ПК в теме ОС: godot --path . res://tools/shot_desktop.tscn -- normal|hacker [app[,app…]]
## Нужен режим с окном. PNG в tools/out/desktop_<ОС>.png.


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var os_name: String = args[0] if args.size() > 0 else "normal"
	var root: Window = get_tree().root
	root.size = Vector2i(1280, 720)
	GameStart.begin()
	GameState.set_var("pc.os", os_name)
	var desktop: Control = (load(Screens.DESKTOP) as PackedScene).instantiate() as Control
	add_child(desktop)
	await get_tree().process_frame
	# Можно несколько приложений через запятую: «mail,terminal» — последнее окажется в фокусе.
	if args.size() > 1:
		for app: String in args[1].split(","):
			desktop.call("open_app", app)
	for i: int in 4:
		await get_tree().process_frame
	root.get_texture().get_image().save_png("res://tools/out/desktop_%s.png" % os_name)
	print("saved ", os_name)
	get_tree().quit()
