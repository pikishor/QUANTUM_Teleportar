extends RefCounted
## WAVE 117 CRITIC: the checks of the independent review (docs/sprint/progress/w117-critic.md). The real main scene, the phone HUD, REAL FINGERS only (InputEventScreenTouch /
## InputEventScreenDrag through Input.parse_input_event, tests/w116_fingers.gd), the phone-only layers on (CrateReveal._quiet = 0); a recorder reads the body once a physics tick.
##   chain   a thumb held on SNAKE for 12 s on three streets: the chain levels off instead of climbing to the roofline, and most of the time is spent ON a rope
##   jump    JUMP at the lowest point of a swing: the swing's own speed and a hop, not the QUANTUM GLIDE burst on top
##   zip     a roof ZIP: never faster than 46 m/s, its rope points UP to the roof's edge, the hero never turns head down
##   relift  in a held chain a thumb lifted right after a bite lets go at once
##   dive    a rope pressed in a fast fall still catches him (guards the anchor score of the levelled chain)
##   thrown  between two ropes the hero leans along the throw
## CRITIC_OLD=1 switches every fix of the critic off (the builders' state): the checks marked [old fails] fail. CRIT_PARTS=chain,jump,... picks parts.
## Run: tools/test.sh tests/test_critic_w117.gd
const TIMEOUT_SECONDS := 145
const Fingers := preload("res://tests/w116_fingers.gd")
const STREETS: Array = [[Vector3(-30.0, 0.0, 4.0), -PI * 0.5], [Vector3(-30.0, 0.0, 4.0), PI * 0.5], [Vector3(240.1, 0.0, -305.0), 0.0]]
const ROOF_SPOT := Vector3(240.1, 0.0, -305.0)          ## yaw PI/2 looks at a facade 15 m away whose roof is 28 m up

var host: Node
var fg: Fingers
var p: Player
var sn: SnakeTraversal
var rec: Rec
var old := false


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



func _fixes(on: bool) -> void:
	SwingMotion.level_chain = on
	SwingMotion.tap_needs_press = on
	SnakeTraversal.jump_takes = on
	SnakeZip.peak_speed = 44.0 if on else 0.0
	SnakeZip.rope_to_edge = on
	SnakePose.zip_upright = on
	SnakePose.throw_pose = on


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	old = OS.get_environment("CRITIC_OLD") == "1"
	_fixes(not old)
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
	TrafficField.bare_street()
	TestMode.god = true
	Difficulty.set_mode(1)
	SnakeTraversal.assist = true
	Engine.physics_ticks_per_second = 180                     # real 1/60 s ticks, three game seconds a second
	Engine.time_scale = 3.0
	Engine.max_physics_steps_per_frame = 3
	TestLib.check(fg.tc != null and fg.tc.controls_on and fg.button(&"snake") != Vector2.INF, "the phone HUD is up and the SNAKE button is on screen (%s)" % ("the builders' state, CRITIC_OLD=1" if old else "with the critic's fixes"))
	var parts := (OS.get_environment("CRIT_PARTS") if OS.get_environment("CRIT_PARTS") != "" else "chain,jump,zip,relift,dive,thrown").split(",")
	for part in parts:
		match part:
			"chain": await _chain()
			"jump": await _jump()
			"zip": await _zip()
			"relift": await _relift()
			"dive": await _dive()
			"thrown": await _thrown()
	fg.up_all()
	_fixes(true)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	Game.force_touch = false
	CrateReveal._quiet = -1
	TestMode.god = false
	rec.queue_free()
	main.queue_free()
	await _f(2)


# --- a thumb held on SNAKE for 12 s, three streets ---------------------------------------------------------------------------------------------

func _chain() -> void:
	var worst_h := 0.0
	var worst_share := 1.0
	var least_net := 1.0e9
	var floors := 0
	var lowest := 1.0e9                                       # least air under the feet on a rope, from the second swing on
	var lines: Array[String] = []
	for i in STREETS.size():
		var yaw: float = STREETS[i][1]
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		await _tp(STREETS[i][0], yaw, 0.2)
		var s0 := sn.swing.swings
		var ok := await _first_rope()
		rec.begin()
		for k in 720:
			if sn.swing.is_hanging() and sn.swing.swings - s0 >= 2:
				lowest = minf(lowest, sn.swing.height)
			await host.get_tree().physics_frame
		var on_rope := float(int(rec.modes.get("swing", 0))) / float(maxi(rec.ticks, 1))
		var net := (p.global_position - rec.start).dot(fwd)
		lines.append("street %d: rope %s, %d swings, top %.1f m over the street, %.0f %% of the time on a rope, %.0f m down the street, floor ticks %d" % [i, ok, sn.swing.swings - s0, rec.max_h, on_rope * 100.0, net, rec.floor_ticks])
		worst_h = maxf(worst_h, rec.max_h)
		worst_share = minf(worst_share, on_rope)
		least_net = minf(least_net, net)
		floors += rec.floor_ticks
		fg.up_all()
		await _until(func() -> bool: return p.is_on_floor() and sn.mode == SnakeTraversal.Mode.NONE, 8.0)
	for l in lines:
		print("CRIT chain ", l)
	TestLib.check(worst_h <= 26.0, "[old fails] a held chain levels off: never higher than 26 m over the street in 12 s on any of three streets (highest %.1f m; the builders' state: 33 to 47 m)" % worst_h)
	TestLib.check(worst_share >= 0.6, "a held chain is swinging most of the time: at least 60 %% of the ticks on a rope on every street (least %.0f %%)" % (worst_share * 100.0))
	TestLib.check(least_net >= 200.0 and floors == 0, "the chain still crosses the city: at least 200 m down every street in 12 s without touching the ground (least %.0f m, floor ticks %d)" % [least_net, floors])
	TestLib.check(lowest >= 2.0, "[old fails] no swing of the chain comes nearer than 2 m to the street (least air under the feet on a rope %.1f m; the builders' state: 1.2 m at 36 m/s after a 2 s fall from the roofline)" % lowest)
	TestLib.check(rec.max_step <= 0.75 and rec.walls == 0, "never flung, no wall passed (biggest move in a tick %.2f m, walls %d)" % [rec.max_step, rec.walls])


# --- JUMP out of a swing -----------------------------------------------------------------------------------------------------------------------

func _jump() -> void:
	await _tp(STREETS[0][0], STREETS[0][1], 0.2)
	var b0 := p.verbs.bursts
	await _first_rope()
	rec.begin()
	await _until(func() -> bool: return sn.swing.is_hanging() and sn.swing._hang_t > 0.3 and sn.swing.rope_angle > -0.05, 4.0)
	var v0 := p.velocity
	fg.press(2, &"jump")
	await _until(func() -> bool: return not sn.swing.active, 0.5)
	var v1 := p.velocity
	await _secs(0.1)
	var v2 := p.velocity
	fg.up(2)
	fg.up_all()
	print("CRIT jump: on the rope %.1f m/s (vy %.1f); the tick it let go %.1f (vy %.1f); 0.1 s later %.1f (vy %.1f); why %s; glide bursts %d" % [v0.length(), v0.y, v1.length(), v1.y, v2.length(), v2.y, sn.swing.last_why, p.verbs.bursts - b0])
	TestLib.check(sn.swing.last_why == &"jump" and v1.length() > v0.length() and v1.y >= 4.0, "JUMP lets go of the swing with a hop (%.1f -> %.1f m/s, %.1f m/s up)" % [v0.length(), v1.length(), v1.y])
	TestLib.check(p.verbs.bursts == b0 and v2.length() <= v1.length() + 1.0, "[old fails] the JUMP that let go is not ALSO a QUANTUM GLIDE burst: 0.1 s later he still flies at the speed of the swing (%.1f then %.1f m/s, bursts %d; the builders' state: 14.6 -> 27.1 m/s)" % [v1.length(), v2.length(), p.verbs.bursts - b0])
	await _until(func() -> bool: return p.is_on_floor(), 6.0)


# --- a roof ZIP --------------------------------------------------------------------------------------------------------------------------------

func _zip() -> void:
	await _tp(ROOF_SPOT, PI * 0.5, 0.5)
	await _secs(0.6)
	var label := fg.button_label(&"snake_zip")              # wave 118: ZIP is a button of its own
	rec.begin()
	await _tap(1, &"snake_zip", 5)
	await _until(func() -> bool: return sn.mode == SnakeTraversal.Mode.ZIP, 0.5)
	var rope_down := 0.0                                      # how far the rope's far end lies BELOW the hand at worst (metres), while his feet are more than 3 m under the roof
	var head_low := 1.0                                       # the lowest the head's direction pointed (1 up, 0 level, -1 down) while the zip pose is on
	var ticks := 0
	while sn.mode == SnakeTraversal.Mode.ZIP and ticks < 600:
		var z := sn.zip
		if z.phase == &"pull" and z.t > 0.0 and z.tendril != null and p.global_position.y < z.dest.y - 3.0:
			rope_down = maxf(rope_down, z.tendril.origin_pos.y - z.tendril.target_pos.y)
		if z.phase == &"pull" and z.t > 0.05 and sn.pose.blend > 0.5:
			head_low = minf(head_low, sn.pose.basis.y.y)
		ticks += 1
		await host.get_tree().physics_frame
	await _until(func() -> bool: return p.is_on_floor(), 3.0)
	print("CRIT zip: label %s, %.1f s, top speed %.1f m/s, biggest move in a tick %.2f m, rope end below the hand at worst %.1f m, head direction at its lowest %.2f, ends at y %.1f (%s)" % [label, ticks / 60.0, rec.max_speed, rec.max_step, rope_down, head_low, p.global_position.y, sn.zip.end_reason])
	TestLib.check(label == "ZIP" and p.global_position.y > 27.0 and p.is_on_floor(), "a tap of ZIP at the roof 28 m up ends standing on it (y %.1f)" % p.global_position.y)
	TestLib.check(rec.max_speed <= 46.0 and rec.max_step <= 0.8, "[old fails] the zip is a ride, not a teleport: never faster than 46 m/s, never more than 0.8 m in a tick (%.1f m/s, %.2f m; the builders' state: 101 m/s, 1.69 m)" % [rec.max_speed, rec.max_step])
	TestLib.check(rope_down <= 0.5, "[old fails] the rope of a roof zip points UP to the roof's edge while it pulls (its far end at worst %.1f m below the hand; the builders' state: it bit the wall 8 m up and hung down)" % rope_down)
	TestLib.check(head_low >= 0.2, "[old fails] the hero never turns head down in a roof zip (the head's direction at its lowest %.2f; under 0 is head down)" % head_low)


# --- in a held chain, a thumb lifted right after a bite -------------------------------------------------------------------------------------------

func _relift() -> void:
	await _tp(STREETS[0][0], STREETS[0][1], 0.2)
	var s0 := sn.swing.swings
	await _first_rope()
	rec.begin()
	var second := await _until(func() -> bool: return sn.swing.swings - s0 >= 2 and sn.swing.is_hanging(), 6.0)
	await _secs(0.12)
	var t0 := rec.ticks
	fg.up(1)
	await _until(func() -> bool: return not sn.swing.is_hanging(), 4.0)
	var took := float(rec.ticks - t0) / 60.0
	print("CRIT relift: second rope %s; the thumb left 0.12 s after its bite; the rope let go %.2f s later (%s)" % [second, took, sn.swing.last_why])
	TestLib.check(second and took <= 0.2, "[old fails] in a held chain LET GO lets go: a thumb lifted 0.12 s after the second bite frees the hero within 0.2 s (%.2f s; the builders' state: 1.05 s, read as a tap)" % took)
	await _until(func() -> bool: return p.is_on_floor(), 6.0)
	# a real tap still is one whole swing
	await _tp(STREETS[0][0], STREETS[0][1], 0.2)
	await _tap(2, &"jump", 6)
	await _until(func() -> bool: return not p.is_on_floor() and p.air_time > 0.12, 0.5)
	await _tap(1, &"snake", 5)
	var hung := await _until(func() -> bool: return sn.swing.is_hanging(), 2.0)
	var h0 := rec.ticks
	await _until(func() -> bool: return not sn.swing.active, 4.0)
	TestLib.check(hung and float(rec.ticks - h0) / 60.0 > 0.6 and sn.swing.last_why == &"chain", "a TAP in the air still is one whole swing (%.2f s, ends by %s)" % [float(rec.ticks - h0) / 60.0, sn.swing.last_why])
	await _until(func() -> bool: return p.is_on_floor(), 6.0)


# --- a rope that bites in a fast fall ----------------------------------------------------------------------------------------------------------------

func _dive() -> void:
	await _tp(STREETS[2][0], STREETS[2][1], 0.2)
	var yaw: float = STREETS[2][1]
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	p.global_position += Vector3(0.0, 46.0, 0.0) + fwd * 60.0   # setup only: the hero starts a fall high over the street, moving along it
	p.velocity = fwd * 22.0
	rec.begin()
	await _until(func() -> bool: return rec.ticks > 20 and p.velocity.y < -24.0 and p.global_position.y < 13.0, 6.0)
	var y0 := p.global_position.y
	var vy0 := p.velocity.y
	fg.press(1, &"snake")
	var hung := await _until(func() -> bool: return sn.swing.is_hanging() or p.is_on_floor(), 2.0)
	hung = hung and sn.swing.is_hanging()
	var low := 1.0e9
	var floor_hit := false
	var n := 0
	while sn.swing.active and n < 360:
		if sn.swing.is_hanging():
			low = minf(low, sn.swing.height)
			floor_hit = floor_hit or p.is_on_floor()
		n += 1
		await host.get_tree().physics_frame
	fg.up_all()
	print("CRIT dive: SNAKE pressed %.1f m up, falling at %.1f m/s; rope %s; lowest air under the feet on the rope %.1f m; floor %s; ended by %s" % [y0, vy0, hung, low, floor_hit, sn.swing.last_why])
	TestLib.check(hung and low >= 1.8 and not floor_hit, "a rope pressed in a fast fall 13 m up still catches him and carries him over the street, never onto it (lowest %.1f m of air under the feet, floor %s)" % [low, floor_hit])
	await _until(func() -> bool: return p.is_on_floor(), 8.0)


# --- between two ropes ---------------------------------------------------------------------------------------------------------------------------

func _thrown() -> void:
	await _tp(STREETS[0][0], STREETS[0][1], 0.2)
	var fwd := Vector3(1.0, 0.0, 0.0)
	await _first_rope()
	rec.begin()
	var r0 := sn.swing.releases
	await _until(func() -> bool: return sn.swing.releases > r0 and not sn.swing.active and sn.mode == SnakeTraversal.Mode.NONE and not p.is_on_floor(), 5.0)
	var lean := -1.0
	var blend := 0.0
	var n := 0
	while sn.mode == SnakeTraversal.Mode.NONE and not p.is_on_floor() and n < 40:
		blend = maxf(blend, sn.pose.blend)
		if sn.pose.blend > 0.5:
			lean = maxf(lean, sn.pose.basis.y.dot(fwd))
		n += 1
		await host.get_tree().physics_frame
	fg.up_all()
	print("CRIT thrown: %d ticks in the air after the first swing let go: pose blend at most %.2f, the body's up axis leans %.2f along the throw" % [n, blend, lean])
	TestLib.check(n >= 6 and blend > 0.5 and lean >= 0.15, "[old fails] thrown by a swing the hero leans along the throw (blend %.2f, lean %.2f; the builders' state: no pose, he stands upright in the air)" % [blend, lean])
	await _until(func() -> bool: return p.is_on_floor(), 8.0)
	await _secs(1.2)
	TestLib.check(sn.pose.blend < 0.1 and p.is_on_floor(), "back on his feet the pose is gone (blend %.2f)" % sn.pose.blend)
