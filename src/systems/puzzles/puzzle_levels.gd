class_name PuzzleLevels
extends RefCounted
## Уровни головоломок: какой уровень играется и откуда берутся его параметры
## (docs/tech/puzzles-spec.md).
##
## Параметры живут в data/balance.json, раздел `puzzles` (числа баланса не в коде). Здесь только
## запасные значения на случай, если раздела нет, и выбор ступени.
##
## **Ступень головоломки задаёт ситуация, а не настройка игры** (решено 15.11.2026): глобальных
## уровней сложности пока нет, они вернутся с полной игрой. Ступени 2, 3 и 4 — лёгкая, средняя и
## тяжёлая; ступень 1 зарезервирована за автовзломом сюжетного режима, который тоже вернётся позже
## (скорее настройкой доступности, чем уровнем сложности). У новой головоломки достаточно трёх таблиц
## параметров на эти ступени — вопрос «как она соотносится с уровнями игры» не возникает.

const MIN_LEVEL: int = 2
const MAX_LEVEL: int = 4

const FALLBACK_PASSWORD: Dictionary = {
	"2": {"length": 5, "tiers": ["common"], "attempts": 6, "known": 2, "candidates": [5, 40]},
	"3": {"length": 5, "tiers": ["common", "regular"], "attempts": 5, "known": 1, "candidates": [20, 150]},
	"4": {"length": 7, "tiers": ["common", "regular", "rare"], "attempts": 4, "known": 0, "candidates": [100, 600]},
}
const FALLBACK_MATRIX: Dictionary = {
	"2": {"size": 5, "buffer": 8, "sequences": 2, "seq_min": 4, "seq_max": 5, "noise": 0, "slack": [3, 4]},
	"3": {"size": 6, "buffer": 8, "sequences": 2, "seq_min": 5, "seq_max": 5, "noise": 0, "slack": [2, 2]},
	"4": {"size": 7, "buffer": 7, "sequences": 3, "seq_min": 5, "seq_max": 6, "noise": 0, "slack": [0, 1]},
}


## Ступень головоломки против сервиса данной сложности (1–4, растёт на 1 после доведённого трейса).
## Сервис 1 — лёгкая, 2 — средняя, 3 и 4 — тяжёлая. Подготовка (`deepscan`, открытые буквы) делает
## головоломку легче, не меняя ступень.
static func level_for_service(service_difficulty: int) -> int:
	return clampi(service_difficulty + 1, MIN_LEVEL, MAX_LEVEL)


const FALLBACK_DUMP: Dictionary = {
	"2": {"width": 8, "rows": 8, "length": 3, "pieces": 2, "match_every": 4, "decoy_chance": 0.2, "scroll_seconds": 1.2},
	"3": {"width": 8, "rows": 8, "length": 3, "pieces": 3, "match_every": 5, "decoy_chance": 0.35, "scroll_seconds": 0.9},
	"4": {"width": 8, "rows": 8, "length": 4, "pieces": 3, "match_every": 6, "decoy_chance": 0.5, "scroll_seconds": 0.7},
}

## Параметры «пароля» на уровне: числа из баланса поверх запасных.
static func password(level: int) -> Dictionary:
	return _merged("password", FALLBACK_PASSWORD, level)


static func matrix(level: int) -> Dictionary:
	return _merged("matrix", FALLBACK_MATRIX, level)


static func dump(level: int) -> Dictionary:
	return _merged("dump", FALLBACK_DUMP, level)


static func section(kind: String) -> Dictionary:
	var puzzles: Dictionary = DataLoader.balance().get("puzzles", {}) as Dictionary
	return puzzles.get(kind, {}) as Dictionary


static func _merged(kind: String, fallback: Dictionary, level: int) -> Dictionary:
	var key: String = str(clampi(level, MIN_LEVEL, MAX_LEVEL))
	var config: Dictionary = section(kind)
	var result: Dictionary = (fallback[key] as Dictionary).duplicate(true)
	var levels: Dictionary = config.get("levels", {}) as Dictionary
	result.merge((levels.get(key, {}) as Dictionary).duplicate(true), true)
	# Общие для всех уровней настройки раздела (число попыток подбора, потолки и т. п.).
	for name: String in config.keys():
		if name != "levels" and not name.begins_with("_"):
			result[name] = config[name]
	return result
