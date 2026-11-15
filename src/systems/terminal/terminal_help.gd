class_name TerminalHelp
extends RefCounted
## Справка терминала: `help` и `help <команда>` (docs/tech/terminal-spec.md, «Служебные»).
## Тексты короткие и без технического жаргона.

## Команда → [синтаксис, что делает]. Порядок — как в `help`.
const COMMANDS: Dictionary = {
	"pwd": ["pwd", "показать текущий каталог"],
	"ls": ["ls [путь]", "список файлов и каталогов; [sys] — системные, [закрыт] — нужны права"],
	"cd": ["cd <путь>", "перейти в каталог; cd .. — выше, cd / — в корень"],
	"cat": ["cat <файл>", "показать содержимое файла"],
	"cp": [
		"cp <файл> [куда]",
		"на узле: скачать файл к себе (по умолчанию в /home/dump); дома: скопировать файл",
	],
	"put": ["put <файл у себя> [куда на узле]", "положить файл со своего ПК на узел"],
	"mv": ["mv <файл> <куда>", "переместить или переименовать"],
	"rm": ["rm <файл или маска>", "удалить; маска * работает: rm * в каталоге логов"],
	"mkdir": ["mkdir <путь>", "создать каталог (только в /home)"],
	"scan": ["scan", "узлы, подключённые к текущему"],
	"probe": ["probe [адрес]", "разведка: открытые порты и защита узла"],
	"connect": ["connect <адрес>", "подключиться к узлу"],
	"dc": ["dc", "отключиться и прервать взлом"],
	"nodes": ["nodes", "все узлы, которые ты уже знаешь"],
	"progs": ["progs", "установленные программы"],
	"run": ["run <программа> [порт]", "запустить программу (можно просто имя программы)"],
	"reboot": ["reboot", "перезагрузить свой ПК"],
	"history": ["history", "последние 50 команд"],
	"clear": ["clear", "очистить экран"],
	"help": ["help [команда]", "список команд или подробности по одной"],
}


static func show(args: PackedStringArray, result: TermResult) -> void:
	if args.is_empty():
		for name: String in COMMANDS.keys():
			result.add("%-8s %s" % [name, (COMMANDS[name] as Array)[1]])
		for id: String in Programs.installed():
			result.add("%-11s %s" % [id, Programs.about(id)])
		return

	var name: String = args[0].to_lower()
	if COMMANDS.has(name):
		var entry: Array = COMMANDS[name] as Array
		result.add("использование: %s" % entry[0])
		result.add(str(entry[1]))
	elif Programs.is_program(name):
		result.add("использование: %s [порт]" % name)
		result.add(Programs.about(name))
	else:
		result.add("команда не найдена: %s" % args[0])
