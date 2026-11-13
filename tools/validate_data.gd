extends SceneTree
## Проверка всех данных в data/ без запуска игры.
## Запуск: godot --headless -s tools/validate_data.gd
## Код возврата 1 при ошибках — годится для проверки перед коммитом и для CI.
##
## Два неочевидных момента:
## 1. extends SceneTree — иначе Godot не поднимает автозагрузки, и Conditions/Effects,
##    которые обращаются к GameState, не скомпилируются.
## 2. Валидатор грузим через load() внутри _initialize(), а не как глобальный класс
##    Validator: скрипт, переданный в -s, компилируется раньше автозагрузок,
##    и ссылка на GameState в зависимостях валит компиляцию.


func _initialize() -> void:
	var validator_script: GDScript = load("res://src/core/validator.gd") as GDScript
	if validator_script == null:
		printerr("Не удалось загрузить src/core/validator.gd")
		quit(1)
		return

	var validator: RefCounted = validator_script.new() as RefCounted
	var ok: bool = bool(validator.call("validate_all"))
	print(validator.call("summary"))
	quit(0 if ok else 1)
