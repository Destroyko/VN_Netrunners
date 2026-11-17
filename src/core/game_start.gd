class_name GameStart
extends RefCounted
## Начало новой игры — одно место для всех кнопок «Новая игра» (главное меню, экран сложности).
## Раньше старт был размазан: стартовые деньги и `game_started` вызывались только на скрытом
## экране сложности, а настоящая кнопка в главном меню их пропускала (найдено 17.11.2026).


static func begin(difficulty: GameState.Difficulty = GameState.Difficulty.NORMAL) -> void:
	GameState.reset(difficulty)
	Rng.randomize_seed()
	Economy.start_new_game()
	Clock.start()
	# На этом событии висят стартовые триггеры (первая подработка, дневник). Отдельно от
	# day_started, который Clock шлёт только при переходе через полночь.
	EventBus.game_started.emit()
