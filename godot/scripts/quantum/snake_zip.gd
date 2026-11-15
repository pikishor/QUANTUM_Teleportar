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
	t = -clampf(from.distance_to(anchor) / SnakeSwing.TRAVEL_SPEED, 0.05, 0.2)       # the head leaves first; the pull starts when it bites
	var dh := Vector3(dest.x - from.x, 0.0, dest.z - from.z)
	dir = dh.normalized() if dh.length() > 0.1 else dir
	var hand := st.hand_callable(1)
	tendril = SnakeTendril.fire(hand, anchor, {"travel": -t, "wriggle": 0.35, "tension": 0.6, "thickness": 0.07, "host": p})
	tendril.user["keep"] = true
	zips += 1
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
	tendril = SnakeTendril.fire(a, b, {"travel": 0.12, "wriggle": 0.1, "tension": 1.0, "thickness": 0.065, "host": p})
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
			_arrive(p, true)
			return active
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
			_arrive(p, false)
			return active
	else:
		_stuck_t = 0.0
	if k >= 1.0:
		_arrive(p, false)
	return active


func _arrive(p: Player, blocked_at_wall: bool) -> void:
	if tendril != null:
		tendril.retract(0.12)
		tendril = null
	if blocked_at_wall or (kind == &"wall" and p.global_position.distance_to(dest) < 1.6):
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
