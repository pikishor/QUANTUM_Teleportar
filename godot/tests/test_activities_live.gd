extends RefCounted
## Side activities in the REAL city scene (scenes/main.tscn): markers on valid ground, HUD readout, range hits, parkour checkpoints, drift, arena waves to the end, rewards, best-score save, clean leave.
## Run: tools/test.sh tests/test_activities_live.gd

const TMP := "user://test_activities_live.cfg"


func run(host: Node) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	var p: Player = Game.player
	var world := Game.world as City
	var a: Activities = host.get_tree().get_first_node_in_group(&"activities")
	if p == null or world == null or a == null or not is_instance_valid(Game.enemies):
		TestLib.check(false, "real game has player, city, enemies and Activities")
		return
	a.save_path = TMP
	a.best = {&"range": 0.0, &"parkour": 0.0, &"drift": 0.0, &"arena": 0.0}
	a.board.clear()
	a.auto_enter = false
	Game.state = &"play"
	var prog := Game.progress as Progress

	# positions against the real map: markers and arena spawns on roads, outside every building footprint; targets over roads; gates and roof points on valid spots
	var e := Activities.entries()
	for id: StringName in Activities.IDS:
		TestLib.check(CityLayout.on_road(e[id].x, e[id].z, 1.0) and world.layout.lot_at(e[id].x, e[id].z, 1.0) == null, "marker %s on open road" % id)
	for sp in Activities.arena_spawns():
		TestLib.check(world.layout.lot_at(sp.x, sp.z, 1.0) == null and CityLayout.on_road(sp.x, sp.z), "arena spawn on road")
	for k in 7:
		var tp := Activities.target_pos(k)
		TestLib.check(world.layout.lot_at(tp.x, tp.z, 0.5) == null, "target %d not in a building" % k)
	for g in Activities.drift_gates():
		TestLib.check(CityLayout.on_road(g.x, g.z), "drift gate on road")
	for rp in Activities.parkour_points():
		var h := world.layout.height_at(rp.x, rp.z)
		TestLib.check(h > 4.0 and absf(rp.y - h) < 8.0, "roof checkpoint over a roof (%.1f vs %.1f)" % [rp.y, h])

	# real entry: stand on the range marker with auto-enter on
	a.auto_enter = true
	p.global_position = e[&"range"] + Vector3(0, 0.3, 0)
	var ok := false
	for i in 120:
		await TestLib.frames(host, 1)
		if a.active == &"range":
			ok = true
			break
	TestLib.check(ok, "stepping on the marker starts the range")
	a.auto_enter = false
	var ro := a.readout()
	TestLib.check(ro["visible"] and String(ro["title"]) == "TARGET RANGE", "HUD readout shows the activity")
	var credits0 := prog.credits if prog != null else 0
	var t: Node = null
	for c in a.get_children():
		if c is StaticBody3D:
			t = c
			break
	TestLib.check(t != null and a.target_count() == Activities.TARGETS, "targets in the live scene")
	t.call(&"damage", 5.0, false)
	for i in 60:
		await TestLib.frames(host, 1)
		if a.hits >= 1:
			break
	TestLib.check(a.hits >= 1, "a hit counts")
	TestLib.check(prog == null or prog.credits >= credits0 + Activities.REWARD[&"range"], "hit pays credits")
	# leaving: walk away, activity ends and nodes are freed
	p.global_position = e[&"range"] + Vector3(Activities.LEAVE_RADIUS + 40.0, 0.3, 0)
	for i in 120:
		await TestLib.frames(host, 1)
		if a.active == &"":
			break
	TestLib.check(a.active == &"" and a.target_count() == 0, "leaving ends it and frees targets")
	TestLib.check(not a._beacon.visible, "beacon hidden")

	# parkour: teleport through the checkpoints in the real scene
	a._cool = 0.0
	p.global_position = e[&"parkour"] + Vector3(0, 0.3, 0)
	TestLib.check(a.start(&"parkour"), "parkour starts")
	for pt in Activities.parkour_points():
		p.global_position = pt + Vector3(0, 0.3, 0)
		a.step(0.2)
		await TestLib.frames(host, 1)
	TestLib.check(a.active == &"" and a.best[&"parkour"] > 0.0, "parkour finishes with a best time")

	# drift (car requirement waived: no vehicle in this sandbox) and arena waves through to the end
	TestLib.check(a.start(&"drift", true), "drift starts")
	for g in Activities.drift_gates():
		p.global_position = g
		a.step(0.3)
	TestLib.check(a.active == &"" and a.board.size() == 1, "drift finishes, leaderboard has a time")

	p.global_position = e[&"arena"] + Vector3(0, 0.3, 0)
	TestLib.check(a.start(&"arena"), "arena starts in the real city")
	var guard := 0
	while a.active == &"arena" and guard < 12:
		guard += 1
		for f in a._foes:
			if is_instance_valid(f):
				f.call(&"damage", 9999.0)
				f.set(&"dead", true)
		a.step(0.2)
		await TestLib.frames(host, 1)
	TestLib.check(a.active == &"" and a.best[&"arena"] >= float(Activities.ARENA_WAVES), "arena ends after %d waves (best %s)" % [Activities.ARENA_WAVES, a.best[&"arena"]])

	# saved scores reload
	var b := Activities.new()
	b.save_path = TMP
	b.load_scores()
	TestLib.check(b.best[&"parkour"] == a.best[&"parkour"] and b.board == a.board and b.best[&"arena"] == a.best[&"arena"], "best scores saved and reloaded")
	b.free()

	Game.state = &"menu"
	main.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	await TestLib.frames(host, 2)
