class_name PuzzleOutcome
extends RefCounted
## Итог головоломки взломщика (docs/gameplay/hacking.md, docs/tech/puzzles-spec.md): слои в
## прогресс, сервис вскрыт целиком (трейс отступает, пароль показан, вход — если вскрыто всё
## нужное), частичный успех или провал с ростом цены за повтор.
##
## Вынесено из `Terminal` (технический разбор 16.11.2026): терминал разбирает ввод и держит
## состояние сеанса, а это — правило исхода взлома.

var _t: Terminal


func _init(terminal: Terminal) -> void:
	_t = terminal


## Сеанс оборвался, пока головоломка открыта (`dc`, перезагрузка, трейс, конец прайм-тайма):
## проваленная попытка (решено 25.11.2026, ISS-009). Собранное в этом окне не засчитано;
## счёт попыток растёт — следующий запуск даёт новую партию и стоит как после провала.
func abandon(data: Dictionary) -> void:
	var node: String = str(data["node"])
	var service: String = str(data["service"])
	var now_minute: int = _t.now()
	var progress: PuzzleProgress = PuzzleProgress.for_game()
	var attempt: int = progress.attempts(node, service, now_minute) + 1
	progress.record(node, service, now_minute, 0)
	EventBus.puzzle_failed.emit(str(data["kind"]), int(data["level"]), node, service, attempt)


## `data` — то, что терминал запомнил при запуске взломщика (узел, сервис, вид, ступень, слоёв
## всего, пароль); `gained` — сколько слоёв вскрыто за эту попытку.
func apply(data: Dictionary, gained: int, result: TermResult) -> void:
	var node: String = str(data["node"])
	var service: String = str(data["service"])
	var kind: String = str(data["kind"])
	var level: int = int(data["level"])
	var layers_total: int = int(data.get("layers_total", 1))
	var password: String = str(data.get("password", ""))
	var now_minute: int = _t.now()
	var progress: PuzzleProgress = PuzzleProgress.for_game()
	var layers_gained: int = gained
	var attempt: int = progress.attempts(node, service, now_minute) + 1
	progress.record(node, service, now_minute, layers_gained)
	var layers_now: int = progress.layers(node, service, now_minute)

	var port: int = _t.net.port_of(node, service)
	if layers_now >= layers_total:
		var done: NetResult = _t.session.crack(service, now_minute)
		progress.clear_service(node, service)
		EventBus.puzzle_solved.emit(kind, level, node, service)
		result.add_as("порт %d: открыт" % port, "ok")
		# Вскрытая часть защиты больше не поднимает шум: трейс отступает (разработчик, 16.11.2026).
		var eased: int = _t.session.ease_trace(int((DataLoader.balance().get("nodes", {}) as Dictionary).get("trace_ease_percent", 25)))
		if eased > 0:
			result.add("трейс: +%d мин (осталось %d)" % [eased, _t.session.trace_left()])
		# Взломщик достал пароль: игрок видит его и вводит сам (hacking.md, «Пароль после перехвата»).
		if not password.is_empty():
			_t.net.access.remember_password(node, service, password)
			result.add("")
			result.add("        пароль: %s" % password.to_upper())
			result.add("")
		# Вскрыто всё нужное — вход происходит сам: игрок входит без лишнего connect.
		if done.cracked >= done.required and not _t.session.has_connection():
			_t.connect_target(result)
	elif layers_gained > 0:
		# Частичный успех: слои остались, добить можно позже (даже после `dc`).
		EventBus.puzzle_solved.emit(kind, level, node, service)
		result.add("порт %d: вскрыто слоёв %d из %d" % [port, layers_now, layers_total])
	else:
		EventBus.puzzle_failed.emit(kind, level, node, service, attempt)
		result.add("ошибка: доступ к порту %d не получен" % port)
