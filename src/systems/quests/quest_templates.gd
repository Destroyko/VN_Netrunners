class_name QuestTemplates
extends RefCounted
## Шаблоны квестов с подстановками (docs/tech/story-engine.md, «Шаблоны»; как aliases в Skyrim):
## один квест «скачать файл с узла», а узел, файл и заказчик подставляются при старте. Нужны
## доске группы, оплате школы и всему повторяемому.
##
## Шаблон — квест с `"template": true` и описанием параметров:
##   "params": {"node": {"from": ["node_a", "node_b"]}, "file": {"sample": "/home/x.txt"}}
## `from` — откуда выбрать, если при старте не передали (поток случайности `quests`); `sample` —
## образец для валидатора, когда значение всегда передаётся при старте. В тексте квеста —
## `{node}`, `{file}`: подставляются в любые строки (цели, эффекты, заголовки).
##
## Экземпляр — `<шаблон>#<номер>` (номер из счётчика, сейв помнит), его состояние хранит
## `template` и `params`. Шаблон можно запускать сколько угодно раз — каждый раз новый экземпляр.
##
## Чистая логика: определение экземпляра собирается из данных шаблона при каждом запросе.

const SEP: String = "#"
const VAR_NEXT: String = "quests.next_instance"


static func is_template(def: Dictionary) -> bool:
	return bool(def.get("template", false))


static func is_instance(id: String) -> bool:
	return id.contains(SEP)


static func template_of(id: String) -> String:
	return id.get_slice(SEP, 0)


## Значения параметров экземпляра: переданные при старте, остальные — из `from` (случайно, с
## сидом) или `sample`. Нет ни того, ни другого — параметр пропущен (валидатор об этом скажет).
static func pick_params(def: Dictionary, given: Dictionary) -> Dictionary:
	var params: Dictionary = {}
	var spec: Dictionary = def.get("params", {}) as Dictionary
	for key: String in spec.keys():
		if given.has(key):
			params[key] = given[key]
			continue
		var options: Dictionary = spec[key] as Dictionary
		var from: Array = options.get("from", []) as Array
		if not from.is_empty():
			params[key] = from[Rng.stream("quests").randi_range(0, from.size() - 1)]
		elif options.has("sample"):
			params[key] = options["sample"]
	return params


## Образцы для валидатора: первое из `from` или `sample`.
static func sample_params(def: Dictionary) -> Dictionary:
	var params: Dictionary = {}
	var spec: Dictionary = def.get("params", {}) as Dictionary
	for key: String in spec.keys():
		var options: Dictionary = spec[key] as Dictionary
		var from: Array = options.get("from", []) as Array
		params[key] = from[0] if not from.is_empty() else options.get("sample", "")
	return params


## Новый номер экземпляра: только растёт — номер удалённого или законченного не повторяется.
static func next_id(template: String) -> String:
	var number: int = int(GameState.get_var_or(VAR_NEXT, 1))
	GameState.set_var(VAR_NEXT, number + 1)
	return "%s%s%d" % [template, SEP, number]


## Подставить параметры во все строки значения (словари и массивы — вглубь). Строка ровно
## `{key}` получает значение как есть (число остаётся числом).
static func substitute(value: Variant, params: Dictionary) -> Variant:
	if params.is_empty():
		return value
	if value is String:
		var text: String = value
		for key: String in params.keys():
			var mark: String = "{%s}" % key
			if text == mark:
				return params[key]
			text = text.replace(mark, str(params[key]))
		return text
	if value is Dictionary:
		var out: Dictionary = {}
		for k: Variant in (value as Dictionary).keys():
			out[k] = substitute((value as Dictionary)[k], params)
		return out
	if value is Array:
		var list: Array = []
		for item: Variant in value as Array:
			list.append(substitute(item, params))
		return list
	return value
