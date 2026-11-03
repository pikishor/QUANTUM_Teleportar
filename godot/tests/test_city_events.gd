extends RefCounted
## City events (headless). Run: tools/test.sh tests/test_city_events.gd

const CE := preload("res://scripts/world/city_events.gd")


func run(host: Node) -> void:
	var ev := CE.new()
	host.add_child(ev)
	var prev := Game.state
	Game.state = &"play"
	var p := Vector3(10.0, 0.0, 20.0)

	# scheduler: nothing before the first interval, then an event inside the distance band
	ev.tick(1.0, p)
	TestLib.check(ev.events.is_empty(), "no event before the first spawn time")
	ev.tick(10.0, p)
	TestLib.check(ev.events.size() == 1, "the scheduler spawned an event")
	var e: Dictionary = ev.events[0]
	var d := Vector2(e["pos"].x - p.x, e["pos"].z - p.z).length()
	var lim := float(Game.HALF) - 10.0
	TestLib.check(d > 5.0 and absf(e["pos"].x) <= lim + 0.01 and absf(e["pos"].z) <= lim + 0.01, "event is near the player and inside the city (%.0f m)" % d)

	# cooldowns and cap
	var first_kind: StringName = e["kind"]
	for i in 20:
		ev.spawn_near(p)
	TestLib.check(ev.events.size() <= CE.MAX_ACTIVE, "never more than MAX_ACTIVE events")
	TestLib.check(ev.spawn_near(p, first_kind).is_empty(), "a kind on cooldown or active does not respawn")

	# rewards and heat on a rescue
	ev.events.clear()
	ev._cool.clear()
	var r: Dictionary = ev.spawn_near(p, &"rescue")
	TestLib.check(not r.is_empty() and r["kind"] == &"rescue", "forced rescue spawns")
	var heat0 := 2.0
	Game.heat = heat0
	var c0 := int(Game.progress.credits) if is_instance_valid(Game.progress) else 0
	var done0: int = ev.completed
	ev.tick(0.1, r["pos"])
	TestLib.check(ev.completed == done0 + 1 and ev.events.is_empty(), "reaching a rescue completes it")
	TestLib.check(Game.heat < heat0 + 0.001, "a rescue lowers or keeps heat")
	if is_instance_valid(Game.progress):
		TestLib.check(int(Game.progress.credits) > c0, "a completed event pays credits")

	# ambush expires as failure and raises nothing
	ev.events.clear()
	ev._cool.clear()
	ev.spawn_near(p, &"ambush")
	var f0: int = ev.failed
	ev.tick(CE.DEF[&"ambush"]["ttl"] + 1.0, Vector3.INF)
	TestLib.check(ev.failed == f0 + 1 and ev.events.is_empty(), "an unanswered ambush expires")

	# markers and rift gravity
	ev.events.clear()
	ev._cool.clear()
	var rf: Dictionary = ev.spawn_near(p, &"rift")
	var m: Array = ev.markers()
	TestLib.check(m.size() == 1 and m[0]["kind"] == &"rift", "the minimap sees the rift marker")
	TestLib.check(ev.gravity_scale_at(rf["pos"]) < 0.5, "gravity is reduced inside a rift")
	TestLib.check(ev.gravity_scale_at(rf["pos"] + Vector3(200.0, 0.0, 0.0)) == 1.0, "normal gravity outside")

	# paused: nothing simulates through _process
	Game.state = &"paused"
	var t0: float = ev.clock
	await TestLib.frames(host, 3)
	TestLib.check(ev.clock == t0, "no simulation while not playing")

	ev.reset()
	TestLib.check(ev.events.is_empty(), "reset clears events")
	Game.state = prev
	Game.heat = 0.0
	ev.queue_free()
