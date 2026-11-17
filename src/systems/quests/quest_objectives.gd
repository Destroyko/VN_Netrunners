class_name QuestObjectives
extends RefCounted
## Цели этапа квеста (docs/tech/quest-format.md, «Словарь»): какое событие шины закрывает какую
## цель. Чистые правила: на вход — цель из данных и случившееся событие, на выход — да или нет.
##
## Событие — словарь {"event": имя сигнала, "node": ..., "path": ...}. Цели «по состоянию»
## (`deliver`, `wait_until`) проверяются без события: выполнено ли условие сейчас.

## Цели, которые закрываются событием шины.
const BY_EVENT: Dictionary = {
	"hack_node": "node_connected",
	"read_file": "file_read",
	"copy_file": "file_copied",
	"delete_file": "file_deleted",
	"wipe_logs": "node_disconnected",
	"deliver": "mail_sent",
	"talk": "dialogue_ended",
}
## Цели, которые закрываются состоянием мира.
const BY_STATE: PackedStringArray = ["file_at", "wait_until"]
## Цели следующих этапов: валидатор их пропускает, но в M2 они не закрываются (диалогов, карты
## и `archmask` ещё нет).
const NOT_YET: PackedStringArray = ["visit_location", "mask_backup"]


## Закрывает ли событие `event` цель `objective`.
static func matches(objective: Dictionary, event: Dictionary) -> bool:
	var type: String = str(objective.get("type", ""))
	if str(BY_EVENT.get(type, "")) != str(event.get("event", "")):
		return false
	if objective.has("node") and str(objective["node"]) != str(event.get("node", "")):
		return false
	if objective.has("file") and str(objective["file"]) != str(event.get("path", "")):
		return false
	if type == "talk":
		# Разговор состоялся: диалог `dialogue` закончился.
		return str(objective.get("dialogue", "")) == str(event.get("dialogue", ""))
	if type == "wipe_logs":
		return logs_clean(str(event.get("node", "")))
	if type == "deliver":
		# Отправить письмо на адрес `to`. С `what` — во вложении нужен файл с этим `file_id`
		# (откуда угодно с ПК героя); без `what` — хватит любого письма («отписаться»).
		if str(objective.get("to", "")) != str(event.get("to", "")):
			return false
		if not objective.has("what"):
			return true
		var sent: PackedStringArray = event.get("file_ids", PackedStringArray()) as PackedStringArray
		return sent.has(str(objective.get("what", "")))
	return true


## Выполнена ли цель «по состоянию» прямо сейчас.
static func satisfied(objective: Dictionary) -> bool:
	match str(objective.get("type", "")):
		"file_at":
			# Файл лежит по пути `path` на узле `node` (по умолчанию — ПК героя).
			return Filesystem.for_node(str(objective.get("node", Network.HOME_ID))).has_file(str(objective.get("path", "")))
		"wait_until":
			return Conditions.check_all(objective.get("until", []) as Array)
	return false


static func is_state_objective(objective: Dictionary) -> bool:
	return BY_STATE.has(str(objective.get("type", "")))


## Следы почищены: в логе узла осталась только неустранимая запись о сеансе (heat.md).
static func logs_clean(node_id: String) -> bool:
	var weights: Dictionary = Logbook.weights_from_balance()
	return Logbook.for_node(node_id).heat_weight() <= int(weights.get(Logbook.CATEGORY_SESSION, 1))
