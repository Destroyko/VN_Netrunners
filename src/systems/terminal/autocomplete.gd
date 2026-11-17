class_name Autocomplete
extends RefCounted
## Автодополнение по Tab (docs/tech/terminal-spec.md, «Автодополнение»).
##
## Правила:
## - дополняем до самого длинного общего префикса;
## - вариант один — дописывается полностью (каталог со слешем на конце);
## - вариантов несколько — показываем список, строка не меняется;
## - что дополнять, зависит от места в строке: первое слово — команда или программа,
##   дальше — то, что ждёт эта команда (файл, адрес, сервис).
## Адреса — только те, что игрок уже знает: иначе Tab выдавал бы карту сети (решено 15.11.2026).

const PATH_COMMANDS: PackedStringArray = ["ls", "cd", "cat", "cp", "mv", "rm", "mkdir", "put", "decrypt"]
const ADDRESS_COMMANDS: PackedStringArray = ["connect", "probe"]


## Дополнить слово под курсором (в конце строки). Возвращает {"line", "options"}.
static func complete(line: String, terminal: Terminal) -> Dictionary:
	var trailing_space: bool = line.ends_with(" ")
	var words: PackedStringArray = CommandLine.parse(line)
	var index: int = words.size() if trailing_space else maxi(words.size() - 1, 0)
	var partial: String = "" if trailing_space or words.is_empty() else words[words.size() - 1]

	var candidates: PackedStringArray = _candidates(words, index, partial, terminal)
	var matches: PackedStringArray = []
	for candidate: String in candidates:
		if candidate.begins_with(partial):
			matches.append(candidate)
	matches.sort()

	if matches.is_empty():
		return {"line": line, "options": PackedStringArray()}

	var common: String = _common_prefix(matches)
	var head: String = line.substr(0, line.length() - partial.length())
	if matches.size() == 1:
		# Один вариант: дописываем и, если это не каталог, ставим пробел для следующего слова.
		var finished: String = matches[0]
		return {"line": head + _quote(finished) + ("" if finished.ends_with("/") else " "), "options": matches}
	return {"line": head + _quote(common), "options": matches}


static func _candidates(
	words: PackedStringArray, index: int, partial: String, terminal: Terminal
) -> PackedStringArray:
	if index == 0:
		return _command_names(terminal)

	var command: String = words[0].to_lower()
	if command == "help":
		return _command_names(terminal)
	if PATH_COMMANDS.has(command):
		return _paths(partial, terminal, command == "put" and index == 1)
	if ADDRESS_COMMANDS.has(command):
		return _addresses(terminal)
	if command == "run" and index == 1:
		return Programs.installed()
	if command == "run" or Programs.is_program(command):
		return _services(terminal)
	return PackedStringArray()


static func _command_names(terminal: Terminal) -> PackedStringArray:
	var names: PackedStringArray = []
	for name: String in TerminalHelp.COMMANDS.keys():
		names.append(name)
	names.append_array(Programs.installed())
	return names


static func _addresses(terminal: Terminal) -> PackedStringArray:
	var result: PackedStringArray = []
	for entry: Dictionary in terminal.net.address_book():
		if str(entry["id"]) != Network.HOME_ID:
			result.append(str(entry["address"]))
	return result


static func _services(terminal: Terminal) -> PackedStringArray:
	var result: PackedStringArray = []
	var target: String = terminal.session.target_id()
	if target.is_empty():
		return result
	for service: Dictionary in terminal.net.describe(target, terminal.now())["services"] as Array:
		result.append(str(service["port"]))
	return result


## Пути к файлам: смотрим каталог, в котором стоит курсор, и берём то, что в нём лежит.
## `put` в первом аргументе берёт файлы со своего ПК, а не с узла.
static func _paths(partial: String, terminal: Terminal, from_home: bool) -> PackedStringArray:
	var files: Filesystem = terminal.home_fs() if from_home else terminal.fs()
	var base: String = terminal.home_cwd() if from_home else terminal.cwd()
	var admin: bool = true if from_home else terminal.admin()

	var slash: int = partial.rfind("/")
	var dir_part: String = partial.substr(0, slash + 1) if slash >= 0 else ""
	var directory: String = FsPath.resolve(base, dir_part) if not dir_part.is_empty() else base

	var result: PackedStringArray = []
	if FsPath.requires_admin(directory) and not admin:
		return result
	for entry: Dictionary in files.list(directory, admin):
		result.append(dir_part + str(entry["name"]) + ("/" if bool(entry["is_dir"]) else ""))
	return result


static func _common_prefix(items: PackedStringArray) -> String:
	var prefix: String = items[0]
	for item: String in items:
		while not item.begins_with(prefix):
			prefix = prefix.substr(0, prefix.length() - 1)
	return prefix


## Путь с пробелом возвращаем в кавычках, иначе при разборе строки он развалится на два слова.
static func _quote(word: String) -> String:
	return "\"%s\"" % word if word.contains(" ") else word
