class_name Programs
extends RefCounted
## Программы героя: что бывает, что установлено, сколько стоит времени
## (docs/tech/terminal-spec.md, «Программы»; docs/gameplay/hacking.md).
##
## Решено 15.11.2026: **на старте у героя нет ни одной программы.** У него обычная ОС, а первые
## задания — прямой доступ: адрес, логин и пароль выданы, остаётся `connect`, походить по
## папкам и сделать работу; взламывать нечего, инструментарий не нужен. Программы приходят
## **вместе с хакерской ОС** (часть в комплекте, остальное позже) и работают только в ней.
## Установленной программа считается по флагу `prog.<имя>`: так обходимся общим языком
## эффектов (`{"set_flag": "prog.passhound"}`), без отдельного типа «выдать программу».
##
## Название — вымышленное, и все взломы вымышленные (CLAUDE.md).

const KIND_CRACKER: String = "cracker"  # головоломка против сервиса, стартует трейс
const KIND_AUTO: String = "auto"        # работает сама, полоска прогресса
const KIND_RECON: String = "recon"      # разведка, трейс не запускает

const FLAG_PREFIX: String = "prog."
## Флаг эпохи группы: вместе с хакерской ОС приходят и трейс, и заметность (heat.md).
const FLAG_GROUP_JOINED: String = "story.group_joined"

## id → описание. `minutes` — ключ в balance.json, раздел action_minutes.
const DEFS: Dictionary = {
	"passhound": {
		"kind": KIND_CRACKER, "puzzle": "password", "minutes": "hack_step",
		"about": "подбор пароля сервиса: головоломка «пароль»",
	},
	"gridrunner": {
		"kind": KIND_CRACKER, "puzzle": "matrix", "minutes": "hack_step",
		"about": "пробивает шифрованный канал и фаервол: головоломка «матрица»",
	},
	"rootstep": {
		"kind": KIND_AUTO, "minutes": "rootstep",
		"about": "повышает права на узле до администратора",
	},
	"logwipe": {
		"kind": KIND_AUTO, "minutes": "logwipe",
		"about": "чистит каталог логов узла одной командой",
	},
	"deepscan": {
		"kind": KIND_RECON, "minutes": "deepscan",
		"about": "расширенная разведка: открывает ещё один символ пароля",
	},
}

const FALLBACK_MINUTES: int = 3


static func ids() -> PackedStringArray:
	var result: PackedStringArray = []
	for id: String in DEFS.keys():
		result.append(id)
	result.sort()
	return result


static func is_program(name: String) -> bool:
	return DEFS.has(name)


static func kind_of(id: String) -> String:
	return str((DEFS.get(id, {}) as Dictionary).get("kind", ""))


## Тип головоломки, против которой работает взломщик, или пустая строка.
static func puzzle_of(id: String) -> String:
	return str((DEFS.get(id, {}) as Dictionary).get("puzzle", ""))


static func about(id: String) -> String:
	return str((DEFS.get(id, {}) as Dictionary).get("about", ""))


static func flag_for(id: String) -> String:
	return FLAG_PREFIX + id


static func is_installed(id: String) -> bool:
	return is_program(id) and GameState.has_flag(flag_for(id))


static func installed() -> PackedStringArray:
	var result: PackedStringArray = []
	for id: String in ids():
		if is_installed(id):
			result.append(id)
	return result


## Игровых минут на запуск. Числа — в balance.json, не в коде.
static func minutes_for(id: String) -> int:
	var key: String = str((DEFS.get(id, {}) as Dictionary).get("minutes", ""))
	var costs: Dictionary = DataLoader.balance().get("action_minutes", {}) as Dictionary
	return int(costs.get(key, FALLBACK_MINUTES))


## Включён ли трейс: он приходит вместе с группой.
static func trace_enabled() -> bool:
	return GameState.has_flag(FLAG_GROUP_JOINED)
