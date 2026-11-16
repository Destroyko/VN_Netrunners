extends GutTest
## BackgroundTasks: офлайн-подбор пароля к архиву идёт по игровому времени, reboot его
## останавливает (docs/gameplay/hacking-loop.md).

const DAY: int = 24 * 60

var _done: Array[String] = []


func before_each() -> void:
	GameState.reset()
	Clock.reload_config()
	_done.clear()
	EventBus.decrypt_done.connect(_on_done)
	# Зашифрованный архив на ПК героя.
	var home: Filesystem = Filesystem.for_node(Network.HOME_ID)
	home.put_file("/home/dump/arhiv.enc", {"encrypted": true, "size_kb": 1200,
		"locked": {"text": "секрет", "file_id": "file_secret"}})


func after_each() -> void:
	EventBus.decrypt_done.disconnect(_on_done)


func _on_done(path: String) -> void:
	_done.append(path)


func test_start_requires_encrypted_file() -> void:
	assert_false(bool(BackgroundTasks.start_decrypt("/home/dump/nope.enc")["ok"]))
	Filesystem.for_node(Network.HOME_ID).put_file("/home/dump/plain.txt", {"text": "x"})
	assert_false(bool(BackgroundTasks.start_decrypt("/home/dump/plain.txt")["ok"]), "не зашифрован")


func test_bruteforce_finishes_after_its_time_and_unlocks() -> void:
	assert_true(bool(BackgroundTasks.start_decrypt("/home/dump/arhiv.enc")["ok"]))
	Clock.advance(BackgroundTasks.brute_minutes() - 1)
	var home: Filesystem = Filesystem.for_node(Network.HOME_ID)
	assert_true(bool(home.file_data("/home/dump/arhiv.enc").get("encrypted", false)), "ещё идёт")
	Clock.advance(1)
	assert_false(bool(home.file_data("/home/dump/arhiv.enc").get("encrypted", false)), "расшифрован")
	assert_eq(str(home.file_data("/home/dump/arhiv.enc").get("text", "")), "секрет", "содержимое раскрыто")
	assert_true(home.has_file_id("file_secret"), "file_id доступен для квестов")
	assert_eq(_done, ["/home/dump/arhiv.enc"] as Array[String])


func test_runs_through_sleep() -> void:
	BackgroundTasks.start_decrypt("/home/dump/arhiv.enc")
	Clock.set_time(1, 22 * 60)
	# Подбор поставлен до сна; спим — время идёт, подбор завершается к утру.
	GameState.set_var(BackgroundTasks.VAR_TASKS, [{"path": "/home/dump/arhiv.enc", "finish_at": Clock.total_minutes() + 300}])
	Rest.sleep_until(8 * 60)
	assert_false(bool(Filesystem.for_node(Network.HOME_ID).file_data("/home/dump/arhiv.enc").get("encrypted", false)))


func test_reboot_cancels_tasks() -> void:
	BackgroundTasks.start_decrypt("/home/dump/arhiv.enc")
	assert_eq(BackgroundTasks.cancel_all(), 1)
	assert_eq(BackgroundTasks.tasks().size(), 0)
	Clock.advance(DAY)
	assert_true(bool(Filesystem.for_node(Network.HOME_ID).file_data("/home/dump/arhiv.enc").get("encrypted", false)), "прерван — не расшифровался")


func test_tasks_survive_save() -> void:
	BackgroundTasks.start_decrypt("/home/dump/arhiv.enc")
	var saved: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(saved)
	assert_eq(BackgroundTasks.tasks().size(), 1)
