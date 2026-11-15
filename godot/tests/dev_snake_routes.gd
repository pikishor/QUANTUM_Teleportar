extends RefCounted
## Dev probe (not a test): how reliable is the swing chain over MANY routes of the real city? Each trial drops the hero 40 m above a random core road point, SNAKE held, assist on, and counts
## swings, metres flown, ground touches and flights. A trial passes like the swing run test: >= 5 swings, >= 400 m, no ground in the first five swings (within 30 s).
##   env SR_K (time scale, default 4: four physics ticks of 1/60 s per frame)  SR_N (trials, default 8)  SR_DIFF (difficulty 0..3, default 1)  SR_SEED  SR_REEL=0 (clearance reel and anchor filter off)  SR_PEN (reel penalty of the finder)  SR_SECS (per trial, 30)
## Run: tools/test.sh tests/dev_snake_routes.gd

const TIMEOUT_SECONDS := 580.0

var host: Node
var p: Player


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	Game.state = &"play"
	TestMode.god = true
	var n := int(OS.get_environment("SR_N")) if OS.get_environment("SR_N") != "" else 8
	var diff := int(OS.get_environment("SR_DIFF")) if OS.get_environment("SR_DIFF") != "" else 1
	var secs := float(OS.get_environment("SR_SECS")) if OS.get_environment("SR_SECS") != "" else 30.0
	var k_scale := float(OS.get_environment("SR_K")) if OS.get_environment("SR_K") != "" else 1.0
	Engine.time_scale = k_scale
	Engine.physics_ticks_per_second = int(60.0 * k_scale)
	seed(int(OS.get_environment("SR_SEED")) if OS.get_environment("SR_SEED") != "" else 7)
	Difficulty.set_mode(diff)
	SnakeTraversal.assist = true
	SnakeSwing.reel_on = OS.get_environment("SR_REEL") != "0"
	if OS.get_environment("SR_LRB") != "":
		SnakeAnchors.long_rope_bonus = float(OS.get_environment("SR_LRB"))
	if OS.get_environment("SR_PEN") != "":
		SnakeAnchors.reel_penalty = float(OS.get_environment("SR_PEN"))
	if OS.get_environment("SR_BARE") == "1":
		TrafficField.bare_street()
	var city := Game.world as City
	var sn := p.snake
	var ok_count := 0
	var total_swings := 0
	var total_path := 0.0
	print("SR start: trials %d diff %d reel %s penalty %.3f secs %.0f" % [n, diff, str(SnakeSwing.reel_on), SnakeAnchors.reel_penalty, secs])
	for i in n:
		var rp := Vector3.ZERO
		var yaw := 0.0
		var fixed := OS.get_environment("SR_FIXED")                        # "x,z,yaw": the same route every trial (the swing run test's own)
		for tries in (1 if fixed != "" else 40):                           # only starts with an anchor in reach count: the outskirts have no tall buildings to swing from
			if fixed != "":
				var fp := fixed.split(",")
				rp = Vector3(float(fp[0]), 0.0, float(fp[1]))
				yaw = float(fp[2])
				break
			rp = city.random_core_road_point()
			yaw = float(randi() % 4) * PI * 0.5
			var o := rp + Vector3(0.0, 41.5, 0.0)
			var head := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var probe := sn.anchors.find_swing(p, head, head, SnakePower.range_m(), true, o, true)
			if not probe.is_empty():
				break
		Input.action_release(&"snake")
		sn.cancel()
		p.invuln = 0.0
		p.teleport_to(rp + Vector3(0.0, 40.0, 0.0))
		await frames(2)
		p.camera_rig.reset_view(yaw, 0.2)
		p.yaw = yaw
		await frames(4)
		sn.energy = SnakePower.max_energy()
		var s0 := sn.swings
		sn.swing.log.clear()
		var f0 := sn.flights
		var path := 0.0
		var ground := false
		var last := p.global_position
		var chained := false
		var t := 0.0
		var prev_armed := 0.0
		var tail: Array[String] = []
		var dumped := false
		Input.action_press(&"snake")
		if OS.get_environment("SR_FWD") == "1":
			Input.action_press(&"move_forward")
		while t < secs:
			await frames(1)
			t += k_scale / 60.0
			var pos := p.global_position
			if sn.swings > s0:
				path += Vector2(pos.x - last.x, pos.z - last.z).length()
				chained = true
				if p.is_on_floor() and sn.mode != SnakeTraversal.Mode.SWING and sn.swings - s0 < 5:
					ground = true
			last = pos
			if sn.mode == SnakeTraversal.Mode.NONE and chained and sn._chain_armed <= 0.0 and prev_armed > 0.0 and not p.is_on_floor():
				print("SR   giveup t=%.1f swings %d pos (%.0f %.0f %.0f) v (%.0f %.0f %.0f) stats %s rays %d" % [t, sn.swings - s0, pos.x, pos.y, pos.z, p.velocity.x, p.velocity.y, p.velocity.z, str(sn.anchors.stats), sn.anchors.rays])
			prev_armed = sn._chain_armed
			if sn.mode == SnakeTraversal.Mode.NONE and chained and not p.is_on_floor() and int(t * 60.0) % 12 == 0:
				tail.append("t=%.1f y=%.0f vy=%.0f sp=%.0f armed=%.1f since=%.1f cd=%.2f hold=%s stats=%s rays=%d" % [t, pos.y, p.velocity.y, p.velocity.length(), sn._chain_armed, sn._since_release, sn.swing_cd, str(Input.is_action_pressed(&"snake")), str(sn.anchors.stats), sn.anchors.rays])
				if tail.size() > 7:
					tail.pop_front()
			if ground and not dumped:
				dumped = true
				for line in tail:
					print("SR   tail ", line)
			if sn.swings - s0 >= 7 and path > 520.0:
				break
			if chained and p.is_on_floor() and sn.mode == SnakeTraversal.Mode.NONE and sn.swings - s0 >= 5:
				break
		Input.action_release(&"snake")
		Input.action_release(&"move_forward")
		var k := sn.swings - s0
		var ok := k >= 5 and path >= 400.0 and not ground
		ok_count += 1 if ok else 0
		total_swings += k
		total_path += path
		var whys := ""
		for e: Dictionary in sn.swing.log:
			whys += "%s(%.0f/%.0f) " % [String(e["why"]).substr(0, 4), float(e["rope"]), float(e["peak"])]
		print("SR trial %d: start (%.0f, %.0f) yaw %.2f  swings %d  path %.0f m  ground-in-first-5 %s  flights %d  %s   ends: %s" % [i, rp.x, rp.z, yaw, k, path, str(ground), sn.flights - f0, "OK" if ok else "FAIL", whys])
		sn.cancel()
		await frames(10)
	print("SR SUMMARY ok %d / %d  (mean swings %.1f, mean path %.0f m)" % [ok_count, n, float(total_swings) / float(n), total_path / float(n)])
	Input.action_release(&"snake")
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	SnakeSwing.reel_on = true
	SnakeAnchors.reel_penalty = 0.0
	Difficulty.set_mode(1)
	TestMode.god = false
	main.queue_free()
	await frames(3)
