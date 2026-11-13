class_name FsPath
extends RefCounted
## Пути виртуальной файловой системы: разбор, нормализация, права, маски.
##
## Отдельный файл, потому что это самая ошибкоёмкая часть файловой системы: `cd ../..`,
## выход за корень, двойные слеши, маски. Чистые функции без состояния — покрываются
## тестами целиком, а операции с файлами (filesystem.gd) на них опираются.
##
## Корней ровно четыре (docs/tech/terminal-spec.md), других путей в игре не бывает.

const ROOT: String = "/"

## Каталоги верхнего уровня. Порядок важен только для вывода `ls /`.
const ROOTS: PackedStringArray = ["/home", "/log", "/sys", "/prog"]

## Требуют прав администратора. Логи специально не здесь: чистить за собой надо
## с первого дня, а rootstep выдаёт группа (docs/gameplay/hacking.md).
const ADMIN_ROOTS: PackedStringArray = ["/sys", "/prog"]


## Привести путь к виду /a/b: убрать двойные слеши, точки, подняться по «..».
## Выход выше корня обрезается, а не считается ошибкой — так ведут себя настоящие оболочки:
## `cd /..` оставляет тебя в корне.
static func normalize(path: String) -> String:
	var parts: PackedStringArray = path.split("/", false)
	var stack: PackedStringArray = []
	for part: String in parts:
		if part == ".":
			continue
		if part == "..":
			if not stack.is_empty():
				stack.remove_at(stack.size() - 1)
			continue
		stack.append(part)
	if stack.is_empty():
		return ROOT
	return ROOT + "/".join(stack)


## Путь, который имел в виду игрок: аргумент команды относительно текущего каталога.
## Абсолютный аргумент (начинается со слеша) заменяет текущий каталог целиком.
static func resolve(cwd: String, arg: String) -> String:
	var trimmed: String = arg.strip_edges()
	if trimmed.is_empty():
		return normalize(cwd)
	if trimmed.begins_with(ROOT):
		return normalize(trimmed)
	return normalize(cwd.path_join(trimmed))


## Внутри ли путь одного из четырёх корней. Сам корень «/» допустим: `ls /` показывает их список.
static func is_valid(path: String) -> bool:
	var normalized: String = normalize(path)
	if normalized == ROOT:
		return true
	return not root_of(normalized).is_empty()


## Корневой каталог пути: /home/mail/a.txt → /home. Пустая строка, если путь вне корней.
static func root_of(path: String) -> String:
	var normalized: String = normalize(path)
	for root: String in ROOTS:
		if normalized == root or normalized.begins_with(root + ROOT):
			return root
	return ""


static func requires_admin(path: String) -> bool:
	return ADMIN_ROOTS.has(root_of(path))


## Родительский каталог. Для корня и для верхнего уровня — корень.
static func parent(path: String) -> String:
	var normalized: String = normalize(path)
	if normalized == ROOT:
		return ROOT
	var cut: int = normalized.rfind(ROOT)
	if cut <= 0:
		return ROOT
	return normalized.substr(0, cut)


## Имя последнего элемента: /home/mail/a.txt → a.txt.
static func name_of(path: String) -> String:
	var normalized: String = normalize(path)
	if normalized == ROOT:
		return ROOT
	return normalized.substr(normalized.rfind(ROOT) + 1)


## Лежит ли путь прямо в каталоге (не глубже). /home/a.txt лежит в /home, /home/x/a.txt — нет.
static func is_direct_child(path: String, directory: String) -> bool:
	return parent(path) == normalize(directory)


static func has_mask(arg: String) -> bool:
	return arg.contains("*") or arg.contains("?")


## Сопоставление с маской: `*` и `?`, как в оболочке. Регистр учитывается:
## в файловой системе игры имена всегда строчные.
static func matches_mask(name: String, mask: String) -> bool:
	return name.match(mask)
