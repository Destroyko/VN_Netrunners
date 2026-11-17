extends SceneTree
## Симуляция баланса: «бот» проживает N дней и печатает отчёт (src/systems/economy/balance_sim.gd).
## Запуск: godot --headless -s tools/balance_sim.gd -- days=7 seed=1
##
## Работу делаем в первом кадре, а не в _initialize(): боту нужны автозагрузки, подписанные на
## шину (потребности, экономика, квесты), а их _ready проходит только когда дерево запущено.
## Сам класс грузим через load() — как в validate_data.gd.

var _done: bool = false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var args: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.split("=")
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	var days: int = int(args.get("days", "5"))
	var seed_value: int = int(args.get("seed", "1"))
	var sim: GDScript = load("res://src/systems/economy/balance_sim.gd") as GDScript
	var report: Dictionary = sim.call("run", days, seed_value) as Dictionary
	print("Симуляция баланса: %d дн., сид %d" % [days, seed_value])
	print("\n".join(report["summary"] as PackedStringArray))
	quit(0)
	return true
