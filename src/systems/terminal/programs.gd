class_name Programs
extends RefCounted
## Программы героя: что бывает, что доступно, сколько стоит времени
## (docs/tech/terminal-spec.md, «Программы»; docs/gameplay/hacking.md).
##
## Описания программ — в `data/programs.json`: новая программа с готовым видом (`cracker`, `auto`,
## `recon`) добавляется данными, без правок кода. Там же её **требования** (`requires`) на общем
## языке условий (docs/tech/quest-format.md): навык, ранг и всё остальное, что умеет `Conditions`.
## Так новой программе сразу выставляется этап игры, на котором игрок её получит.
##
## Программа **доступна**, когда стоит флаг `prog.<имя>` (выдал сюжет, набор ОС или награда)
## **или** выполнены её непустые требования. Решено 15.11.2026: на старте у героя нет ни одной
## программы, у него обычная ОС, а первые задания — прямой доступ без взлома. Программы приходят
## вместе с хакерской ОС (часть в комплекте, остальное позже) и работают только в ней.
##
## Название — вымышленное, и все взломы вымышленные (CLAUDE.md).

const KIND_CRACKER: String = "cracker"  # головоломка против сервиса, стартует трейс
const KIND_AUTO: String = "auto"        # работает сама, полоска прогресса
const KIND_RECON: String = "recon"      # разведка, трейс не запускает

const KINDS: PackedStringArray = [KIND_CRACKER, KIND_AUTO, KIND_RECON]

const FLAG_PREFIX: String = "prog."
## Ворота давления (docs/tech/gates.md): пока они закрыты, на узлах нет трейса и не растёт
## заметность. Кто и когда их открывает — дело рельсов, песочнице это неважно.
const GATE_PRESSURE: String = "gate.pressure"

const FALLBACK_MINUTES: int = 3


## Описания всех программ из данных. Ключи, начинающиеся с «_», — комментарии.
static func definitions() -> Dictionary:
	var result: Dictionary = {}
	var data: Dictionary = DataLoader.programs()
	for id: String in data.keys():
		if not id.begins_with("_") and data[id] is Dictionary:
			result[id] = data[id]
	return result


static func ids() -> PackedStringArray:
	var result: PackedStringArray = []
	for id: String in definitions().keys():
		result.append(id)
	result.sort()
	return result


static func is_program(name: String) -> bool:
	return definitions().has(name)


static func kind_of(id: String) -> String:
	return str(_field(id, "kind"))


## Тип головоломки, против которой работает взломщик, или пустая строка.
static func puzzle_of(id: String) -> String:
	return str(_field(id, "puzzle"))


static func about(id: String) -> String:
	return str(_field(id, "about"))


## Требования программы на языке условий; пустой список — требований нет.
static func requirements(id: String) -> Array:
	var value: Variant = _field(id, "requires")
	return (value as Array) if value is Array else []


static func flag_for(id: String) -> String:
	return FLAG_PREFIX + id


## Выдана ли программа явно: флагом набора ОС, награды, сюжета.
static func is_granted(id: String) -> bool:
	return GameState.has_flag(flag_for(id))


## Хватает ли герою навыка, ранга и прочего, что требует программа. Пустые требования —
## не «выполнены», а «нет требований»: программа без них приходит только по выдаче.
static func requirements_met(id: String) -> bool:
	var required: Array = requirements(id)
	return not required.is_empty() and Conditions.check_all(required)


static func is_installed(id: String) -> bool:
	return is_program(id) and (is_granted(id) or requirements_met(id))


static func installed() -> PackedStringArray:
	var result: PackedStringArray = []
	for id: String in ids():
		if is_installed(id):
			result.append(id)
	return result


## Игровых минут на запуск. Числа — в balance.json, не в коде.
static func minutes_for(id: String) -> int:
	var key: String = str(_field(id, "minutes"))
	var costs: Dictionary = DataLoader.balance().get("action_minutes", {}) as Dictionary
	return int(costs.get(key, FALLBACK_MINUTES))


## Включён ли трейс: он идёт за теми же воротами, что и заметность.
static func trace_enabled() -> bool:
	return GameState.has_flag(GATE_PRESSURE)


static func _field(id: String, name: String) -> Variant:
	return (definitions().get(id, {}) as Dictionary).get(name)
