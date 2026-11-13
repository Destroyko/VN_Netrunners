extends Control
## Главное меню. Первый экран игры (M0.5).
##
## «Продолжить» неактивна: сохранения по роадмапу в M4. Кнопка есть, чтобы игрок видел,
## что она будет, и чтобы раскладка меню не менялась потом.

@onready var _continue_button: Button = $Rows/Continue


func _ready() -> void:
	# Настройки применяем здесь: это первый экран, и дальше они нужны уже готовыми.
	var settings := AppSettings.new()
	settings.load_from()
	settings.apply(get_window())

	_continue_button.disabled = true
	_continue_button.tooltip_text = "Сохранения появятся позже"

	$Rows/NewGame.pressed.connect(_on_new_game)
	$Rows/Settings.pressed.connect(_on_settings)
	$Rows/About.pressed.connect(_on_about)
	$Rows/Quit.pressed.connect(_on_quit)
	$Rows/NewGame.grab_focus()


func _on_new_game() -> void:
	get_tree().change_scene_to_file(Screens.NEW_GAME)


func _on_settings() -> void:
	get_tree().change_scene_to_file(Screens.SETTINGS)


func _on_about() -> void:
	get_tree().change_scene_to_file(Screens.ABOUT)


func _on_quit() -> void:
	get_tree().quit()
