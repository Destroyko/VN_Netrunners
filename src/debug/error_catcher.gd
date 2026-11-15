extends Logger
## Ловит ошибки и предупреждения Godot и отдаёт их журналу сессии (`SessionLog`).
## Вызывается движком, возможно, из других потоков, поэтому только передаёт строку дальше
## через отложенный вызов.

## Куда писать: `SessionLog.write` с привязанным видом записи.
var sink: Callable


func _log_error(
	function: String, file: String, line: int, code: String, rationale: String,
	_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]
) -> void:
	var kind: String = "предупреждение" if error_type == ERROR_TYPE_WARNING else "ошибка"
	var text: String = rationale if not rationale.is_empty() else code
	if sink.is_valid():
		sink.call_deferred("%s: %s (%s:%d, %s)" % [kind, text, file, line, function])


func _log_message(message: String, error: bool) -> void:
	if error and sink.is_valid():
		sink.call_deferred(message.strip_edges())
