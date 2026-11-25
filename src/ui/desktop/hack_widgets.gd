class_name HackWidgets
extends RefCounted
## Виджеты взлома рядом с консолью (концепция `tech/desktop-layout.md`; шаг 7, часть 6):
## `connect` открывает карту сети справа от консоли, `probe` — виджет «Защита узла» под ней.
## Оба живут как обычные окна стола: их можно закрыть и подвинуть; следующий `connect` или
## `probe` снова поставит их рядом. Свежесть — на каждом итоге консоли (`refresh`).
##
## Правил здесь нет: стол открывает окна, сети и терминалу всё равно, видит ли их игрок.

const DEFENSE_APP: String = "defense"
const GAP: float = 8.0

var _desktop: Desktop
var _terminal: Terminal
## Узел, к которому были подключены на прошлом итоге: новый — значит, был `connect`.
var _last_target: String = ""


func _init(desktop: Desktop, terminal: Terminal) -> void:
	_desktop = desktop
	_terminal = terminal
	_last_target = terminal.session.target_id()


## Итог команды: подключились к новому узлу — карта рядом; окна перечитывают состояние.
func sync() -> void:
	var target: String = _terminal.session.target_id()
	if not target.is_empty() and target != _last_target:
		open_map()
	_last_target = target
	var defense: DesktopWindow = _desktop.window_of(DEFENSE_APP)
	if defense != null:
		(defense.body.get_child(0) as DefenseView).refresh()


## Карта сети справа от консоли.
func open_map() -> DesktopWindow:
	var map: DesktopWindow = _desktop.window_of("map")
	if map == null:
		map = _desktop.open_app("map")
	if map == null:
		return null
	arrange()
	return map


## `probe`: виджет «Защита узла» под картой, рядом с консолью.
func open_defense(node: String) -> DesktopWindow:
	var window: DesktopWindow = _desktop.window_of(DEFENSE_APP)
	if window == null:
		window = DesktopWindow.new()
		window.app_id = DEFENSE_APP
		window.set_minimum(Vector2(280, 150))
		var view := DefenseView.new()
		view.setup(_terminal, node)
		window.body.add_child(view)
		_desktop.attach_window(window, Vector2(420, 210))
	else:
		(window.body.get_child(0) as DefenseView).show_node(node)
	window.title = "Защита узла — %s" % str(Network.for_game().definition(node).get("address", node))
	arrange()
	_desktop.focus(window)
	return window


## Консоль слева, справа от неё колонка: карта сверху, «Защита узла» под ней. Не помещается
## справа — консоль отъезжает к левому краю, колонка сужается до свободного места.
func arrange() -> void:
	var console: DesktopWindow = _desktop.window_of("terminal")
	var map: DesktopWindow = _desktop.window_of("map")
	var defense: DesktopWindow = _desktop.window_of(DEFENSE_APP)
	if console == null or (map == null and defense == null):
		return
	var area: Vector2 = console.get_parent_area_size()
	if area == Vector2.ZERO:
		return
	var want: float = 0.0
	for window: DesktopWindow in [map, defense]:
		if window != null:
			want = maxf(want, window.get_combined_minimum_size().x)
	if console.position.x + console.size.x + GAP + want > area.x:
		console.position.x = GAP
	var x: float = console.position.x + console.size.x + GAP
	var width: float = maxf(want, area.x - x - GAP)
	var y: float = console.position.y
	for window: DesktopWindow in [map, defense]:
		if window == null:
			continue
		window.size.x = width
		window.position = Vector2(minf(x, area.x - width), y)
		var room: float = area.y - y - GAP
		window.size.y = clampf(window.size.y, window.get_combined_minimum_size().y, maxf(window.get_combined_minimum_size().y, room))
		y = window.position.y + window.size.y + GAP
