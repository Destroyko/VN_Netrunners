class_name PasswordPuzzle
extends RefCounted
## «Пароль»: подбор слова программой `passhound` (docs/tech/puzzles-spec.md, раздел 1).
##
## Игрок вводит слова той же длины, что и загаданное; каждая буква получает метку: точно / есть,
## но не там / нет — как в Wordle (повторяющиеся буквы помечаются не больше, чем их в слове).
## Часть букв известна заранее и показана на своих местах. Слово всегда берётся из словаря
## через сид, зацепок-ребусов в файлах нет; сложность задают длина слова и число открытых букв.
##
## Чистая логика без сцен. Один сид — одна и та же головоломка (testing.md).
## Решаемость гарантирует солвер: `generate` отдаёт только то, что он решил за допустимое число
## попыток и в допустимом диапазоне кандидатов (конвейер отбора из testing.md).

const MARK_ABSENT: int = 0
const MARK_PRESENT: int = 1
const MARK_EXACT: int = 2

## Штраф за «редкость» слова в оценке: градация 0/1/2 умножается на него.
const RARITY_PENALTY: float = 0.2

var level: int = 2
var puzzle_seed: int = 0
var word: String = ""
var length: int = 0
## Известные буквы: позиция (с нуля) → буква.
var known: Dictionary = {}
var max_attempts: int = 6
## Сделанные попытки: [{"word": ..., "marks": [..]}].
var history: Array[Dictionary] = []
var solved: bool = false
## Метрики конвейера отбора (см. _measure).
var metrics: Dictionary = {}

## Метрики зависят только от шаблона открытых букв, а не от самого слова: шаблон одинаков у
## многих сидов, и пересчитывать солвер на каждый нет смысла.
static var _pattern_cache: Dictionary = {}


# --- Генерация ---------------------------------------------------------------

## Головоломка по уровню и сиду. `extra_known` — сколько букв сверх базовых открыл `deepscan`.
## `params` — параметры вместо тех, что в balance.json (так их задают тесты и отчёт).
static func generate(
	game_level: int, seed_value: int, extra_known: int = 0, params: Dictionary = {}
) -> PasswordPuzzle:
	var config: Dictionary = params if not params.is_empty() else PuzzleLevels.password(game_level)
	var tries: int = maxi(1, int(config.get("max_tries", 40)))
	var best: PasswordPuzzle = null
	var best_gap: float = INF

	for attempt: int in tries:
		var sub_seed: int = ("%d:%d" % [seed_value, attempt]).hash()
		var puzzle: PasswordPuzzle = _roll(game_level, seed_value, sub_seed, extra_known, config)
		var gap: float = puzzle._measure(config, extra_known)
		if gap == 0.0:
			puzzle.metrics["accepted"] = true
			puzzle.metrics["tries"] = attempt + 1
			return puzzle
		if gap < best_gap:
			best = puzzle
			best_gap = gap

	# Ничего подходящего за отведённые попытки: отдаём наименее плохое и честно помечаем.
	best.metrics["accepted"] = false
	best.metrics["tries"] = tries
	return best


static func _roll(
	game_level: int, seed_value: int, sub_seed: int, extra_known: int, config: Dictionary
) -> PasswordPuzzle:
	var rng: RandomNumberGenerator = Rng.fixed(sub_seed)
	var puzzle := PasswordPuzzle.new()
	puzzle.level = game_level
	puzzle.puzzle_seed = seed_value
	puzzle.length = int(config["length"])
	puzzle.max_attempts = int(config["attempts"])

	var pool: PackedStringArray = Words.answers(puzzle.length, config["tiers"] as Array)
	puzzle.word = pool[rng.randi_range(0, pool.size() - 1)]

	# Открытых букв не больше, чем длина минус минимум неизвестных: иначе слово выдаётся само.
	var min_unknown: int = int(config.get("min_unknown", 3))
	var count: int = clampi(int(config["known"]) + extra_known, 0, maxi(puzzle.length - min_unknown, 0))
	var positions: Array = range(puzzle.length)
	for index: int in range(positions.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var swap: Variant = positions[index]
		positions[index] = positions[other]
		positions[other] = swap
	for index: int in count:
		var position: int = int(positions[index])
		puzzle.known[position] = puzzle.word[position]
	return puzzle


## Считает метрики и возвращает «расстояние до допустимого»: 0 — подходит.
func _measure(config: Dictionary, extra_known: int) -> float:
	var key: String = "%d:%s" % [length, pattern()]
	if not _pattern_cache.has(key):
		_pattern_cache[key] = PasswordSolver.analyze(candidates())
	var stats: Dictionary = _pattern_cache[key] as Dictionary

	var count: int = int(stats["count"])
	var rarity: int = Words.tier_index(word)
	var worst: int = int(stats["worst"])
	metrics = {
		"candidates_after_hints": count,
		"solver_attempts_avg": float(stats["avg"]),
		"solver_attempts_worst": worst,
		"word_rarity": rarity,
		"first_guess": str(stats["first"]),
		"score": float(stats["avg"]) + 0.5 * float(worst - max_attempts) + RARITY_PENALTY * float(maxi(rarity, 0)),
	}

	var gap: float = 0.0
	if worst > max_attempts:
		gap += 1000.0 + float(worst - max_attempts)
	var range_bounds: Array = config.get("candidates", [0, 1000000]) as Array
	# Открытые deepscan буквы легче нормы по определению: нижнюю границу тогда не проверяем.
	if extra_known == 0 and count < int(range_bounds[0]):
		gap += float(int(range_bounds[0]) - count)
	if count > int(range_bounds[1]):
		gap += float(count - int(range_bounds[1]))
	return gap


# --- Состояние ---------------------------------------------------------------

## Шаблон открытых букв: «..а.о» — по нему считаются кандидаты.
func pattern() -> String:
	var result: String = ""
	for position: int in length:
		result += str(known[position]) if known.has(position) else "."
	return result


## Слова словаря, подходящие под открытые буквы.
func candidates() -> PackedStringArray:
	var result: PackedStringArray = []
	for candidate: String in Words.all(length):
		var fits: bool = true
		for position: int in known.keys():
			if candidate[int(position)] != str(known[position]):
				fits = false
				break
		if fits:
			result.append(candidate)
	return result


func attempts_left() -> int:
	return max_attempts - history.size()


func is_over() -> bool:
	return solved or attempts_left() <= 0


## Игрок назвал слово. Возвращает:
##   valid — слово принято (иначе попытка не потрачена), reason — почему нет (length / unknown / over);
##   marks — метки по буквам; solved — угадано; failed — попытки кончились.
## `strict = false` — слово не из словаря тоже считается попыткой (интерфейс с ячейками: опечаток
## там нет, а подбирать буквы без цены нельзя); `in_dictionary` в ответе говорит, было ли оно словом.
func guess(text: String, strict: bool = true) -> Dictionary:
	var result: Dictionary = {
		"valid": false, "reason": "", "marks": [], "solved": false, "failed": false,
		"attempts_left": attempts_left(), "in_dictionary": true,
	}
	if is_over():
		result["reason"] = "over"
		return result

	var entered: String = text.strip_edges().to_lower().replace("ё", "е")
	if entered.length() != length:
		result["reason"] = "length"
		return result
	# Опечатка не тратит попытку: слово должно быть из словаря.
	var known_word: bool = Words.has(entered)
	if not known_word and strict:
		result["reason"] = "unknown"
		return result
	result["in_dictionary"] = known_word

	var marks: Array[int] = marks_for(word, entered)
	history.append({"word": entered, "marks": marks})
	solved = entered == word
	result["valid"] = true
	result["marks"] = marks
	result["solved"] = solved
	result["failed"] = not solved and attempts_left() <= 0
	result["attempts_left"] = attempts_left()
	return result


# --- Метки -------------------------------------------------------------------

## Метки как в Wordle. Сначала «точно», затем «есть, но не там» — только пока такие буквы
## остаются в загаданном слове: повторяющиеся буквы не размечаются чаще, чем встречаются.
static func marks_for(answer: String, attempt: String) -> Array[int]:
	var marks: Array[int] = []
	var left: Dictionary = {}
	for position: int in answer.length():
		marks.append(MARK_ABSENT)
		if attempt[position] == answer[position]:
			marks[position] = MARK_EXACT
		else:
			left[answer[position]] = int(left.get(answer[position], 0)) + 1

	for position: int in answer.length():
		if marks[position] == MARK_EXACT:
			continue
		var letter: String = attempt[position]
		if int(left.get(letter, 0)) > 0:
			marks[position] = MARK_PRESENT
			left[letter] = int(left[letter]) - 1
	return marks


## Метки одним числом (по три на букву): чтобы группировать слова по ответу в солвере.
static func feedback_code(answer: String, attempt: String) -> int:
	var code: int = 0
	var factor: int = 1
	for mark: int in marks_for(answer, attempt):
		code += mark * factor
		factor *= 3
	return code


static func clear_cache() -> void:
	_pattern_cache.clear()
