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


## Консоль слева, справа от неё колонка: карта сверху, «Защита узла» под ней.
func arrange() -> void:
	var console: DesktopWindow = _desktop.window_of("terminal")
	var map: DesktopWindow = _desktop.window_of("map")
	var defense: DesktopWindow = _desktop.window_of(DEFENSE_APP)
	if console == null or (map == null and defense == null):
		return
	# Область окон стола; до раскладки (стол только собран) она бывает меньше самой консоли —
	# тогда берём экран.
	var area: Vector2 = console.get_parent_area_size()
	if area.x < console.size.x or area.y < console.size.y:
		area = console.get_viewport_rect().size
	var column: Array[DesktopWindow] = []
	var sizes: Array[Rect2] = []
	for window: DesktopWindow in [map, defense]:
		if window != null:
			column.append(window)
			sizes.append(Rect2(Vector2.ZERO, window.size).merge(Rect2(Vector2.ZERO, window.get_combined_minimum_size())))
	var plan: Dictionary = layout(area, Rect2(console.position, console.size), sizes)
	console.position.x = float(plan["console_x"])
	for i: int in column.size():
		var rect: Rect2 = (plan["column"] as Array)[i] as Rect2
		column[i].position = rect.position
		column[i].size = rect.size


## Расчёт расстановки без окон (тестируется отдельно). `sizes` — окна колонки сверху вниз:
## size — желаемый размер, он же не меньше минимального. Не помещается справа — консоль
## отъезжает к левому краю, колонка занимает свободную ширину, по высоте окна идут подряд.
## Возвращает {console_x, column: [Rect2]}.
static func layout(area: Vector2, console: Rect2, sizes: Array[Rect2]) -> Dictionary:
	var want: float = 0.0
	for size: Rect2 in sizes:
		want = maxf(want, size.size.x)
	var console_x: float = console.position.x
	if console_x + console.size.x + GAP + want > area.x:
		console_x = GAP
	var x: float = console_x + console.size.x + GAP
	var width: float = maxf(minf(want, area.x - x - GAP), 1.0)
	var y: float = console.position.y
	var column: Array[Rect2] = []
	for size: Rect2 in sizes:
		var height: float = clampf(size.size.y, 1.0, maxf(1.0, area.y - y - GAP))
		column.append(Rect2(Vector2(x, y), Vector2(width, height)))
		y += height + GAP
	return {"console_x": console_x, "column": column}
