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
}

var code: Code = Code.OK
## Путь, к которому относится результат — нужен и для текста ошибки, и для события.
var path: String = ""
## Затронутые пути: что удалено, скопировано, перемещено. Для `rm *` их несколько.
var paths: PackedStringArray = []
## Текст для вывода (например, содержимое файла при `cat`).
var text: String = ""
## Файл на месте назначения был заменён. Не ошибка (`cp` и `mv` перезаписывают, как в шелле),
## но терминал об этом сообщает: молча потерять свой файл обиднее, чем осознанно.
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


## Текст ошибки для игрока. Формулировки — из спецификации терминала.
func message() -> String:
	match code:
		Code.OK:
			return ""
		Code.NOT_FOUND:
			return "нет такого файла: %s" % path
		Code.NOT_A_DIR:
			return "это не каталог: %s" % path
		Code.IS_A_DIR:
			return "это каталог, а не файл: %s" % path
		Code.NO_PERMISSION:
			return "недостаточно прав. нужен доступ администратора"
		Code.ALREADY_EXISTS:
			return "уже существует: %s" % path
		Code.BAD_PATH:
			return "так нельзя: %s" % path
		Code.NOT_WRITABLE:
			return "сюда нельзя писать: %s" % path
		_:
			return "неизвестная ошибка"
