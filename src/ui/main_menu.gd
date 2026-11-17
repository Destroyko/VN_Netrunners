extends Control
## Главное меню. Первый экран игры (M0.5).
##
## «Продолжить» неактивна: сохранения по роадмапу в M4. Кнопка есть, чтобы игрок видел,
## что она будет, и чтобы раскладка меню не менялась потом.

@onready var _continue_button: Button = $Rows/Continue


func _ready() -> void:
	# В меню время не идёт: игра ещё не начата или поставлена на выход.
	Clock.stop()
	# Вышли в меню — спрятанный стол прошлой игры больше не нужен.
	Desktop.discard_kept()
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


## Глобальных уровней сложности пока нет (docs/gameplay/difficulty.md): новая игра начинается сразу.
## Экран выбора (Screens.NEW_GAME) лежит нетронутым и вернётся вместе с уровнями.
func _on_new_game() -> void:
	Desktop.discard_kept()
	GameStart.begin()
	get_tree().change_scene_to_file(Screens.ROOM)


func _on_settings() -> void:
	get_tree().change_scene_to_file(Screens.SETTINGS)


func _on_about() -> void:
	get_tree().change_scene_to_file(Screens.ABOUT)


func _on_quit() -> void:
	get_tree().quit()
