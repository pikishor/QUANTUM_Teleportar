extends RefCounted
## Dev probe (wave 115 PLAY critic, not a test): how many roof legs of the tutorial SWING ACROSS THE CITY have an anchor for the swing off the roof edge, with the old random pick of the next roof and with
## SnakeMissions._pick_swingable? Counts SnakeMissions.swing_possible (1 anchor, 0 none, -1 unknown) for the legs a -> b and b -> c of LG_N missions. env LG_N (default 40), LG_SEED.
## Run: scratchpad/run_probe.sh tests/dev_w115p_swingpick.gd 200 "^SP"

const TIMEOUT_SECONDS := 200.0

var host: Node


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	SnakeMissions.reset_flags()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	var p := Game.player as Player
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TrafficField.bare_street()
	Game.state = &"play"
	TestMode.god = true
	var city := Game.world as City
	city.collision_chunks().activate_all()
	await frames(6)
	seed(int(OS.get_environment("LG_SEED")) if OS.get_environment("LG_SEED") != "" else 7)
	var n := int(OS.get_environment("LG_N")) if OS.get_environment("LG_N") != "" else 40
	var old := [0, 0, 0]
	var neu := [0, 0, 0]
	var t0 := Time.get_ticks_usec()
	for mi in n:
		var origin := city.random_core_road_point()
		var o := Vector3(origin.x, 0.0, origin.z)
		var r0 := RandomNumberGenerator.new()
		r0.seed = 900 + mi
		var a := SnakeMissions._pick(SnakeMissions.roofs(o, 55.0, 120.0, 26.0, 70.0), r0)
		if a.is_empty():
			continue
		var used: Array = [a["pos"]]
		var list_b := SnakeMissions.roofs(a["pos"], 95.0, 160.0, 26.0, 90.0, used)
		var r1 := RandomNumberGenerator.new()
		r1.seed = 5000 + mi
		var r2 := RandomNumberGenerator.new()
		r2.seed = 5000 + mi
		var b_old := SnakeMissions._pick(list_b, r1)
		var b_new := SnakeMissions._pick_swingable(list_b, a["pos"], r2)
		if b_old.is_empty() or b_new.is_empty():
			continue
		var so := SnakeMissions.swing_possible(a["pos"], b_old["pos"])
		var sn_ := SnakeMissions.swing_possible(a["pos"], b_new["pos"])
		old[1 - so if so >= 0 else 2] += 1
		neu[1 - sn_ if sn_ >= 0 else 2] += 1
		print("SP mission %d: old %d new %d (%d candidates)" % [mi, so, sn_, mini(list_b.size(), 6)])
	print("SP SUMMARY legs a->b over %d missions: old pick  anchor %d none %d unknown %d | swingable pick  anchor %d none %d unknown %d | %.0f ms per leg pair" % [n, old[0], old[1], old[2], neu[0], neu[1], neu[2], float(Time.get_ticks_usec() - t0) / 1000.0 / float(maxi(n, 1))])
	TestMode.god = false
	main.queue_free()
	await frames(3)
