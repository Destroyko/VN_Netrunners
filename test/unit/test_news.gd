extends GutTest
## News и NewsManager: фоновая новость в начале дня, последствия с задержкой, лента и
## непрочитанное (docs/gameplay/news.md).

const DAY: int = 24 * 60

var _published: Array[String] = []


func before_each() -> void:
	GameState.reset()
	Clock.reload_config()
	Rng.set_seed(42)
	_published.clear()
	EventBus.news_published.connect(_on_published)


func after_each() -> void:
	EventBus.news_published.disconnect(_on_published)


func _on_published(id: String) -> void:
	_published.append(id)


func test_one_background_news_per_day() -> void:
	News.publish_background(1)
	assert_eq(News.feed().size(), 1)
	var first: String = str(News.feed()[0]["id"])
	News.publish_background(2)
	assert_eq(News.feed().size(), 2)
	assert_ne(str(News.feed()[0]["id"]), first, "два дня подряд — не одна и та же")


func test_day_started_publishes_background() -> void:
	Clock.advance(DAY)  # переход в день 2 → day_started
	assert_eq(News.published().size(), 1, "утром пришла фоновая новость")


func test_scheduled_consequence_comes_with_delay() -> void:
	Effects.apply({"schedule_news": {"id": "news_project_closed", "delay_days": 1}})
	assert_eq(News.published().size(), 0, "сразу новости нет")
	News.publish_due(1)
	assert_eq(News.published().size(), 0, "в тот же день ещё нет")
	News.publish_due(2)
	assert_true(_published.has("news_project_closed"), "на следующий день — пришла")


func test_quest_outcome_news_reaches_feed_next_morning() -> void:
	# Заказ 5 в исходе done планирует новость-последствие.
	Quests.definition("side_job_5")  # прогрев кэша данных
	Effects.apply({"schedule_news": {"id": "news_project_closed", "delay_days": 1}})
	Clock.advance(DAY)  # day_started(2) → publish_due + фоновая
	var ids: Array = News.published().map(func(e: Dictionary) -> String: return str(e["id"]))
	assert_true(ids.has("news_project_closed"))


func test_feed_newest_first_and_unread_count() -> void:
	News.publish("news_weather", 1)
	News.publish("news_crime", 2)
	assert_eq(str(News.feed()[0]["id"]), "news_crime", "новые сверху")
	assert_eq(News.unread_count(), 2)
	News.mark_read("news_crime")
	assert_eq(News.unread_count(), 1)


func test_unknown_news_is_not_published() -> void:
	assert_false(News.publish("news_ghost", 1))
	assert_push_error_count(1)


func test_news_feed_survives_save() -> void:
	News.publish("news_weather", 1)
	var saved: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(saved)
	assert_eq(News.feed().size(), 1)
