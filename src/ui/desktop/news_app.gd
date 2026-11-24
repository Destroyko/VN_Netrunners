class_name NewsApp
extends HBoxContainer
## Приложение «Новости» (docs/gameplay/news.md): лента слева (непрочитанные — с точкой), текст
## справа. Правил здесь нет: читает ленту `News`, при открытии помечает прочитанным.

var _list: ItemList
var _headline: Label
var _date: Label
var _body: Label
var _ids: PackedStringArray = []


func _init() -> void:
	name = "NewsApp"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list = ItemList.new()
	_list.name = "Feed"
	_list.custom_minimum_size = Vector2(220, 0)
	_list.item_selected.connect(func(index: int) -> void: open(_ids[index]))
	add_child(_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	_date = Label.new()
	_date.theme_type_variation = "DimLabel"
	right.add_child(_date)
	_headline = Label.new()
	_headline.theme_type_variation = "HeaderLabel"
	_headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_headline)
	_body = Label.new()
	_body.name = "Body"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_body)


func _ready() -> void:
	EventBus.news_published.connect(func(_id: String) -> void: refresh())
	refresh()


func refresh() -> void:
	_list.clear()
	_ids.clear()
	for e: Dictionary in News.feed():
		var def: Dictionary = News.definition(str(e["id"]))
		var mark: String = "" if bool(e["read"]) else "● "
		_list.add_item("%s%s" % [mark, str(def.get("headline", ""))])
		_ids.append(str(e["id"]))
	if _ids.is_empty():
		_body.text = "Пока новостей нет"


func open(id: String) -> void:
	News.mark_read(id)
	var def: Dictionary = News.definition(id)
	for e: Dictionary in News.feed():
		if str(e["id"]) == id:
			_date.text = Clock.format_date(int(e["day"]))
	_headline.text = str(def.get("headline", ""))
	_body.text = str(def.get("body", ""))
	refresh()
