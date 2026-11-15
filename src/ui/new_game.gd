extends Control
## Экран новой игры: выбор сложности. **Пока не используется** (решено 15.11.2026): глобальных
## уровней нет, главное меню начинает игру сразу. Экран и его тесты живы — вернётся с уровнями.
##
## Сложность фиксируется при старте и не меняется (docs/gameplay/difficulty.md), поэтому
## это единственное место, где её выбирают по-человечески. В отладочной консоли она
## по-прежнему переключается командой — для быстрых проверок.
##
## Тексты уровней здесь, а не в данных: системы локализации пока нет, а четыре подписи
## в JSON добавили бы файл без пользы.

const LEVELS: Array[Dictionary] = [
	{
		"difficulty": GameState.Difficulty.STORY,
		"name": "Сюжетный",
		"text": "Головоломки проходятся сами. Для тех, кто пришёл за историей.",
	},
	{
		"difficulty": GameState.Difficulty.EASY,
		"name": "Лёгкий",
		"text": "Больше попыток и ходов, больше известных символов.",
	},
	{
		"difficulty": GameState.Difficulty.NORMAL,
		"name": "Средний",
		"text": "Так задумано. Разведка помогает, ошибки стоят времени.",
	},
	{
		"difficulty": GameState.Difficulty.NETRUNNER,
		"name": "Нетраннер",
		"text": "Каждый шаг надо продумывать заранее. Арест — конец игры.",
	},
]

var _selected: GameState.Difficulty = GameState.Difficulty.NORMAL

@onready var _hint: Label = $Rows/Hint
@onready var _levels: VBoxContainer = $Rows/Levels


func _ready() -> void:
	for level: Dictionary in LEVELS:
		_add_level_button(level)
	$Rows/Start.pressed.connect(_on_start)
	$Rows/Back.pressed.connect(_on_back)
	_select(_selected)


func _add_level_button(level: Dictionary) -> void:
	var button := Button.new()
	button.text = str(level["name"])
	button.toggle_mode = true
	button.set_meta(&"difficulty", int(level["difficulty"]))
	button.set_meta(&"text", str(level["text"]))
	button.pressed.connect(_on_level_pressed.bind(button))
	_levels.add_child(button)


func _on_level_pressed(button: Button) -> void:
	_select(int(button.get_meta(&"difficulty")) as GameState.Difficulty)


func _select(difficulty: GameState.Difficulty) -> void:
	_selected = difficulty
	for child: Node in _levels.get_children():
		var button: Button = child as Button
		if button == null:
			continue
		var is_current: bool = int(button.get_meta(&"difficulty")) == int(difficulty)
		button.button_pressed = is_current
		if is_current:
			_hint.text = str(button.get_meta(&"text"))


func _on_start() -> void:
	# Новая игра: чистое состояние с выбранной сложностью и свой сид случайности.
	GameState.reset(_selected)
	Rng.randomize_seed()
	get_tree().change_scene_to_file(Screens.DESKTOP)


func _on_back() -> void:
	get_tree().change_scene_to_file(Screens.MAIN_MENU)
