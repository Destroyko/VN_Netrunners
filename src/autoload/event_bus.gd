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
## Доставка еды (gameplay/needs.md): заказано, приехало (лежит в запасе), съедено.
signal order_placed(item_id: String)
## Почта: письмо пришло, прочитано, на него ответили (квесты слушают ответ), вложение сохранено.
signal mail_received(uid: String, mail_id: String)
signal mail_read(uid: String, mail_id: String)
signal mail_replied(uid: String, mail_id: String, reply_id: String)
## Письмо удалено игроком (у отправленного `mail_id` пустой).
signal mail_deleted(uid: String, mail_id: String)
## Мессенджер (Messenger): пришло сообщение, чат прочитан, герой ответил.
signal message_received(uid: String, message_id: String)
signal messages_read(contact: String)
signal message_replied(uid: String, message_id: String, reply_id: String)
## Показано всплывающее уведомление (`kind`: "message"…) — звук уведомления (шаг 17 M3).
signal notification_shown(kind: String)
signal attachment_saved(uid: String, path: String)
## Герой отправил письмо со своего ПК: кому и `file_id` вложений (у файлов без id их нет).
## По нему закрывается цель `deliver`.
signal mail_sent(to: String, file_ids: PackedStringArray)
signal order_delivered(item_id: String)
signal food_consumed(item_id: String)
## Содержимое контейнера изменилось (Inventory): окно инвентаря перерисовывается.
signal inventory_changed(container: String)
signal heat_changed(heat: int, delta: int)

# --- Время (шлёт Clock) ------------------------------------------------------

## Прошло игровое время. minutes — сколько потратило действие.
signal time_advanced(minute: int, minutes_passed: int)
## Часы сдвинулись — сеанс взлома тикнул (HackManager). `events` — что случилось: трейс перевалил
## за половину, дошёл до конца, узел ушёл из сети. Пусто — просто прошло время под трейсом.
signal session_advanced(events: Array)
## Начался новый день: NewsManager публикует новости, TriggerManager проверяет триггеры.
signal day_started(day: int)
## Опубликована новость (NewsManager): лента и иконка обновляются (gameplay/news.md).
signal news_published(news_id: String)
## Новость прочитана: иконка обновляется.
signal news_read(news_id: String)
## Фоновый подбор пароля к архиву закончился: архив расшифрован (gameplay/hacking-loop.md).
signal decrypt_done(path: String)
## Началась новая игра (не загрузка): на нём висит стартовый триггер первой подработки. Шлётся
## один раз из «Новой игры», отдельно от day_started — чтобы не срабатывать при любой смене дня.
signal game_started
## Диалоги (DialogueManager): начался, показан новый узел, закончился (квесты ждут «поговорить»).
signal dialogue_started(dialogue_id: String)
## Герой перешёл в локацию (Locations.enter): окно сцены перестраивается, цель visit_location.
signal location_entered(location_id: String)
signal dialogue_node_changed(dialogue_id: String, node_id: String)
signal dialogue_ended(dialogue_id: String)
## Игра сохранена в слот / загружена из слота (SaveSystem).
signal game_saved(slot: String)
signal game_loaded(slot: String)

## Разбудить героя: звонок, стук в дверь, конец фоновой задачи. Вне сна ничего не делает.
signal wake_requested(reason: String)
## Сон или ожидание закончились: `mode` — "sleep" / "wait", сколько минут прошло, что разбудило
## ("" — будильник).
signal rested(mode: String, minutes: int, interrupted: String)
## Герой что-то почувствовал: "energy_low" — скоро пора отдыхать, "hungry" — пора поесть
## (gameplay/needs.md). Интерфейс показывает мысль героя.
signal need_warned(kind: String)
## Герой думает вслух (эффект `hero_thought` из данных): намёк, а не подсказка интерфейса.
signal hero_thought(text: String)
## Шкалы изменились не от хода времени (поел, консоль) — виджету перечитать.
signal needs_changed
## Энергия кончилась: героя выкидывает из-за ПК, начинается сон до полного восстановления.
signal passed_out
## Проснулся после вырубания: сколько минут проспал.
signal woke_after_pass_out(minutes: int)

## Флешка починила свой ПК: вернула файлы из /sys и (или) поставила обычную ОС.
signal system_restored(paths: PackedStringArray, os_changed: bool)
## Свой ПК выключили (false) или он загрузился (true): PcPower. Перезагрузка — оба подряд.
signal pc_power_changed(on: bool)
## Начались загрузка своего ПК (или установка системы с флешки), минуты идут под полоской:
## экран загрузки показывает её и в конце зовёт `PcPower.finish_power_on`.
signal pc_boot_started(install: bool, minutes: int)

# --- Квесты (шлёт Quests через QuestManager, M2) -----------------------------

signal quest_stage_changed(quest_id: String, stage_id: String)
signal quest_completed(quest_id: String, outcome: String)
## Игрок выбрал задачу для трекера (Planner.track).
signal task_tracked(quest_id: String)
## Цель этапа выполнена: `key` — "o<номер>" (обязательная) или "p<номер>" (необязательная).
signal quest_objective_done(quest_id: String, key: String, optional: bool)

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
## Файл изменён командой `edit` (цель квеста «исправить файл» перепроверяется).
signal file_edited(node_id: String, path: String)

# --- Головоломки (M1) --------------------------------------------------------

## `difficulty` — реально сыгранный уровень (2–4). `attempt` — номер неудачной попытки на этом
## сервисе: по нему система заметности считает растущую цену провала (heat.md).
signal puzzle_solved(kind: String, difficulty: int, node_id: String, service_id: String)
signal puzzle_failed(kind: String, difficulty: int, node_id: String, service_id: String, attempt: int)
