class_name DefenseView
extends VBoxContainer
## Виджет «Защита узла» рядом с консолью (концепция `tech/desktop-layout.md`, п. 3; шаг 7, часть 6):
## блоки слоёв, которые `probe` уже раскрыл, — порты (закрыт / открыт), мониторинг подключений,
## анализ действий. Слои появляются по мере сканирования; вскрыл сервис — блок перекрашивается.
## Сколько слоёв впереди, не видно, как и в консоли.
##
## Правил здесь нет: что раскрыто — `Network.probe_layers`, что вскрыто — `Network.describe`.

const BLOCK_SIZE: Vector2 = Vector2(120, 52)

var terminal: Terminal
var node_id: String = ""
var theme_id: String = GameTheme.pc_theme_id()

var _title: Label
var _grid: HFlowContainer
var _hint: Label


func setup(shared_terminal: Terminal, node: String) -> void:
	terminal = shared_terminal
	name = "DefenseView"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_title = Label.new()
	_title.name = "Node"
	_title.theme_type_variation = "DimLabel"
	add_child(_title)
	# Блоки переносятся по ширине окна: колонка рядом с консолью бывает узкой.
	_grid = HFlowContainer.new()
	_grid.name = "Blocks"
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	add_child(_grid)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.theme_type_variation = "DimLabel"
	_hint.text = "сканирование: probe"
	add_child(_hint)
	show_node(node)


func show_node(node: String) -> void:
	node_id = node
	refresh()


## Блоки: что раскрыто — то видно, вскрытый порт — цветом «ок», закрытый — «опасно».
func refresh() -> void:
	if terminal == null or node_id.is_empty():
		return
	var net: Network = Network.for_game()
	var info: Dictionary = net.describe(node_id, terminal.now())
	_title.text = "%s  %s" % [str(info.get("address", "")), str(info.get("title", ""))]
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var known: int = net.probe_layers(node_id)
	var blocks: Array[Dictionary] = blocks_of(info, known)
	for i: int in blocks.size():
		_grid.add_child(_block(i, blocks[i]))
	_hint.visible = blocks.is_empty()


## Раскрытые слои по порядку сканирования: {title, state, good}. Порядок — как у `probe`.
static func blocks_of(info: Dictionary, known: int) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for service: Dictionary in info.get("services", []) as Array:
		var open: bool = bool(service["cracked"])
		all.append({"title": "порт %d\n%s" % [int(service["port"]), str(service["name"])],
			"state": "открыт" if open else "закрыт", "good": open})
	var trace: int = int(info.get("trace_minutes", 0))
	all.append({"title": "мониторинг", "state": ("трейс %d мин" % trace) if trace > 0 else "нет", "good": trace <= 0})
	var ids: bool = bool(info.get("ids", false))
	all.append({"title": "анализ действий", "state": "есть" if ids else "нет", "good": not ids})
	return all.slice(0, mini(known, all.size()))


func block_count() -> int:
	return _grid.get_child_count()


func _block(index: int, block: Dictionary) -> PanelContainer:
	var good: bool = bool(block["good"])
	var tone: Color = GameTheme.color("ok" if good else "danger", theme_id)
	var panel := PanelContainer.new()
	panel.name = "Block_%d" % index
	panel.custom_minimum_size = BLOCK_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(tone, 0.14)
	style.border_color = tone
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	var title := Label.new()
	title.text = str(block["title"])
	title.add_theme_font_override("font", GameTheme.font("mono"))
	title.add_theme_font_size_override("font_size", 12)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(title)
	var state := Label.new()
	state.name = "State"
	state.text = str(block["state"])
	state.add_theme_color_override("font_color", tone)
	state.add_theme_font_size_override("font_size", 12)
	column.add_child(state)
	return panel
