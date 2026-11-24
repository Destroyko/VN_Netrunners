class_name DesktopPuzzles
extends RefCounted
## Окно головоломки на рабочем столе (docs/tech/desktop-layout.md): обычное окно поверх терминала,
## его можно свернуть и закрыть. Закрытие — это «выйти»: засчитывается то, что успели собрать.
## Итог уходит в терминал, его ответ — в вывод окна терминала. Тренировка из консоли F1 (`play`)
## идёт тем же окном, но терминал о ней не знает.
##
## Вынесено из `Desktop` (технический разбор 16.11.2026): стол раскладывает окна, а жизнь окна
## головоломки — здесь.

const APP_ID: String = "puzzle"

var _desktop: Desktop
var _terminal: Terminal
var _dialog: PuzzleDialog
var _window: DesktopWindow
## Тренировочная головоломка: итог не в терминал, а в `on_practice_finished`.
var _practice: bool = false
var _on_practice_finished: Callable


func _init(desktop: Desktop, terminal: Terminal, on_practice_finished: Callable) -> void:
	_desktop = desktop
	_terminal = terminal
	_on_practice_finished = on_practice_finished


func is_open() -> bool:
	return _window != null and is_instance_valid(_window)


## Тренировка: головоломка без взлома и без подключения. Нельзя, пока открыта другая.
func play(kind: String, level: int, seed_value: int) -> bool:
	if is_open():
		return false
	var puzzle: RefCounted
	var layers_total: int = 1
	if kind == "password":
		puzzle = PasswordPuzzle.generate(level, seed_value, 0)
	elif kind == "dump":
		puzzle = DumpPuzzle.generate(level, seed_value)
	else:
		layers_total = int(PuzzleLevels.matrix(level)["sequences"])
		puzzle = MatrixPuzzle.generate_round(level, seed_value, 0)
	show({
		"type": "puzzle", "kind": kind, "node": "тренировка", "service": kind,
		"layers_done": 0, "layers_total": layers_total, "puzzle": puzzle,
		"rounds": layers_total, "seed": seed_value, "difficulty": level,
	}, null)
	return true


## Открыть окно по запросу терминала (`view` — куда отдать итог; null — тренировка).
func show(request: Dictionary, view: TerminalView) -> void:
	if is_open():
		return
	# Головоломка воспроизводится по виду, ступени и сиду — их и пишем в журнал.
	var puzzle_obj: Object = request.get("puzzle") as Object
	SessionLog.write("puzzle", "открыта: %s, ступень %s, сид %s, узел %s, порт %s" % [
		request.get("kind", ""), request.get("difficulty", request.get("level", "?")),
		puzzle_obj.get("puzzle_seed") if puzzle_obj != null else "?",
		request.get("node", ""), request.get("port", "-"),
	])
	_practice = view == null
	var window := DesktopWindow.new()
	window.app_id = APP_ID
	window.title = "Взлом"
	window.set_minimum(Vector2(420, 460))
	window.closed.connect(func(_w: DesktopWindow) -> void:
		# Окно уже закрывается: итог отдаём, а второй раз закрывать не надо.
		_window = null
		if _dialog != null and is_instance_valid(_dialog):
			_dialog.abandon())
	_dialog = PuzzleDialog.new()
	window.body.add_child(_dialog)
	_dialog.setup(request)
	_dialog.finished.connect(func(gained: int) -> void:
		var done_window: DesktopWindow = _window
		_dialog = null
		_window = null
		if view != null:
			view.show_result(_terminal.finish_puzzle(gained))
		else:
			_on_practice_finished.call(gained)
		if is_instance_valid(done_window):
			done_window.close())
	# Окно не меньше содержимого: широкая сетка дампа не должна обрезаться.
	var needed: Vector2 = _dialog.get_combined_minimum_size() + Vector2(2 * DesktopWindow.PAD + 2, WindowRules.TITLE_HEIGHT + DesktopWindow.PAD + DesktopWindow.GAP + 2)
	_window = window
	_desktop.attach_window(window, Vector2(440, 480).max(needed))


## Сеанс оборвали (`dc`, трейс), пока головоломка открыта: окну больше нечего решать.
func close_stale() -> void:
	if is_open() and not _practice and _terminal.current_puzzle() == null:
		var stale: DesktopWindow = _window
		_dialog = null
		_window = null
		stale.close()
