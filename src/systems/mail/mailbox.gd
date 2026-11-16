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
## Ящик — в `GameState.mail_state()`: [{uid, id, day, minute, read, reply}], новые в конце.

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
	EventBus.mail_received.emit(str(entry["uid"]), id)
	return true


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
	var state: Dictionary = GameState.mail_state()
	if not state.has("inbox"):
		state["inbox"] = []
	return state["inbox"]
