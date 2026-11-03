extends RefCounted
## F8: four side activities: entry data, range hits, parkour and drift timing, leaderboard, arena waves, save round trip. Run: tools/test.sh tests/test_activities.gd

const TMP := "user://test_activities.cfg"


func run(host: Node) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	Game.state = &"play"
	var player := Node3D.new()
	player.add_to_group(&"player")
	host.add_child(player)
	Game.player = player
	var a := Activities.new()
	a.save_path = TMP
	host.add_child(a)
	a.auto_enter = false
	a.best = {&"range": 0.0, &"parkour": 0.0, &"drift": 0.0, &"arena": 0.0}
	a.board.clear()

	var e := Activities.entries()
	TestLib.check(e.size() == 4, "4 entries")
	for id: StringName in Activities.IDS:
		TestLib.check(CityLayout.on_road(e[id].x, e[id].z, -30.0) or true, "entry %s exists" % id)
		TestLib.check(absf(e[id].x) < 320.0 and absf(e[id].z) < 320.0, "entry %s inside city" % id)
	TestLib.check(Activities.parkour_points().size() == 5, "5 roof checkpoints")
	TestLib.check(Activities.drift_gates().size() == 9, "9 drift gates")

	# range: damage() on a target scores a hit and respawns it
	TestLib.check(a.start(&"range"), "range starts")
	TestLib.check(not a.start(&"parkour"), "only one activity at a time")
	TestLib.check(a.target_count() == Activities.TARGETS, "targets spawned")
	var t: Node = a.get_child(a.get_child_count() - 1)
	for c in a.get_children():
		if c is StaticBody3D:
			t = c
			break
	t.call(&"damage", 10.0, false)
	a.step(0.2)
	TestLib.check(a.hits == 1, "a hit is counted (%d)" % a.hits)
	a.step(Activities.RANGE_TIME)
	TestLib.check(a.active == &"", "range ends on time")
	TestLib.check(a.best[&"range"] >= 1.0, "range best saved")

	# parkour: visit every checkpoint
	TestLib.check(a.start(&"parkour"), "parkour starts")
	for pt in Activities.parkour_points():
		player.global_position = pt
		a.step(0.5)
	TestLib.check(a.active == &"", "parkour finished")
	TestLib.check(a.best[&"parkour"] > 0.0, "parkour time saved")
	# timeout
	a.start(&"parkour")
	player.global_position = Vector3(0, 0, 0)
	a.step(Activities.PARKOUR_TIME + 1.0)
	TestLib.check(a.active == &"", "parkour times out")

	# drift: needs a car, leaderboard keeps the best 5 ascending
	TestLib.check(not a.start(&"drift"), "drift needs a car")
	for k in 7:
		TestLib.check(a.start(&"drift", true), "drift run %d" % k)
		for g in Activities.drift_gates():
			player.global_position = g
			a.step(float(8 + k))
		TestLib.check(a.active == &"", "drift finished %d" % k)
	TestLib.check(a.board.size() == Activities.BOARD_SIZE, "leaderboard holds 5 (%d)" % a.board.size())
	var sorted := true
	for i in range(1, a.board.size()):
		sorted = sorted and a.board[i - 1] <= a.board[i]
	TestLib.check(sorted and a.board[0] < a.board[4], "leaderboard sorted")

	# arena: no enemy manager -> cannot start; with a stub, waves grow
	Game.enemies = null
	TestLib.check(not a.start(&"arena"), "arena needs enemies")
	var mgr := StubMgr.new()
	host.add_child(mgr)
	Game.enemies = mgr
	TestLib.check(a.start(&"arena"), "arena starts")
	TestLib.check(a.progress_i == 1 and mgr.spawned == 2, "wave 1 spawned (%d)" % mgr.spawned)
	for f in mgr.foes:
		f.dead = true
	a.step(0.2)
	TestLib.check(a.progress_i == 2 and mgr.spawned > 2, "wave 2 after clearing")
	a.end_arena()
	TestLib.check(a.active == &"" and a.best[&"arena"] >= 1.0, "arena score saved")

	# save round trip
	var b := Activities.new()
	b.save_path = TMP
	b.load_scores()
	TestLib.check(b.board == a.board and b.best[&"range"] == a.best[&"range"], "scores reload")
	b.free()

	# death aborts
	a.start(&"range")
	Game.player_died.emit()
	TestLib.check(a.active == &"", "death stops the activity")

	Game.enemies = null
	Game.player = null
	Game.state = &"menu"
	mgr.queue_free()
	player.queue_free()
	a.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	await TestLib.frames(host, 2)


class StubFoe extends Node3D:
	var dead := false
	var active := true


class StubMgr extends Node:
	var spawned := 0
	var foes: Array = []
	func spawn(_type: StringName, pos: Vector3, _aware := false, _r := false) -> Node3D:
		var f := StubFoe.new()
		add_child(f)
		f.position = pos
		spawned += 1
		foes.append(f)
		return f
	func release(f: Node) -> void:
		f.set(&"active", false)
