extends RefCounted
## WAVE 117, THE SWING ITSELF (owner round 7: "zip line should be just like spiderman ... our hero can jump"; "it behaves abnormally").
## The real main scene, the phone HUD, REAL FINGERS only (InputEventScreenTouch / InputEventScreenDrag through Input.parse_input_event, tests/w116_fingers.gd), the phone-only
## layers on (CrateReveal._quiet = 0). Nothing here calls a game function to act; a recorder reads the body once per physics tick.
##   manual  five swings down a street, each one a finger down and a finger up: off the ground, forward, release speed and direction sane
##   hold    one long hold: the chain keeps its direction (the camera's), never turns back
##   tap     a tap in the air is a whole swing (to the front of the arc), not a 0.5 s twitch
##   jump    JUMP during a swing lets go with a boost
##   steer   the stick steers the swing left and right
##   still   a rope that stops swinging lowers the hero and lets go
##   land    letting go: an air brake, a soft landing with a roll, never an unasked climb, never stuck
##   wall    a swing at a facade: no wall is passed, the hero is never left hanging
## SWING_OLD=1 runs the wave 116 motion (SnakeSwing.old_motion): the 13 checks marked [old fails] fail (measured; the others guard what the old motion also did). SW117_PARTS=manual,hold,... picks parts.
## Run: tools/test.sh tests/test_swing_w117.gd

const TIMEOUT_SECONDS := 145
const Fingers := preload("res://tests/w116_fingers.gd")
const STREET := Vector3(-30.0, 0.0, 4.0)
const YAW := -PI * 0.5                      ## looks along +X down the avenue
const FWD := Vector3(1.0, 0.0, 0.0)

var host: Node
var fg: Fingers
var p: Player
var sn: SnakeTraversal
var rec: Rec


## One sample per physics tick, taken after the player moved.
class Rec extends Node:
	var p: Player
	var sn: SnakeTraversal
	var on := false
	var ticks := 0
	var floor_ticks := 0
	var min_h := 1.0e9                    ## feet over whatever is under them
	var max_step := 0.0
	var max_speed := 0.0
	var path := 0.0
	var walls := 0                        ## ticks in which the straight line of the move crossed world geometry
	var wall_at := Vector3.ZERO
	var step_at := ""
	var back_ticks := 0                   ## ticks of a swing in which the hero moved against `fwd`
	var fwd := Vector3.ZERO
	var modes := {}
	var rope_err := 0.0                   ## worst (distance to the pivot minus the rope) while hanging on a rope that has its length
	var rope_changes := 0.0                ## metres the rope got LONGER while hanging
	var hang_ticks := 0
	var start := Vector3.ZERO
	var hpath := 0.0                      ## metres over the ground (no height)
	var rel_v := Vector3.ZERO             ## the velocity in the tick the last swing let go, and the tick before it
	var pre_v := Vector3.ZERO
	var rel_n := 0                        ## swings let go since begin()
	var _rel0 := 0
	var _v_prev := Vector3.ZERO
	var _prev := Vector3.ZERO
	var _rope_prev := -1.0
	var _rq := PhysicsRayQueryParameters3D.new()

	func begin(forward := Vector3.ZERO) -> void:
		on = true
		ticks = 0
		floor_ticks = 0
		min_h = 1.0e9
		max_step = 0.0
		max_speed = 0.0
		path = 0.0
		walls = 0
		back_ticks = 0
		fwd = forward
		modes = {}
		rope_err = 0.0
		rope_changes = 0.0
		hang_ticks = 0
		start = p.global_position
		hpath = 0.0
		rel_n = 0
		_rel0 = sn.swing.releases
		_v_prev = p.velocity
		_prev = p.global_position
		_rope_prev = -1.0

	func _physics_process(_dt: float) -> void:
		if not on or p == null:
			return
		var pos := p.global_position
		ticks += 1
		var step := pos.distance_to(_prev)
		if step > max_step and sn.mode != SnakeTraversal.Mode.ZIP:       # the zip's own speed is not this test's subject
			max_step = step
			step_at = "%s %s v %.1f lowering %s" % [sn.mode_name(), sn.swing.phase, p.velocity.length(), sn.swing.lowering]
		path += step
		hpath += Vector2(pos.x - _prev.x, pos.z - _prev.z).length()
		if sn.swing.releases != _rel0:
			_rel0 = sn.swing.releases
			rel_n += 1
			rel_v = p.velocity
			pre_v = _v_prev
		_v_prev = p.velocity
		max_speed = maxf(max_speed, p.velocity.length())
		if p.is_on_floor():
			floor_ticks += 1
		var space := p.get_world_3d().direct_space_state
		_rq.collision_mask = Game.L_WORLD
		_rq.exclude = [p.get_rid()]
		_rq.from = pos + Vector3(0.0, 0.6, 0.0)
		_rq.to = pos + Vector3(0.0, -80.0, 0.0)
		var g := space.intersect_ray(_rq)
		min_h = minf(min_h, (pos.y - (g["position"] as Vector3).y) if not g.is_empty() else 80.0)
		if step > 0.02:
			_rq.from = _prev + Vector3(0.0, 1.0, 0.0)
			_rq.to = pos + Vector3(0.0, 1.0, 0.0)
			var w := space.intersect_ray(_rq)
			if not w.is_empty():
				walls += 1
				wall_at = w["position"]
		var m := sn.mode_name()
		modes[m] = int(modes.get(m, 0)) + 1
		if sn.swing.is_hanging():
			hang_ticks += 1
			if fwd != Vector3.ZERO and (pos - _prev).dot(fwd) < -0.02:
				back_ticks += 1
			var d := (pos + Vector3(0.0, SnakeSwing.BODY_CENTRE, 0.0)).distance_to(sn.swing.pivot)
			rope_err = maxf(rope_err, d - sn.swing.rope)
			if _rope_prev > 0.0 and sn.swing.rope > _rope_prev:
				rope_changes += sn.swing.rope - _rope_prev
			_rope_prev = sn.swing.rope
		else:
			_rope_prev = -1.0
		_prev = pos

	func line() -> String:
		return "ticks %d floor %d min height %.1f m, path %.0f m, biggest step %.2f m, (%s), top speed %.1f m/s, walls crossed %d, back ticks %d, modes %s" % [ticks, floor_ticks, min_h, path, max_step, step_at, max_speed, walls, back_ticks, modes]


func _f(n: int) -> void:
	await TestLib.frames(host, n)


## Game seconds (physics ticks), whatever the time scale.
func _until(cond: Callable, secs: float) -> bool:
	var n := int(secs * 60.0)
	for i in n:
		if cond.call():
			return true
		await host.get_tree().physics_frame
	return cond.call()


## A finger event has reached the game: events sent through Input.parse_input_event are delivered at the next rendered frame, and this test runs three physics ticks a frame.
func _seen() -> void:
	await host.get_tree().process_frame
	await host.get_tree().process_frame
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
	await _f(20)


func _tap(finger: int, action: StringName, frames := 4) -> bool:
	if not fg.press(finger, action):
		return false
	await _f(frames)
	fg.up(finger)
	return true


func _state() -> String:
	return "mode %s pos %s v %.1f (vy %.1f) floor %s" % [sn.mode_name(), p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), p.velocity.length(), p.velocity.y, p.is_on_floor()]


## Why the swings since swing number `s0` ended (SnakeSwing.log).
func _whys(s0: int) -> Array:
	var out := []
	var n := mini(sn.swing.swings - s0, sn.swing.log.size())
	for k in range(sn.swing.log.size() - n, sn.swing.log.size()):
		var e: Dictionary = sn.swing.log[k]
		out.append("%s %.1fs rope %.0f angle %.2f rel %.0f" % [e["why"], e["hang"], e["rope"], e["angle"], e["rel"]])
	return out


func _hspeed() -> float:
	return Vector2(p.velocity.x, p.velocity.z).length()


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	SnakeSwing.old_motion = OS.get_environment("SWING_OLD") == "1"
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
	Engine.physics_ticks_per_second = 180                     # three game seconds a second with REAL ticks: the physics dt is time_scale / ticks_per_second = 1 / 60 (time_scale alone makes the ticks longer, 1 / 20 s: another game)
	Engine.time_scale = 3.0
	Engine.max_physics_steps_per_frame = 3
	TestLib.check(fg.tc != null and fg.tc.controls_on and fg.button(&"snake") != Vector2.INF, "the phone HUD is up and the SNAKE button is on screen (%s motion)" % ("OLD wave 116" if SnakeSwing.old_motion else "new"))
	var parts := (OS.get_environment("SW117_PARTS") if OS.get_environment("SW117_PARTS") != "" else "manual,hold,tap,jump,steer,still,land,wall").split(",")
	for part in parts:
		match part:
			"manual": await _manual()
			"hold": await _hold()
			"tap": await _tap_swing()
			"jump": await _jump()
			"steer": await _steer()
			"still": await _still()
			"land": await _land()
			"wall": await _wall()
	fg.up_all()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	Game.force_touch = false
	CrateReveal._quiet = -1
	SnakeSwing.old_motion = false
	TestMode.god = false
	rec.queue_free()
	main.queue_free()
	await _f(2)


## From the street: JUMP, then finger on SNAKE. True when the rope hangs.
func _first_rope() -> bool:
	for attempt in 3:                                         # in the air first: on the street the same button is ZIP / CLIMB (the rope agent's ground)
		await _tap(2, &"jump", 6)
		if await _until(func() -> bool: return not p.is_on_floor() and p.air_time > 0.12, 0.5):
			break
	fg.press(1, &"snake")
	return await _until(func() -> bool: return sn.swing.is_hanging(), 2.5)


## The front of the arc: past the lowest point and rising.
func _front() -> bool:
	return sn.swing.is_hanging() and sn.swing.rope_angle > 0.4 and p.velocity.y > 1.0


# --- five swings, each a finger down and a finger up ------------------------------------------------------------------------------------------

func _manual() -> void:
	await _tp(STREET, YAW, 0.2)
	var s0 := sn.swing.swings
	var rels: Array[Vector3] = []
	var ropes: Array[float] = []
	var hangs: Array[float] = []
	var ok := await _first_rope()
	rec.begin(FWD)                                            # from the first bite on (the hero stood on the street until the JUMP)
	var done := 0
	var t0 := rec.ticks
	for k in 5:
		if k > 0:
			# the next rope: a new press in the air, once the throw has topped out
			await _until(func() -> bool: return p.velocity.y < 1.5 or p.is_on_floor(), 2.0)
			if p.is_on_floor():
				break
			fg.press(1, &"snake")
			ok = await _until(func() -> bool: return sn.swing.is_hanging() or p.is_on_floor(), 2.5)
			ok = ok and sn.swing.is_hanging()
		if not ok:
			break
		ropes.append(sn.swing.rope)
		var h0 := rec.ticks
		var front := await _until(_front, 4.0)
		hangs.append(float(rec.ticks - h0) / 60.0)
		if not sn.swing.is_hanging():
			fg.up(1)
			if not front:
				break
		var rn0 := rec.rel_n
		fg.up(1)
		await _until(func() -> bool: return rec.rel_n > rn0, 0.5)
		rels.append(rec.rel_v)
		if done == 0:
			rec.min_h = 1.0e9                                  # the lowest point counts from the first release on (the first rope lifts him off the street)
		done += 1
	fg.up_all()
	var swings := sn.swing.swings - s0
	var net := (p.global_position - rec.start).dot(FWD)
	var vmin := 1.0e9
	var vmax := 0.0
	var dir_ok := true
	for v in rels:
		vmin = minf(vmin, v.length())
		vmax = maxf(vmax, v.length())
		var vh := Vector3(v.x, 0.0, v.z)
		if vh.length() < 1.0 or vh.normalized().dot(FWD) < 0.8 or v.y < 0.0:
			dir_ok = false
	print("SW117 manual: %d swings let go at the front (%d ropes), net %.0f m down the street of %.0f m path in %.1f s; release speeds %s; ropes %s; hang times %s; %s" % [done, swings, net, rec.path, float(rec.ticks - t0) / 60.0, rels.map(func(v: Vector3) -> String: return "%.1f(vy %.1f)" % [v.length(), v.y]), ropes.map(func(r: float) -> float: return snappedf(r, 0.1)), hangs.map(func(r: float) -> float: return snappedf(r, 0.01)), rec.line()])
	print("SW117 manual ends: ", _whys(s0))
	TestLib.check(done >= 5, "five swings in a row down the street, each a new press of SNAKE in the air (%d)" % done)
	TestLib.check(rec.floor_ticks == 0 and rec.min_h > 2.0, "the five swings never touch the street (ticks on the floor %d, lowest %.1f m over it)" % [rec.floor_ticks, rec.min_h])
	TestLib.check(done >= 2 and vmin >= 14.0 and vmax <= 36.0 and vmax <= vmin * 1.7, "[old fails] every release throws at a sane, even speed (%.1f to %.1f m/s; 14 to 36, spread under 1.7)" % [vmin, vmax])
	TestLib.check(done >= 2 and dir_ok, "[old fails] every release at the front of the arc throws forward and up")
	var drift := absf((p.global_position - rec.start).z)
	TestLib.check(net > rec.hpath * 0.9 and net > 150.0 and drift < 15.0, "[old fails] the chain runs down the street the camera looks along (%.0f m net of %.0f m over the ground, %.1f m off the line)" % [net, rec.hpath, drift])
	TestLib.check(rec.max_step <= 0.75 and rec.max_speed <= 45.0, "[old fails] never flung: the biggest move in one tick %.2f m (limit 0.75), top speed %.1f m/s (limit 45)" % [rec.max_step, rec.max_speed])
	TestLib.check(rec.walls == 0, "no wall is passed (%d ticks, last at %s)" % [rec.walls, rec.wall_at.snapped(Vector3(0.1, 0.1, 0.1))])
	TestLib.check(rec.rope_err < 0.6 and rec.rope_changes < 0.5, "the rope keeps its length: never longer than it was, the body never more than 0.6 m beyond it (%.2f m, grew %.2f m)" % [rec.rope_err, rec.rope_changes])
	var hmin := 1.0e9
	var hmax := 0.0
	for x in hangs:
		hmin = minf(hmin, x)
		hmax = maxf(hmax, x)
	TestLib.check(done >= 2 and hmax <= 2.6 and hmin >= 0.35, "[old fails] a rhythm: every swing takes 0.35 to 2.6 s to reach the front of its arc (%.2f to %.2f s)" % [hmin, hmax])
	await _settle("manual")


## Hands off after a part: the hero must come to rest on his feet (never left hanging, never climbing unasked).
func _settle(tag: String) -> void:
	fg.up_all()
	var rolls0 := sn.landing_rolls
	var down := await _until(func() -> bool: return p.is_on_floor() and sn.mode == SnakeTraversal.Mode.NONE, 9.0)
	await _f(60)
	print("SW117 %s settle: on his feet %s, rolls +%d, 1 s later %s" % [tag, down, sn.landing_rolls - rolls0, _state()])
	TestLib.check(down and sn.mode == SnakeTraversal.Mode.NONE, "%s: hands off, the hero is on his feet within 9 s, in no snake state (%s)" % [tag, _state()])


# --- one long hold ---------------------------------------------------------------------------------------------------------------------------

func _hold() -> void:
	await _tp(STREET, YAW, 0.2)
	var s0 := sn.swing.swings
	var l0 := sn.swing.log.size()
	await _first_rope()
	rec.begin(FWD)
	await _until(func() -> bool: return sn.swing.swings - s0 >= 6 or (rec.ticks > 120 and p.is_on_floor() and sn.mode == SnakeTraversal.Mode.NONE), 14.0)
	var n := sn.swing.swings - s0
	var net := (p.global_position - rec.start).dot(FWD)
	var secs := float(rec.ticks) / 60.0
	fg.up_all()
	var rel: Array[float] = []
	for k in range(l0, sn.swing.log.size()):
		rel.append(float(sn.swing.log[k]["rel"]))
	print("SW117 hold: %d swings in %.1f s, net %.0f m of %.0f m path, release speeds %s; %s" % [n, secs, net, rec.path, rel, rec.line()])
	print("SW117 hold ends: ", _whys(s0), " last search ", sn.anchors.stats)
	TestLib.check(n >= 5 and rec.floor_ticks == 0, "one held button chains five swings and more off the ground (%d swings, %d ticks on the floor)" % [n, rec.floor_ticks])
	var drift := absf((p.global_position - rec.start).z)
	TestLib.check(net > rec.hpath * 0.9 and drift < 15.0, "[old fails] the held chain keeps the direction of the camera (%.0f m net of %.0f m over the ground, %.1f m off the line)" % [net, rec.hpath, drift])
	TestLib.check(rec.back_ticks == 0, "no swing of the chain turns back on itself (%d ticks moving back)" % rec.back_ticks)
	TestLib.check(rec.max_step <= 0.75 and rec.walls == 0, "[old fails] no fling, no wall passed (step %.2f m, walls %d)" % [rec.max_step, rec.walls])
	await _settle("hold")


# --- a tap --------------------------------------------------------------------------------------------------------------------------------------

func _tap_swing() -> void:
	await _tp(STREET, YAW, 0.2)
	await _tap(2, &"jump")
	await _f(8)
	rec.begin(FWD)
	var s0 := sn.swing.swings
	var r0 := sn.swing.releases
	await _tap(1, &"snake", 4)
	var bit := await _until(func() -> bool: return sn.swing.is_hanging(), 2.0)
	var from := p.global_position
	var let_go := await _until(func() -> bool: return sn.swing.releases > r0, 4.0)
	var v := p.velocity
	var arc := p.global_position.distance_to(from)
	var entry: Dictionary = sn.swing.log[sn.swing.log.size() - 1] if not sn.swing.log.is_empty() else {}
	print("SW117 tap: bit %s, let go %s after %.2f s and %.1f m at angle %.2f, v %.1f (vy %.1f), why %s; %s" % [bit, let_go, float(entry.get("hang", 0.0)), arc, float(entry.get("angle", 0.0)), v.length(), v.y, entry.get("why", "?"), rec.line()])
	TestLib.check(bit and sn.swing.swings == s0 + 1, "a tap of SNAKE in the air bites")
	TestLib.check(let_go and float(entry.get("angle", 0.0)) > 0.3 and v.y > 0.0 and arc > 12.0, "[old fails] and it is a whole swing: let go by itself at the front of the arc, rising (angle %.2f rad, vy %.1f, %.0f m)" % [float(entry.get("angle", 0.0)), v.y, arc])
	TestLib.check(rec.floor_ticks == 0, "a tapped swing does not put the hero on the street (%d ticks)" % rec.floor_ticks)
	await _settle("tap")


# --- JUMP lets go with a boost -----------------------------------------------------------------------------------------------------------------

func _jump() -> void:
	await _tp(STREET, YAW, 0.2)
	await _first_rope()
	await _until(func() -> bool: return sn.swing.is_hanging() and sn.swing.rope_angle > 0.1 and sn.swing.rope_angle < 0.4 and p.velocity.y > 0.5, 4.0)
	var r0 := sn.swing.releases
	rec.begin(FWD)
	fg.press(2, &"jump")
	await _until(func() -> bool: return rec.rel_n > 0, 0.5)
	var v0 := rec.pre_v                                       # the tick before the rope let go, and the tick it did
	var v1 := rec.rel_v
	fg.up(2)
	var why: StringName = sn.swing.log[sn.swing.log.size() - 1]["why"] if not sn.swing.log.is_empty() else &"?"
	print("SW117 jump: %.1f m/s (vy %.1f) -> %.1f m/s (vy %.1f), why %s, SNAKE still held: %s" % [v0.length(), v0.y, v1.length(), v1.y, why, _state()])
	TestLib.check(sn.swing.releases == r0 + 1 and why == &"jump" and sn.mode == SnakeTraversal.Mode.NONE, "JUMP during a swing lets go at once")
	TestLib.check(v1.length() >= v0.length() * 1.04 and v1.y >= v0.y + 2.0 and v1.length() <= 45.0, "with a boost: faster and higher (%.1f -> %.1f m/s, vy %.1f -> %.1f), never over 45 m/s" % [v0.length(), v1.length(), v0.y, v1.y])
	var s0 := sn.swing.swings
	await _f(50)
	TestLib.check(sn.swing.swings == s0, "[old fails] the jump is the player's own: the still-held SNAKE fires no rope by itself in the next 0.8 s (%d)" % (sn.swing.swings - s0))
	await _settle("jump")


# --- the stick steers -------------------------------------------------------------------------------------------------------------------------

func _steer() -> void:
	var side: Array[float] = []
	for sx in [0.0, 1.0, -1.0]:
		await _tp(STREET, YAW, 0.2)
		await _first_rope()
		if sx != 0.0:
			fg.stick(Vector2(sx, 0.0))
		var z0 := p.global_position.z
		rec.begin(FWD)
		await _until(func() -> bool: return not sn.swing.is_hanging(), 1.4)
		side.append(p.global_position.z - z0)                 # +Z is the right hand of a hero who looks along +X
		fg.up_all()
		await _f(30)
	print("SW117 steer: sideways after 1.4 s of swing: no stick %.1f m, stick right %.1f m, stick left %.1f m; %s" % [side[0], side[1], side[2], rec.line()])
	TestLib.check(side[1] - side[0] > 2.5 and side[0] - side[2] > 2.5, "[old fails] the stick steers the swing: right %.1f m, left %.1f m beside the untouched arc" % [side[1] - side[0], side[2] - side[0]])
	TestLib.check(absf(side[0]) < 4.0, "[old fails] an untouched swing goes where the camera looks, not sideways into the building that holds the rope (%.1f m off the line)" % side[0])


# --- a still rope -----------------------------------------------------------------------------------------------------------------------------

func _still() -> void:
	await _tp(STREET, YAW, 0.2)
	rec.begin()
	var s0 := sn.swing.swings
	await _first_rope()
	fg.stick(Vector2(0.0, 1.0))                              # the thumb pulls back: brake
	var still_t := -1.0
	var worst_hang := 0.0
	var hang := 0.0
	var slow := 0.0
	for i in 60 * 12:
		await host.get_tree().physics_frame
		if sn.swing.is_hanging():
			hang += 1.0 / 60.0
			slow = slow + 1.0 / 60.0 if p.velocity.length() < 2.5 else 0.0
			worst_hang = maxf(worst_hang, slow)
		else:
			hang = 0.0
			slow = 0.0
		if p.is_on_floor() and sn.mode == SnakeTraversal.Mode.NONE and i > 60:
			still_t = float(i) / 60.0
			break
	var vy_land := rec.max_step
	print("SW117 still: SNAKE held, stick back: on the street after %.1f s (-1: never in 12 s), swings %d, longest time on a still rope %.2f s; %s; %s" % [still_t, sn.swing.swings - s0, worst_hang, rec.line(), _state()])
	TestLib.check(still_t > 0.0, "[old fails] a rope that is braked to a stop lowers the hero to the street while the button is still held (%.1f s)" % still_t)
	TestLib.check(sn.swing.swings - s0 <= 2, "[old fails] and the held button does not fire rope after rope at a hero who brakes (%d ropes)" % (sn.swing.swings - s0))
	TestLib.check(worst_hang < 2.5, "never left hanging on a still rope (%.2f s)" % worst_hang)
	fg.up_all()
	await _f(20)


# --- letting go -------------------------------------------------------------------------------------------------------------------------------

func _land() -> void:
	await _tp(STREET, YAW, 0.2)
	await _first_rope()
	fg.stick(Vector2(0.0, -1.0))                              # the left thumb stays forward, as a player's does
	await _until(_front, 4.0)
	fg.up(1)                                                  # the right thumb lets go
	await _seen()
	var v0 := p.velocity.length()
	var y0 := p.global_position.y
	var rolls0 := sn.landing_rolls
	rec.begin(FWD)
	var down := await _until(func() -> bool: return p.is_on_floor(), 8.0)
	var t_air := float(rec.ticks) / 60.0
	var v_touch := _hspeed()
	var modes_air: Dictionary = rec.modes.duplicate()
	await _f(60)
	var v_after := _hspeed()
	print("SW117 land: let go at %.1f m/s %.1f m up; touched down %s after %.1f s at %.1f m/s over the ground, rolls +%d, 1 s later %.1f m/s, %s; air modes %s; %s" % [v0, y0, down, t_air, v_touch, sn.landing_rolls - rolls0, v_after, _state(), modes_air, rec.line()])
	TestLib.check(down and not modes_air.has(&"climb") and sn.mode == SnakeTraversal.Mode.NONE, "hands off after a release: the hero lands on his feet, never on a wall in CLIMB (%s)" % sn.mode_name())
	TestLib.check(v_touch <= 14.0, "an air brake: he does not meet the street at swing speed (%.1f m/s over the ground, let go at %.1f)" % [v_touch, v0])
	TestLib.check(sn.landing_rolls > rolls0, "a landing out of a swing is a roll")
	TestLib.check(v_after <= Player.WALK_SPEED * Player.SPRINT_MULT + 0.6, "and one second later he is at running speed or slower (%.1f m/s)" % v_after)
	TestLib.check(rec.walls == 0, "no wall passed on the way down (%d)" % rec.walls)


# --- a swing at a facade ----------------------------------------------------------------------------------------------------------------------

func _wall() -> void:
	var worst_hang := 0.0
	var walls := 0
	var climbs := 0
	var stuck := 0
	var step := 0.0
	var tried := 0
	for yaw in [0.0, PI, -PI * 0.25, PI * 0.75]:              # across the avenue, at the facades and the corners
		await _tp(STREET, yaw, 0.35)
		rec.begin()
		var got := await _first_rope()
		if got:
			tried += 1
		await _f(60 * 3)
		fg.up_all()
		var down := await _until(func() -> bool: return p.is_on_floor() and sn.mode == SnakeTraversal.Mode.NONE, 8.0)
		walls += rec.walls
		step = maxf(step, rec.max_step)
		climbs += int(rec.modes.get(&"climb", 0))
		if not down:
			stuck += 1
		print("SW117 wall yaw %.2f: rope %s, down %s, %s; %s" % [yaw, got, down, rec.line(), _state()])
	TestLib.check(tried >= 2, "SNAKE held while looking at a facade bites an anchor (%d of 4 views)" % tried)
	TestLib.check(walls == 0, "a swing at a facade passes no wall (%d ticks)" % walls)
	TestLib.check(climbs == 0 and stuck == 0, "and never leaves the hero hanging on the wall: no unasked CLIMB (%d ticks), on his feet 8 s after the finger lifts (%d of 4 not)" % [climbs, stuck])
	TestLib.check(step <= 0.75, "no fling at the wall (biggest step %.2f m)" % step)
