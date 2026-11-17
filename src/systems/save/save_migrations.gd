class_name SaveMigrations
extends RefCounted
## Миграции сейва (CLAUDE.md: «Меняешь структуру GameState — добавь миграцию»). Сейв старой
## версии поднимается до текущей по шагам: v1 → v2 → … Каждый шаг — функция, которая получает
## словарь состояния версии N и возвращает словарь версии N+1.
##
## Как добавить: поднять `GameState.SAVE_VERSION`, дописать сюда шаг для прежней версии и тест
## на него (test/unit/test_save.gd). Ключ — версия, С КОТОРОЙ шаг поднимает.
##
## Разделы, добавленные в M2 (`economy`, `mail`), `GameState.from_dict` читает пустыми, если их
## нет, — для них шаг не нужен. Шаг нужен, когда старые данные надо переложить по-новому.


## Шаги по версиям: {N: Callable(state: Dictionary) -> Dictionary}.
static func steps() -> Dictionary:
	return {1: v1_to_v2}


## v1 → v2 (M3): предмет был флагом `item.<имя>`, еда — счётчиком «запаса» у магазина
## (`economy.pantry`). Теперь это экземпляры в контейнерах: предметы — в инвентарь героя, запас —
## в холодильник (он и был «запасом дома»).
static func v1_to_v2(state: Dictionary) -> Dictionary:
	var hero: Array = []
	var fridge: Array = []
	var next: int = 1
	var flags: Dictionary = state.get("flags", {}) as Dictionary
	for flag: String in flags.keys():
		if flag.begins_with("item."):
			hero.append({"uid": "it_%d" % next, "kind": "item_" + flag.trim_prefix("item."), "label": "", "quest": ""})
			next += 1
	for flag: String in flags.keys().filter(func(f: String) -> bool: return f.begins_with("item.")):
		flags.erase(flag)
	var economy: Dictionary = state.get("economy", {}) as Dictionary
	var pantry: Dictionary = economy.get("pantry", {}) as Dictionary
	for kind: String in pantry.keys():
		for i: int in int(pantry[kind]):
			fridge.append({"uid": "it_%d" % next, "kind": kind, "label": "", "quest": ""})
			next += 1
	economy.erase("pantry")
	state["inventory"] = {"containers": {"hero": hero, "fridge": fridge}, "next": next}
	return state


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
