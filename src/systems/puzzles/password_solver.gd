class_name PasswordSolver
extends RefCounted
## Солвер «пароля» (docs/tech/puzzles-spec.md, «Метрики солвера»): жадный по информации.
## На каждом шаге называет то из оставшихся слов, которое сильнее всего дробит остальные
## (максимум энтропии ответов), а затем играет против каждого возможного загаданного слова.
##
## Зачем он нужен: головоломка попадает к игроку, только если солвер решает её за
## допустимое число попыток (`solver_attempts_worst <= A`). Это и есть гарантия решаемости.
##
## Играет «строгим» режимом — называет только слова, совместимые со всем, что уже узнал.
## Так работает и игрок, а перебор остаётся квадратичным по числу кандидатов, а не кубическим.

## Если кандидатов больше, на каждом шаге пробуем только эту долю вариантов: иначе на уровне
## «нетраннер» (всё слово неизвестно) выбор первого слова занимал бы заметное время.
const GUESS_SAMPLE: int = 80


## Результат: {"avg": среднее число попыток, "worst": худший случай, "first": лучшее первое слово,
## "count": сколько кандидатов}.
static func analyze(candidates: PackedStringArray) -> Dictionary:
	if candidates.is_empty():
		return {"avg": 0.0, "worst": 0, "first": "", "count": 0}
	var sorted: PackedStringArray = candidates.duplicate()
	sorted.sort()
	var outcome: Array = _solve(sorted)
	return {
		"avg": float(outcome[0]) / float(sorted.size()),
		"worst": int(outcome[1]),
		"first": str(outcome[2]),
		"count": sorted.size(),
	}


## [сумма попыток по всем загаданным словам набора, худший случай, первое слово].
static func _solve(words: PackedStringArray) -> Array:
	if words.size() == 1:
		return [1, 1, words[0]]

	var guess: String = _best_guess(words)
	var groups: Dictionary = {}
	for word: String in words:
		var code: int = PasswordPuzzle.feedback_code(word, guess)
		# Упакованный массив из словаря приходит копией: дописывать надо и класть обратно.
		var members: PackedStringArray = groups.get(code, PackedStringArray()) as PackedStringArray
		members.append(word)
		groups[code] = members

	var total: int = 0
	var worst: int = 1
	for code: int in groups.keys():
		var group: PackedStringArray = groups[code] as PackedStringArray
		# Группа из одного слова, равного догадке, — это попадание с первой попытки.
		if group.size() == 1 and group[0] == guess:
			total += 1
			continue
		var sub: Array = _solve(group)
		total += group.size() + int(sub[0])
		worst = maxi(worst, 1 + int(sub[1]))
	return [total, worst, guess]


## Слово из набора с самым неравномерным ответом: чем больше разных ответов и чем они ровнее,
## тем меньше слов остаётся после хода.
static func _best_guess(words: PackedStringArray) -> String:
	var step: int = maxi(1, ceili(float(words.size()) / float(GUESS_SAMPLE)))
	var best: String = words[0]
	var best_score: float = -1.0
	var index: int = 0
	while index < words.size():
		var guess: String = words[index]
		var counts: Dictionary = {}
		for word: String in words:
			var code: int = PasswordPuzzle.feedback_code(word, guess)
			counts[code] = int(counts.get(code, 0)) + 1
		var score: float = _entropy(counts, words.size())
		if score > best_score:
			best_score = score
			best = guess
		index += step
	return best


static func _entropy(counts: Dictionary, total: int) -> float:
	var sum: float = 0.0
	for code: int in counts.keys():
		var p: float = float(counts[code]) / float(total)
		sum -= p * log(p)
	return sum
