class_name News
extends RefCounted
## Новости (docs/gameplay/news.md): лента на ПК. Каждый день — одна фоновая новость из пула
## (случайно, через Rng), плюс запланированные последствия (эффект `schedule_news`, очередь
## `news.queue`) публикуются утром нужного дня. Реакция мира приходит с задержкой — «а, это же я».
##
## Чистые правила без сцен. День подаёт автозагрузка `NewsManager`. Лента — переменная состояния
## `news.published` (сейв её помнит): [{id, day, read}], новые в конце. Пул и тексты — `data/news/`.

const VAR_PUBLISHED: String = "news.published"
const VAR_QUEUE: String = "news.queue"  # совпадает с Effects.VAR_NEWS_QUEUE
const VAR_LAST_BG: String = "news.last_background"


static func definition(id: String) -> Dictionary:
	return DataLoader.news().get(id, {}) as Dictionary


static func published() -> Array:
	return GameState.get_var_or(VAR_PUBLISHED, []) as Array


## Лента: новые сверху, [{id, day, read}].
static func feed() -> Array:
	var list: Array = published().duplicate()
	list.reverse()
	return list


static func unread_count() -> int:
	return published().filter(func(e: Dictionary) -> bool: return not bool(e["read"])).size()


## Опубликовать новость в ленту. Нет такой в данных — не публикуется.
static func publish(id: String, day: int) -> bool:
	if definition(id).is_empty():
		push_error("News: нет новости в data/news: %s" % id)
		return false
	var list: Array = published().duplicate()
	list.append({"id": id, "day": day, "read": false})
	GameState.set_var(VAR_PUBLISHED, list)
	EventBus.news_published.emit(id)
	return true


static func mark_read(id: String) -> void:
	var list: Array = published().duplicate()
	var changed: bool = false
	for e: Dictionary in list:
		if str(e["id"]) == id and not bool(e["read"]):
			e["read"] = true
			changed = true
	if changed:
		GameState.set_var(VAR_PUBLISHED, list)
		EventBus.news_read.emit(id)


## Запланированные последствия (`schedule_news`), чьё время пришло: опубликовать и убрать из очереди.
static func publish_due(day: int) -> void:
	var queue: Array = GameState.get_var_or(VAR_QUEUE, []) as Array
	if queue.is_empty():
		return
	var left: Array = []
	for item: Dictionary in queue:
		if int(item["day"]) <= day:
			publish(str(item["id"]), day)
		else:
			left.append(item)
	GameState.set_var(VAR_QUEUE, left)


## Одна фоновая новость из пула (поле `background: true`), случайно, не та же, что вчера.
static func publish_background(day: int) -> void:
	var pool: Array = []
	for id: String in DataLoader.news().keys():
		if bool((DataLoader.news()[id] as Dictionary).get("background", false)):
			pool.append(id)
	if pool.is_empty():
		return
	var last: String = str(GameState.get_var_or(VAR_LAST_BG, ""))
	if pool.size() > 1 and pool.has(last):
		pool.erase(last)
	var id: String = str(Rng.pick(pool))
	GameState.set_var(VAR_LAST_BG, id)
	publish(id, day)
