extends "res://test/unit/terminal_fixture.gd"
## Файл в работе у программы (фоновый подбор пароля) не удаляется, не перемещается, не
## переименовывается и не заменяется (docs/issues.md: ISS-018; решено 25.11.2026).

const ARCHIVE: String = "/home/downloads/arhiv.enc"


func before_each() -> void:
	super.before_each()
	Filesystem.for_node(Network.HOME_ID).put_file(ARCHIVE, {"encrypted": true, "size_kb": 1200,
		"locked": {"text": "секрет"}})
	Filesystem.for_node(Network.HOME_ID).put_file("/home/downloads/notes.txt", {"text": "x"})
	GameState.set_flag(Gates.AUTOCRACK)
	run("decrypt %s -auto" % ARCHIVE)
	assert_true(BackgroundTasks.is_running(ARCHIVE))


func _home() -> Filesystem:
	return Filesystem.for_node(Network.HOME_ID)


func test_archive_under_bruteforce_cannot_be_removed() -> void:
	assert_string_contains(run("rm %s" % ARCHIVE), "занят: arhiv.enc")
	assert_true(_home().has_file(ARCHIVE))


func test_archive_under_bruteforce_cannot_be_moved_or_renamed() -> void:
	assert_string_contains(run("mv %s /home/downloads/other.enc" % ARCHIVE), "занят: arhiv.enc")
	assert_true(_home().has_file(ARCHIVE))
	assert_false(_home().has_file("/home/downloads/other.enc"))


func test_archive_under_bruteforce_cannot_be_replaced() -> void:
	assert_string_contains(run("cp /home/downloads/notes.txt %s" % ARCHIVE), "занят: arhiv.enc")
	assert_true(bool(_home().file_data(ARCHIVE).get("encrypted", false)), "архив тот же")
	assert_string_contains(run("mv /home/downloads/notes.txt %s" % ARCHIVE), "занят: arhiv.enc")


func test_mask_skips_the_busy_file_and_removes_the_rest() -> void:
	var out: String = run("rm /home/downloads/*")
	assert_string_contains(out, "занят: arhiv.enc")
	assert_string_contains(out, "удалено: 1")
	assert_true(_home().has_file(ARCHIVE))
	assert_false(_home().has_file("/home/downloads/notes.txt"))


func test_archive_is_free_after_bruteforce() -> void:
	Clock.advance(BackgroundTasks.brute_minutes())
	assert_false(BackgroundTasks.is_running(ARCHIVE))
	run("mv %s /home/downloads/open.txt" % ARCHIVE)
	assert_true(_home().has_file("/home/downloads/open.txt"), "подбор кончился — файл свободен")
