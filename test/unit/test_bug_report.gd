extends GutTest
## Журнал сессии и снимок «здесь баг»: имена папок, строки журнала, что попадает в снимок.

const TEST_DIR: String = "user://test_bugreports"

var log_node: Node


func before_each() -> void:
	_wipe(ProjectSettings.globalize_path(TEST_DIR))
	log_node = (load("res://src/debug/session_log.gd") as Script).new() as Node
	add_child_autofree(log_node)
	log_node.call("begin", ProjectSettings.globalize_path(TEST_DIR))


func after_all() -> void:
	_wipe(ProjectSettings.globalize_path(TEST_DIR))


func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub: String in DirAccess.get_directories_at(path):
		_wipe(path.path_join(sub))
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func test_stamp_sorts_like_time() -> void:
	var early: String = BugReport.stamp({"year": 2026, "month": 11, "day": 9, "hour": 23, "minute": 5, "second": 1})
	var late: String = BugReport.stamp({"year": 2026, "month": 11, "day": 15, "hour": 8, "minute": 0, "second": 0})
	assert_eq(early, "2026-11-09_23-05-01")
	assert_lt(early, late, "по имени — по времени")


func test_latest_skips_the_sessions_folder() -> void:
	var names: PackedStringArray = ["2026-11-15_10-00-00", "sessions", "2026-11-15_12-30-00", ".gdignore"]
	assert_eq(BugReport.latest(names), "2026-11-15_12-30-00")


func test_line_shows_real_and_game_time() -> void:
	var text: String = BugReport.line(12345, 3, 14 * 60 + 5, "term", "home:/home$ scan")
	assert_string_contains(text, "+0012.345")
	assert_string_contains(text, "[д3 14:05]")
	assert_string_contains(text, "home:/home$ scan")


func test_session_log_records_what_happens() -> void:
	log_node.call("write", "term", "home:/home$ scan")
	EventBus.rested.emit("sleep", 2, "")
	var sessions: String = ProjectSettings.globalize_path(TEST_DIR).path_join(BugReport.SESSIONS_SUBDIR)
	var files: PackedStringArray = DirAccess.get_files_at(sessions)
	assert_eq(files.size(), 1)
	var text: String = FileAccess.get_file_as_string(sessions.path_join(files[0]))
	assert_string_contains(text, "home:/home$ scan")
	assert_string_contains(text, "rested(sleep, 2, )", "события шины пишутся сами")


func test_snapshot_keeps_state_log_and_note() -> void:
	GameState.set_flag("gate.pressure")
	log_node.call("write", "term", "probe")
	var dir: String = str(log_node.call("snapshot", "лупа зелёная у края"))
	assert_true(FileAccess.file_exists(dir.path_join("state.json")))
	assert_true(FileAccess.file_exists(dir.path_join("session.log")))
	assert_eq(FileAccess.get_file_as_string(dir.path_join("note.txt")), "лупа зелёная у края")
	var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("state.json"))) as Dictionary
	assert_true(state.has("_seed"), "по сиду игру можно повторить")
	assert_string_contains(FileAccess.get_file_as_string(dir.path_join("session.log")), "probe")
	assert_eq(BugReport.latest(DirAccess.get_directories_at(ProjectSettings.globalize_path(TEST_DIR))), dir.get_file())
