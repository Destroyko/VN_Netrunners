extends Node
## Лист иконок для просмотра: все значки без плашки и на плашках, на тёмном фоне интерфейса.
##   godot --path . res://tools/shot_icons.tscn
## Нужен обычный режим с окном (не --headless). Кладёт PNG в tools/out/icons.png.

const ICONS: PackedStringArray = ["terminal", "netmap", "files", "mail", "bank", "news", "shop", "tasks",
	"messenger", "work", "group", "alarm", "citymap"]


func _ready() -> void:
	var root: Window = get_tree().root
	root.size = Vector2i(1280, 420)
	root.theme = GameTheme.build()
	var back := ColorRect.new()
	back.color = GameTheme.color("background")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	for row: int in 2:
		var kind: String = "glyph" if row == 0 else "tile"
		for i: int in ICONS.size():
			var path: String = "res://assets/ui/icons/%s/%s.svg" % [kind, ICONS[i]]
			if not ResourceLoader.exists(path):
				continue
			var rect := TextureRect.new()
			rect.texture = load(path) as Texture2D
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.size = Vector2(80, 80)
			rect.position = Vector2(24 + i * 96, 30 + row * 180)
			add_child(rect)
			var label := Label.new()
			label.text = ICONS[i]
			label.position = Vector2(24 + i * 96, 114 + row * 180)
			label.add_theme_font_size_override("font_size", 12)
			add_child(label)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	root.get_texture().get_image().save_png("res://tools/out/icons.png")
	print("saved icons")
	get_tree().quit()
