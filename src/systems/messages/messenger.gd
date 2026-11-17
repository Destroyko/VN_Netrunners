class_name Messenger
extends RefCounted
## Сообщения (docs/gameplay/messages.md): чаты с персонажами в телефоне и на ПК. Чистые
## правила без сцен; приложение «Сообщения» только показывает и передаёт «прочитал» и «ответил».
##
## Сообщение приходит эффектом `send_text` (квест, триггер, диалог, консоль) из
## `data/messages/msg_*.json`. Ответ — выбор из готовых вариантов (`replies`) со своими
## условиями и эффектами: что он меняет, решают данные, мессенджер сюжета не знает.
##
## Переписка — в переменной `messages.log` (в сейве): входящие {kind: "in", uid, id, from, day,
## minute, read, reply} и ответы героя {kind: "out", to, text, day, minute}, по порядку.

const VAR_LOG: String = "messages.log"
const IN: String = "in"
const OUT: String = "out"


static func definition(id: String) -> Dictionary:
	return DataLoader.messages().get(id, {}) as Dictionary


static func exists(id: String) -> bool:
	return not definition(id).is_empty()


## Доставить сообщение. Одно и то же может прийти не раз, поэтому у каждого свой `uid`.
static func deliver(id: String) -> bool:
	if not exists(id):
		push_error("Messenger: нет сообщения в data/messages: %s" % id)
		return false
	var log: Array = _log()
	var entry: Dictionary = {
		"kind": IN,
		"uid": "%s#%d" % [id, log.size() + 1],
		"id": id,
		"from": str(definition(id).get("from", "")),
		"day": GameState.day,
		"minute": GameState.minute,
		"read": false,
		"reply": "",
	}
	log.append(entry)
	GameState.set_var(VAR_LOG, log)
	EventBus.message_received.emit(str(entry["uid"]), id)
	return true


## Собеседники, с кем есть переписка: последний написавший — первым.
static func chats() -> PackedStringArray:
	var order: PackedStringArray = []
	var log: Array = _log()
	for i: int in range(log.size() - 1, -1, -1):
		var contact: String = contact_of(log[i] as Dictionary)
		if not order.has(contact):
			order.append(contact)
	return order


## Переписка с одним собеседником, по порядку.
static func thread(contact: String) -> Array:
	return _log().filter(func(e: Dictionary) -> bool: return contact_of(e) == contact)


static func contact_of(entry: Dictionary) -> String:
	return str(entry.get("from", "")) if str(entry.get("kind", "")) == IN else str(entry.get("to", ""))


## Текст записи для показа: у входящих — из данных (с подстановкой имён), у ответов — свой.
static func text_of(entry: Dictionary) -> String:
	if str(entry.get("kind", "")) == OUT:
		return str(entry.get("text", ""))
	return DialogueText.with_names(str(definition(str(entry.get("id", ""))).get("text", "")))


## Непрочитанные: всего ("") или от одного собеседника.
static func unread_count(contact: String = "") -> int:
	return _log().filter(func(e: Dictionary) -> bool:
		return str(e.get("kind", "")) == IN and not bool(e.get("read", false)) \
			and (contact.is_empty() or contact_of(e) == contact)).size()


## Открыл чат — всё в нём прочитано.
static func mark_read(contact: String) -> void:
	var changed: bool = false
	for e: Dictionary in _log():
		if str(e.get("kind", "")) == IN and contact_of(e) == contact and not bool(e.get("read", false)):
			e["read"] = true
			changed = true
	if changed:
		EventBus.messages_read.emit(contact)


static func entry(uid: String) -> Dictionary:
	for e: Dictionary in _log():
		if str(e.get("uid", "")) == uid:
			return e
	return {}


## Ответы, которые можно выбрать сейчас (свои `requires` у каждого). Отвечают один раз.
static func available_replies(uid: String) -> Array:
	var e: Dictionary = entry(uid)
	if e.is_empty() or not str(e.get("reply", "")).is_empty():
		return []
	var replies: Array = definition(str(e["id"])).get("replies", []) as Array
	return replies.filter(func(r: Dictionary) -> bool: return Conditions.check_all(r.get("requires", []) as Array))


## Сообщение в чате, на которое сейчас можно ответить ("" — нет): последнее входящее с ответами.
static func awaiting_reply(contact: String) -> String:
	var items: Array = thread(contact)
	for i: int in range(items.size() - 1, -1, -1):
		var e: Dictionary = items[i] as Dictionary
		if str(e.get("kind", "")) == IN and not available_replies(str(e["uid"])).is_empty():
			return str(e["uid"])
	return ""


## Ответить: текст героя ложится в переписку, эффекты применяются, шина узнаёт.
static func reply(uid: String, reply_id: String) -> bool:
	for r: Dictionary in available_replies(uid):
		if str(r.get("id", "")) != reply_id:
			continue
		var e: Dictionary = entry(uid)
		e["reply"] = reply_id
		e["read"] = true
		var log: Array = _log()
		log.append({
			"kind": OUT,
			"to": str(e["from"]),
			"text": DialogueText.with_names(str(r.get("text", ""))),
			"day": GameState.day,
			"minute": GameState.minute,
		})
		GameState.set_var(VAR_LOG, log)
		Effects.apply_all(r.get("effects", []) as Array)
		EventBus.message_replied.emit(uid, str(e["id"]), reply_id)
		return true
	return false


## Записи меняются на месте (прочитано, ответ), поэтому журнал сразу кладём в состояние.
static func _log() -> Array:
	if not (GameState.get_var_or(VAR_LOG, null) is Array):
		GameState.set_var(VAR_LOG, [])
	return GameState.get_var_or(VAR_LOG, []) as Array
