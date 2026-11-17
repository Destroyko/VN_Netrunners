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
