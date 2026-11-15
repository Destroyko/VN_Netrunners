class_name PuzzleDialog
extends VBoxContainer
## Содержимое окна головоломки на рабочем столе (docs/tech/desktop-layout.md): выбирает панель
## по виду головоломки, отдаёт итог — сколько слоёв вскрыто (`Terminal.finish_puzzle`) — и даёт
## выйти. Само окно (свернуть, закрыть) — обычный `DesktopWindow`, его создаёт стол.

signal finished(gained: int)

var panel: Control

var _done: bool = false


func setup(request: Dictionary) -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var header := Label.new()
	header.text = _header(request)
	add_child(header)

	var puzzle: RefCounted = request.get("puzzle") as RefCounted
	if puzzle is PasswordPuzzle:
		var password := PasswordPanel.new()
		password.setup(puzzle as PasswordPuzzle)
		password.finished.connect(_on_finished)
		panel = password
	elif puzzle is MatrixPuzzle:
		var matrix := MatrixPanel.new()
		matrix.setup(puzzle as MatrixPuzzle)
		matrix.finished.connect(_on_finished)
		panel = matrix
	else:
		push_error("PuzzleDialog: неизвестный вид головоломки: %s" % [request.get("kind")])
		_on_finished(0)
		return
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(panel)

	var exit := Button.new()
	exit.name = "Exit"
	exit.text = "Выйти"
	exit.pressed.connect(abandon)
	add_child(exit)


static func _header(request: Dictionary) -> String:
	var text: String = "%s · сервис %s" % [str(request.get("node", "")), str(request.get("service", ""))]
	var total: int = int(request.get("layers_total", 1))
	if total > 1:
		text += " · слой %d из %d" % [int(request.get("layers_done", 0)) + 1, total]
	return text


## Выйти, не доиграв (кнопка или закрытие окна): засчитывается то, что успел собрать.
func abandon() -> void:
	if _done or panel == null:
		return
	_on_finished(int(panel.call("abandon_gained")))


func is_done() -> bool:
	return _done


func _on_finished(gained: int) -> void:
	if _done:
		return
	_done = true
	finished.emit(gained)
