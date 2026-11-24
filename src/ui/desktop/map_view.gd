class_name MapView
extends ScrollContainer
## Окно «Карта сети»: квадратик — узел, подсветка — где игрок сейчас, линии — известные связи.
## Показывает только то, что игрок уже узнал (docs/gameplay/network.md). Никаких правил:
## читает `Network` и текущий узел терминала.

const NODE_SIZE: Vector2 = Vector2(120, 44)

var terminal: Terminal
## Тема ПК героя: узлы, связи и подписи рисуются ролями её цветов.
var theme_id: String = GameTheme.pc_theme_id()

var _canvas: Control
var _positions: Dictionary = {}


func setup(shared_terminal: Terminal) -> void:
	terminal = shared_terminal
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas = Control.new()
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)
	refresh()


## Перерисовать после команды: `scan` и `connect` меняют карту.
func refresh() -> void:
	var net: Network = Network.for_game()
	var book: Array[Dictionary] = net.address_book()
	var ids: PackedStringArray = []
	var links: Dictionary = {}
	for entry: Dictionary in book:
		var id: String = str(entry["id"])
		ids.append(id)
		links[id] = net.definition(id).get("links", [])
	var layout: Dictionary = MapLayout.compute(ids, links)
	_positions = layout["positions"] as Dictionary
	_canvas.custom_minimum_size = layout["size"] as Vector2
	_canvas.queue_redraw()


func known_nodes() -> PackedStringArray:
	var result: PackedStringArray = []
	for id: String in _positions.keys():
		result.append(id)
	result.sort()
	return result


func _draw_map() -> void:
	var net: Network = Network.for_game()
	var ids: PackedStringArray = known_nodes()
	var links: Dictionary = {}
	for id: String in ids:
		links[id] = net.definition(id).get("links", [])
	for edge: Array in MapLayout.edges(ids, links):
		var a: Vector2 = (_positions[edge[0]] as Vector2) + NODE_SIZE / 2.0
		var b: Vector2 = (_positions[edge[1]] as Vector2) + NODE_SIZE / 2.0
		_canvas.draw_line(a, b, GameTheme.color("border", theme_id), 2.0)

	var here: String = terminal.node_id()
	var font: Font = get_theme_default_font()
	var text: Color = GameTheme.color("text", theme_id)
	var dim: Color = GameTheme.color("text_dim", theme_id)
	var panel: Color = GameTheme.color("panel_raised", theme_id)
	for id: String in ids:
		var rect := Rect2(_positions[id] as Vector2, NODE_SIZE)
		var entry: Dictionary = net.book_entry(id)
		# Взломанный узел — подложка с оттенком `ok`, текущий — рамка акцента.
		var fill: Color = panel.lerp(GameTheme.color("ok", theme_id), 0.35) if bool(entry["hacked"]) else panel
		_canvas.draw_rect(rect, fill)
		_canvas.draw_rect(rect, GameTheme.color("accent", theme_id) if id == here else GameTheme.color("border", theme_id), false, 3.0 if id == here else 1.0)
		var title: String = str(entry["title"])
		_canvas.draw_string(font, rect.position + Vector2(6, 18), str(entry["address"]), HORIZONTAL_ALIGNMENT_LEFT, NODE_SIZE.x - 12, 14, text)
		_canvas.draw_string(font, rect.position + Vector2(6, 36), title if not title.is_empty() else str(entry["device"]), HORIZONTAL_ALIGNMENT_LEFT, NODE_SIZE.x - 12, 12, dim)
