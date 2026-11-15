extends GutTest
## Общая заготовка для тестов терминала. Сам по себе не запускается: в имени нет `test_`.
## Терминал работает на настоящих данных из data/nodes: он связывает файловую систему, сеть,
## часы и шину событий, и опечатку в цепочке ловит только такой прогон.

var t: Terminal
var last: TermResult


func before_each() -> void:
	GameState.reset()
	# Полдень первого дня: офис (8–18) в сети, вечерний ПК мужа (18–23:30) — нет.
	Clock.set_time(1, 12 * 60)
	t = Terminal.new()
	watch_signals(EventBus)


## Выполнить строку и вернуть текст ответа. Полный результат остаётся в `last`.
func run(line: String) -> String:
	last = t.execute(line)
	return last.text()


func learn_programs() -> void:
	for id: String in Programs.ids():
		GameState.set_flag(Programs.flag_for(id))


func address_of(node_id: String) -> String:
	return str((DataLoader.nodes()[node_id] as Dictionary)["address"])


func service_ids(node_id: String) -> Array:
	var ids: Array = []
	for service: Variant in (DataLoader.nodes()[node_id] as Dictionary)["services"] as Array:
		ids.append(str((service as Dictionary)["id"]))
	return ids


## Заказ выдал адрес, а клиент дал логины на перечисленные сервисы.
func reveal(node_id: String, open: Array = []) -> void:
	Effects.apply({"reveal_node": {"node": node_id, "open": open}})


## Узнать узел, сразу вскрыть всё и подключиться: чтобы тест не повторял весь взлом.
func enter(node_id: String) -> String:
	reveal(node_id, service_ids(node_id))
	return run("connect " + address_of(node_id))


## Игрок прошёл через домашний роутер к учебному узлу — так, как задумано в игре.
func reach_training_pc() -> void:
	run("scan")
	run("connect 10.0.0.1")
	run("scan")
	run("dc")


func minute() -> int:
	return GameState.minute


func logbook(node_id: String) -> Logbook:
	return Logbook.for_node(node_id)
