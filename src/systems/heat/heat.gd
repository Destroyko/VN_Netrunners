class_name Heat
extends RefCounted
## Заметность: сколько прибавить, когда спадает, на каком она этапе
## (docs/gameplay/heat.md). Чистые правила без сцен и без подписок на события:
## слушает шину HeatManager, а считает и меняет `GameState.heat` этот класс.
##
## Источники растут только за воротами `gate.pressure` (docs/tech/gates.md): пока они закрыты,
## взломы ничего не стоят. Спад работает всегда: за каждые полные сутки без нового начисления
## (решено 16.11.2026, разработчик) — чтобы сбросить заметность, надо реально залечь на дно.
## Все числа — в `data/balance.json`, раздел `heat`.

const FALLBACK_STAGE_SIZE: int = 20
const FALLBACK_DECAY: int = 5
const FALLBACK_FAILED: int = 5
const FALLBACK_RETRY_STEP: int = 2
const FALLBACK_TRACE: int = 20
const FALLBACK_QUIET_MINUTES: int = 1440
## С какой минуты игры (`Clock.total_minutes`) считаются тихие сутки: последнее начисление или
## последний спад.
const VAR_QUIET_SINCE: String = "heat.quiet_since"
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


## Игрок отключился: начислить заметность за следы этого визита (ещё не оплаченные) и пометить
## их оплаченными. Возвращает, сколько добавилось.
static func pay_traces(node_id: String) -> int:
	var book: Logbook = Logbook.for_node(node_id)
	var added: int = gain(book.unpaid_weight())
	book.mark_paid()
	return added


# --- Рост и спад --------------------------------------------------------------

## Прибавить заметность за промах. Возвращает, сколько реально добавилось (за закрытыми
## воротами и при нулевой цене — 0).
static func gain(amount: int) -> int:
	if amount <= 0 or not is_active():
		return 0
	var before: int = GameState.heat
	GameState.add_heat(amount)
	restart_quiet()
	return GameState.heat - before


## Любое начисление — даже 1 за аккуратный взлом, эффект квеста или консоль — заново запускает
## отсчёт тихих суток.
static func restart_quiet() -> void:
	GameState.set_var(VAR_QUIET_SINCE, Clock.total_minutes())


## Прошло время: за каждые полные тихие сутки (`quiet_minutes`) с последнего начисления или
## спада — спад на `decay_per_quiet_day`, линейно, до нуля. Возвращает, на сколько упала.
static func on_time_passed() -> int:
	var period: int = maxi(_num("quiet_minutes", FALLBACK_QUIET_MINUTES), 1)
	var since: int = int(GameState.get_var_or(VAR_QUIET_SINCE, 0))
	var days: int = (Clock.total_minutes() - since) / period
	if days <= 0:
		return 0
	GameState.set_var(VAR_QUIET_SINCE, since + days * period)
	return decay(days)


## Спад за `days` тихих суток. Возвращает, на сколько упала заметность.
static func decay(days: int) -> int:
	if days <= 0:
		return 0
	var before: int = GameState.heat
	GameState.add_heat(-days * _num("decay_per_quiet_day", FALLBACK_DECAY))
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
