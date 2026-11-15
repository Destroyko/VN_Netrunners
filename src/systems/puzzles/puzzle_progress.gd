class_name PuzzleProgress
extends RefCounted
## Прогресс головоломок по сервисам: сколько слоёв вскрыто и сколько попыток уже было
## (docs/tech/puzzles-spec.md, «Частичный прогресс»).
##
## Главный риск частичного успеха: если прогресс копится бесплатно, игрок будет перезапускать
## головоломку, пока не выпадет лёгкая генерация. Поэтому:
##   - повторный запуск на том же сервисе оставляет слои и добавляет попытку;
##   - добровольный `dc` слои сохраняет: взлом можно растянуть на несколько дней;
##   - доведённый трейс обнуляет всё по узлу (`reset_node`): цель перенастроила защиту;
##   - два игровых дня без продвижения — слои тают сами (`puzzles.progress_reset_days`).
##
## Чистая логика над словарём: в игре это словарь GameState, чтобы после загрузки сейва мир
## помнил, что сервис наполовину вскрыт. Время — абсолютные игровые минуты, как в Network.

const FALLBACK_RESET_DAYS: int = 2
const MINUTES_PER_DAY: int = 1440

var _state: Dictionary
var _melt_minutes: int


func _init(state: Dictionary, balance: Dictionary = {}) -> void:
	_state = state
	var puzzles: Dictionary = balance.get("puzzles", {}) as Dictionary
	var clock: Dictionary = balance.get("clock", {}) as Dictionary
	var per_day: int = int(clock.get("minutes_per_day", MINUTES_PER_DAY))
	_melt_minutes = int(puzzles.get("progress_reset_days", FALLBACK_RESET_DAYS)) * per_day


static func for_game() -> PuzzleProgress:
	return PuzzleProgress.new(GameState.puzzle_state(), DataLoader.balance())


## Вскрытых слоёв у сервиса. Если два дня без продвижения — слои растаяли, и запись сброшена.
func layers(node_id: String, service_id: String, now: int) -> int:
	return int(_fresh(node_id, service_id, now).get("layers", 0))


## Сколько попыток уже сделано на этом сервисе (растущая цена провала считается по ним).
func attempts(node_id: String, service_id: String, now: int) -> int:
	return int(_fresh(node_id, service_id, now).get("attempts", 0))


## Попытка закончена: +1 к счётчику, `gained` новых слоёв к прогрессу. Продвижением считается
## только слой; провал время «таяния» не продлевает.
func record(node_id: String, service_id: String, now: int, gained: int) -> void:
	var entry: Dictionary = _fresh(node_id, service_id, now)
	if entry.is_empty():
		entry = {"layers": 0, "attempts": 0, "since": now}
	entry["attempts"] = int(entry["attempts"]) + 1
	if gained > 0:
		entry["layers"] = int(entry["layers"]) + gained
		entry["since"] = now
	_state[_key(node_id, service_id)] = entry


## Сервис вскрыт целиком: записи о нём больше не нужны.
func clear_service(node_id: String, service_id: String) -> void:
	_state.erase(_key(node_id, service_id))


## Трейс дошёл до конца: все частичные слои узла и счётчики попыток обнуляются.
func reset_node(node_id: String) -> void:
	var prefix: String = node_id + "|"
	for key: String in _state.keys():
		if key.begins_with(prefix):
			_state.erase(key)


## Сид головоломки: один и тот же для одной и той же попытки (чтобы после загрузки сейва
## игрок получил ту же головоломку), но разный между попытками и между «осторожностями» цели.
## Игровой сид входит в него, поэтому у разных прохождений головоломки разные.
static func seed_for(game_seed: int, node_id: String, service_id: String, alert: int, attempt: int) -> int:
	return ("%d|%s|%s|%d|%d" % [game_seed, node_id, service_id, alert, attempt]).hash()


# --- Внутреннее --------------------------------------------------------------

func _key(node_id: String, service_id: String) -> String:
	return "%s|%s" % [node_id, service_id]


## Запись о сервисе или пустой словарь; растаявшую запись удаляет.
func _fresh(node_id: String, service_id: String, now: int) -> Dictionary:
	var key: String = _key(node_id, service_id)
	if not _state.has(key):
		return {}
	var entry: Dictionary = _state[key] as Dictionary
	if now - int(entry.get("since", now)) >= _melt_minutes:
		_state.erase(key)
		return {}
	return entry
