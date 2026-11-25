class_name MapView
extends ScrollContainer
## Окно «Карта сети» (docs/tech/desktop-layout.md, «Карта сети»): узлы — точки со значком устройства,
## линии — известные связи. Живая, как в хакерских играх: текущий узел пульсирует, по линиям бегут
## импульсы, сеть спокойно «дышит». Подписи не висят постоянно — карточка узла (адрес, имя, тип,
## состояние) появляется при наведении. Показывает только то, что игрок уже узнал
## (docs/gameplay/network.md). Правил нет: читает `Network` и текущий узел терминала.

## Клетка раскладки (`MapLayout`): по её центру стоит узел.
const NODE_SIZE: Vector2 = Vector2(120, 44)
const RADIUS: float = 17.0
const ICON_SIDE: float = 20.0
## Наведение «цепляет» узел чуть дальше его круга.
const HOVER_RADIUS: float = 24.0
const PULSE_SECONDS: float = 1.8
const BREATH_SECONDS: float = 4.0
## Скорость импульса по линии (px/с) и сколько их на линии.
const PULSE_SPEED: float = 70.0
## Тип устройства для игрока; узел, о котором ещё ничего не знают, — «неизвестное устройство».
const DEVICE_TITLES: Dictionary = {
	"pc": "ПК", "router": "Роутер", "server": "Сервер", "phone": "Телефон", "unknown": "Неизвестное устройство",
}

var terminal: Terminal
var theme_id: String = GameTheme.pc_theme_id()

var _canvas: Control
var _card: PanelContainer
var _card_text: RichTextLabel
var _positions: Dictionary = {}
var _entries: Dictionary = {}
var _edges: Array[Array] = []
var _layout_size: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _hovered: String = ""
## Значки устройств узлов: id → TextureRect поверх холста.
var _icons: Dictionary = {}


func setup(shared_terminal: Terminal) -> void:
	terminal = shared_terminal
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.draw.connect(_draw_map)
	_canvas.gui_input.connect(_on_canvas_input)
	_canvas.mouse_exited.connect(func() -> void: _hover(""))
	add_child(_canvas)
	_build_card()
	resized.connect(_fit_canvas)
	refresh()


## Карточка узла при наведении: в теме окна, поверх карты.
func _build_card() -> void:
	_card = PanelContainer.new()
	_card.name = "NodeCard"
	_card.visible = false
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.theme_type_variation = "CardPanel"
	_card.top_level = true
	_card.z_index = 10
	_canvas.add_child(_card)
	_card_text = RichTextLabel.new()
	_card_text.bbcode_enabled = true
	_card_text.fit_content = true
	_card_text.scroll_active = false
	_card_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_card_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_card_text)


## Перечитать карту после команды: `scan`, `probe` и `connect` меняют её.
func refresh() -> void:
	var net: Network = Network.for_game()
	var ids: PackedStringArray = []
	var links: Dictionary = {}
	_entries.clear()
	for entry: Dictionary in net.address_book():
		var id: String = str(entry["id"])
		ids.append(id)
		links[id] = net.definition(id).get("links", [])
		_entries[id] = entry
	var layout: Dictionary = MapLayout.compute(ids, links)
	_positions = layout["positions"] as Dictionary
	_layout_size = layout["size"] as Vector2
	_edges = MapLayout.edges(known_nodes(), links)
	_fit_canvas()


func known_nodes() -> PackedStringArray:
	var result: PackedStringArray = []
	for id: String in _positions.keys():
		result.append(id)
	result.sort()
	return result


## Устройство узла для карты: пока узел не прощупан и не взломан, игрок не знает, что это.
func device_of(id: String) -> String:
	if id == Network.HOME_ID:
		return "pc"
	var entry: Dictionary = _entries.get(id, {}) as Dictionary
	var net: Network = Network.for_game()
	if not net.is_probed(id) and not bool(entry.get("hacked", false)):
		return "unknown"
	var device: String = str(entry.get("device", "pc"))
	return device if DEVICE_TITLES.has(device) else "unknown"


## Холст не меньше окна: маленькая сеть стоит по центру, большая прокручивается.
func _fit_canvas() -> void:
	if _canvas == null:
		return
	_canvas.custom_minimum_size = _layout_size.max(size)
	_place_icons()
	_canvas.queue_redraw()


## Значки устройств: по одному на известный узел, по центру его круга.
func _place_icons() -> void:
	for id: String in _icons.keys():
		if not _positions.has(id):
			(_icons[id] as Node).queue_free()
			_icons.erase(id)
	var side: Vector2 = Vector2(ICON_SIDE, ICON_SIDE)
	for id: String in known_nodes():
		var icon: TextureRect = _icons.get(id) as TextureRect
		if icon == null:
			icon = TextureRect.new()
			icon.name = "Icon_" + id
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_canvas.add_child(icon)
			_canvas.move_child(_card, -1)
			_icons[id] = icon
		icon.texture = GameTheme.glyph("node_" + device_of(id), theme_id)
		icon.position = _center(id) - side / 2.0
		icon.size = side


## Сдвиг раскладки к центру холста, когда сеть меньше окна.
func _offset() -> Vector2:
	return ((_canvas.custom_minimum_size - _layout_size) / 2.0).max(Vector2.ZERO)


func _center(id: String) -> Vector2:
	return (_positions[id] as Vector2) + NODE_SIZE / 2.0 + _offset()


# --- Анимация -------------------------------------------------------------------

## Карта живёт, только пока её видно: свёрнутое окно ничего не перерисовывает.
func _process(delta: float) -> void:
	if _canvas == null or not is_visible_in_tree():
		return
	_time += delta
	_canvas.queue_redraw()


func _draw_map() -> void:
	var colors: Dictionary = _colors()
	_draw_grid(colors)
	var current: String = here()
	for edge: Array in _edges:
		_draw_edge(str(edge[0]), str(edge[1]), current, colors)
	for id: String in known_nodes():
		_draw_node(id, id == current, colors)


## Цвета карты из темы окна: фон, сетка, линии, импульсы, узлы по состоянию.
func _colors() -> Dictionary:
	var dark: bool = GameTheme.color("panel", theme_id).get_luminance() < 0.4
	var background: Color = GameTheme.color("background", theme_id)
	var panel: Color = GameTheme.color("panel", theme_id)
	return {
		"back": background.darkened(0.25) if dark else panel.lerp(Color.WHITE, 0.35),
		"grid": Color(GameTheme.color("border", theme_id), 0.18),
		"line": Color(GameTheme.color("border", theme_id), 0.75),
		"pulse": GameTheme.color("accent_alt", theme_id),
		"hot": GameTheme.color("accent", theme_id),
		"ok": GameTheme.color("ok", theme_id),
		"node": background if dark else panel,
		"ring": GameTheme.color("border", theme_id),
		"text": GameTheme.color("text", theme_id),
		"dim": GameTheme.color("text_dim", theme_id),
	}


## Фон и редкая точечная сетка — «экран радара».
func _draw_grid(colors: Dictionary) -> void:
	var area: Vector2 = _canvas.size
	_canvas.draw_rect(Rect2(Vector2.ZERO, area), colors["back"] as Color)
	var step: float = 24.0
	var dot: Color = colors["grid"] as Color
	var y: float = step / 2.0
	while y < area.y:
		var x: float = step / 2.0
		while x < area.x:
			_canvas.draw_rect(Rect2(x, y, 1.5, 1.5), dot)
			x += step
		y += step


## Связь: тонкая линия и бегущие по ней импульсы (к текущему узлу — цветом акцента).
func _draw_edge(a_id: String, b_id: String, here: String, colors: Dictionary) -> void:
	var a: Vector2 = _center(a_id)
	var b: Vector2 = _center(b_id)
	var hot: bool = a_id == here or b_id == here
	var line: Color = colors["line"] as Color
	_canvas.draw_line(a, b, line, 1.5, true)
	var length: float = a.distance_to(b)
	if length < 1.0:
		return
	var pulse: Color = (colors["hot"] if hot else colors["pulse"]) as Color
	# Импульсы идут от текущего узла наружу; у каждой линии своя фаза, чтобы сеть не мигала в такт.
	var from: Vector2 = b if b_id == here else a
	var to: Vector2 = a if b_id == here else b
	var phase: float = float(absi(hash(a_id + b_id)) % 1000) / 1000.0
	var count: int = maxi(1, int(length / 140.0))
	for k: int in count:
		var t: float = fposmod(_time * PULSE_SPEED / length + phase + float(k) / float(count), 1.0)
		var at: Vector2 = from.lerp(to, t)
		var fade: float = sin(t * PI)
		_canvas.draw_circle(at, 4.0, Color(pulse, 0.18 * fade), true, -1.0, true)
		_canvas.draw_circle(at, 2.0, Color(pulse, 0.9 * fade), true, -1.0, true)


## Узел: круг со значком устройства. Кольцо — состояние: текущий (акцент, расходящийся пульс),
## взломан (`ok`), остальные — цвет рамки; все слегка «дышат».
func _draw_node(id: String, current: bool, colors: Dictionary) -> void:
	var c: Vector2 = _center(id)
	var entry: Dictionary = _entries.get(id, {}) as Dictionary
	var ring: Color = colors["ring"] as Color
	if current:
		ring = colors["hot"] as Color
	elif bool(entry.get("hacked", false)) or id == Network.HOME_ID:
		ring = colors["ok"] as Color
	var phase: float = float(absi(hash(id)) % 1000) / 1000.0
	var breath: float = 0.5 + 0.5 * sin(TAU * (_time / BREATH_SECONDS + phase))
	if current:
		var p: float = fposmod(_time / PULSE_SECONDS, 1.0)
		_canvas.draw_arc(c, RADIUS + 4.0 + 22.0 * p, 0.0, TAU, 48, Color(ring, 0.55 * (1.0 - p)), 2.0, true)
	# Мягкий ореол дыхания и сам узел.
	_canvas.draw_circle(c, RADIUS + 5.0, Color(ring, 0.08 + 0.08 * breath), true, -1.0, true)
	_canvas.draw_circle(c, RADIUS, colors["node"] as Color, true, -1.0, true)
	var width: float = 2.5 if current or id == _hovered else 1.5
	_canvas.draw_arc(c, RADIUS, 0.0, TAU, 40, Color(ring, 0.75 + 0.25 * breath), width, true)
	# Значок устройства — отдельный узел поверх холста (`_place_icons`): нарисованный на холсте после
	# множества примитивов, он выходил белым квадратом.


# --- Наведение ------------------------------------------------------------------

func _on_canvas_input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion == null:
		return
	var found: String = ""
	for id: String in known_nodes():
		if _center(id).distance_to(motion.position) <= HOVER_RADIUS:
			found = id
	_hover(found)


## Показать карточку узла рядом с ним (или спрятать, если мышь ушла с узлов).
func _hover(id: String) -> void:
	if id == _hovered:
		return
	_hovered = id
	_card.visible = not id.is_empty()
	if id.is_empty():
		return
	_card_text.text = card_text(id)
	_card.reset_size()
	# Карточка под узлом, по центру; у нижнего края окна — над ним; за боковые края не выходит.
	var c: Vector2 = _canvas.global_position + _center(id)
	var at: Vector2 = Vector2(c.x - _card.size.x / 2.0, c.y + RADIUS + 12.0)
	if at.y + _card.size.y > global_position.y + size.y:
		at.y = c.y - RADIUS - 12.0 - _card.size.y
	at.x = clampf(at.x, global_position.x + 4.0, maxf(global_position.x + size.x - _card.size.x - 4.0, global_position.x + 4.0))
	_card.global_position = at


## Текст карточки: адрес, имя (если узнали), тип устройства и состояние.
func card_text(id: String) -> String:
	var entry: Dictionary = _entries.get(id, {}) as Dictionary
	var colors: Dictionary = _colors()
	var dim: String = (colors["dim"] as Color).to_html(false)
	var lines: PackedStringArray = []
	var address: String = str(entry.get("address", ""))
	lines.append("[b]%s[/b]" % (address if not address.is_empty() else id))
	var title: String = str(entry.get("title", ""))
	if id == Network.HOME_ID:
		title = "Мой ПК" if title.is_empty() else title
	if not title.is_empty():
		lines.append(title)
	lines.append("[color=#%s]%s[/color]" % [dim, DEVICE_TITLES.get(device_of(id), "")])
	lines.append("[color=#%s]%s[/color]" % [_state_color(id, colors).to_html(false), state_of(id)])
	return "\n".join(lines)


## Состояние узла для игрока.
## Где герой для карты: узел, к которому подключён, даже если ещё у двери (вход не выполнен) —
## как в приглашении консоли `10.0.0.7>` (баг разработчика 25.11.2026); иначе свой ПК.
func here() -> String:
	if terminal == null:
		return Network.HOME_ID
	var target: String = terminal.session.target_id()
	return target if not target.is_empty() else terminal.node_id()


func state_of(id: String) -> String:
	if terminal != null and id == here():
		return "вы здесь"
	if id == Network.HOME_ID:
		return "свой компьютер"
	if bool((_entries.get(id, {}) as Dictionary).get("hacked", false)):
		return "доступ получен"
	return "доступа нет"


func _state_color(id: String, colors: Dictionary) -> Color:
	if terminal != null and id == here():
		return colors["hot"] as Color
	if id == Network.HOME_ID or bool((_entries.get(id, {}) as Dictionary).get("hacked", false)):
		return colors["ok"] as Color
	return colors["dim"] as Color
