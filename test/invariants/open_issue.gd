extends RefCounted
## Метка теста на открытую проблему из docs/issues.md. Тест описывает правильное поведение; пока
## проблема не исправлена, он помечается `pending` и не выполняется — набор остаётся зелёным.
##
## Прогнать такие тесты по-настоящему (увидеть, что они падают): переменная окружения
## `RUN_OPEN_ISSUES=1` перед запуском godot. Проблему исправили — убрать из теста две строки
## `if OpenIssue.skip(...): return`.


static func skip(test: GutTest, text: String) -> bool:
	if OS.get_environment("RUN_OPEN_ISSUES") == "1":
		return false
	test.pending(text)
	return true
