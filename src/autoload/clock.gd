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


func _ready() -> void:
	reload_config()


## Числа берём из data/balance.json, раздел "clock". Нет файла — работаем на заглушках.
func reload_config() -> void:
	var cfg: Dictionary = DataLoader.balance().get("clock", {}) as Dictionary
	configure(cfg)


func configure(cfg: Dictionary) -> void:
	minutes_per_day = int(cfg.get("minutes_per_day", DEFAULT_MINUTES_PER_DAY))
	real_seconds_per_minute = maxf(0.1, float(cfg.get("real_seconds_per_minute", 4.0)))
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
	_carry += seconds
	while _carry >= real_seconds_per_minute:
		_carry -= real_seconds_per_minute
		advance(1)


func start() -> void:
	running = true
	_carry = 0.0


func stop() -> void:
	running = false
	_carry = 0.0


func pause(reason: String) -> void:
	_pauses[reason] = true


func resume(reason: String) -> void:
	_pauses.erase(reason)


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


## Перевод времени напрямую — для отладочной консоли и загрузки сценариев.
## Событий не шлёт: это не «прошло время», а «состояние стало таким».
func set_time(day: int, minute: int) -> void:
	GameState.day = maxi(1, day)
	GameState.minute = clampi(minute, 0, minutes_per_day - 1)


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


## Для интерфейса и логов: «День 3, 14:30».
func format_time() -> String:
	return "День %d, %02d:%02d" % [GameState.day, hour(), minute_of_hour()]
