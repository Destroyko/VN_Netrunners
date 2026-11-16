extends Node
## Шина событий: все системы общаются через неё, а не напрямую друг с другом.
## Здесь нет состояния и нет логики — только объявления сигналов.
## Имена сигналов — в прошедшем времени: событие уже произошло.
## Новые сигналы добавляем по мере появления систем (M1: терминал, сеть, головоломки).

# --- Состояние игры (шлёт GameState) ----------------------------------------

signal flag_changed(flag: String, value: bool)
signal var_changed(key: String, value: Variant)
signal money_changed(money: int, delta: int)
## Счета банка (gameplay/economy.md): выставлен, просрочен (напоминание — один раз), оплачен.
signal bill_issued(bill_id: String)
signal bill_overdue(bill_id: String)
signal bill_paid(bill_id: String)
signal heat_changed(heat: int, delta: int)

# --- Время (шлёт Clock) ------------------------------------------------------

## Прошло игровое время. minutes — сколько потратило действие.
signal time_advanced(minute: int, minutes_passed: int)
## Часы сдвинулись — сеанс взлома тикнул (HackManager). `events` — что случилось: трейс перевалил
## за половину, дошёл до конца, узел ушёл из сети. Пусто — просто прошло время под трейсом.
signal session_advanced(events: Array)
## Начался новый день: NewsManager публикует новости, TriggerManager проверяет триггеры.
signal day_started(day: int)

## Разбудить героя: звонок, стук в дверь, конец фоновой задачи. Вне сна ничего не делает.
signal wake_requested(reason: String)
## Сон или ожидание закончились: `mode` — "sleep" / "wait", сколько минут прошло, что разбудило
## ("" — будильник).
signal rested(mode: String, minutes: int, interrupted: String)
## Герой что-то почувствовал: "energy_low" — скоро пора отдыхать, "hungry" — пора поесть
## (gameplay/needs.md). Интерфейс показывает мысль героя.
signal need_warned(kind: String)
## Шкалы изменились не от хода времени (поел, консоль) — виджету перечитать.
signal needs_changed
## Энергия кончилась: героя выкидывает из-за ПК, начинается сон до полного восстановления.
signal passed_out
## Проснулся после вырубания: сколько минут проспал.
signal woke_after_pass_out(minutes: int)

## Флешка починила свой ПК: вернула файлы из /sys и (или) поставила обычную ОС.
signal system_restored(paths: PackedStringArray, os_changed: bool)

# --- Квесты (шлёт QuestManager, M2) -----------------------------------------

signal quest_stage_changed(quest_id: String, stage_id: String)
signal quest_completed(quest_id: String, outcome: String)

# --- Взлом (M1) --------------------------------------------------------------

signal hack_completed(node_id: String)
signal node_connected(node_id: String)
signal node_disconnected(node_id: String)
signal trace_started(node_id: String)
signal trace_finished(node_id: String)

# --- Файлы (M1) --------------------------------------------------------------

signal file_read(node_id: String, path: String)
signal file_copied(node_id: String, path: String)
signal file_deleted(node_id: String, path: String)

# --- Головоломки (M1) --------------------------------------------------------

## `difficulty` — реально сыгранный уровень (2–4). `attempt` — номер неудачной попытки на этом
## сервисе: по нему система заметности считает растущую цену провала (heat.md).
signal puzzle_solved(kind: String, difficulty: int, node_id: String, service_id: String)
signal puzzle_failed(kind: String, difficulty: int, node_id: String, service_id: String, attempt: int)
