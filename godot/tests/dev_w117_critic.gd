extends RefCounted
## WAVE 117 CRITIC PROBE (not a test: it prints facts, it checks nothing). The real main scene, the phone HUD, real fingers only.
##   CR_PARTS=streets,hold0,hold1,hold2,early,relift,jump,wall,noanchor,ziproof,zipwall,fly  tools/test.sh tests/dev_w117_critic.gd
const TIMEOUT_SECONDS := 145
const Fingers := preload("res://tests/w116_fingers.gd")
const STREETS: Array = [[Vector3(-30.0, 0.0, 4.0), -PI * 0.5], [Vector3(-30.0, 0.0, 4.0), PI * 0.5], [Vector3(240.1, 0.0, -305.0), 0.0]]

var host: Node
var fg: Fingers
var p: Player
var sn: SnakeTraversal
var rec: Rec


class Rec extends Node:
	var p: Player
	var sn: SnakeTraversal
	var on := false
	var ticks := 0
	var floor_ticks := 0
	var min_h := 1.0e9
	var max_h := 0.0
	var max_step := 0.0
	var step_at := ""
	var max_speed := 0.0
	var walls := 0
	var modes := {}
	var trace: Array[String] = []
	var every := 6
	var start := Vector3.ZERO
	var max_acc := 0.0                 ## biggest change of velocity in one tick (m/s)
	var acc_at := ""
	var cam_in_wall := 0               ## ticks the line from the hero's chest to the camera crosses world geometry
	var hero_off := 0                  ## ticks the hero is not in the camera's view
	var _prev := Vector3.ZERO
	var _vprev := Vector3.ZERO
	var _rq := PhysicsRayQueryParameters3D.new()

	func begin() -> void:
		on = true
		ticks = 0
		floor_ticks = 0
		min_h = 1.0e9
		max_h = 0.0
		max_step = 0.0
		max_speed = 0.0
		max_acc = 0.0
		walls = 0
		cam_in_wall = 0
		hero_off = 0
		modes = {}
		trace = []
		start = p.global_position
		_prev = p.global_position
		_vprev = p.velocity

	func _physics_process(_dt: float) -> void:
		if not on or p == null:
			return
		var pos := p.global_position
		ticks += 1
		var step := pos.distance_to(_prev)
		if step > max_step:
			max_step = step
			step_at = "%s/%s/%s t%d" % [sn.mode_name(), sn.swing.phase, sn.zip.phase, ticks]
		var dv := (p.velocity - _vprev).length()
		if dv > max_acc:
			max_acc = dv
			acc_at = "%s/%s/%s t%d v %.1f->%.1f" % [sn.mode_name(), sn.swing.phase, sn.zip.phase, ticks, _vprev.length(), p.velocity.length()]
		_vprev = p.velocity
		max_speed = maxf(max_speed, p.velocity.length())
		if p.is_on_floor():
			floor_ticks += 1
		var space := p.get_world_3d().direct_space_state
		_rq.collision_mask = Game.L_WORLD
		_rq.exclude = [p.get_rid()]
		_rq.from = pos + Vector3(0.0, 0.6, 0.0)
		_rq.to = pos + Vector3(0.0, -200.0, 0.0)
		var g := space.intersect_ray(_rq)
		var h: float = (pos.y - (g["position"] as Vector3).y) if not g.is_empty() else 200.0
		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)
		if step > 0.02:
			_rq.from = _prev + Vector3(0.0, 1.0, 0.0)
			_rq.to = pos + Vector3(0.0, 1.0, 0.0)
			if not space.intersect_ray(_rq).is_empty():
				walls += 1
		var cam := p.get_viewport().get_camera_3d()
		if cam != null:
			_rq.from = pos + Vector3(0.0, 1.3, 0.0)
			_rq.to = cam.global_position
			if not space.intersect_ray(_rq).is_empty():
				cam_in_wall += 1
			if cam.is_position_behind(pos + Vector3(0.0, 1.0, 0.0)):
				hero_off += 1
			else:
				var sp := cam.unproject_position(pos + Vector3(0.0, 1.0, 0.0))
				var vs := p.get_viewport().get_visible_rect().size
				if sp.x < 0.0 or sp.y < 0.0 or sp.x > vs.x or sp.y > vs.y:
					hero_off += 1
		var m := "%s" % sn.mode_name()
		modes[m] = int(modes.get(m, 0)) + 1
		if ticks % every == 0:
			trace.append("%.1fs %s/%s%s pos(%.0f %.1f %.0f) h%.1f v%.1f vy%.1f rope%.0f ang%.2f" % [ticks / 60.0, m, sn.swing.phase if m == "swing" else (sn.zip.phase if m == "zip" else &"-"), " FLOOR" if p.is_on_floor() else "", pos.x, pos.y, pos.z, h, p.velocity.length(), p.velocity.y, sn.swing.rope, sn.swing.rope_angle])
		_prev = pos

	func line() -> String:
		return "ticks %d floor %d h %.1f..%.1f, biggest step %.2f (%s), biggest dv %.1f (%s), top %.1f m/s, walls %d, cam-through-wall ticks %d, hero off screen ticks %d, modes %s" % [ticks, floor_ticks, min_h, max_h, max_step, step_at, max_acc, acc_at, max_speed, walls, cam_in_wall, hero_off, modes]


func _f(n: int) -> void:
	await TestLib.frames(host, n)


func _until(cond: Callable, secs: float) -> bool:
	var n := int(secs * 60.0)
	for i in n:
		if cond.call():
			return true
		await host.get_tree().physics_frame
	return cond.call()


func _secs(s: float) -> void:
	for i in int(s * 60.0):
		await host.get_tree().physics_frame


func _tp(pos: Vector3, yaw: float, pitch: float) -> void:
	fg.up_all()
	await _f(2)
	sn.cancel()
	sn.reset()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await _f(30)


func _tap(finger: int, action: StringName, frames := 4) -> bool:
	if not fg.press(finger, action):
		return false
	await _f(frames)
	fg.up(finger)
	return true


func _state() -> String:
	return "mode %s pos %s v %.1f (vy %.1f) floor %s label %s roll %.2f" % [sn.mode_name(), p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), p.velocity.length(), p.velocity.y, p.is_on_floor(), fg.button_label(&"snake"), sn.roll_t]


func _whys(s0: int) -> Array:
	var out := []
	var n := mini(sn.swing.swings - s0, sn.swing.log.size())
	for k in range(sn.swing.log.size() - n, sn.swing.log.size()):
		var e: Dictionary = sn.swing.log[k]
		out.append("%s hang %.2fs rope %.0f dy %.0f ang %.2f rel %.0f" % [e["why"], e["hang"], e["rope"], e["dy"], e["angle"], e["rel"]])
	return out


func _first_rope() -> bool:
	for attempt in 3:
		await _tap(2, &"jump", 6)
		if await _until(func() -> bool: return not p.is_on_floor() and p.air_time > 0.12, 0.5):
			break
	fg.press(1, &"snake")
	return await _until(func() -> bool: return sn.swing.is_hanging(), 2.5)


func _dump(tag: String, n := 400) -> void:
	print("CR %s: %s" % [tag, rec.line()])
	var k := 0
	for l in rec.trace:
		if k >= n:
			break
		print("   ", l)
		k += 1


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _f(20)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	sn = p.snake
	fg = Fingers.new(host)
	rec = Rec.new()
	rec.p = p
	rec.sn = sn
	rec.process_physics_priority = 1000
	host.add_child(rec)
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	Difficulty.set_mode(1)
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = 3.0
	Engine.max_physics_steps_per_frame = 3
	var parts := (OS.get_environment("CR_PARTS") if OS.get_environment("CR_PARTS") != "" else "streets").split(",")
	for part in parts:
		print("CR ===== part ", part)
		match part:
			"streets": await _streets()
			"hold0": await _hold(0)
			"hold1": await _hold(1)
			"hold2": await _hold(2)
			"press0": await _press5(0)
			"press1": await _press5(1)
			"press2": await _press5(2)
			"early": await _early()
			"relift": await _relift()
			"jump": await _jump()
			"wall": await _wall()
			"noanchor": await _noanchor()
			"ziproof": await _zip(0.5)
			"zipwall": await _zip(0.2)
			"fly": await _fly()
			"ground": await _ground()
			"scan": await _scan()
			"wallg": await _wallg()
	fg.up_all()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	Game.force_touch = false
	CrateReveal._quiet = -1
	TestMode.god = false
	rec.queue_free()
	main.queue_free()
	await _f(2)


## Which way is a street? clear length of a ray 3 m up from candidate spots.
func _streets() -> void:
	var space := p.get_world_3d().direct_space_state
	for s: Vector3 in [Vector3(-30.0, 0.0, 4.0), Vector3(240.1, 0.0, -305.0), Vector3(100.0, 0.0, 100.0), Vector3(-200.0, 0.0, -150.0), Vector3(0.0, 0.0, -200.0)]:
		await _tp(s, 0.0, 0.1)
		var out := []
		for yaw: float in [0.0, PI * 0.5, PI, -PI * 0.5]:
			var d := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0.0, 3.0, 0.0), p.global_position + Vector3(0.0, 3.0, 0.0) + d * 300.0, Game.L_WORLD)
			var hit := space.intersect_ray(q)
			out.append("yaw %.2f clear %.0f" % [yaw, 300.0 if hit.is_empty() else (hit["position"] as Vector3).distance_to(q.from)])
		print("CR street spot ", s, " stands at ", p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), " ", out)


func _hold(i: int) -> void:
	var st: Array = STREETS[i]
	var yaw: float = st[1]
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	await _tp(st[0], yaw, 0.2)
	var s0 := sn.swing.swings
	var r0 := sn.landing_rolls
	var f0 := sn.flights
	var c0 := sn.climbs
	var ok := await _first_rope()
	rec.begin()
	await _secs(12.0)
	var d := p.global_position - rec.start
	print("CR hold%d after 12 s held: first rope %s, %d swings, net %.0f m along the look, %.1f m off line, %s" % [i, ok, sn.swing.swings - s0, d.dot(fwd), (d - fwd * d.dot(fwd)).length(), _state()])
	fg.up_all()
	await _until(func() -> bool: return p.is_on_floor() and sn.mode == SnakeTraversal.Mode.NONE, 8.0)
	await _secs(1.5)
	print("CR hold%d ends: %s rolls %d flights %d climbs %d; %s" % [i, _state(), sn.landing_rolls - r0, sn.flights - f0, sn.climbs - c0, _whys(s0)])
	_dump("hold%d" % i)


func _press5(i: int) -> void:
	var st: Array = STREETS[i]
	var yaw: float = st[1]
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	await _tp(st[0], yaw, 0.2)
	var s0 := sn.swing.swings
	var ok := await _first_rope()
	rec.begin()
	var done := 0
	for k in 5:
		if k > 0:
			await _until(func() -> bool: return p.velocity.y < 1.5 or p.is_on_floor(), 2.0)
			if p.is_on_floor():
				break
			fg.press(1, &"snake")
			ok = await _until(func() -> bool: return sn.swing.is_hanging() or p.is_on_floor(), 3.5)
			ok = ok and sn.swing.is_hanging()
		if not ok:
			break
		await _until(func() -> bool: return not sn.swing.is_hanging() or (sn.swing.rope_angle > 0.4 and p.velocity.y > 1.0), 4.0)
		fg.up(1)
		await _secs(0.1)
		done += 1
	fg.up_all()
	var d := p.global_position - rec.start
	print("CR press%d: %d of 5 swings, net %.0f m, off line %.1f m, %s; %s" % [i, done, d.dot(fwd), (d - fwd * d.dot(fwd)).length(), _state(), _whys(s0)])
	await _until(func() -> bool: return p.is_on_floor() and sn.mode == SnakeTraversal.Mode.NONE, 8.0)
	await _secs(1.0)
	print("CR press%d landed: %s" % [i, _state()])
	_dump("press%d" % i)


## Let go EARLY: 0.3 s after each bite (on the way down).
func _early() -> void:
	await _tp(STREETS[0][0], STREETS[0][1], 0.2)
	var s0 := sn.swing.swings
	var ok := await _first_rope()
	rec.begin()
	for k in 4:
		if k > 0:
			await _secs(0.5)
			if p.is_on_floor():
				break
			fg.press(1, &"snake")
			ok = await _until(func() -> bool: return sn.swing.is_hanging() or p.is_on_floor(), 2.5)
			if not sn.swing.is_hanging():
				break
		await _secs(0.35)
		print("CR early: lifting at angle %.2f v %.1f vy %.1f h %.1f" % [sn.swing.rope_angle, p.velocity.length(), p.velocity.y, p.global_position.y])
		fg.up(1)
		await _secs(0.05)
		print("CR early: 3 ticks after the lift: mode %s hanging %s commit %s" % [sn.mode_name(), sn.swing.is_hanging(), sn.swing._commit])
	fg.up_all()
	await _until(func() -> bool: return p.is_on_floor() and sn.mode == SnakeTraversal.Mode.NONE, 8.0)
	await _secs(1.0)
	print("CR early ends: %s; %s" % [_state(), _whys(s0)])
	_dump("early")


## A held chain; the finger lifts just after the second rope bit: does the hero let go?
func _relift() -> void:
	await _tp(STREETS[0][0], STREETS[0][1], 0.2)
	var s0 := sn.swing.swings
	await _first_rope()
	rec.begin()
	await _until(func() -> bool: return sn.swing.swings - s0 >= 2 and sn.swing.is_hanging(), 6.0)
	await _secs(0.12)
	var t0 := rec.ticks
	fg.up(1)
	await _until(func() -> bool: return not sn.swing.is_hanging(), 4.0)
	print("CR relift: finger lifted 0.12 s after the 2nd bite; the rope let go %.2f s later (%s); %s" % [float(rec.ticks - t0) / 60.0, sn.swing.last_why, _state()])
	# and a quick double press: lift then press again within 0.3 s
	await _until(func() -> bool: return p.is_on_floor(), 6.0)
	_dump("relift", 0)


func _jump() -> void:
	await _tp(STREETS[0][0], STREETS[0][1], 0.2)
	var s0 := sn.swing.swings
	var f0 := sn.flights
	var dj := sn.double_jumps
	await _first_rope()
	rec.begin()
	await _until(func() -> bool: return sn.swing.is_hanging() and sn.swing._hang_t > 0.3 and sn.swing.rope_angle > -0.05, 4.0)
	var v0 := p.velocity
	fg.press(2, &"jump")
	await _secs(0.08)
	fg.up(2)
	print("CR jump: at angle %.2f v %.1f vy %.1f -> after JUMP mode %s v %.1f vy %.1f why %s" % [sn.swing.rope_angle, v0.length(), v0.y, sn.mode_name(), p.velocity.length(), p.velocity.y, sn.swing.last_why])
	await _secs(2.5)
	print("CR jump: 2.5 s later, SNAKE still held: %s swings %d flights %d double jumps %d" % [_state(), sn.swing.swings - s0, sn.flights - f0, sn.double_jumps - dj])
	fg.up(1)
	await _secs(0.1)
	fg.press(1, &"snake")
	await _secs(1.0)
	print("CR jump: lifted and pressed SNAKE again: %s swings %d" % [_state(), sn.swing.swings - s0])
	fg.up_all()
	await _until(func() -> bool: return p.is_on_floor() and sn.mode == SnakeTraversal.Mode.NONE, 8.0)
	print("CR jump ends: %s; %s" % [_state(), _whys(s0)])
	_dump("jump")


## Swing AT a facade: look across the street at the building.
func _wall() -> void:
	for yaw: float in [0.0, PI]:
		await _tp(STREETS[0][0], yaw, 0.35)
		var s0 := sn.swing.swings
		var c0 := sn.climbs
		var z0 := sn.zips
		var ok := await _first_rope()
		rec.begin()
		await _secs(6.0)
		print("CR wall yaw %.2f: rope %s; after 6 s held: %s swings %d climbs %d zips %d; %s" % [yaw, ok, _state(), sn.swing.swings - s0, sn.climbs - c0, sn.zips - z0, _whys(s0)])
		fg.up_all()
		await _secs(3.0)
		print("CR wall yaw %.2f: 3 s after lifting: %s" % [yaw, _state()])
		_dump("wall%.0f" % yaw, 80)


func _noanchor() -> void:
	await _tp(Vector3(1200.0, 0.0, 0.0), 0.0, 0.05)
	var f0 := sn.flights
	var w0 := sn.whiffs
	print("CR noanchor on the ground: label %s fly button %s" % [fg.button_label(&"snake"), fg.button(&"fly") != Vector2.INF])
	fg.press(1, &"snake")
	await _secs(0.2)
	print("CR noanchor ground press 0.2 s: %s whiffs %d" % [_state(), sn.whiffs - w0])
	await _secs(1.5)
	print("CR noanchor ground press held 1.7 s: %s flights %d" % [_state(), sn.flights - f0])
	fg.up_all()
	await _secs(3.0)
	print("CR noanchor 3 s after lift: %s" % _state())
	fg.up_all()
	await _tp(Vector3(1200.0, 0.0, 0.0), 0.0, 0.05)
	await _tap(2, &"jump", 6)
	await _secs(0.2)
	fg.press(1, &"snake")
	await _secs(0.15)
	fg.up(1)
	await _secs(2.0)
	print("CR noanchor air TAP: %s whiffs %d flights %d" % [_state(), sn.whiffs - w0, sn.flights - f0])


func _zip(pitch: float) -> void:
	for spot: Array in [[Vector3(240.1, 0.0, -305.0), PI * 0.5], [Vector3(-30.0, 0.0, 4.0), 0.0], [Vector3(-30.0, 0.0, 4.0), PI]]:
		await _tp(spot[0], spot[1], pitch)
		await _secs(0.6)
		var z := sn.zip_target
		var label := fg.button_label(&"snake")
		var z0 := sn.zips
		var c0 := sn.climbs
		var s0 := sn.swing.swings
		rec.begin()
		rec.every = 3
		await _tap(1, &"snake", 5)
		await _until(func() -> bool: return sn.mode != SnakeTraversal.Mode.NONE, 0.5)
		var t0 := rec.ticks
		await _until(func() -> bool: return sn.mode == SnakeTraversal.Mode.NONE and p.is_on_floor(), 8.0)
		var t1 := rec.ticks
		await _secs(0.8)
		print("CR zip pitch %.2f spot %s yaw %.2f: label %s target %s; zips %d swings %d climbs %d hauls %d drops %d end %s in %.2f s dist %.0f; %s" % [pitch, spot[0], spot[1], label, z.get("kind", "none"), sn.zips - z0, sn.swing.swings - s0, sn.climbs - c0, sn.zip.hauls, sn.zip.drops, sn.zip.end_reason, float(t1 - t0) / 60.0, sn.zip.last_dist, _state()])
		_dump("zip", 60)
		rec.every = 6


func _fly() -> void:
	await _tp(STREETS[0][0], STREETS[0][1], 0.2)
	print("CR fly on the ground: FLY button shown %s, labels %s" % [fg.button(&"fly") != Vector2.INF, fg.button_label(&"fly")])
	rec.begin()
	await _tap(2, &"jump", 6)
	var shown := await _until(func() -> bool: return fg.button(&"fly") != Vector2.INF, 1.0)
	var t_show := rec.ticks
	print("CR fly: button shown %s after %.2f s in the air, h %.1f" % [shown, t_show / 60.0, p.global_position.y])
	await _tap(4, &"fly", 5)
	await _secs(0.5)
	print("CR fly: after FLY tap: %s fly label %s" % [_state(), fg.button_label(&"fly")])
	fg.stick(Vector2(0.0, -1.0))
	await _secs(3.0)
	print("CR fly: 3 s stick forward: %s energy %.0f" % [_state(), sn.energy])
	fg.stick(Vector2.ZERO)
	await _secs(1.0)
	print("CR fly: 1 s thumbs off: %s" % _state())
	var t0 := rec.ticks
	await _tap(4, &"fly", 5)
	await _until(func() -> bool: return sn.mode == SnakeTraversal.Mode.NONE and p.is_on_floor(), 10.0)
	print("CR fly: LAND tapped: on the ground after %.2f s: %s" % [float(rec.ticks - t0) / 60.0, _state()])
	_dump("fly", 80)


## SNAKE pressed while standing on the street (the first thing a player does).
func _ground() -> void:
	for st: Array in STREETS:
		await _tp(st[0], st[1], 0.2)
		await _secs(0.6)
		var label := fg.button_label(&"snake")
		var s0 := sn.swing.swings
		var z0 := sn.zips
		var c0 := sn.climbs
		var f0 := sn.flights
		rec.begin()
		fg.press(1, &"snake")
		await _secs(6.0)
		var fwd := Vector3(-sin(st[1]), 0.0, -cos(st[1]))
		print("CR ground %s yaw %.2f: label %s; held 6 s: swings %d zips %d climbs %d flights %d net %.0f m; %s; %s" % [st[0], st[1], label, sn.swing.swings - s0, sn.zips - z0, sn.climbs - c0, sn.flights - f0, (p.global_position - rec.start).dot(fwd), _state(), _whys(s0)])
		fg.up_all()
		await _secs(2.0)
		_dump("ground", 70)


## Which anchors does the search see from high over a street? (direct calls: a probe of the search, not of the controls)
func _scan() -> void:
	for st: Array in STREETS:
		var yaw: float = st[1]
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		for hh: float in [16.0, 26.0]:
			await _tp(st[0], yaw, 0.2)
			p.global_position = (st[0] as Vector3) + fwd * 110.0 + Vector3(0.0, hh, 0.0)
			p.velocity = fwd * 27.0
			sn.anchors.debug = true
			var hit := sn.anchors.find_swing(p, fwd, fwd, SnakePower.range_m(), true)
			var o := p.global_position + Vector3(0.0, 1.5, 0.0)
			print("CR scan street %s h %.0f scan_h %.1f -> pick %s stats %s" % [st[0], hh, SwingMotion.scan_h, "none" if hit.is_empty() else "dy %.0f fwd %.0f d %.0f" % [(hit["pos"] as Vector3).y - o.y, ((hit["pos"] as Vector3) - o).dot(fwd), o.distance_to(hit["pos"] as Vector3)], sn.anchors.stats])
			var cs := sn.anchors.cands.duplicate()
			cs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
			for c: Dictionary in cs.slice(0, 8):
				var pos: Vector3 = c["pos"]
				print("     yaw %.2f pitch %.2f dy %.0f fwd %.0f side %.0f score %.2f" % [c["yaw"], c["pitch"], pos.y - o.y, (pos - o).dot(fwd), ((pos - o) - fwd * (pos - o).dot(fwd) - Vector3(0.0, pos.y - o.y, 0.0)).length(), c["score"]])
			sn.anchors.debug = false


## SNAKE pressed and held on the GROUND, looking at the facade across the avenue (the wall part of test_swing_w117 when its JUMP comes late).
func _wallg() -> void:
	for rep in 4:
		await _tp(STREETS[0][0], 0.0, 0.35)
		await _first_rope()
		await _f(180)
		fg.up_all()
		await _until(func() -> bool: return p.is_on_floor() and sn.mode == SnakeTraversal.Mode.NONE, 8.0)
		await _tp(STREETS[0][0], PI, 0.35)
		var c0 := sn.climbs
		var last := ""
		var mon := func() -> void:
			var now := "%s/%s/%s/%s" % [sn.mode_name(), sn.zip.phase, sn.zip.end_reason, sn.swing.phase]
			if now != last:
				print("CR wallg %d tick %d: %s kind %s pos %s floor %s air %.2f climbs %d snake %s jump %s" % [rep, rec.ticks, now, sn.zip.kind, p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), p.is_on_floor(), p.air_time, sn.climbs - c0, Input.is_action_pressed(&"snake"), Input.is_action_pressed(&"jump")])
				last = now
		rec.begin()
		host.get_tree().physics_frame.connect(mon)
		await _first_rope()
		await _f(180)
		fg.up_all()
		await _secs(1.0)
		host.get_tree().physics_frame.disconnect(mon)
		print("CR wallg ends: ", _state())
