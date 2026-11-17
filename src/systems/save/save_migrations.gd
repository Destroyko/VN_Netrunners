class_name SaveMigrations
extends RefCounted
## Миграции сейва (CLAUDE.md: «Меняешь структуру GameState — добавь миграцию»). Сейв старой
## версии поднимается до текущей по шагам: v1 → v2 → … Каждый шаг — функция, которая получает
## словарь состояния версии N и возвращает словарь версии N+1.
##
## Как добавить: поднять `GameState.SAVE_VERSION`, дописать сюда шаг для прежней версии и тест
## на него (test/unit/test_save.gd). Ключ — версия, С КОТОРОЙ шаг поднимает.
##
## Шагов пока нет: v1 — первая версия сейва (сохранений до M2 не было). Разделы, добавленные в
## M2 (`economy`, `mail`), `GameState.from_dict` и так читает пустыми, если их нет.


## Шаги по версиям: {N: Callable(state: Dictionary) -> Dictionary}.
static func steps() -> Dictionary:
	return {}


## Поднять состояние до `target`. Возвращает {ok, state, error}. Версия новее текущей —
## отказ: сейв из будущей версии игры этой не прочитать.
static func migrate(state: Dictionary, target: int = GameState.SAVE_VERSION, by_version: Dictionary = {}) -> Dictionary:
	var table: Dictionary = by_version if not by_version.is_empty() else steps()
	var data: Dictionary = state.duplicate(true)
	var version: int = int(data.get("version", 1))
	if version > target:
		return {"ok": false, "state": data, "error": "сейв из более новой версии игры (%d > %d)" % [version, target]}
	while version < target:
		if not table.has(version):
			return {"ok": false, "state": data, "error": "нет миграции с версии %d" % version}
		data = (table[version] as Callable).call(data) as Dictionary
		version += 1
		data["version"] = version
	return {"ok": true, "state": data, "error": ""}
