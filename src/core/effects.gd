class_name Effects
extends RefCounted
## Один язык эффектов для квестов, триггеров, диалогов и ивентов
## (словарь типов — docs/tech/quest-format.md).
##
## Эффект — словарь, где ключ это тип: {"money": 500}, {"set_flag": "story.x"}.
## Эффекты меняют только GameState; системы узнают об изменениях из EventBus.
## Подстановку параметров шаблонов ({reward} у radiant-квестов) делает вызывающий,
## сюда приходят уже готовые значения.

## Реализованные типы.
const KNOWN_TYPES: PackedStringArray = [
	"money",
	"heat",
	"set_flag",
	"clear_flag",
	"set_var",
	"rep",
	"reveal_node",
	"give_item",
	"take_item",
	"energy",
	"set_energy",
	"satiety",
	"set_satiety",
	"send_message",
	"unlock_quest",
	"quest_choice",
	"schedule_news",
]

## Типы из документации, которым нужны системы следующих этапов.
## Валидатор их пропускает, применение пока только пишет предупреждение.
const DEFERRED_TYPES: PackedStringArray = [
	"add_file",       # filesystem, M1
	"add_note",       # блокнот заметок, docs/gameplay/notebook.md
]

## Очередь новостей-последствий: [{id, day}] — публикует NewsManager (шаг 9 M2).
const VAR_NEWS_QUEUE: String = "news.queue"

## Репутация хранится как переменная состояния: rep.<кто>.
const VAR_REP_PREFIX: String = "rep."


## Применить один эффект. Возвращает true, если эффект действительно применён.
static func apply(effect: Dictionary) -> bool:
	var applied: bool = false
	for type: String in effect.keys():
		applied = _apply_one(type, effect[type]) or applied
	return applied


static func apply_all(effects: Array) -> void:
	for effect: Variant in effects:
		if effect is Dictionary:
			apply(effect as Dictionary)


## Для валидатора: тип либо работает, либо запланирован — но не опечатка.
static func is_known(type: String) -> bool:
	return KNOWN_TYPES.has(type) or DEFERRED_TYPES.has(type)


static func is_implemented(type: String) -> bool:
	return KNOWN_TYPES.has(type)


## Узел, который открывает эффект reveal_node: строка или поле node у объекта.
static func reveal_target(value: Variant) -> String:
	if value is Dictionary:
		return str((value as Dictionary).get("node", ""))
	return str(value)


## Сервисы, открытые «логинами» из заказа. Пустой список, если логинов нет.
static func reveal_open(value: Variant) -> Array:
	if value is Dictionary:
		return (value as Dictionary).get("open", []) as Array
	return []


## Все узлы, которые открывают эффекты reveal_node где-то в данных (квесты, триггеры,
## on_hacked узлов). Нужно валидатору: такой узел не должен находиться через scan.
static func collect_revealed(data: Variant, found: Dictionary) -> void:
	if data is Dictionary:
		for key: Variant in (data as Dictionary).keys():
			if str(key) == "reveal_node":
				found[reveal_target((data as Dictionary)[key])] = true
			collect_revealed((data as Dictionary)[key], found)
	elif data is Array:
		for item: Variant in data as Array:
			collect_revealed(item, found)


static func _apply_one(type: String, value: Variant) -> bool:
	match type:
		"money":
			# Через экономику — чтобы перевод остался строкой в истории банка.
			Economy.apply_delta(int(value), "Перевод")
			return true
		"heat":
			GameState.add_heat(int(value))
			if int(value) > 0:
				Heat.restart_quiet()
			return true
		"set_flag":
			GameState.set_flag(str(value), true)
			return true
		"clear_flag":
			GameState.set_flag(str(value), false)
			return true
		"set_var":
			# Формат: {"set_var": ["ключ", значение]}
			var pair: Array = value as Array
			if pair == null or pair.size() != 2:
				push_error("Effects: set_var ожидает [ключ, значение], получено: %s" % [value])
				return false
			GameState.set_var(str(pair[0]), pair[1])
			return true
		"rep":
			# Формат: {"rep": ["персонаж_или_фракция", изменение]}
			var pair_rep: Array = value as Array
			if pair_rep == null or pair_rep.size() != 2:
				push_error("Effects: rep ожидает [кто, изменение], получено: %s" % [value])
				return false
			var key: String = VAR_REP_PREFIX + str(pair_rep[0])
			GameState.set_var(key, int(GameState.get_var_or(key, 0)) + int(pair_rep[1]))
			return true
		# Потребности по ходу сцены (gameplay/needs.md): {"energy": -30} — прибавить или убавить,
		# {"set_energy": 100} — задать; так же сытость. Границы держит `Needs`.
		"energy":
			Needs.set_energy(Needs.energy() + float(value))
			EventBus.needs_changed.emit()
			return true
		"set_energy":
			Needs.set_energy(float(value))
			EventBus.needs_changed.emit()
			return true
		"satiety":
			Needs.set_satiety(Needs.satiety() + float(value))
			EventBus.needs_changed.emit()
			return true
		"set_satiety":
			Needs.set_satiety(float(value))
			EventBus.needs_changed.emit()
			return true
		"unlock_quest":
			# Формат: {"unlock_quest": "side_x"} — начать квест (если выполнены его requires).
			return Quests.start(str(value))
		"quest_choice":
			# Формат: {"quest_choice": ["side_x", "choice_id"]} — выбор на текущем этапе квеста;
			# обычно стоит в ответе на письмо.
			var pick: Array = value as Array
			if pick == null or pick.size() != 2:
				push_error("Effects: quest_choice ожидает [квест, выбор], получено: %s" % [value])
				return false
			return Quests.choose(str(pick[0]), str(pick[1]))
		"schedule_news":
			# Формат: {"schedule_news": {"id": "news_x", "delay_days": 1}} или просто "news_x" (на
			# завтра). Новость встаёт в очередь; публикует её NewsManager утром нужного дня (шаг 9).
			var ref: Dictionary = value as Dictionary if value is Dictionary else {"id": str(value)}
			var queue: Array = (GameState.get_var_or(VAR_NEWS_QUEUE, []) as Array).duplicate()
			queue.append({"id": str(ref.get("id", "")), "day": GameState.day + int(ref.get("delay_days", 1))})
			GameState.set_var(VAR_NEWS_QUEUE, queue)
			return true
		"send_message":
			# Формат: {"send_message": "mail_x"} — письмо из data/mail. Мессенджер — позже (M3).
			return Mailbox.deliver(str(value))
		"give_item":
			return Inventory.give(str(value))
		"take_item":
			return Inventory.take(str(value))
		"reveal_node":
			# Формат: {"reveal_node": "node_x"} или {"reveal_node": {"node": "node_x", "open": ["svc_login"], "admin": true}}.
			# Заказ даёт адрес и, если клиент знает логины, открывает часть сервисов заранее;
			# "admin": логин администратора — на узле сразу с правами.
			var target: String = reveal_target(value)
			var net: Network = Network.for_game()
			var now: int = net.abs_minute(GameState.day, GameState.minute)
			var admin: bool = value is Dictionary and bool((value as Dictionary).get("admin", false))
			if not net.reveal(target, reveal_open(value), now, admin):
				push_error("Effects: reveal_node: нет такого узла: '%s'" % target)
				return false
			return true
		_:
			if DEFERRED_TYPES.has(type):
				push_warning("Effects: эффект '%s' ещё не реализован (нужна система следующего этапа)" % type)
				return false
			push_error("Effects: неизвестный тип эффекта '%s'" % type)
			return false
