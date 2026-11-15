class_name PuzzleDialog
extends Control
## Модальное окно головоломки поверх рабочего стола (docs/tech/desktop-layout.md): затемняет
## всё остальное, пока партия не закончена. Сам головоломку не решает — выбирает панель по виду
## и отдаёт итог: сколько слоёв вскрыто (`Terminal.finish_puzzle`).

signal finished(gained: int)

var panel: Control


func setup(request: Dictionary) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var frame := PanelContainer.new()
	# Своя непрозрачная заливка: иначе иконки стола просвечивают сквозь окно.
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = Color(0.09, 0.1, 0.13)
	backdrop.set_content_margin_all(14)
	frame.add_theme_stylebox_override("panel", backdrop)
	center.add_child(frame)
	var rows := VBoxContainer.new()
	frame.add_child(rows)

	var header := Label.new()
	header.text = _header(request)
	rows.add_child(header)

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
		finished.emit(0)
		return
	rows.add_child(panel)


static func _header(request: Dictionary) -> String:
	var text: String = "%s · сервис %s" % [str(request.get("node", "")), str(request.get("service", ""))]
	var total: int = int(request.get("layers_total", 1))
	if total > 1:
		text += " · слой %d из %d" % [int(request.get("layers_done", 0)) + 1, total]
	return text


func _on_finished(gained: int) -> void:
	finished.emit(gained)
	queue_free()
