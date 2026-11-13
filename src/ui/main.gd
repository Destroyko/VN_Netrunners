extends Control
## Заглушка главной сцены на этап M0: показывает, что проект запускается
## и что автозагрузки живы. Настоящий рабочий стол появится в M1.
##
## UI только читает GameState и слушает EventBus — правил игры здесь нет.

const DEBUG_CONSOLE: String = "res://src/debug/debug_console.tscn"

@onready var _info: Label = $Info


func _ready() -> void:
	EventBus.time_advanced.connect(_on_time_advanced)
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.heat_changed.connect(_on_heat_changed)
	_add_debug_console()
	_refresh()


## Консоль разработчика только в отладочной сборке — в релиз она не попадёт.
func _add_debug_console() -> void:
	if not OS.is_debug_build():
		return
	var scene: PackedScene = load(DEBUG_CONSOLE) as PackedScene
	if scene != null:
		add_child(scene.instantiate())


func _refresh() -> void:
	_info.text = "\n".join([
		"VN-netrunners — каркас M0",
		"",
		Clock.format_time() + "  (" + Clock.time_of_day() + ")",
		"Деньги: %d    Заметность: %d" % [GameState.money, GameState.heat],
		"Сид случайности: %d" % Rng.get_seed(),
		"",
		"Сложность: %d" % int(GameState.difficulty),
		"",
		"Пробел — потратить час игрового времени",
		"F1 — консоль разработчика",
		"Esc — в главное меню",
	])


func _input(event: InputEvent) -> void:
	# Проверка руками, что время идёт и события доходят до интерфейса.
	if event.is_action_pressed(&"ui_accept"):
		Clock.advance(60)
	elif event.is_action_pressed(&"ui_cancel"):
		get_tree().change_scene_to_file(Screens.MAIN_MENU)


func _on_time_advanced(_minute: int, _minutes_passed: int) -> void:
	_refresh()


func _on_money_changed(_money: int, _delta: int) -> void:
	_refresh()


func _on_heat_changed(_heat: int, _delta: int) -> void:
	_refresh()
