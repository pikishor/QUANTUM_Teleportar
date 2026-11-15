extends RefCounted
## Dev probe (wave 115 PLAY critic, not a test): the ten snake VERBS against LIVE enemies. The builders' test stages dummies (physics off, a million hit points, they cannot move or die); here the enemies are real
## (aware, shooting, moving, dying), the hero is in god mode, the verb is armed and fired like a thumb does it (FIRE), and after 7 s every enemy and every hold is checked: finite position, not under the
## street, holds expired, snakes gone, no script error. One line per verb x enemy type.
## env VB_TYPES ("operative,brute,heavy,sentinel,flanker"), VB_VERBS (default all ten), VB_SECS (7), VB_K (time scale, 3)
## Run: scratchpad/run_probe.sh tests/dev_w115p_verbs.gd 560 "^VB"

const TIMEOUT_SECONDS := 560.0

var host: Node
var p: Player
var war: SnakeWar
var _spot := Vector3.ZERO
var _yaw := 0.0


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _right() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


func _lane() -> bool:
	var city := Game.world as City
	var space := p.get_world_3d().direct_space_state
	for tries in 600:
		var rp: Vector3 = city.random_core_road_point()
		if not rp.is_finite():
			continue
		for k in 8:
			var yaw := TAU * float(k) / 8.0
			var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var a := rp + Vector3(0, 1.5, 0)
			var ok := true
			for off in [-5.0, 0.0, 5.0]:
				var side := dir.cross(Vector3.UP) * float(off)
				var q := PhysicsRayQueryParameters3D.create(a + side, a + side + dir * 64.0, Game.L_WORLD | Game.L_VEHICLE)
				if not space.intersect_ray(q).is_empty():
					ok = false
					break
			if ok:
				_spot = rp
				_yaw = yaw
				return true
	return false


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	SnakeWarMissions.reset_flags()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	war = SnakeWar.of(p)
	if Encounters.current != null:
		Encounters.current.enabled = false
	TrafficField.bare_street()
	Game.state = &"play"
	TestMode.god = true
	WeaponDefs.hero_mode = true                                     # every verb open, no energy, no cooldown: the probe is about the verbs against live enemies
	Difficulty.set_mode(1)
	if not _lane():
		print("VB no open lane")
		return
	var k := float(int(OS.get_environment("VB_K")) if OS.get_environment("VB_K") != "" else 3)
	Engine.time_scale = k
	Engine.physics_ticks_per_second = int(60.0 * k)
	var types_s := OS.get_environment("VB_TYPES") if OS.get_environment("VB_TYPES") != "" else "operative,brute,heavy,sentinel,flanker"
	var verbs_s := OS.get_environment("VB_VERBS")
	var verbs: Array[StringName] = []
	for v in (verbs_s.split(",", false) if verbs_s != "" else PackedStringArray(["sv_pull", "sv_grab", "sv_disarm", "sv_net", "sv_lash", "sv_trap", "sv_guard", "sv_decoy", "sv_shield", "sv_yank"])):
		verbs.append(StringName(v))
	var secs := float(OS.get_environment("VB_SECS")) if OS.get_environment("VB_SECS") != "" else 7.0
	var bad := 0
	var total := 0
	await frames(5)
	for tn in types_s.split(",", false):
		for vid in verbs:
			total += 1
			var line := await _trial(StringName(tn), vid, secs)
			if line.begins_with("BAD"):
				bad += 1
			print("VB %-9s %-10s %s" % [tn, str(vid), line])
	print("VB SUMMARY %d trials, %d with a problem" % [total, bad])
	for l in Dev.error_lines():
		print("VB ERRLINE ", l)
	WeaponDefs.hero_mode = false
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	main.queue_free()
	await frames(3)


func _trial(type: StringName, vid: StringName, secs: float) -> String:
	Input.action_release(&"fire")
	Input.action_release(&"altfire")
	var sw := SnakeSwarm.current
	if sw != null:
		sw.clear()
	war.reset()
	war.disarm()
	if SnakeTendrilPool.current != null:
		SnakeTendrilPool.current.clear()
	var ops := BlastOps.shared(p.get_tree())
	ops.reset()
	(Game.enemies as EnemyManager).clear()
	p.invuln = 0.0
	p.hp = p.max_hp
	p.teleport_to(_spot)
	p.camera_rig.reset_view(_yaw, -0.04)
	p.yaw = _yaw
	p.velocity = Vector3.ZERO
	p.snake.cancel()
	p.snake.jam_t = 0.0
	var em := Game.enemies as EnemyManager
	var foes: Array[Drone] = []
	for i in 3:
		var base_d := 5.0 if vid == &"sv_lash" else 11.0                       # the lash reaches 7.5 m
		var pos := _spot + _dir() * (base_d + 1.6 * float(i)) + _right() * (float(i - 1) * 2.4)
		pos.y = _spot.y
		var f := em.spawn(type, pos, true)
		if f != null:
			foes.append(f)
	var spawned := foes.size()
	if spawned == 0:
		return "no enemy of that type spawned"
	var car: Node3D = null
	if vid == &"sv_yank":
		var vm := Game.vehicles as VehicleManager
		vm._reset_all()
		car = vm.spawn_parked(&"sedan", _spot + _dir() * 8.0 + _right() * 4.0, _yaw + PI * 0.5)
	await frames(10)
	var e0 := Dev.errors.total
	war.arm(vid)
	var t := 0.0
	var clock0 := p.snake.time
	var last := p.snake.time
	var fired := 0
	var hp0 := 0.0
	for f in foes:
		hp0 += f.hp
	var casts0 := war.casts
	var whiff0 := war.whiffs
	var tracked_hold := false
	var rec_max := 0
	var swarm_peak := 0
	var low_y := 1.0e9
	var nan_seen := false
	while t < secs:
		await frames(1)
		t = p.snake.time - clock0
		var dt := p.snake.time - last
		last = p.snake.time
		if dt <= 0.0:
			continue
		# aim at the nearest live foe; fire (a tap, or a hold of 1.2 s then release for GRAB) every 1.3 s during the first 4 s
		var best: Drone = null
		var bd := 1.0e9
		for f in foes:
			if is_instance_valid(f) and f.active and not f.dead:
				var d := f.global_position.distance_to(p.global_position)
				if d < bd:
					bd = d
					best = f
		if best != null:
			p.camera_rig.aim_at(SnakeAim.center_of(best))
		var phase := fmod(t, 1.4)
		if t < 4.2 and war.armed != &"":
			var hold_len := 1.1 if vid == &"sv_grab" or vid == &"sv_lash" else 0.12
			if phase < hold_len:
				Input.action_press(&"fire")
			else:
				Input.action_release(&"fire")
		else:
			Input.action_release(&"fire")
		rec_max = maxi(rec_max, war.holds.recs.size())
		if sw != null:
			swarm_peak = maxi(swarm_peak, sw.count())
		for f in foes:
			if is_instance_valid(f):
				if not f.global_position.is_finite():
					nan_seen = true
				else:
					low_y = minf(low_y, f.global_position.y)
	Input.action_release(&"fire")
	await frames(60 * 5)                                             # five more seconds: nothing may still be held or drawn after that
	var alive := 0
	var dead := 0
	var hp1 := 0.0
	var held_left := 0
	var gone := 0
	for f in foes:
		if not is_instance_valid(f):
			gone += 1
		elif f.dead or not f.active:
			dead += 1
		else:
			alive += 1
			hp1 += f.hp
	for key: Variant in war.holds.recs.keys():
		held_left += 1
	var errs := Dev.errors.total - e0
	var problems: Array[String] = []
	if nan_seen:
		problems.append("an enemy had a non-finite position")
	if low_y < -2.0 and vid != &"sv_decoy":
		problems.append("an enemy sank to y %.1f" % low_y)
	if held_left > 0:
		problems.append("%d holds still alive 5 s after the last fire" % held_left)
	if errs > 0:
		problems.append("%d script errors" % errs)
	if war.casts == casts0 and vid != &"sv_yank":
		problems.append("nothing was cast (whiffs %d)" % (war.whiffs - whiff0))
	var tail := "casts %d whiffs %d | spawned %d alive %d dead %d freed %d | hp %.0f -> %.0f | holds peak %d, left %d | snakes peak %d, now %d | lowest y %.1f" % [war.casts - casts0, war.whiffs - whiff0, spawned, alive, dead, gone, hp0, hp1, rec_max, held_left, swarm_peak, sw.count() if sw != null else 0, low_y]
	war.disarm()
	return ("BAD  " + "; ".join(problems) + " | " + tail) if not problems.is_empty() else ("ok   " + tail)
