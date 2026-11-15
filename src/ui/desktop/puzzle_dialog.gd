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
		var level: int = int(request.get("difficulty", request.get("level", 2)))
		var seed_value: int = int(request.get("seed", 0))
		var make_round: Callable = func(index: int) -> MatrixPuzzle:
			return MatrixPuzzle.generate_round(level, seed_value, index)
		matrix.setup(puzzle as MatrixPuzzle, int(request.get("rounds", 1)), make_round, int(request.get("layers_done", 0)))
		matrix.finished.connect(_on_finished)
		panel = matrix
	elif puzzle is DumpPuzzle:
		var dump := DumpPanel.new()
		dump.setup(puzzle as DumpPuzzle)
		dump.finished.connect(_on_finished)
		panel = dump
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
	if request.has("port"):
		return "%s · порт %d" % [str(request.get("address", request.get("node", ""))), int(request["port"])]
	return str(request.get("node", ""))


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
	SessionLog.write("puzzle", "итог: слоёв %d" % gained)
	finished.emit(gained)
