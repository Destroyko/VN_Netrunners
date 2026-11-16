class_name BankApp
extends VBoxContainer
## Приложение «Банк» (docs/gameplay/economy.md, «Приложение банка»): баланс, счета к оплате со
## сроком и пеней, история операций. Правил здесь нет: «Оплатить» — это `Economy.pay`.

var _balance: Label
var _bills: VBoxContainer
var _history: ItemList


func _init() -> void:
	name = "BankApp"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_balance = Label.new()
	_balance.name = "Balance"
	add_child(_balance)
	add_child(_caption("Счета"))
	_bills = VBoxContainer.new()
	_bills.name = "Bills"
	add_child(_bills)
	add_child(_caption("История"))
	_history = ItemList.new()
	_history.name = "History"
	_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_history)


func _ready() -> void:
	EventBus.money_changed.connect(func(_m: int, _d: int) -> void: refresh())
	for sig: Signal in [EventBus.bill_issued, EventBus.bill_overdue, EventBus.bill_paid]:
		sig.connect(func(_id: String) -> void: refresh())
	EventBus.day_started.connect(func(_day: int) -> void: refresh())
	refresh()


func refresh() -> void:
	_balance.text = "Баланс: %d ₽" % GameState.money
	for child: Node in _bills.get_children():
		_bills.remove_child(child)
		child.queue_free()
	var open: Array = Economy.unpaid()
	if open.is_empty():
		var none := Label.new()
		none.text = "Неоплаченных счетов нет"
		_bills.add_child(none)
	for b: Dictionary in open:
		_bills.add_child(_bill_row(b))
	_history.clear()
	var list: Array = Economy.history()
	for i: int in range(list.size() - 1, -1, -1):
		var h: Dictionary = list[i]
		_history.add_item("%s %02d:%02d   %+d ₽   %s" % [
			Clock.format_date(int(h["day"])), int(h["minute"]) / 60, int(h["minute"]) % 60,
			int(h["amount"]), str(h["label"])])


func _bill_row(b: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Bill_" + str(b["id"])
	var text := Label.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var line: String = "%s — %d ₽, до %s" % [str(b["title"]), Economy.total_of(b), Clock.format_date(int(b["due_day"]))]
	if Economy.is_overdue(b):
		line += " — просрочено, пеня %d ₽" % int(b["penalty"])
	text.text = line
	row.add_child(text)
	var pay := Button.new()
	pay.name = "Pay"
	pay.text = "Оплатить"
	pay.disabled = not GameState.can_afford(Economy.total_of(b))
	pay.pressed.connect(func() -> void: Economy.pay(str(b["id"])))
	row.add_child(pay)
	return row


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	return label
