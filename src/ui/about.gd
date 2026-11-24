extends Control
## Экран «Об игре»: версия, движок, где искать лицензии ассетов.
##
## Версия берётся из project.godot, чтобы не расходилась с настоящей.
## Реестр лицензий на звук и графику — docs/art/audio.md и docs/art/blender-scenes.md («Лицензии»);
## к релизу (M4) его содержимое должно попасть сюда.

@onready var _text: Label = $Rows/Text


func _ready() -> void:
	$Rows/Back.pressed.connect(_on_back)
	_text.text = "\n".join([
		"Версия: %s" % ProjectSettings.get_setting("application/config/version", "0.0.0"),
		"Движок: Godot %s" % Engine.get_version_info().get("string", "?"),
		"",
		"Сюжетный симулятор жизни хакера.",
		"Все взломы, программы и команды вымышленные.",
		"",
		"Лицензии ассетов — в титрах (появятся к релизу).",
	])


func _on_back() -> void:
	get_tree().change_scene_to_file(Screens.MAIN_MENU)
