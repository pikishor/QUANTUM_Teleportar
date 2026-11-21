class_name SnakeZip
extends RefCounted
## SNAKE ZIP: the snake bites a target (a roof edge, a ledge, a wall, any point in reach) and reels the hero in: a short pull-in that accelerates, a straight line with a small lift, then a
## landing animation (a crouching touchdown on a roof, a slap against a wall that turns into a CLIMB). Also `start_line(a, b)`: a taut snake between two anchors that the hero rides from a to b
## (a rail between lamp posts, cranes, rooftops: missions and the world can place them). Owned by SnakeTraversal (`player.snake.zip`).
## The path is swept with move_and_collide, so a zip that meets a corner ends there instead of going through it.

const SPEED := 62.0
const MIN_TIME := 0.2
const MAX_TIME := 1.3
const LAND_TIME := 0.34
const LIFT := 0.07                       ## the arc rises this fraction of the distance (a roof zip rises more through the target itself)

var st: SnakeTraversal
var active := false
var phase: StringName = &"none"           ## pull, land
var kind: StringName = &"roof"            ## roof, wall, ground, vehicle, line
var from := Vector3.ZERO
var dest := Vector3.ZERO
var anchor := Vector3.ZERO
var normal := Vector3.UP
var dur := 0.4
var t := 0.0
var zips := 0
var lines := 0
var last_dist := 0.0
var land_t := 0.0
var dir := Vector3.FORWARD
var tendril: SnakeTendril
var _line_b := Vector3.ZERO
var _line := false
var _arrive_speed := 0.0
var _prev := Vector3.ZERO
var _stuck_t := 0.0
var _travel := 0.0                        ## seconds the snake head needs (the hero starts to move when it has bitten)
static var roof_arc := true               ## a zip to a roof rises early and comes in over the edge (a test switches it off to show the straight line of wave 115)
var end_reason: StringName = &""          ## how the last zip ended: arrived, wall (a wall in the way: a climb), stuck (held up for 0.35 s), cancel (tests and the wave 117 defect list read it)
var blocked_by := ""                      ## what held it up (the collider's path), "" when nothing did
## Wave 117 (critic 116 #4, flight log #1-2: "a ZIP ends hanging on a wall in CLIMB in about half the presses, 4 s later still there"): a zip that meets a wall no longer leaves the hero
## hanging. The snakes bite the roof edge above and HAUL him up the facade and over it (phase `haul`, end_reason `hauled`); with no edge within haul_max or something in the way he is
## DROPPED cleanly (a push off the wall, a short line on screen, end_reason `drop`). JUMP during a haul leaps off. `wall_end = false` = the old hang (tests show it failing).
static var haul_max := 140.0              ## metres of facade the snakes haul him up at most (a test lowers it to see the clean drop)
const HAUL_SPEED := 26.0
const HAUL_TIME_MAX := 3.2                ## ... in this many seconds at most: a tall tower is a faster ride
const HAUL_OVER := 0.32
const HAUL_COST_M := 0.3                  ## snake energy a metre of haul (a 28 m facade costs about as much as the zip itself)
static var wall_end := true
var hauls := 0
var drops := 0
var _haul_from := Vector3.ZERO
var _haul_stand := Vector3.ZERO
var _haul_rise := 0.5
var _haul_t := 0.0
var _haul_over_from := Vector3.ZERO
var _rq := PhysicsRayQueryParameters3D.new()
## Critic 117 (frames and a recorder per tick, real fingers): a roof ZIP of 31 m peaked at 101 m/s, 1.7 m in ONE tick, street to roof in 8 frames at 30 fps (a teleport), and
## its rope was fired at the point of the WALL under the crosshair (8 m up) while the hero went to the roof 28 m up: from the second frame on the rope hung DOWN from his hand.
## Now no zip is faster than `peak_speed` at any moment (it takes longer instead: 31 m in about 1.5 s) and the rope of a roof zip bites the roof's edge.
## `peak_speed = 0.0` and `rope_to_edge = false` are the builders' state (tests/test_critic_w117.gd shows its checks failing on them).
static var peak_speed := 44.0
static var rope_to_edge := true
const PEAK_K := 1.7                       ## the fastest moment of the pull is this many times its mean speed (the ease), 2.1 with the early rise of a roof zip
const PEAK_K_ROOF := 2.1
const MAX_TIME_CAPPED := 2.2             ## ... but no pull takes longer than this (tests/test_flight_cost_w116.gd gives a zip 3 s to end, head travel and landing included): a roof zip longer than 46 m is faster again (56 m: about 54 m/s at its peak)


func _init(owner_st: SnakeTraversal = null) -> void:
	st = owner_st


func cancel() -> void:
	if tendril != null:
		tendril.kill()
		tendril = null
	active = false
	phase = &"none"
	_line = false


## Start a zip toward a result of SnakeAnchors.find_zip.
func begin(p: Player, hit: Dictionary) -> void:
	active = true
	phase = &"pull"
	_line = false
	_stuck_t = 0.0
	kind = hit.get("kind", &"roof")
	anchor = hit["pos"]
	dest = hit["dest"]
	normal = hit.get("normal", Vector3.UP)
	from = p.global_position
	var d := from.distance_to(dest)
	last_dist = d
	dur = clampf(0.14 + d / SPEED, MIN_TIME, MAX_TIME)
	if peak_speed > 0.0:
		dur = clampf(maxf(dur, d * (PEAK_K_ROOF if (roof_arc and kind == &"roof" and dest.y > from.y + 1.5) else PEAK_K) / peak_speed), MIN_TIME, MAX_TIME_CAPPED)
	if rope_to_edge and kind == &"roof" and dest.y > anchor.y + 1.0:
		anchor = Vector3(anchor.x, dest.y + 0.05, anchor.z) + Vector3(normal.x, 0.0, normal.z) * 0.06
	t = -clampf(from.distance_to(anchor) / SnakeSwing.TRAVEL_SPEED, 0.05, 0.2)       # the head leaves first; the pull starts when it bites
	var dh := Vector3(dest.x - from.x, 0.0, dest.z - from.z)
	dir = dh.normalized() if dh.length() > 0.1 else dir
	var hand := st.hand_callable(1)
	tendril = SnakeTendril.fire(hand, anchor, {"travel": -t, "wriggle": 0.35, "tension": 0.6, "thickness": 0.07, "braid": 3, "host": p})
	tendril.user["keep"] = true
	zips += 1
	end_reason = &""
	blocked_by = ""
	_prev = from
	p.velocity = Vector3.ZERO
	st.energy_spend(SnakePower.cost(8.0))
	st.on_zip_started(from, dest)


## Ride a taut snake from a to b (the hero first reaches a with a short zip when he is not there). The line stays visible for the ride.
func start_line(p: Player, a: Vector3, b: Vector3) -> void:
	active = true
	phase = &"pull"
	_line = true
	kind = &"line"
	anchor = b
	dest = b + Vector3(0.0, -1.6, 0.0)
	from = a + Vector3(0.0, -1.6, 0.0)
	normal = Vector3.UP
	var d := from.distance_to(dest)
	last_dist = d
	dur = clampf(0.3 + d / (SPEED * 0.8), 0.4, 3.0)
	t = 0.0
	dir = Vector3(b.x - a.x, 0.0, b.z - a.z).normalized() if Vector2(b.x - a.x, b.z - a.z).length() > 0.1 else dir
	p.global_position = from
	p.velocity = Vector3.ZERO
	tendril = SnakeTendril.fire(a, b, {"travel": 0.12, "wriggle": 0.1, "tension": 1.0, "thickness": 0.065, "braid": 3, "host": p})
	tendril.user["keep"] = true
	lines += 1
	_prev = from
	st.on_zip_started(from, dest)


func is_landing() -> bool:
	return active and phase == &"land"


## One physics tick. Returns true while the zip still owns the body.
func tick(p: Player, dt: float, jump_pressed: bool) -> bool:
	if not active:
		return false
	if tendril != null and not tendril.is_alive():
		tendril = null
	if phase == &"haul":
		return _tick_haul(p, dt, jump_pressed)
	if phase == &"land":
		land_t -= dt
		p.velocity = p.velocity.lerp(dir * 4.0, 1.0 - exp(-8.0 * dt)) if kind != &"wall" else Vector3.ZERO
		p.move_and_slide()
		if land_t <= 0.0 or (jump_pressed and kind != &"wall"):
			_done(p)
			return false
		return true
	t += dt
	if t < 0.0:
		# the head is on its way: the hero hangs where he is, a hair of lift so he does not sag
		p.velocity = Vector3.ZERO
		return true
	var k := clampf(t / dur, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var e2 := e * (0.55 + 0.45 * e)               # a long ease-in, a late brake
	var pos := from.lerp(dest, e2)
	if not _line:
		# wave 116 (touch probe: 5 of 7 and 4 of 12 roof zips ended hanging under the roof edge or back on the street): the pull ran on a straight line from the street to a point ON the
		# roof, 1.4 m in from the edge, so it met the wall just below the edge and became a climb at the top of the facade. A zip up to a roof now gains its height early (the hero rises
		# along the facade first and comes in over the edge from above), with the same small lift on top.
		if roof_arc and kind == &"roof" and dest.y > from.y + 1.5:
			pos.y = lerpf(from.y, dest.y, 1.0 - (1.0 - e2) * (1.0 - e2) * (1.0 - e2))
		pos.y += sin(k * PI) * minf(last_dist * LIFT, 3.0)
	var step := pos - p.global_position
	var start := p.global_position
	var col := p.move_and_collide(step)
	if col != null and step.length() > 0.0005:
		var n := col.get_normal()
		var left := step.slide(n) * (1.0 - col.get_travel().length() / maxf(step.length(), 0.0001))
		var high := col.get_position().y - start.y > 0.75                                # a contact above the knees: a wall; below it a curb or a prop (the zip slides over it)
		var cobj := col.get_collider() as CollisionObject3D
		var is_static := cobj != null and (cobj.collision_layer & Game.L_VEHICLE) == 0     # a car that drives across the way is not a wall
		if absf(n.y) < 0.6 and n.dot(step.normalized()) < -0.3 and high and is_static:  # a wall in the way: the zip ends here
			normal = n
			p.velocity = (p.global_position - start) / maxf(dt, 0.0001)
			_arrive_speed = maxf(p.velocity.length(), _arrive_speed)
			end_reason = &"wall"
			blocked_by = str(cobj.get_path()) if cobj != null and cobj.is_inside_tree() else ""
			_arrive(p, true)
			return active
		blocked_by = str(cobj.get_path()) if cobj != null and cobj.is_inside_tree() else ""
		p.move_and_collide(left)                                                        # a curb, the floor, a ledge: slide along it
	p.velocity = (p.global_position - start) / maxf(dt, 0.0001)
	_arrive_speed = p.velocity.length()
	if tendril != null:
		tendril.tension = 1.0
		if _line:
			tendril.set_target(anchor)
	if k > 0.3 and p.velocity.length() < 1.0:                                           # held up by something that is not a wall: give up (never stuck in a zip)
		_stuck_t += dt
		if _stuck_t > 0.35:
			end_reason = &"stuck"
			_arrive(p, false)
			return active
	else:
		_stuck_t = 0.0
	if k >= 1.0:
		end_reason = &"arrived"
		_arrive(p, false)
	return active


func _arrive(p: Player, blocked_at_wall: bool) -> void:
	if tendril != null:
		tendril.retract(0.12)
		tendril = null
	if blocked_at_wall or (kind == &"wall" and p.global_position.distance_to(dest) < 1.6):
		if wall_end:
			var stand := edge_above(p, normal)
			if stand.is_finite():
				_begin_haul(p, stand)
			else:
				_drop(p)
			return
		var sn := st
		var wall := {"pos": p.global_position - normal * (Player.CAPSULE_RADIUS + 0.1), "normal": normal, "node": null, "kind": &"wall"}
		active = false
		phase = &"none"
		p.velocity = Vector3.ZERO
		if sn.climb_from_zip(p, wall):
			return
		return
	phase = &"land"
	land_t = LAND_TIME
	var v := Vector3(p.velocity.x, 0.0, p.velocity.z)
	dir = v.normalized() if v.length() > 0.5 else dir
	p.velocity = dir * minf(maxf(v.length() * 0.35, 3.0), 12.0)
	p.camera_rig.bump(clampf(_arrive_speed / 55.0, 0.2, 0.6))
	FX.shake(0.14)
	FX.burst(p.global_position + Vector3(0.0, 0.1, 0.0), Color(0.5, 1.0, 1.0), 10, 5.0, 0.4, 3.0, 0.9)
	st.on_zip_landed(p.global_position)


func _done(p: Player) -> void:
	active = false
	phase = &"none"
	var v := p.velocity
	p.velocity = v
	st.on_zip_ended()


func _ray(p: Player, a: Vector3, b: Vector3) -> Dictionary:
	_rq.from = a
	_rq.to = b
	_rq.collision_mask = Game.L_WORLD
	_rq.exclude = [p.get_rid()]
	return p.get_world_3d().direct_space_state.intersect_ray(_rq)


## Where the hero would stand after climbing over the edge of the wall he hangs on (wall normal `n`, feet at `from` or where he is): the first place above him where the wall ends
## and a floor with headroom begins, with nothing over his head on the way up. Vector3.INF when there is none within haul_max. About 20 rays for a 30 m facade, 70 at most.
func edge_above(p: Player, n: Vector3, from := Vector3.INF) -> Vector3:
	var into := -Vector3(n.x, 0.0, n.z)
	if into.length() < 0.2:
		return Vector3.INF
	into = into.normalized()
	var feet := from if from.is_finite() else p.global_position
	# 1. where the wall ends: coarse steps up the facade, then three halvings
	var lo := 0.4
	var hi := -1.0
	var h := 2.4
	while h <= haul_max + 2.4:
		var at := feet + Vector3(0.0, h, 0.0)
		if _ray(p, at, at + into * 2.6).is_empty():
			hi = h
			break
		lo = h
		h += 2.4
	if hi < 0.0:
		return Vector3.INF
	for i in 3:
		var mid := (lo + hi) * 0.5
		var at2 := feet + Vector3(0.0, mid, 0.0)
		if _ray(p, at2, at2 + into * 2.6).is_empty():
			hi = mid
		else:
			lo = mid
	# 2. the floor behind the edge (a parapet or a cornice can be two or three metres deep)
	var stand := Vector3.INF
	for depth in [1.1, 1.8, 2.6, 3.5]:
		var col: Vector3 = feet + Vector3(0.0, hi + 1.3, 0.0) + into * float(depth)
		var top := _ray(p, col, col + Vector3.DOWN * 4.2)
		if top.is_empty() or (top["normal"] as Vector3).y < 0.75:
			continue
		var st2 := (top["position"] as Vector3) + Vector3(0.0, 0.05, 0.0)
		if _ray(p, st2 + Vector3.UP * 0.25, st2 + Vector3.UP * 2.0).is_empty():
			stand = st2
			break
	if not stand.is_finite() or stand.y - feet.y > haul_max:
		return Vector3.INF
	# 3. nothing over his head on the way up (an overhang, a balcony, a bridge)
	if not _ray(p, feet + Vector3(0.0, 0.5, 0.0), Vector3(feet.x, stand.y + 0.6, feet.z)).is_empty():
		return Vector3.INF
	return stand


func _begin_haul(p: Player, stand: Vector3) -> void:
	phase = &"haul"
	end_reason = &"hauled"
	hauls += 1
	_haul_from = p.global_position
	_haul_stand = stand
	_haul_t = 0.0
	_stuck_t = 0.0
	var up := maxf(stand.y + 0.3 - _haul_from.y, 0.0)
	_haul_rise = clampf(0.22 + up / HAUL_SPEED, 0.3, HAUL_TIME_MAX)
	var into := -Vector3(normal.x, 0.0, normal.z).normalized()
	dir = into
	p.velocity = Vector3.ZERO
	if tendril != null:
		tendril.kill()
	# the rope lets go of the wall and bites the edge of the roof
	var edge := Vector3(_haul_from.x, stand.y + 0.05, _haul_from.z) + into * 0.55
	tendril = SnakeTendril.fire(st.hand_callable(1), edge, {"travel": 0.08, "wriggle": 0.25, "tension": 1.0, "thickness": 0.07, "braid": 3, "host": p})
	tendril.user["keep"] = true
	Sfx.play(&"snk_fire", -5.0)
	st.event.emit(&"zip_haul")


func _tick_haul(p: Player, dt: float, jump_pressed: bool) -> bool:
	_haul_t += dt
	if jump_pressed:                                                               # JUMP leaps off the wall
		if tendril != null:
			tendril.retract(0.12)
			tendril = null
		p.velocity = normal * 6.0 + Vector3.UP * 7.0
		end_reason = &"leap"
		_done(p)
		return false
	var top_y := _haul_stand.y + 0.3
	if _haul_t < _haul_rise:
		var k := _haul_t / _haul_rise
		var e := k * k * (3.0 - 2.0 * k)
		var want := Vector3(_haul_from.x, lerpf(_haul_from.y, top_y, e), _haul_from.z)
		var before := p.global_position
		var col := p.move_and_collide(want - before)
		p.velocity = (p.global_position - before) / maxf(dt, 0.0001)
		st.energy_spend(SnakePower.cost(HAUL_COST_M) * maxf(p.global_position.y - before.y, 0.0))      # the ride up is paid by the metre (it never stops for lack of energy: he is not left hanging)
		if col != null and want.y - p.global_position.y > 0.25:
			_stuck_t += dt
			if _stuck_t > 0.25:                                                     # something in the way after all: never left hanging
				_drop(p)
				return false
		_haul_over_from = p.global_position
		if tendril != null:
			tendril.tension = 1.0
		return true
	var k2 := clampf((_haul_t - _haul_rise) / HAUL_OVER, 0.0, 1.0)
	var e2 := k2 * k2 * (3.0 - 2.0 * k2)
	var dest2 := _haul_stand + dir * 0.3
	var pos := _haul_over_from.lerp(dest2, e2)
	pos.y = maxf(pos.y, lerpf(_haul_over_from.y, dest2.y, e2)) + sin(k2 * PI) * 0.25
	var prev := p.global_position
	p.global_position = pos
	p.velocity = (pos - prev) / maxf(dt, 0.0001)
	if k2 >= 1.0:
		if tendril != null:
			tendril.retract(0.2)
			tendril = null
		kind = &"roof"
		phase = &"land"
		land_t = LAND_TIME * 0.6
		p.velocity = dir * 3.0
		p.camera_rig.bump(0.2)
		FX.burst(p.global_position + Vector3(0.0, 0.1, 0.0), Color(0.5, 1.0, 1.0), 8, 4.0, 0.4, 3.0, 0.9)
		st.on_zip_landed(p.global_position)
	return true


## No edge to climb over: the snakes let go and the hero comes off the wall and falls clear of it (a line on screen says why; nothing hurts him: there is no fall damage and a long
## fall ends in the landing roll).
func _drop(p: Player) -> void:
	if tendril != null:
		tendril.retract(0.15)
		tendril = null
	drops += 1
	end_reason = &"drop"
	p.velocity = Vector3(normal.x, 0.0, normal.z) * 2.2 + Vector3(0.0, 1.0, 0.0)
	Game.say("NO LEDGE ABOVE  DROPPED", 1.3)
	Sfx.play(&"snk_miss", -6.0)
	_done(p)
