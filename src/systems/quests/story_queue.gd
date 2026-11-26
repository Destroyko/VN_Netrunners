class_name StoryQueue
extends RefCounted
## Очередь событий двигателя сюжета (docs/tech/story-engine.md): события ставятся в очередь и
## разбираются по одному до конца — обновление квеста никогда не прерывается другим обновлением.
## Так эффект, пославший событие (`move_to` → `location_entered`), не вкладывает квест сам в себя
## (ISS-010, ISS-011).
##
## «Удержание» (`hold` / `release`): пока квест меняется изнутри (старт, выбор, исход) или идёт
## разбор, новые события только встают в очередь; разбор — когда удержание снято. Вызовы можно
## вкладывать: очередь разбирается на внешнем `release`.
##
## После того как очередь опустела, цели «по состоянию» перепроверяются один раз (ISS-017): файл
## на месте, письмо прочитано, время пришло.
##
## Чистая логика: события сюда кладёт автозагрузка `StoryEngine`, состояние — в `GameState`.
## Очередь живёт в памяти: сейв посреди разбора невозможен (разбор синхронный).

## Сколько событий за один разбор — больше значит, что правила зовут друг друга по кругу.
const DEFAULT_MAX_STEPS: int = 200

static var _queue: Array[Dictionary] = []
static var _held: int = 0


## Событие: {"event": имя, ...аргументы}. Пусто ({}) — только перепроверка целей по состоянию.
static func post(event: Dictionary) -> void:
	_queue.append(event)
	if _held == 0:
		_drain()


static func hold() -> void:
	_held += 1


static func release() -> void:
	_held = maxi(0, _held - 1)
	if _held == 0 and not _queue.is_empty():
		_drain()


static func is_busy() -> bool:
	return _held > 0


## Для тестов: выбросить всё, что застряло.
static func reset() -> void:
	_queue.clear()
	_held = 0


static func _drain() -> void:
	_held += 1
	var steps: int = 0
	var limit: int = int((DataLoader.balance().get("story", {}) as Dictionary).get("max_steps", DEFAULT_MAX_STEPS))
	while true:
		while not _queue.is_empty():
			steps += 1
			if steps > limit:
				push_warning("StoryQueue: больше %d событий за разбор — правила зовут друг друга по кругу; остаток выброшен" % limit)
				SessionLog.write("story", "разбор прерван: больше %d событий" % limit)
				_queue.clear()
				break
			var event: Dictionary = _queue.pop_front()
			if not event.is_empty():
				SessionLog.write("story", "событие %s" % str(event.get("event", "")))
				Triggers.fire(event)
			Quests.on_event(event)
		# Очередь пуста — цели «по состоянию» один раз; они могли поставить новые события.
		Quests.on_event({})
		if _queue.is_empty():
			break
	_held -= 1
