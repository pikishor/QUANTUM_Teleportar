extends RefCounted
## Dev probe (wave 115 PLAY critic, not a test): a MONKEY on the snake buttons. Random thumbs (taps of 0.05 to 0.25 s, holds, JUMP, FLY, the stick, the camera) from random streets, roofs and
## mid-air spots of the real city, god mode on. Every physics tick is checked: finite position and velocity, inside the world, not embedded in a building (the capsule overlaps the world layer),
## not in one snake state for an absurd time, and every script error is listed. Prints one line per episode and a summary.
## env MK_N (episodes, 16), MK_SECS (game seconds per episode, 20), MK_SEED, MK_DIFF (0..3, 1), MK_K (time scale, 3), MK_TRAFFIC=1 (keep the cars), MK_START (street|roof|air|mixed)
## Run: scratchpad/run_probe.sh tests/dev_w115p_monkey.gd 560 "^MK"

const TIMEOUT_SECONDS := 560.0

var host: Node
var p: Player
var sn: SnakeTraversal
var rng := RandomNumberGenerator.new()
var _caps := CapsuleShape3D.new()
var _q := PhysicsShapeQueryParameters3D.new()
var anomalies: Array[String] = []
var embedded_ticks := 0
var embedded_eps := 0
var nan_ticks := 0
var fell := 0
var mode_time := {"none": 0.0, "swing": 0.0, "zip": 0.0, "climb": 0.0, "fly": 0.0}
var mode_run := 0.0
var last_mode := &"none"
var long_modes := {}
var _ep := 0
var _ep_emb := 0
var _max_speed := 0.0
var _max_jerk := 0.0
var _prev_v := Vector3.ZERO
var _jerk_events := 0


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func release_all() -> void:
	for a in [&"snake", &"fly", &"jump", &"move_forward", &"move_back", &"move_left", &"move_right", &"crouch", &"sprint", &"fire", &"swap", &"altfire"]:
		Input.action_release(a)


func _embedded() -> bool:
	_caps.radius = Player.CAPSULE_RADIUS - 0.1
	_caps.height = Player.CAPSULE_HEIGHT - 0.25
	_q.shape = _caps
	_q.transform = Transform3D(Basis.IDENTITY, p.global_position + Vector3(0.0, Player.CAPSULE_HEIGHT * 0.5, 0.0))
	_q.collision_mask = Game.L_WORLD
	_q.margin = 0.0
	return not p.get_world_3d().direct_space_state.intersect_shape(_q, 1).is_empty()


func _check_tick() -> void:
	var pos := p.global_position
	var v := p.velocity
	if not pos.is_finite() or not v.is_finite():
		nan_ticks += 1
		if nan_ticks == 1:
			anomalies.append("ep %d: non-finite position or velocity in mode %s" % [_ep, sn.mode_name()])
		return
	if pos.y < -4.0:
		fell += 1
		anomalies.append("ep %d: fell out of the world to y %.1f (mode %s)" % [_ep, pos.y, sn.mode_name()])
		p.teleport_to(Vector3(0.0, 1.0, 0.0))
	_max_speed = maxf(_max_speed, v.length())
	var m := sn.mode_name()
	var dt := 1.0 / 60.0
	mode_time[str(m)] = float(mode_time.get(str(m), 0.0)) + dt
	if m == last_mode:
		mode_run += dt
	else:
		mode_run = 0.0
		last_mode = m
	var limit: float = float({"swing": 9.0, "zip": 3.5, "climb": 90.0, "fly": 120.0}.get(str(m), 1.0e9))
	if mode_run > limit and not long_modes.has("%d:%s" % [_ep, str(m)]):
		long_modes["%d:%s" % [_ep, str(m)]] = true
		anomalies.append("ep %d: mode %s lasted %.1f s (limit %.0f) at %s" % [_ep, str(m), mode_run, float(limit), str(pos.snapped(Vector3(0.1, 0.1, 0.1)))])
	if _embedded():
		embedded_ticks += 1
		_ep_emb += 1
		if _ep_emb == 20:                                                    # 1/3 s inside a building: report once per episode
			anomalies.append("ep %d: EMBEDDED in a building for 20 ticks, mode %s at %s, v %.1f" % [_ep, sn.mode_name(), str(pos.snapped(Vector3(0.1, 0.1, 0.1))), v.length()])


func _random_start(city: City, kind: String) -> Vector3:
	var rp := city.random_core_road_point()
	match kind:
		"roof":
			var roofs := SnakeMissions.roofs(rp, 10.0, 160.0, 26.0, 120.0)
			if not roofs.is_empty():
				var r: Dictionary = roofs[rng.randi() % mini(roofs.size(), 8)]
				var pr: Vector3 = r["pos"]
				return pr + Vector3(0.0, 0.5, 0.0)
		"air":
			return rp + Vector3(0.0, rng.randf_range(30.0, 70.0), 0.0)
	return rp


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	SnakeMissions.reset_flags()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	sn = p.snake
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	if OS.get_environment("MK_TRAFFIC") != "1":
		TrafficField.bare_street()
	Game.state = &"play"
	TestMode.god = true
	var city := Game.world as City
	city.collision_chunks().activate_all()
	var k := float(int(OS.get_environment("MK_K")) if OS.get_environment("MK_K") != "" else 3)
	Engine.time_scale = k
	Engine.physics_ticks_per_second = int(60.0 * k)
	var n := int(OS.get_environment("MK_N")) if OS.get_environment("MK_N") != "" else 16
	var secs := float(OS.get_environment("MK_SECS")) if OS.get_environment("MK_SECS") != "" else 20.0
	var diff := int(OS.get_environment("MK_DIFF")) if OS.get_environment("MK_DIFF") != "" else 1
	rng.seed = int(OS.get_environment("MK_SEED")) if OS.get_environment("MK_SEED") != "" else 5
	var start_kind := OS.get_environment("MK_START") if OS.get_environment("MK_START") != "" else "mixed"
	Difficulty.set_mode(diff)
	SnakeTraversal.assist = true
	await frames(5)
	var err0 := Dev.errors.total
	print("MK start: episodes %d x %.0f s, difficulty %d, start %s, k %.0f" % [n, secs, diff, start_kind, k])
	for ep in n:
		_ep = ep
		_ep_emb = 0
		var kind := start_kind
		if kind == "mixed":
			kind = ["street", "roof", "air", "roof", "air"][ep % 5]
		release_all()
		sn.cancel()
		p.invuln = 0.0
		p.hp = p.max_hp
		sn.energy = SnakePower.max_energy()
		var sp := _random_start(city, kind)
		p.teleport_to(sp)
		var yaw := rng.randf() * TAU
		p.camera_rig.reset_view(yaw, rng.randf_range(-0.1, 0.4))
		p.yaw = yaw
		await frames(8)
		var combat := OS.get_environment("MK_COMBAT") == "1"
		var war := SnakeWar.of(p)
		if combat:
			(Game.enemies as EnemyManager).clear()
			war.reset()
			for ei in 5:
				var ang := rng.randf() * TAU
				var epos := p.global_position + Vector3(cos(ang), 0.0, sin(ang)) * rng.randf_range(8.0, 22.0)
				(Game.enemies as EnemyManager).spawn([&"operative", &"flanker", &"sentinel", &"brute", &"heavy"][ei % 5], epos, true)
		var s0 := sn.swings
		var z0 := sn.zips
		var c0 := sn.climbs
		var f0 := sn.flights
		var m0 := sn.flight.crashes
		var e0 := Dev.errors.total
		# the monkey's script: next-change times of each input
		var t := 0.0
		var next := {"snake": 0.0, "fly": rng.randf_range(1.0, 5.0), "jump": rng.randf_range(0.2, 2.0), "stick": 0.0, "look": 0.0, "crouch": 3.0, "arm": rng.randf_range(1.0, 4.0), "fire": rng.randf_range(0.5, 2.0), "swap": rng.randf_range(4.0, 9.0), "alt": rng.randf_range(2.0, 6.0)}
		var release_at := {}
		var look_rate := Vector2.ZERO
		var clock0 := sn.time
		var last_clock := sn.time
		_max_speed = 0.0
		while t < secs:
			await frames(1)
			t = sn.time - clock0
			var dt := sn.time - last_clock
			last_clock = sn.time
			if dt <= 0.0:
				continue
			_check_tick()
			# the thumbs
			for a: StringName in release_at.keys():
				if t >= float(release_at[a]):
					Input.action_release(a)
					release_at.erase(a)
			if t >= float(next["snake"]):
				var hold := rng.randf_range(0.05, 0.25) if rng.randf() < 0.45 else rng.randf_range(0.4, 4.0)
				Input.action_press(&"snake")
				release_at[&"snake"] = t + hold
				next["snake"] = t + hold + rng.randf_range(0.1, 1.6)
			if t >= float(next["fly"]):
				Input.action_press(&"fly")
				release_at[&"fly"] = t + rng.randf_range(0.05, 0.3)
				next["fly"] = t + rng.randf_range(2.0, 9.0)
			if t >= float(next["jump"]):
				Input.action_press(&"jump")
				release_at[&"jump"] = t + (rng.randf_range(0.05, 0.2) if rng.randf() < 0.7 else rng.randf_range(0.3, 1.2))
				next["jump"] = t + rng.randf_range(0.3, 3.0)
			if t >= float(next["crouch"]):
				Input.action_press(&"crouch")
				release_at[&"crouch"] = t + rng.randf_range(0.2, 1.5)
				next["crouch"] = t + rng.randf_range(4.0, 12.0)
			if t >= float(next["stick"]):
				for a in [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint"]:
					Input.action_release(a)
				var r := rng.randf()
				if r < 0.65:
					Input.action_press(&"move_forward")
				elif r < 0.75:
					Input.action_press(&"move_back")
				if rng.randf() < 0.3:
					Input.action_press(&"move_left" if rng.randf() < 0.5 else &"move_right")
				if rng.randf() < 0.5:
					Input.action_press(&"sprint")
				next["stick"] = t + rng.randf_range(0.4, 2.5)
			if t >= float(next["look"]):
				look_rate = Vector2(rng.randf_range(-1.6, 1.6) if rng.randf() < 0.7 else 0.0, rng.randf_range(-0.5, 0.5))
				next["look"] = t + rng.randf_range(0.3, 2.0)
			p.camera_rig.add_look(look_rate.x * dt, look_rate.y * dt)
			if combat:
				if t >= float(next["arm"]):
					var ids := SnakeRows.ids()
					war.arm(ids[rng.randi() % ids.size()])
					next["arm"] = t + rng.randf_range(1.5, 6.0)
				if t >= float(next["fire"]):
					Input.action_press(&"fire")
					release_at[&"fire"] = t + (rng.randf_range(0.05, 0.3) if rng.randf() < 0.6 else rng.randf_range(0.5, 2.0))
					next["fire"] = t + rng.randf_range(0.4, 2.5)
				if t >= float(next["swap"]):
					Input.action_press(&"swap")
					release_at[&"swap"] = t + 0.08
					next["swap"] = t + rng.randf_range(4.0, 12.0)
				if t >= float(next["alt"]):
					Input.action_press(&"altfire")
					release_at[&"altfire"] = t + 0.1
					next["alt"] = t + rng.randf_range(2.0, 7.0)
				# aim at the nearest live enemy now and then (the snake verbs need a target)
				if int(t * 4.0) % 5 == 0:
					var best: Node3D = null
					var bd := 1.0e9
					for e in (Game.enemies as EnemyManager).get_children():
						if e is Drone and is_instance_valid(e) and (e as Drone).active and not (e as Drone).dead:
							var d := (e as Node3D).global_position.distance_to(p.global_position)
							if d < bd:
								bd = d
								best = e as Node3D
					if best != null and rng.randf() < 0.6:
						p.camera_rig.aim_at(SnakeAim.center_of(best))
		release_all()
		await frames(10)
		var errs := Dev.errors.total - e0
		print("MK ep %2d %-6s: swings %2d zips %2d climbs %2d flights %2d crashes %d, top speed %.0f m/s, embedded ticks %d, errors %d, hp %.0f, ended %s" % [ep, kind, sn.swings - s0, sn.zips - z0, sn.climbs - c0, sn.flights - f0, sn.flight.crashes - m0, _max_speed, _ep_emb, errs, p.hp, sn.mode_name()])
		if _ep_emb > 0:
			embedded_eps += 1
	release_all()
	var errs_total := Dev.errors.total - err0
	for a in anomalies:
		print("MK ANOMALY ", a)
	if errs_total > 0:
		for line in Dev.error_lines():
			print("MK ERRLINE ", line)
	var times := ""
	for key in mode_time:
		times += " %s %.0f s" % [key, float(mode_time[key])]
	print("MK SUMMARY episodes %d: embedded episodes %d (%d ticks), non-finite ticks %d, fell %d, anomalies %d, script errors %d, time in modes:%s" % [n, embedded_eps, embedded_ticks, nan_ticks, fell, anomalies.size(), errs_total, times])
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	main.queue_free()
	await frames(3)
