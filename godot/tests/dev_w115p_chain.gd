extends RefCounted
## Dev probe (wave 115 PLAY critic, not a test): a 60 second SWING RUN from the STREET as a thumb would do it (jump, hold SNAKE, steer the camera along the avenue, tap SNAKE again on the ground),
## measured every physics tick and every rendered frame: position jumps, velocity jumps and reversals (jitter), the rope correction, the camera's distance to the hero, whether the lens sits behind a wall
## or inside one (camera clipping), the time on the street, the snake energy and the swing count. Prints one line per run and the ten worst events of each kind.
## env CH_N (runs, 3), CH_SECS (45), CH_DIFF (1), CH_K (time scale, 2), CH_SEED, CH_START (spawn|random), CH_TRAFFIC=1
## Run: scratchpad/run_probe.sh tests/dev_w115p_chain.gd 560 "^CH"

const TIMEOUT_SECONDS := 560.0

var host: Node
var p: Player
var sn: SnakeTraversal
var rng := RandomNumberGenerator.new()
var _prev_pos := Vector3.ZERO
var _prev_v := Vector3.ZERO
var _have_prev := false
var _pos_jumps: Array[String] = []
var _v_jumps: Array[String] = []
var _reversals: Array[String] = []
var _cam_blocked := 0
var _cam_inside := 0
var _cam_jumps: Array[String] = []
var _cam_jump_n := 0
var _cam_inside_real := 0
var _cam_through := 0
var _cam_frames := 0
var _cam_prev := Vector3.ZERO
var _cam_have := false
var _cam_min_d := 99.0
var _cam_max_d := 0.0
var _cam_events: Array[String] = []
var _t := 0.0
var _space: PhysicsDirectSpaceState3D
var _sphere := SphereShape3D.new()
var _sq := PhysicsShapeQueryParameters3D.new()
var _rq := PhysicsRayQueryParameters3D.new()
var _ticks := 0
var _ground_ticks := 0
var _mode_ticks := {}


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func release_all() -> void:
	for a in [&"snake", &"fly", &"jump", &"move_forward", &"move_back", &"move_left", &"move_right", &"crouch", &"sprint", &"fire"]:
		Input.action_release(a)


func _tick() -> void:
	var pos := p.global_position
	var v := p.velocity
	_ticks += 1
	if p.is_on_floor():
		_ground_ticks += 1
	var m := sn.mode_name()
	_mode_ticks[m] = int(_mode_ticks.get(m, 0)) + 1
	if _have_prev:
		var dpos := pos - _prev_pos
		var expect := _prev_v * (1.0 / 60.0)
		if dpos.length() > maxf(expect.length() * 2.5, 1.2) and sn.mode != SnakeTraversal.Mode.ZIP:
			_pos_jumps.append("t %.1f %s moved %.2f m in a tick (v %.1f m/s, expected %.2f m) at %s" % [_t, m, dpos.length(), v.length(), expect.length(), str(pos.snapped(Vector3(0.1, 0.1, 0.1)))])
		var dv := (v - _prev_v).length()
		if dv > 22.0 and sn.mode != SnakeTraversal.Mode.ZIP:
			_v_jumps.append("t %.1f %s dv %.1f m/s in one tick (%.1f -> %.1f) swing phase %s rope %.1f" % [_t, m, dv, _prev_v.length(), v.length(), str(sn.swing.phase), sn.swing.rope])
		if _prev_v.length() > 12.0 and v.length() > 12.0 and v.normalized().dot(_prev_v.normalized()) < -0.2:
			_reversals.append("t %.1f %s velocity reversed (dot %.2f) at %.1f m/s" % [_t, m, v.normalized().dot(_prev_v.normalized()), v.length()])
	_prev_pos = pos
	_prev_v = v
	_have_prev = true


## One rendered frame: the camera against the hero and the world.
func _cam_frame() -> void:
	var cam := p.camera_rig.camera
	if cam == null or not cam.is_inside_tree():
		return
	_cam_frames += 1
	var head := p.global_position + Vector3(0.0, 1.5, 0.0)
	var cp := cam.global_position
	var d := head.distance_to(cp)
	_cam_min_d = minf(_cam_min_d, d)
	_cam_max_d = maxf(_cam_max_d, d)
	_space = p.get_world_3d().direct_space_state
	_rq.from = head
	_rq.to = cp
	_rq.collision_mask = Game.L_WORLD
	_rq.exclude = [p.get_rid()]
	var hit := _space.intersect_ray(_rq)
	if not hit.is_empty() and head.distance_to(hit["position"] as Vector3) < d - 0.15:
		_cam_blocked += 1
		if _cam_events.size() < 12:
			_cam_events.append("t %.1f %s lens %.1f m from the head, wall %.1f m from the head (camera BEHIND a wall) at %s" % [_t, sn.mode_name(), d, head.distance_to(hit["position"] as Vector3), str(cp.snapped(Vector3(0.1, 0.1, 0.1)))])
	_sphere.radius = 0.12
	_sq.shape = _sphere
	_sq.transform = Transform3D(Basis.IDENTITY, cp)
	_sq.collision_mask = Game.L_WORLD
	if p.camera_rig.through_wall:
		_cam_through += 1
	if not _space.intersect_shape(_sq, 1).is_empty():
		_cam_inside += 1
		if not p.camera_rig.through_wall:
			_cam_inside_real += 1
			if _cam_events.size() < 12:
				_cam_events.append("t %.1f %s lens INSIDE a collider (not the designed through-the-facade case) at %s, hero %.1f m/s" % [_t, sn.mode_name(), str(cp.snapped(Vector3(0.1, 0.1, 0.1))), p.velocity.length()])
	if _cam_have:
		var jump := cp.distance_to(_cam_prev)
		var allow := p.velocity.length() * 0.05 + 1.2                      # up to ~50 ms of hero travel plus a margin
		if jump > allow:
			_cam_jump_n += 1
		if jump > allow and _cam_jumps.size() < 12:
			_cam_jumps.append("t %.1f %s lens moved %.2f m in a frame (hero %.1f m/s)" % [_t, sn.mode_name(), jump, p.velocity.length()])
	_cam_prev = cp
	_cam_have = true


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
	if OS.get_environment("CH_TRAFFIC") != "1":
		TrafficField.bare_street()
	Game.state = &"play"
	TestMode.god = true
	var city := Game.world as City
	city.collision_chunks().activate_all()
	var k := float(int(OS.get_environment("CH_K")) if OS.get_environment("CH_K") != "" else 2)
	Engine.time_scale = k
	Engine.physics_ticks_per_second = int(60.0 * k)
	var n := int(OS.get_environment("CH_N")) if OS.get_environment("CH_N") != "" else 3
	var secs := float(OS.get_environment("CH_SECS")) if OS.get_environment("CH_SECS") != "" else 45.0
	var diff := int(OS.get_environment("CH_DIFF")) if OS.get_environment("CH_DIFF") != "" else 1
	rng.seed = int(OS.get_environment("CH_SEED")) if OS.get_environment("CH_SEED") != "" else 9
	Difficulty.set_mode(diff)
	SnakeTraversal.assist = true
	var start_kind := OS.get_environment("CH_START") if OS.get_environment("CH_START") != "" else "random"
	await frames(5)
	host.get_tree().process_frame.connect(_cam_frame)
	print("CH start: runs %d x %.0f s, difficulty %d, start %s, k %.0f" % [n, secs, diff, start_kind, k])
	for run_i in n:
		release_all()
		sn.cancel()
		p.invuln = 0.0
		p.hp = p.max_hp
		sn.energy = SnakePower.max_energy()
		var sp := Game.SPAWN if (start_kind == "spawn" or (run_i == 0 and start_kind == "random")) else city.random_core_road_point()
		var yaw := rng.randf() * TAU if run_i > 0 else 0.0
		p.teleport_to(sp)
		p.camera_rig.reset_view(yaw, 0.15)
		p.yaw = yaw
		await frames(15)
		# reset the metrics
		_pos_jumps.clear()
		_v_jumps.clear()
		_reversals.clear()
		_cam_jumps.clear()
		_cam_events.clear()
		_cam_blocked = 0
		_cam_inside = 0
		_cam_inside_real = 0
		_cam_through = 0
		_cam_jump_n = 0
		_cam_frames = 0
		_cam_have = false
		_have_prev = false
		_cam_min_d = 99.0
		_cam_max_d = 0.0
		_ticks = 0
		_ground_ticks = 0
		_mode_ticks.clear()
		var s0 := sn.swings
		var z0 := sn.zips
		var c0 := sn.climbs
		var f0 := sn.flights
		var w0 := sn.whiffs
		var energy_min := 100.0
		var travelled := 0.0
		var last := p.global_position
		var first_swing_t := -1.0
		var t0 := sn.time
		var last_clock := sn.time
		var jumped := false
		var cur_yaw := yaw
		var steer_t := 0.0
		var steer_dir := 0.0
		while _t < secs:
			await frames(1)
			_t = sn.time - t0
			var dt := sn.time - last_clock
			last_clock = sn.time
			if dt <= 0.0:
				continue
			_tick()
			energy_min = minf(energy_min, sn.energy)
			travelled += p.global_position.distance_to(last)
			last = p.global_position
			if first_swing_t < 0.0 and sn.swings > s0:
				first_swing_t = _t
			# the thumb: on the ground tap JUMP once, then hold SNAKE in the air; on the ground again after a chain, jump and hold again
			if p.is_on_floor() and sn.mode == SnakeTraversal.Mode.NONE:
				Input.action_release(&"snake")
				if not jumped or _t > 0.0:
					Input.action_press(&"jump")
					Input.action_press(&"move_forward")
					jumped = true
			else:
				Input.action_release(&"jump")
				if p.air_time > 0.25 or sn.mode != SnakeTraversal.Mode.NONE:
					Input.action_press(&"snake")
			# steer: a slow random drift of the camera like a thumb nudging it (the view also leans after the direction of travel by itself)
			steer_t -= dt
			if steer_t <= 0.0:
				steer_dir = rng.randf_range(-0.5, 0.5)
				steer_t = rng.randf_range(1.0, 3.0)
			p.camera_rig.add_look(steer_dir * dt, 0.0)
		release_all()
		var t_str := ""
		for key in _mode_ticks:
			t_str += " %s %.0f%%" % [key, 100.0 * float(_mode_ticks[key]) / maxf(float(_ticks), 1.0)]
		print("CH run %d at %s: %.0f s, %d swings (first at %.1f s), zips %d, climbs %d, flights %d, whiffs %d, path %.0f m, street %.0f%% of the time, energy min %.0f, modes:%s" % [run_i, str(sp.snapped(Vector3(1, 1, 1))), _t, sn.swings - s0, first_swing_t, sn.zips - z0, sn.climbs - c0, sn.flights - f0, sn.whiffs - w0, travelled, 100.0 * float(_ground_ticks) / maxf(float(_ticks), 1.0), energy_min, t_str])
		print("CH    jitter: position jumps %d, velocity jumps %d, reversals %d | camera: %d frames, lens %.1f to %.1f m from the head, behind a wall %d, inside a collider %d (of which by design through a facade %d, real %d), lens jumps %d" % [_pos_jumps.size(), _v_jumps.size(), _reversals.size(), _cam_frames, _cam_min_d, _cam_max_d, _cam_blocked, _cam_inside, _cam_inside - _cam_inside_real, _cam_inside_real, _cam_jump_n])
		for l in _pos_jumps.slice(0, 6):
			print("CH      POS ", l)
		for l in _v_jumps.slice(0, 6):
			print("CH      DV ", l)
		for l in _reversals.slice(0, 4):
			print("CH      REV ", l)
		for l in _cam_events.slice(0, 6):
			print("CH      CAM ", l)
		for l in _cam_jumps.slice(0, 4):
			print("CH      CAMJ ", l)
		_t = 0.0
	host.get_tree().process_frame.disconnect(_cam_frame)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	main.queue_free()
	await frames(3)
