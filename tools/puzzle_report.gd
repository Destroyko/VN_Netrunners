extends SceneTree
## Отчёт по головоломкам: распределение метрик и время генерации (docs/tech/puzzles-spec.md).
## Запуск: godot --headless -s tools/puzzle_report.gd -- count=1000 seed=1 out=путь/к/файлу.csv
##
##   count — сколько головоломок на каждый тип и уровень (по умолчанию 1000);
##   seed  — первый сид (по умолчанию 1), дальше по порядку;
##   out   — куда записать CSV (по умолчанию user://puzzle_report.csv).
##
## Сводку печатаем в консоль, а подробности пишем в CSV: по нему удобно калибровать диапазоны
## в balance.json. Матрица на 1000 головоломок на уровень занимает несколько минут.
##
## Как и у validate_data.gd, сам отчёт грузим через load() внутри _initialize(): скрипт из -s
## компилируется раньше автозагрузок, а головоломки обращаются к Rng.


func _initialize() -> void:
	var args: Dictionary = _parse(OS.get_cmdline_user_args())
	var count: int = int(args.get("count", "1000"))
	var first_seed: int = int(args.get("seed", "1"))
	var out_path: String = str(args.get("out", "user://puzzle_report.csv"))

	var report_script: GDScript = load("res://src/systems/puzzles/puzzle_report.gd") as GDScript
	if report_script == null:
		printerr("Не удалось загрузить src/systems/puzzles/puzzle_report.gd")
		quit(1)
		return

	print("Отчёт по головоломкам: %d на каждый тип и уровень, первый сид %d" % [count, first_seed])
	var result: Dictionary = report_script.call("run", count, first_seed) as Dictionary
	print("\n".join(result["summary"] as PackedStringArray))

	var file: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		printerr("Не удалось записать %s" % out_path)
		quit(1)
		return
	file.store_string(str(result["csv"]))
	file.close()
	print("CSV: %s" % ProjectSettings.globalize_path(out_path))
	quit(0)


func _parse(raw: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = {}
	for item: String in raw:
		var parts: PackedStringArray = item.split("=", true, 1)
		if parts.size() == 2:
			parsed[parts[0]] = parts[1]
	return parsed
