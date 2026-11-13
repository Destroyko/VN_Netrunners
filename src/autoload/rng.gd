extends Node
## Вся случайность в игре — только отсюда. Прямые randi() запрещены (CLAUDE.md):
## иначе баг нельзя воспроизвести, а головоломку нельзя проверить тестом.
##
## Потоки (stream): у каждой подсистемы свой генератор, выведенный из общего сида.
## Так расход случайности в одном месте не сдвигает последовательность в другом —
## ивенты не меняются от того, что игрок сгенерировал лишнюю головоломку.

var _seed: int = 0
var _main: RandomNumberGenerator = RandomNumberGenerator.new()
var _streams: Dictionary = {}


func _ready() -> void:
	# По умолчанию — случайный сид; тесты и отладка задают свой через set_seed().
	randomize_seed()


## Общий сид игры. Пишется в сейв, чтобы мир после загрузки вёл себя так же.
func set_seed(value: int) -> void:
	_seed = value
	_main.seed = value
	_streams.clear()


func get_seed() -> int:
	return _seed


func randomize_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	set_seed(int(rng.randi()))


# --- Общий поток -------------------------------------------------------------

func randi_range(from: int, to: int) -> int:
	return _main.randi_range(from, to)


func randf() -> float:
	return _main.randf()


func randf_range(from: float, to: float) -> float:
	return _main.randf_range(from, to)


## Случайный элемент массива. Пустой массив → null, чтобы не падать на данных.
func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[_main.randi_range(0, items.size() - 1)]


## Перемешивание на месте, своим генератором (Array.shuffle() берёт глобальный).
func shuffle(items: Array) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j: int = _main.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp


# --- Именованные потоки ------------------------------------------------------

## Постоянный поток подсистемы: Rng.stream("events"), Rng.stream("news").
## Один и тот же общий сид → одна и та же последовательность в каждом потоке.
func stream(name: String) -> RandomNumberGenerator:
	if _streams.has(name):
		return _streams[name] as RandomNumberGenerator
	var rng := RandomNumberGenerator.new()
	rng.seed = _derive_seed(name)
	_streams[name] = rng
	return rng


## Независимый генератор для одного конкретного объекта: generate(type, difficulty, seed).
## Не зависит от общего сида — головоломка по сиду всегда одна и та же (docs/tech/testing.md).
func fixed(value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	return rng


func _derive_seed(name: String) -> int:
	return hash(str(_seed, ":", name))
