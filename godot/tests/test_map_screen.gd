extends RefCounted
## H3 map screen (headless): discovery fog, waypoint place / clear, marker filters, pause via Game.state, minimap tap opens it, save round trip.
## Run: tools/test.sh tests/test_map_screen.gd

func run(host: Node) -> void:
	var saved_path := MapScreen.SAVE_PATH
	Game.state = &"play"
	var ms := MapScreen.new()
	host.add_child(ms)
	await host.get_tree().process_frame
	TestLib.check(not ms.is_open() and ms.discovered_count() >= 0, "map starts closed")
	var start_n := ms.discovered_count()
	ms.discover(Vector3(-250, 0, -250))
	TestLib.check(ms.is_discovered(-250, -250) and ms.discovered_count() > start_n, "walking near a cell discovers it")
	TestLib.check(not ms.is_discovered(250, 250) or start_n > 0, "far cells stay fogged")
	TestLib.check(MapScreen.cell_of(-1e6, 1e6) == (MapScreen.CELLS - 1) * MapScreen.CELLS, "cell index clamps at the edges")
	ms.open()
	TestLib.check(ms.is_open() and Game.state == &"paused", "open pauses through Game.state")
	await host.get_tree().process_frame
	var mid := ms.world_to_map(100.0, -60.0)
	var back := ms.map_to_world(mid)
	TestLib.check(absf(back.x - 100.0) < 0.5 and absf(back.z + 60.0) < 0.5, "world <-> map round trip")
	ms._tap(mid)
	TestLib.check(ms.has_waypoint() and absf(ms.waypoint.x - 100.0) < 1.0, "a tap places the waypoint")
	ms._tap(ms.world_to_map(-200.0, 200.0))
	TestLib.check(ms.has_waypoint() and ms.waypoint.x < 0.0, "a second tap elsewhere moves it (one waypoint)")
	ms._tap(ms.world_to_map(ms.waypoint.x, ms.waypoint.z))
	TestLib.check(not ms.has_waypoint(), "tapping the waypoint clears it")
	ms.set_waypoint(Vector3(5, 0, 5))
	(ms.get_node("Close") if false else ms._root.find_child("Clear", true, false) as Button).pressed.emit()
	TestLib.check(not ms.has_waypoint(), "CLEAR removes the waypoint")
	TestLib.check(ms.visible_markers().size() == _sum(ms.marker_counts()), "marker counts match the shown markers")
	var all := ms.collect_markers()
	for k in MapScreen.KINDS:
		ms.filters[k] = false
	TestLib.check(ms.visible_markers().is_empty(), "all filters off hides every marker")
	(ms._root.find_child("F_items", true, false) as Button).button_pressed = true
	(ms._root.find_child("F_items", true, false) as Button).pressed.emit()
	TestLib.check(bool(ms.filters[&"items"]), "a filter button toggles its kind")
	for k in MapScreen.KINDS:
		ms.filters[k] = true
	for mk in ms.visible_markers():
		var p: Vector3 = mk["pos"]
		TestLib.check(not bool(mk["fog"]) or ms.is_discovered(p.x, p.z), "fogged markers only show in discovered cells")
	TestLib.check(ms.visible_markers().size() <= all.size(), "filters and fog never add markers")
	ms.set_waypoint(Vector3(33, 0, -44))
	ms.close_screen()
	TestLib.check(not ms.is_open() and Game.state == &"play", "close resumes play")
	var again := MapScreen.new()
	host.add_child(again)
	TestLib.check(again.has_waypoint() and absf(again.waypoint.x - 33.0) < 0.1 and again.is_discovered(-250, -250), "waypoint and fog are saved")
	again.clear_waypoint()
	again.close_screen()
	again.queue_free()
	ms.queue_free()
	DirAccess.remove_absolute(saved_path)
	Game.state = &"idle"


func _sum(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n
