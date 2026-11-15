class_name SystemFiles
extends RefCounted
## Состояние своего ПК: что работает, что сломано, какая тема применена.
##
## Правила — docs/gameplay/hacking.md, раздел «Свой ПК можно сломать»:
## нет x-server.sys — вместо рабочего стола аварийная консоль (терминал в ней работает,
## поэтому игрок вытащит себя сам); нет net.sys — пропадает сеть; нет theme.sys —
## оформление становится стандартным, и это всё.
##
## Чистые функции над файловой системой: ни сцен, ни EventBus. Что показывать игроку,
## решает интерфейс (шаг 7), а события шлёт терминал.

const FILE_X_SERVER: String = "/sys/x-server.sys"
const FILE_NET: String = "/sys/net.sys"
const FILE_THEME: String = "/sys/theme.sys"

## Что восстанавливает резервный носитель. Только /sys: пользовательские файлы она не трогает
## (docs/gameplay/hacking.md). Тема сюда не входит — она косметика, не система.
const RESTORABLE: PackedStringArray = [FILE_X_SERVER, FILE_NET]

## Где лежит применённая тема. Обычная переменная состояния, новых полей в GameState не нужно.
const VAR_APPLIED_THEME: String = "pc.applied_theme"


# --- Что работает ------------------------------------------------------------

## Рабочий стол зависит от x-server.sys **в работе**, а не только при загрузке: удалил —
## и стол сразу складывается в аварийную консоль. Так игрок видит причину и следствие рядом.
static func has_desktop(filesystem: Filesystem) -> bool:
	return filesystem.has_file(FILE_X_SERVER)


static func has_network(filesystem: Filesystem) -> bool:
	return filesystem.has_file(FILE_NET)


## «ПК сломан» — это именно отсутствие рабочего стола. Без сети машина работает,
## просто локально.
static func is_broken(filesystem: Filesystem) -> bool:
	return not has_desktop(filesystem)


static func missing(filesystem: Filesystem) -> PackedStringArray:
	var result: PackedStringArray = []
	for path: String in RESTORABLE:
		if not filesystem.has_file(path):
			result.append(path)
	return result


## Сообщения для аварийной консоли: то, что игрок увидит вместо рабочего стола.
static func boot_errors(filesystem: Filesystem) -> PackedStringArray:
	var result: PackedStringArray = []
	for path: String in missing(filesystem):
		result.append("системный файл не найден: %s" % path)
	if not has_desktop(filesystem):
		result.append("рабочий стол не загружен. терминал доступен")
	return result


# --- Тема --------------------------------------------------------------------

## Тема, которая лежит в системе и применится при следующей загрузке.
## Пустая строка — файла нет, значит стандартное оформление.
static func theme_in_system(filesystem: Filesystem) -> String:
	if not filesystem.has_file(FILE_THEME):
		return ""
	return str(filesystem.file_data(FILE_THEME).get("file_id", ""))


## Тема, которая применена сейчас.
static func applied_theme() -> String:
	return str(GameState.get_var_or(VAR_APPLIED_THEME, ""))


## Скопировал чужую тему, но ещё не перезагрузился.
static func theme_pending(filesystem: Filesystem) -> bool:
	return theme_in_system(filesystem) != applied_theme()


# --- Перезагрузка ------------------------------------------------------------

## Перезагрузка: применяет тему и пересобирает стол. Фоновые задачи останавливает
## вызывающий — он же шлёт события (их система появится в M2).
##
## Почему тема только здесь, а стол ломается сразу: стол держится на работающем
## x-server.sys, а тема читается один раз при загрузке. Для игрока это и правдоподобно,
## и предсказуемо: сломал — увидел сразу, поменял оформление — перезагрузись.
static func reboot(filesystem: Filesystem) -> Dictionary:
	var previous: String = applied_theme()
	var current: String = theme_in_system(filesystem)
	GameState.set_var(VAR_APPLIED_THEME, current)
	return {
		"theme": current,
		"theme_changed": current != previous,
		"desktop": has_desktop(filesystem),
		"network": has_network(filesystem),
		"errors": boot_errors(filesystem),
	}


# --- Восстановление ----------------------------------------------------------

## Резервный носитель: возвращает недостающие системные файлы. Пользовательские не трогает.
## Возвращает, что именно восстановила — пусто, если всё было на месте.
static func restore_system(filesystem: Filesystem) -> PackedStringArray:
	var restored: PackedStringArray = []
	for path: String in missing(filesystem):
		filesystem.put_file(path, {"system": true})
		restored.append(path)
	return restored
