class_name ShopApp
extends VBoxContainer
## Приложение «Магазин» — доставка еды (docs/gameplay/needs.md): каталог с «Заказать», заказы в
## пути, запас дома с «Съесть». Правил здесь нет: всё делает `Shop`.

var _items: VBoxContainer
var _orders: VBoxContainer
var _pantry: VBoxContainer


func _init() -> void:
	name = "ShopApp"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_caption("Доставка"))
	_items = _box("Items")
	add_child(_caption("В пути"))
	_orders = _box("Orders")
	add_child(_caption("Дома"))
	_pantry = _box("Pantry")


func _ready() -> void:
	EventBus.money_changed.connect(func(_m: int, _d: int) -> void: refresh())
	# «Через N мин» у заказов в пути тает вместе с часами.
	EventBus.time_advanced.connect(func(_m: int, _p: int) -> void: refresh())
	for sig: Signal in [EventBus.order_placed, EventBus.order_delivered, EventBus.food_consumed]:
		sig.connect(func(_id: String) -> void: refresh())
	refresh()


func refresh() -> void:
	_clear(_items)
	var catalog: Dictionary = Shop.catalog()
	for id: String in catalog.keys():
		var def: Dictionary = catalog[id]
		var price: int = int(def.get("price", 0))
		_items.add_child(_row("Item_" + id, "%s — %d ₽" % [Shop.title_of(id), price], "Заказать",
			not GameState.can_afford(price), func() -> void: Shop.order(id)))
	_clear(_orders)
	for o: Dictionary in Shop.orders():
		var left: int = maxi(int(o["arrive_at"]) - Clock.total_minutes(), 0)
		_orders.add_child(_text("%s — через %d мин" % [Shop.title_of(str(o["item"])), left]))
	if Shop.orders().is_empty():
		_orders.add_child(_text("Ничего"))
	_clear(_pantry)
	var pantry: Dictionary = Shop.pantry()
	for id: String in pantry.keys():
		_pantry.add_child(_row("Food_" + id, "%s × %d" % [Shop.title_of(id), int(pantry[id])], "Съесть",
			false, func() -> void: Shop.consume(id)))
	if pantry.is_empty():
		_pantry.add_child(_text("Пусто"))


func _row(row_name: String, caption: String, action: String, disabled: bool, on_press: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	var label := _text(caption)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var button := Button.new()
	button.name = "Action"
	button.text = action
	button.disabled = disabled
	button.pressed.connect(on_press)
	row.add_child(button)
	return row


func _box(box_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = box_name
	add_child(box)
	return box


func _clear(box: Container) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _caption(text: String) -> Label:
	var label := _text(text)
	label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	return label
