class_name Room
extends RefCounted
## Комната героя: что показывает монитор, что делает системный блок и как работает флешка
## (docs/gameplay/hacking.md, «Комната: взаимодействие с ПК»).
##
## Чистые правила без сцен. Сцена комнаты (src/ui/room.gd) только показывает текст и передаёт
## клики. Сюжет сюда не проникает: кто и когда дал флешку, решают рельсы (docs/tech/gates.md).


static func os_level() -> String:
	return str(GameState.get_var_or(Terminal.VAR_OS, Terminal.OS_NORMAL))


## Клик по монитору. `desktop` — рабочий стол загрузится; иначе вместо него аварийная консоль.
## `lines` — что видно на экране, если стол не загрузился.
static func monitor(home: Filesystem) -> Dictionary:
	var desktop: bool = SystemFiles.has_desktop(home) and os_level() != Terminal.OS_OLD
	var lines: PackedStringArray = []
	if not desktop:
		lines.append("fatal error")
		lines.append_array(SystemFiles.boot_errors(home))
		if os_level() == Terminal.OS_OLD:
			lines.append("операционная система не найдена")
	return {"desktop": desktop, "lines": lines}


## Клик по системному блоку без предмета: что внутри. Железо пока одно, апгрейды — M2.
static func hardware() -> PackedStringArray:
	return PackedStringArray([
		"системный блок: обычное железо, без апгрейдов",
		"ОС: " + os_level(),
	])


## Подключить предмет-носитель к системному блоку. Возвращает {ok, lines, restored, os_changed}.
## Флешка не расходуется: она остаётся резервной копией навсегда. ОС она только поднимает
## (old → normal) и никогда не понижает: с хакерской ОС ничего не меняется.
static func use_item(item_id: String, home: Filesystem) -> Dictionary:
	var result: Dictionary = {"ok": false, "lines": PackedStringArray(), "restored": PackedStringArray(), "os_changed": false}
	var lines: PackedStringArray = result["lines"]
	if not Inventory.has(item_id):
		lines.append("этого предмета у тебя нет")
		return result
	if Inventory.kind_of(item_id) != Inventory.KIND_RESTORE:
		lines.append("%s: к системному блоку это не подключить" % Inventory.name_of(item_id))
		return result

	result["ok"] = true
	if os_level() == Terminal.OS_OLD:
		GameState.set_var(Terminal.VAR_OS, Terminal.OS_NORMAL)
		result["os_changed"] = true
		lines.append("установлена обычная ОС")
	var restored: PackedStringArray = SystemFiles.restore_system(home)
	result["restored"] = restored
	for path: String in restored:
		lines.append("восстановлено: %s" % path)
	if lines.is_empty():
		lines.append("системные файлы на месте, чинить нечего")
	if not restored.is_empty() or bool(result["os_changed"]):
		EventBus.system_restored.emit(restored, bool(result["os_changed"]))
	return result
