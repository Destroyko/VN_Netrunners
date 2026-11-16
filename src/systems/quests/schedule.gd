class_name Schedule
extends RefCounted
## Отложенные эффекты: «через N дней в ЧЧ:ММ сделай вот это» (эффект `schedule`, docs/tech/
## quest-format.md). Так приходит утреннее письмо с заказом, а позже — звонки и новости.
##
## Чистые правила. Ход часов передаёт сюда `TriggerManager`. Очередь — переменная состояния
## (сейв её помнит): [{at: минута игры, effects}].

const VAR_QUEUE: String = "schedule.queue"


## Поставить в очередь. `delay_days` — через сколько суток (0 — сегодня), `at` — «09:00»; без
## `at` — ровно через `delay_days` суток от сейчас. Время уже прошло — сработает на ближайшей минуте.
static func add(spec: Dictionary) -> bool:
	var effects: Array = spec.get("effects", []) as Array
	if effects.is_empty():
		return false
	var days: int = int(spec.get("delay_days", 0))
	var at_total: int
	if spec.has("at"):
		var minute: int = Rest.parse_clock(str(spec["at"]))
		if minute < 0:
			push_error("Schedule: время — ЧЧ:ММ, получено: %s" % spec["at"])
			return false
		at_total = (GameState.day - 1 + days) * Clock.minutes_per_day + minute
	else:
		at_total = Clock.total_minutes() + days * Clock.minutes_per_day
	var queue: Array = (GameState.get_var_or(VAR_QUEUE, []) as Array).duplicate()
	queue.append({"at": at_total, "effects": effects})
	GameState.set_var(VAR_QUEUE, queue)
	return true


## Прошло время: применить всё, чьё время пришло (по порядку постановки).
static func on_time_passed() -> void:
	var queue: Array = GameState.get_var_or(VAR_QUEUE, []) as Array
	if queue.is_empty():
		return
	var now: int = Clock.total_minutes()
	var due: Array = []
	var left: Array = []
	for item: Dictionary in queue:
		(due if int(item["at"]) <= now else left).append(item)
	if due.is_empty():
		return
	# Сначала убрать из очереди, потом применять: эффект может поставить в очередь новое.
	GameState.set_var(VAR_QUEUE, left)
	for item: Dictionary in due:
		Effects.apply_all(item["effects"] as Array)


static func pending() -> Array:
	return GameState.get_var_or(VAR_QUEUE, []) as Array
