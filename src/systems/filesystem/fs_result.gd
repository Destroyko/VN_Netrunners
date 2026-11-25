class_name FsResult
extends RefCounted
## Результат операции с файлами: получилось или нет, и что именно не так.
##
## Почему код ошибки, а не сразу текст: файловая система не знает, кто её спрашивает.
## Один и тот же «нет такого файла» терминал печатает игроку, а квестовая проверка
## просто учитывает как неуспех. Тексты для игрока — в message(), ровно те, что
## записаны в docs/tech/terminal-spec.md.

enum Code {
	OK,
	NOT_FOUND,
	NOT_A_DIR,
	IS_A_DIR,
	NO_PERMISSION,
	ALREADY_EXISTS,
	BAD_PATH,
	NOT_WRITABLE,
	## Не ошибка, а вопрос. Терминал печатает его, запоминает команду и повторяет её,
	## если игрок ответил «y».
	## На месте назначения уже есть файл: `cp`, `mv`.
	NEEDS_CONFIRM_REPLACE,
	## Под удаление попал системный файл: `rm`.
	NEEDS_CONFIRM_DELETE,
	## Файл в работе у программы (фоновый подбор, «Блокнот»): не двигается, не удаляется.
	BUSY,
}

var code: Code = Code.OK
## Путь, к которому относится результат — нужен и для текста ошибки, и для события.
var path: String = ""
## Затронутые пути: что удалено, скопировано, перемещено. Для `rm *` их несколько.
var paths: PackedStringArray = []
## Файлы, которые маска пропустила, потому что они заняты (`rm *`).
var skipped: PackedStringArray = []
## Текст для вывода (например, содержимое файла при `cat`).
var text: String = ""
## Файл на месте назначения был заменён — после того, как игрок ответил «y».
## Терминал об этом сообщает: молча потерять свой файл обиднее, чем осознанно.
var replaced: bool = false


static func ok(for_path: String = "", with_text: String = "") -> FsResult:
	var result := FsResult.new()
	result.path = for_path
	result.text = with_text
	if not for_path.is_empty():
		result.paths = [for_path]
	return result


static func ok_many(affected: PackedStringArray) -> FsResult:
	var result := FsResult.new()
	result.paths = affected
	return result


static func fail(error: Code, for_path: String = "") -> FsResult:
	var result := FsResult.new()
	result.code = error
	result.path = for_path
	return result


func is_ok() -> bool:
	return code == Code.OK


## Операция не сделана, но и не провалена: ждёт ответа игрока.
func needs_confirm() -> bool:
	return code == Code.NEEDS_CONFIRM_REPLACE or code == Code.NEEDS_CONFIRM_DELETE


## Текст ошибки для игрока. Формулировки — из спецификации терминала.
func message() -> String:
	match code:
		Code.OK:
			return ""
		Code.NOT_FOUND:
			return "файл не найден: %s" % path
		Code.NOT_A_DIR:
			return "это не каталог: %s" % path
		Code.IS_A_DIR:
			return "это каталог, а не файл: %s" % path
		Code.NO_PERMISSION:
			return "доступ запрещён"
		Code.ALREADY_EXISTS:
			return "уже существует: %s" % path
		Code.BAD_PATH:
			return "так нельзя: %s" % path
		Code.NOT_WRITABLE:
			return "сюда нельзя писать: %s" % path
		Code.NEEDS_CONFIRM_REPLACE:
			return "здесь уже есть %s. заменить? (y/n)" % FsPath.name_of(path)
		Code.BUSY:
			return "занят: %s" % FsPath.name_of(path)
		Code.NEEDS_CONFIRM_DELETE:
			# Консоль не рассказывает, что случится: она только переспрашивает.
			if paths.size() > 1:
				return "вы действительно хотите удалить системные файлы (%d)? (y/n)" % paths.size()
			return "вы действительно хотите удалить системный файл %s? (y/n)" % FsPath.name_of(path)
		_:
			return "неизвестная ошибка"
