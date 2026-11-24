class_name Mailbox
extends RefCounted
## Почта (docs/tech/quest-format.md, «Каналы получения квестов»): письма из `data/mail/`,
## входящие и прочитанные, вложения на свой ПК, ответ кнопкой (выбор квеста).
##
## Чистые правила без сцен. Письмо приходит эффектом `send_message` (квест, триггер, консоль);
## приложение «Почта» только показывает и передаёт «прочитал», «сохранить», «ответить».
## Что меняет ответ — решают данные письма (`effects` у ответа) и квесты, слушающие
## `mail_replied`; сама почта сюжета не знает.
##
## Ящик — в `GameState.mail_state()`: входящие [{uid, id, day, minute, read, reply}] (новые в
## конце), отправленные [{to, subject, body, files, file_ids, day, minute}] и адресная книга.
##
## Отправить письмо можно только на известный адрес (адресная книга): так игрок не отправит
## файл случайно не туда (разработчик, 16.11.2026). Адреса узнаются из писем — отправитель и
## поле `contacts` («вот почта босса») — и эффектом `add_contact`.

## Куда кладутся сохранённые вложения на своём ПК.
const ATTACHMENTS_DIR: String = "/home/mail"
## Ключи данных квеста, которыми квест ссылается на письмо: отправка (`send_message`) и цель
## «прочитать» (`read_mail`, поле `mail`).
const QUEST_MAIL_KEYS: PackedStringArray = ["send_message", "mail"]


static func definition(id: String) -> Dictionary:
	return DataLoader.mail().get(id, {}) as Dictionary


static func exists(id: String) -> bool:
	return not definition(id).is_empty()


## Доставить письмо. Одно и то же письмо может прийти не раз (шаблоны radiant), поэтому у
## каждого доставленного свой `uid`. Нет такого письма в данных — false.
static func deliver(id: String) -> bool:
	if not exists(id):
		push_error("Mailbox: нет письма в data/mail: %s" % id)
		return false
	var list: Array = _list()
	var entry: Dictionary = {
		"uid": "%s#%d" % [id, list.size() + 1],
		"id": id,
		"day": GameState.day,
		"minute": GameState.minute,
		"read": false,
		"reply": "",
	}
	list.append(entry)
	var def: Dictionary = definition(id)
	learn_contact(str(def.get("from", "")))
	for address: Variant in def.get("contacts", []) as Array:
		learn_contact(str(address))
	EventBus.mail_received.emit(str(entry["uid"]), id)
	return true


# --- Адресная книга и исходящие ---------------------------------------------------

## Запомнить адрес. Не адрес (нет «@») — не запоминается: «Домовладелец» в поле «от» — это имя.
static func learn_contact(address: String) -> void:
	if not address.contains("@"):
		return
	var book: Array = _state_list("contacts")
	if not book.has(address):
		book.append(address)


static func contacts() -> Array:
	return _state_list("contacts").duplicate()


## Забыть адрес: человек больше не нужен на этом этапе игры (эффект `forget_contact`), чтобы
## список «Кому» не разрастался ненужными адресами.
static func forget_contact(address: String) -> void:
	_state_list("contacts").erase(address)


## Куда и с какой темой отвечать на письмо: {to, subject}. Нет адреса у отправителя — пусто.
## Тема — поле письма `reply_subject` («Готово»), иначе «Re: <тема>».
static func reply_draft(uid: String) -> Dictionary:
	var e: Dictionary = entry(uid)
	if e.is_empty():
		return {}
	var def: Dictionary = definition(str(e["id"]))
	var to: String = str(def.get("from", ""))
	if not to.contains("@"):
		return {}
	var subject: String = str(def.get("reply_subject", "Re: " + str(def.get("subject", ""))))
	return {"to": to, "subject": subject}


## Отправить письмо со своего ПК. `files` — пути вложений на своём ПК (можно несколько или ни
## одного). Неизвестный адрес или хоть одного файла нет — false, ничего не ушло.
static func send(to: String, subject: String, body: String, files: PackedStringArray = []) -> bool:
	if not contacts().has(to):
		return false
	var home: Filesystem = Filesystem.for_node(Network.HOME_ID)
	var file_ids: PackedStringArray = []
	for file: String in files:
		if not home.has_file(file):
			return false
		var file_id: String = str(home.file_data(file).get("file_id", ""))
		if not file_id.is_empty():
			file_ids.append(file_id)
	_state_list("sent").append({
		"to": to, "subject": subject, "body": body, "files": Array(files), "file_ids": Array(file_ids),
		"day": GameState.day, "minute": GameState.minute,
	})
	EventBus.mail_sent.emit(to, file_ids)
	return true


static func sent() -> Array:
	return _state_list("sent").duplicate()


## Входящие, новые сверху.
static func inbox() -> Array:
	var list: Array = _list().duplicate()
	list.reverse()
	return list


static func entry(uid: String) -> Dictionary:
	for e: Dictionary in _list():
		if str(e["uid"]) == uid:
			return e
	return {}


static func unread_count() -> int:
	return _list().filter(func(e: Dictionary) -> bool: return not bool(e["read"])).size()


static func mark_read(uid: String) -> void:
	var e: Dictionary = entry(uid)
	if e.is_empty() or bool(e["read"]):
		return
	e["read"] = true
	EventBus.mail_read.emit(uid, str(e["id"]))


## Ответы, которые можно выбрать сейчас: у каждого свои `requires` (знает ли герой нужное).
static func available_replies(uid: String) -> Array:
	var e: Dictionary = entry(uid)
	if e.is_empty() or not str(e["reply"]).is_empty():
		return []
	var replies: Array = definition(str(e["id"])).get("replies", []) as Array
	return replies.filter(func(r: Dictionary) -> bool: return Conditions.check_all(r.get("requires", []) as Array))


## Ответить. Отвечают один раз; ответ применяет свои эффекты и сообщает шине (квест узнает).
static func reply(uid: String, reply_id: String) -> bool:
	for r: Dictionary in available_replies(uid):
		if str(r.get("id", "")) == reply_id:
			var e: Dictionary = entry(uid)
			e["reply"] = reply_id
			e["read"] = true
			Effects.apply_all(r.get("effects", []) as Array)
			EventBus.mail_replied.emit(uid, str(e["id"]), reply_id)
			return true
	return false


# --- Удаление ------------------------------------------------------------------------

## Квесты, которые ссылаются на письмо `mail_id` в своих данных (отправляют его или ждут, что его
## прочтут), и квесты, которые начинает ответ на него (`unlock_quest` в `replies`).
static func linked_quests(mail_id: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var quests: Dictionary = DataLoader.quests()
	for quest_id: String in quests.keys():
		if _mentions(quests[quest_id], mail_id):
			result.append(quest_id)
	for reply: Variant in definition(mail_id).get("replies", []) as Array:
		for effect: Variant in (reply as Dictionary).get("effects", []) as Array:
			var quest_id: String = str((effect as Dictionary).get("unlock_quest", ""))
			if not quest_id.is_empty() and not result.has(quest_id):
				result.append(quest_id)
	return result


## Почему письмо нельзя удалить ("" — можно). Нельзя, пока идёт связанный с ним квест (письмо —
## часть задания), и пока на него можно ответить (ответ — выбор, удалив письмо, его потеряешь).
static func delete_block(uid: String) -> String:
	var e: Dictionary = entry(uid)
	if e.is_empty():
		return "нет такого письма"
	for quest_id: String in linked_quests(str(e["id"])):
		if Quests.is_active(quest_id):
			return "письмо нужно для задачи «%s»" % Planner.title_of(quest_id)
	if not available_replies(uid).is_empty():
		return "на письмо ещё не ответили"
	return ""


static func can_delete(uid: String) -> bool:
	return delete_block(uid).is_empty()


## Удалить входящее письмо. Нельзя (`delete_block`) — false, письмо на месте.
static func delete(uid: String) -> bool:
	if not can_delete(uid):
		return false
	var list: Array = _list()
	for i: int in list.size():
		if str((list[i] as Dictionary)["uid"]) == uid:
			var id: String = str((list[i] as Dictionary)["id"])
			list.remove_at(i)
			EventBus.mail_deleted.emit(uid, id)
			return true
	return false


## Удалить отправленное письмо по номеру в `sent()` (новые в конце). Отправленное уже ушло — его
## копия у игрока ничего не держит, удалять можно всегда.
static func delete_sent(index: int) -> bool:
	var list: Array = _state_list("sent")
	if index < 0 or index >= list.size():
		return false
	list.remove_at(index)
	EventBus.mail_deleted.emit("sent#%d" % index, "")
	return true


## Есть ли в данных квеста ссылка на письмо по одному из ключей `QUEST_MAIL_KEYS`.
static func _mentions(data: Variant, mail_id: String) -> bool:
	if data is Dictionary:
		for key: Variant in (data as Dictionary).keys():
			var value: Variant = (data as Dictionary)[key]
			if QUEST_MAIL_KEYS.has(str(key)) and str(value) == mail_id:
				return true
			if _mentions(value, mail_id):
				return true
	elif data is Array:
		for item: Variant in data as Array:
			if _mentions(item, mail_id):
				return true
	return false


## Сохранить вложение `index` к себе в `/home/mail`. Возвращает путь ("" — нет вложения). Файл
## несёт свой `file_id`: условия квестов находят его, куда бы игрок его ни переложил.
static func save_attachment(uid: String, index: int) -> String:
	var e: Dictionary = entry(uid)
	if e.is_empty():
		return ""
	var files: Array = definition(str(e["id"])).get("attachments", []) as Array
	if index < 0 or index >= files.size():
		return ""
	var file: Dictionary = (files[index] as Dictionary).duplicate(true)
	var name: String = str(file.get("name", "attachment.txt"))
	file.erase("name")
	var home: Filesystem = Filesystem.for_node(Network.HOME_ID)
	var path: String = _free_path(home, ATTACHMENTS_DIR.path_join(name))
	home.put_file(path, file)
	GameState.set_filesystem_state(Network.HOME_ID, home.to_dict())
	EventBus.attachment_saved.emit(uid, path)
	return path


## Имя занято — «имя_2.txt»: вложение не должно молча затирать файл игрока.
static func _free_path(fs: Filesystem, path: String) -> String:
	if not fs.has_file(path):
		return path
	var base: String = path.get_basename()
	var ext: String = path.get_extension()
	var n: int = 2
	while fs.has_file("%s_%d.%s" % [base, n, ext]):
		n += 1
	return "%s_%d.%s" % [base, n, ext]


static func _list() -> Array:
	return _state_list("inbox")


static func _state_list(key: String) -> Array:
	var state: Dictionary = GameState.mail_state()
	if not state.has(key):
		state[key] = []
	return state[key]
