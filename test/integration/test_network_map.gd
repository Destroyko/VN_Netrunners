extends GutTest
## Карта сети и аварийная консоль рабочего стола.

var desktop: Desktop


func before_each() -> void:
	GameState.reset()
	Clock.set_time(1, 12 * 60)
	var scene: PackedScene = load(Screens.DESKTOP) as PackedScene
	desktop = scene.instantiate() as Desktop
	add_child_autofree(desktop)
	await wait_frames(2)


# --- Раскладка -----------------------------------------------------------------

func test_chain_goes_left_to_right() -> void:
	var layout: Dictionary = MapLayout.compute(PackedStringArray(["a", "b", "c"]), {"a": ["b"], "b": ["a", "c"], "c": ["b"]})
	var pos: Dictionary = layout["positions"] as Dictionary
	assert_lt((pos["a"] as Vector2).x, (pos["b"] as Vector2).x)
	assert_lt((pos["b"] as Vector2).x, (pos["c"] as Vector2).x)


func test_islands_do_not_overlap() -> void:
	var layout: Dictionary = MapLayout.compute(PackedStringArray(["a", "b", "z"]), {"a": ["b"]})
	var pos: Dictionary = layout["positions"] as Dictionary
	assert_ne(pos["a"], pos["z"])
	assert_gt((pos["z"] as Vector2).y, (pos["a"] as Vector2).y, "остров z ниже острова a-b")


func test_branches_share_a_column() -> void:
	var layout: Dictionary = MapLayout.compute(PackedStringArray(["a", "b", "c"]), {"a": ["b", "c"]})
	var pos: Dictionary = layout["positions"] as Dictionary
	assert_eq((pos["b"] as Vector2).x, (pos["c"] as Vector2).x)
	assert_ne((pos["b"] as Vector2).y, (pos["c"] as Vector2).y)


func test_one_sided_link_still_connects() -> void:
	var layout: Dictionary = MapLayout.compute(PackedStringArray(["a", "b"]), {"b": ["a"]})
	var pos: Dictionary = layout["positions"] as Dictionary
	assert_ne((pos["a"] as Vector2).x, (pos["b"] as Vector2).x, "связь записана только у b, но они на одном острове")


func test_edges_need_both_ends_and_have_no_duplicates() -> void:
	var edges: Array[Array] = MapLayout.edges(PackedStringArray(["a", "b"]), {"a": ["b", "ghost"], "b": ["a"]})
	assert_eq(edges.size(), 1)


# --- Карта в игре ---------------------------------------------------------------

func test_map_shows_only_known_nodes() -> void:
	var map: MapView = desktop.open_app("map").body.get_child(0) as MapView
	var before: int = map.known_nodes().size()
	assert_true(map.known_nodes().has(Network.HOME_ID))
	var view: TerminalView = desktop.open_app("terminal").body.get_child(0) as TerminalView
	view.submit("scan")
	assert_gt(map.known_nodes().size(), before, "scan открыл соседа, карта обновилась")
	assert_false(map.known_nodes().has("node_office_server"), "чужое, неизвестное не показывается")


# --- Аварийная консоль ----------------------------------------------------------

func test_healthy_pc_shows_the_desktop() -> void:
	assert_false(desktop.is_emergency())


func test_deleting_x_server_folds_the_desktop_into_an_emergency_console() -> void:
	var view: TerminalView = desktop.open_app("terminal").body.get_child(0) as TerminalView
	view.submit("rm /sys/x-server.sys")
	view.submit("y")
	assert_true(desktop.is_emergency(), "стол сложился сразу")


func test_restoring_the_file_brings_the_desktop_back() -> void:
	var view: TerminalView = desktop.open_app("terminal").body.get_child(0) as TerminalView
	view.submit("rm /sys/x-server.sys")
	view.submit("y")
	assert_true(desktop.is_emergency())
	Room.use_item("item_flash_backup", Filesystem.for_node(Network.HOME_ID))  # без предмета ничего не чинит
	assert_true(desktop.is_emergency())
	Inventory.give("item_flash_backup")
	Room.use_item("item_flash_backup", Filesystem.for_node(Network.HOME_ID))
	desktop.apply_mode()
	assert_false(desktop.is_emergency())


func test_old_os_also_gives_the_emergency_console() -> void:
	GameState.set_var(Terminal.VAR_OS, Terminal.OS_OLD)
	desktop.apply_mode()
	assert_true(desktop.is_emergency())
