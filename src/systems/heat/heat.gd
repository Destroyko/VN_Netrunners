class_name Heat
extends RefCounted
## Заметность: сколько прибавить, когда спадает, на каком она этапе
## (docs/gameplay/heat.md). Чистые правила без сцен и без подписок на события:
## слушает шину HeatManager, а считает и меняет `GameState.heat` этот класс.
##
## Источники растут только за воротами `gate.pressure` (docs/tech/gates.md): пока они закрыты,
## взломы ничего не стоят. Спад от сна работает всегда.
## Все числа — в `data/balance.json`, раздел `heat`.

const FALLBACK_STAGE_SIZE: int = 20
const FALLBACK_DECAY: int = 5
const FALLBACK_FAILED: int = 5
const FALLBACK_RETRY_STEP: int = 2
const FALLBACK_TRACE: int = 20
## Делений в полоске панели задач: одно деление — десять единиц.
const BAR_CELLS: int = 10


static func is_active() -> bool:
	return Programs.trace_enabled()


# --- Что сколько стоит --------------------------------------------------------

## Провал головоломки: растёт с номером попытки на том же сервисе (5, 7, 9…).
static func puzzle_failed_cost(attempt: int) -> int:
	return _num("gain_puzzle_failed", FALLBACK_FAILED) \
		+ maxi(attempt - 1, 0) * _num("gain_puzzle_retry_step", FALLBACK_RETRY_STEP)


## Трейс дошёл до конца: самая дорогая ошибка.
static func trace_finished_cost() -> int:
	return _num("gain_trace_finished", FALLBACK_TRACE)


## Следы на узле к моменту отключения: сумма весов оставшихся категорий.
static func traces_cost(node_id: String) -> int:
	return Logbook.for_node(node_id).heat_weight()


# --- Рост и спад --------------------------------------------------------------

## Прибавить заметность за промах. Возвращает, сколько реально добавилось (за закрытыми
## воротами и при нулевой цене — 0).
static func gain(amount: int) -> int:
	if amount <= 0 or not is_active():
		return 0
	var before: int = GameState.heat
	GameState.add_heat(amount)
	return GameState.heat - before


## Спад за выспанные ночи (−5 за ночь, линейно; heat.md, открытый вопрос 2).
## Возвращает, на сколько упала заметность.
static func rest(nights: int) -> int:
	if nights <= 0:
		return 0
	var before: int = GameState.heat
	GameState.add_heat(-nights * _num("decay_per_night", FALLBACK_DECAY))
	return before - GameState.heat


# --- Как это видно -------------------------------------------------------------

## Этап 1–5: «чисто», «замечен», «под вниманием», «опасно», «на грани».
static func stage_of(heat: int) -> int:
	var size: int = maxi(_num("stage_size", FALLBACK_STAGE_SIZE), 1)
	return clampi(heat / size, 0, 4) + 1


static func stage() -> int:
	return stage_of(GameState.heat)


## Заполненные деления полоски (0–10). Точного числа игрок не знает.
static func bar_cells(heat: int) -> int:
	return clampi(heat / 10, 0, BAR_CELLS)


static func _num(key: String, fallback: int) -> int:
	var section: Dictionary = DataLoader.balance().get("heat", {}) as Dictionary
	return int(section.get(key, fallback))
