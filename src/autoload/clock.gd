extends Node
## Игровое время: минуты, дни, время суток.
## Clock только двигает время и сообщает об этом. Что происходит в новый день,
## решают NewsManager и TriggerManager, слушая day_started (docs/tech/architecture.md).
##
## Само время хранится в GameState (иначе сейв его забудет), здесь только правила.

## ВНИМАНИЕ: длина дня и границы времени суток — пока заглушки.
## В docs/gameplay/core-loop.md это открытый вопрос, числа подбираем на плейтесте.
const DEFAULT_MINUTES_PER_DAY: int = 1440

var minutes_per_day: int = DEFAULT_MINUTES_PER_DAY
## Сколько реальных секунд длится игровая минута (balance.json, clock.real_seconds_per_minute).
var real_seconds_per_minute: float = 4.0
## Идёт ли время само. Включает начало игры (главное меню → «Новая игра»), выключает главное
## меню. Тесты и отладочные запуски сцен его не включают: там время двигают только действия.
var running: bool = false

## Причины паузы: время стоит, пока есть хоть одна. Решено 15.11.2026 — только диалоги и сюжетные
## сцены (они могут сами перематывать время). Счётчик, а не флаг: пауз бывает несколько сразу.
var _pauses: Dictionary = {}
## Номер последнего сдвига часов: слушатели сверяют его, чтобы один сдвиг не обработать дважды.
var advance_count: int = 0
var _carry: float = 0.0
## Границы времени суток в минутах от начала дня: ночь → утро → день → вечер.
var _bounds: Dictionary = {"morning": 360, "day": 660, "evening": 1080, "night": 1320}
## Во сколько раз быстрее идут минуты программы (balance.json, clock.program_speedup).
var program_speedup: float = 3.0
## Короче этого — минуты тратятся сразу: секунда полоски ради `cat` только раздражает.
var program_min_minutes: int = 2
## Сколько минут программы ещё пройти ускоренно и сколько было всего (для полоски).
var _fast_left: int = 0
var _fast_total: int = 0
## Минута отрезка идёт из `tick`: она уже списана с `_fast_left`, `advance` её второй раз не считает.
var _in_fast_tick: bool = false

## Ускоренный отрезок программы закончился: терминал снова принимает ввод.
signal fast_forward_finished
## Ускоренный отрезок брошен раньше конца (Ctrl+C, обрыв, выключение ПК): программа не успела.
signal fast_forward_dropped


func _ready() -> void:
	reload_config()


## Числа берём из data/balance.json, раздел "clock". Нет файла — работаем на заглушках.
func reload_config() -> void:
	var cfg: Dictionary = DataLoader.balance().get("clock", {}) as Dictionary
	configure(cfg)


func configure(cfg: Dictionary) -> void:
	minutes_per_day = int(cfg.get("minutes_per_day", DEFAULT_MINUTES_PER_DAY))
	start_date = str(cfg.get("start_date", DEFAULT_START_DATE))
	real_seconds_per_minute = maxf(0.1, float(cfg.get("real_seconds_per_minute", 4.0)))
	program_speedup = maxf(1.0, float(cfg.get("program_speedup", 3.0)))
	program_min_minutes = int(cfg.get("program_min_minutes", 2))
	var bounds: Dictionary = cfg.get("time_of_day_bounds", {}) as Dictionary
	for key: String in _bounds.keys():
		if bounds.has(key):
			_bounds[key] = int(bounds[key])


# --- Ход в реальном времени ---------------------------------------------------

func _process(delta: float) -> void:
	tick(delta)


## Прошло `seconds` реального времени. Отдельный метод, чтобы тест мог «прокрутить» секунды
## без ожидания кадров. Каждая накопленная игровая минута — обычный `advance(1)`: все, кто
## слушает `time_advanced` (трейс, панель задач), не отличают ход времени от действий.
func tick(seconds: float) -> void:
	if not running or is_paused():
		return
	# Идёт программа: её минуты бегут в `program_speedup` раз быстрее, обычный ход ждёт.
	if _fast_left > 0:
		_carry += seconds * program_speedup
		while _carry >= real_seconds_per_minute and _fast_left > 0:
			_carry -= real_seconds_per_minute
			_fast_left -= 1
			_in_fast_tick = true
			advance(1)
			_in_fast_tick = false
		if _fast_left == 0:
			_fast_total = 0
			_carry = 0.0
			fast_forward_finished.emit()
		return
	_carry += seconds
	while _carry >= real_seconds_per_minute:
		_carry -= real_seconds_per_minute
		advance(1)


## Потратить минуты программы или передачи (docs/gameplay/time.md, «Что именно ускоряется»):
## в игре они проходят ускоренно, пока в терминале бежит полоска; короткие (меньше
## `program_min_minutes`) и всё вне игры (тесты, часы стоят) — сразу, как `advance`.
## `bar` — показать полоску и для короткого отрезка (слой `probe` — минута).
func fast_forward(minutes: int, bar: bool = false) -> void:
	if minutes <= 0:
		return
	if not will_fast_forward(minutes, bar):
		advance(minutes)
		return
	_fast_left += minutes
	_fast_total += minutes


## Пойдут ли эти минуты ускоренно под полоску (иначе — сразу).
func will_fast_forward(minutes: int, bar: bool = false) -> bool:
	return running and (bar or minutes >= program_min_minutes)


## Бросить оставшиеся минуты программы (Ctrl+C, обрыв соединения): прошедшие остаются.
func cancel_fast_forward() -> void:
	var was: bool = _fast_left > 0
	_fast_left = 0
	_fast_total = 0
	_carry = 0.0
	if was:
		fast_forward_dropped.emit()


## Сколько реальных секунд уже набежало к следующей игровой минуте (для обратного отсчёта трейса).
## Под полоской программы счёт идёт в ускоренных секундах.
func seconds_into_minute() -> float:
	return _carry


func is_fast_forwarding() -> bool:
	return _fast_left > 0


## Сколько уже прошло от ускоренного отрезка, 0..1 (для полоски).
func fast_progress() -> float:
	if _fast_total <= 0:
		return 1.0
	return 1.0 - float(_fast_left) / float(_fast_total)


func start() -> void:
	running = true
	_carry = 0.0


func stop() -> void:
	# Остановили посреди программы (выход в меню): её терминал узнаёт, что она не дошла.
	cancel_fast_forward()
	running = false
	_carry = 0.0
	_fast_left = 0
	_fast_total = 0


func pause(reason: String) -> void:
	_pauses[reason] = true


func resume(reason: String) -> void:
	_pauses.erase(reason)


## Снять все паузы — после загрузки сейва: занавес или диалог, державшие паузу, остались в
## прошлой сцене.
func reset_pauses() -> void:
	_pauses.clear()


## Стоит ли время по этой причине (например, открыто меню игры — телефон прячется).
func is_paused_by(reason: String) -> bool:
	return _pauses.has(reason)


func is_paused() -> bool:
	return not _pauses.is_empty()


# --- Движение времени --------------------------------------------------------

## Потратить minutes игровых минут. Переход через полночь начинает новый день.
func advance(minutes: int) -> void:
	if minutes <= 0:
		return
	advance_count += 1
	GameState.minute += minutes
	# Цикл, а не if: действие может занять больше суток (брутфорс на несколько дней).
	while GameState.minute >= minutes_per_day:
		GameState.minute -= minutes_per_day
		GameState.day += 1
		EventBus.day_started.emit(GameState.day)
	EventBus.time_advanced.emit(GameState.minute, minutes)
	# Время прошло другим путём (сон, вырубание, еда), пока шла программа: эти минуты — её минуты
	# (ISS-002). Трейс и расписание узла видели каждую из них раньше: оборвали — итога не будет.
	if _fast_left > 0 and not _in_fast_tick:
		_fast_left = maxi(0, _fast_left - minutes)
		if _fast_left == 0:
			_fast_total = 0
			_carry = 0.0
			fast_forward_finished.emit()


## Перевод времени напрямую — для отладочной консоли и загрузки сценариев.
## Событий не шлёт: это не «прошло время», а «состояние стало таким».
func set_time(day: int, minute: int) -> void:
	GameState.day = maxi(1, day)
	GameState.minute = clampi(minute, 0, minutes_per_day - 1)


## Сколько минут прошло с начала игры — для отсчётов длиннее суток (тихие сутки заметности).
func total_minutes() -> int:
	return (GameState.day - 1) * minutes_per_day + GameState.minute


## Сколько минут до начала следующего дня.
func minutes_until_next_day() -> int:
	return minutes_per_day - GameState.minute


# --- Чтение времени ----------------------------------------------------------

func hour() -> int:
	return GameState.minute / 60


func minute_of_hour() -> int:
	return GameState.minute % 60


## Время суток: "night" / "morning" / "day" / "evening".
## Нужно системам, которые открывают и закрывают места и заказы (docs/gameplay/systems.md).
func time_of_day() -> String:
	var m: int = GameState.minute
	if m < int(_bounds["morning"]):
		return "night"
	if m < int(_bounds["day"]):
		return "morning"
	if m < int(_bounds["evening"]):
		return "day"
	if m < int(_bounds["night"]):
		return "evening"
	return "night"


# --- Дата (docs/gameplay/time.md, «Дата и календарь») ---------------------------
# Источник правды — счётчик дней; дата выводится: start_date + (day − 1). Сейв не меняется.

const WEEKDAYS: PackedStringArray = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
const MONTHS: PackedStringArray = [
	"января", "февраля", "марта", "апреля", "мая", "июня",
	"июля", "августа", "сентября", "октября", "ноября", "декабря",
]
const DEFAULT_START_DATE: String = "2026-04-02"

var start_date: String = DEFAULT_START_DATE


## Дата игрового дня `day`: {year, month, day, weekday} (weekday: 0 — воскресенье, как в Godot).
func date_of(day: int) -> Dictionary:
	var start: int = Time.get_unix_time_from_datetime_string(start_date + "T12:00:00")
	return Time.get_datetime_dict_from_unix_time(start + (day - 1) * 86400)


## «чт, 2 апреля» — так дата видна игроку везде; год в интерфейсе не мелькает.
func format_date(day: int = GameState.day) -> String:
	var d: Dictionary = date_of(day)
	return "%s, %d %s" % [WEEKDAYS[int(d["weekday"])], int(d["day"]), MONTHS[int(d["month"]) - 1]]


## «чт, 2 апреля 14:30» — для панели задач и комнаты.
func format_now() -> String:
	return "%s %02d:%02d" % [format_date(), hour(), minute_of_hour()]


## Для логов: «День 3, 14:30».
func format_time() -> String:
	return "День %d, %02d:%02d" % [GameState.day, hour(), minute_of_hour()]
