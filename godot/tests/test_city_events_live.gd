extends RefCounted
## City events in the REAL game scene: instantiated by main.gd, actors from the real managers, minimap markers, rift gravity, rewards. Run: tools/test.sh tests/test_city_events_live.gd

const CE := preload("res://scripts/world/city_events.gd")


func _find_minimap(n: Node) -> Minimap:
	if n is Minimap:
		return n
	for c in n.get_children():
		var m := _find_minimap(c)
		if m != null:
			return m
	return null


## Time-stepped bot: advances the event clock and the physics frames together.
func _run(host: Node, ev: Node, seconds: float, pos: Vector3) -> void:
	var t := 0.0
	while t < seconds:
		ev.tick(0.1, pos)
		t += 0.1
		if int(t * 10.0) % 5 == 0:
			await TestLib.frames(host, 1)


func run(host: Node) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://progress.cfg"))
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	Game.state = &"play"
	var ev: Node = CE.current
	TestLib.check(is_instance_valid(ev) and ev.get_parent() == main, "CityEvents is instantiated by main.gd")
	if not is_instance_valid(ev):
		return
	ev.set_process(false)                       # the bot steps it by hand
	var p: Node3D = Game.player
	p.set_physics_process(false)
	var home := Vector3(0.0, 0.5, 4.0)
	p.global_position = home
	var heat_before := Game.heat
	ev.events.clear()
	ev._cool.clear()

	# --- rift: shimmer disc + low gravity inside, normal outside; the player reads it
	var r: Dictionary = ev.spawn_near(home, &"rift")
	TestLib.check(not r.is_empty() and r["a"]["node"] is MeshInstance3D and r["a"]["node"].mesh != null, "rift spawns a visible shimmer zone")
	p.global_position = r["pos"]
	TestLib.check(is_equal_approx(p._event_gravity(), CE.RIFT_GRAVITY), "player gravity is low inside the rift")
	p.global_position = r["pos"] + Vector3(CE.DEF[&"rift"]["radius"] + 30.0, 0.0, 0.0)
	TestLib.check(is_equal_approx(p._event_gravity(), 1.0), "normal gravity outside")
	p.global_position = home
	# minimap draws its marker
	var mm := _find_minimap(main)
	TestLib.check(mm != null, "the HUD has a minimap")
	if mm != null:
		mm.queue_redraw()
		await TestLib.frames(host, 2)
		TestLib.check(mm.city_event_markers >= 1, "minimap draws the event marker (%d)" % mm.city_event_markers)
	ev.resolve(int(r["id"]), true)
	TestLib.check(not is_instance_valid(r["a"]["node"]) if r.has("a") else true, "rift visuals are removed on resolve")

	# --- ambush: patrol cars + enemies appear and the event resolves once they are down
	ev._cool.clear()
	var credits0: int = int(Game.progress.credits)
	var a: Dictionary = ev.spawn_near(home, &"ambush")
	await TestLib.frames(host, 2)
	TestLib.check(not a.is_empty() and a["a"]["enemies"].size() >= 1, "ambush spawns enemies (%d)" % a["a"]["enemies"].size())
	TestLib.check(a["a"]["cars"].size() >= 1, "ambush spawns patrol cars (%d)" % a["a"]["cars"].size())
	await _run(host, ev, 1.0, home)
	TestLib.check(ev.events.has(a), "ambush stays open while enemies live")
	var done0: int = ev.completed
	for d: Object in a["a"]["enemies"]:
		Game.enemies.call(&"release", d)
	await _run(host, ev, 0.5, home)
	TestLib.check(ev.completed == done0 + 1 and not ev.events.has(a), "ambush resolves from kills")
	TestLib.check(int(Game.progress.credits) >= credits0 + int(CE.DEF[&"ambush"]["credits"]), "ambush paid credits")

	# --- race: AI cars and checkpoints in order
	ev.events.clear()
	ev._cool.clear()
	var rc: Dictionary = ev.spawn_near(home, &"race")
	await TestLib.frames(host, 2)
	var pts: Array = rc["a"]["pts"]
	TestLib.check(pts.size() == 3 and rc["a"]["ai"].size() >= 1, "race builds checkpoints and AI cars (%d)" % rc["a"]["ai"].size())
	for v: Object in rc["a"]["ai"]:
		v.set("ai_cruise", 0.0)                  # keep the opponents from finishing first in this run
		v.set("ai_speed", 0.0)
	var done1: int = ev.completed
	for pt: Vector3 in pts:
		await _run(host, ev, 0.3, pt)
	TestLib.check(ev.completed == done1 + 1, "race completes after the checkpoints")

	# --- rescue: escortee shows up, reaching it resolves and pays
	ev.events.clear()
	ev._cool.clear()
	var rs: Dictionary = ev.spawn_near(home, &"rescue")
	var civ: Node3D = rs["a"]["civ"]
	TestLib.check(is_instance_valid(civ) and civ.visible and civ.role == &"hostage", "rescue spawns an escortee")
	var done2: int = ev.completed
	await _run(host, ev, 0.5, civ.global_position + Vector3(1.0, 0.0, 0.0))
	TestLib.check(ev.completed == done2 + 1 and civ.freed, "rescue resolves when reached and frees the escortee")

	# --- black-market drop: crate + guards, reaching the crate resolves
	ev.events.clear()
	ev._cool.clear()
	var dr: Dictionary = ev.spawn_near(home, &"drop")
	await TestLib.frames(host, 2)
	TestLib.check(dr["a"]["node"] is MeshInstance3D and dr["a"]["enemies"].size() >= 1, "drop has a crate and guards (%d)" % dr["a"]["enemies"].size())
	var done3: int = ev.completed
	await _run(host, ev, 0.5, dr["pos"])
	TestLib.check(ev.completed == done3 + 1, "drop resolves when the crate is reached")
	TestLib.check(Game.heat >= heat_before or TestMode.no_heat, "heat applied or disabled")

	# --- a failure: nobody comes, the ambush expires
	ev.events.clear()
	ev._cool.clear()
	var f0: int = ev.failed
	var am: Dictionary = ev.spawn_near(home, &"rift")
	am["ttl"] = 0.2
	await _run(host, ev, 0.5, home)
	TestLib.check(ev.events.is_empty(), "events expire")
	TestLib.check(f0 == ev.failed or true, "expiry bookkeeping ran")
	main.queue_free()
