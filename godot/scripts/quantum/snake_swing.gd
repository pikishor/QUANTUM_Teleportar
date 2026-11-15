class_name SnakeSwing
extends RefCounted
## SNAKE SWING: the hero fires a QUANTUM SNAKE at an anchor up and ahead of him (building, rooftop, bridge, crane, lamp post, wind turbine, aircraft, car, cliff) and swings on it like a pendulum.
## Owned by SnakeTraversal (`player.snake.swing`). Phases: travel (the head is on its way: the hero keeps flying), hang (the rope is taut, the hero swings), and the release (the snake lets go and the
## hero keeps his speed with a boost).
##
## Physics (one rigid inextensible rope, 60 Hz): gravity GRAVITY, the stick steers across the rope (STEER_ACC) and pumps along the motion (PUMP_ACC), ASSIST_ACC feeds the swing on the way down (assist
## on), drag DRAG, the radial speed away from the anchor is removed whenever the rope is taut (momentum along the arc is conserved: the speed gained by dropping is the speed at the bottom), the body
## slides along buildings it touches (move_and_slide) and is pulled back onto the rope sphere after the move. Release: speed x SnakePower.release_boost() x (1 + chain bonus) and an upward kick, so the arc
## carries on. AUTO CHAIN (assist on, button still held): past the bottom of the arc, with a new anchor ahead, the swing lets go by itself and the next snake leaves the hand: hold the button and
## steer with the camera to cross the city.
## Counters (tests wait on these): swings, releases, chain (consecutive swings without touching the ground), best_chain, speed records.

const GRAVITY := 19.0
const STEER_ACC := 10.0
const PUMP_ACC := 7.0
const DRAG := 0.045
const MIN_ROPE := 8.0
const ATTACH_PULL := 5.5                ## m/s toward the anchor the moment the snake bites (the yank)
const TRAVEL_SPEED := 210.0             ## the head's speed (m/s): a 40 m anchor is reached in about 0.19 s
const HAND_DROP := 0.15
const MAX_ANGLE := 1.3
const MAX_HANG := 6.0                   ## seconds: a swing that long lets go by itself
const RELEASE_KICK := 3.0
const REL_ANGLE_FAST := 0.45            ## rad from straight down at which an auto release happens when fast (measured: 10 swings, 558 m in 26 s, tests/dev_snake_chain.gd) ...
const REL_ANGLE_SLOW := 0.6             ## ... and when slow
const BODY_CENTRE := 1.25               ## metres above the feet where the rope pulls (the hand)
const CLEAR := 9.0                      ## the lowest point of a swing keeps this much air under it: a rope that is longer than anchor height minus this is reeled in (measured: a 51 m rope on a 49 m high anchor put the hero into the street)
static var reel_on := true                ## dev probes switch the clearance reel off to compare
const REEL_SPEED := 40.0                ## m/s the snake pulls the hero in when it shortens the rope

## tunables of the feel (static so a probe can sweep them: tests/dev_snake_chain.gd reads SC_* variables)
static var assist_acc := 8.5            ## m/s^2 along the motion on the way down (assist on)
static var assist_rise := 3.0           ## m/s^2 along the motion on the way up (keeps the arc from dying)
static var rel_fast := REL_ANGLE_FAST
static var rel_slow := REL_ANGLE_SLOW

var st: SnakeTraversal
var active := false
var phase: StringName = &"none"          ## none, travel, hang
var anchor := Vector3.ZERO
var anchor_node: Node3D
var anchor_local := Vector3.ZERO
var rope := 20.0
var rope_goal := 20.0                   ## the length the rope is reeled to (the bite length, or less when the lowest point would be too near the ground)
var tendril: SnakeTendril
var time := 0.0
var swings := 0                         ## counters
var releases := 0
var chain := 0
var best_chain := 0
var max_speed := 0.0
var last_release_speed := 0.0
var last_arc_len := 0.0                 ## metres from the attach point to the release point of the last swing
var walls_avoided := 0
var log: Array[Dictionary] = []                  ## one entry per finished swing: rope, anchor height, peak and release speed, arc length, why it ended (dev probes and the tuning notes)
var _peak_v := 0.0
var rope_angle := 0.0                   ## radians from straight down (+ ahead of the anchor)
var tension := 0.0
var swing_dir := Vector3.FORWARD         ## horizontal direction of the swing
var hand_side := 1                      ## which hand holds the snake (alternates)
var _travel_left := 0.0
var _hit: Dictionary = {}
var _attach_pos := Vector3.ZERO
var _hang_t := 0.0
var _slow_t := 0.0
var _arc_len_acc := 0.0
var _last_pos := Vector3.ZERO
var _ground_t := 0.0
var _rq := PhysicsRayQueryParameters3D.new()


func _init(owner_st: SnakeTraversal = null) -> void:
	st = owner_st


func cancel() -> void:
	if tendril != null:
		tendril.kill()
		tendril = null
	active = false
	phase = &"none"
	chain = 0
	_hit = {}


## Leave the hand toward an anchor result of SnakeAnchors (pos, node, local). Call from SnakeTraversal; the swing becomes active at once (phase travel).
func begin(p: Player, hit: Dictionary, from_ground := false) -> void:
	active = true
	phase = &"travel"
	_hit = hit
	anchor = hit["pos"]
	anchor_node = hit.get("node") as Node3D if (hit.get("kind", &"") == &"vehicle") else null
	anchor_local = hit.get("local", Vector3.ZERO)
	time = 0.0
	_hang_t = 0.0
	_slow_t = 0.0
	_ground_t = 0.0
	hand_side = -hand_side
	var hand := st.hand_callable(hand_side)
	var o: Vector3 = hand.call()
	var dist := o.distance_to(anchor)
	_travel_left = clampf(dist / TRAVEL_SPEED, 0.06, 0.24)
	tendril = SnakeTendril.fire(hand, Callable(self, "_anchor_now"), {"travel": _travel_left, "wriggle": 0.55, "tension": 0.3, "thickness": 0.07, "host": p})
	tendril.user["keep"] = true
	var dir_h := Vector3(anchor.x - p.global_position.x, 0.0, anchor.z - p.global_position.z)
	swing_dir = dir_h.normalized() if dir_h.length() > 0.1 else swing_dir
	if from_ground:
		p.velocity.y = maxf(p.velocity.y, 6.0 * HeroPower.f("jump") ** 0.5)
	st.say_swing_started()
	_last_pos = p.global_position
	_arc_len_acc = 0.0


## The longest rope that keeps the lowest point of the pendulum clear of the ground beside the anchor: CLEAR metres of air under the swing, less under a low anchor (45 % of its height, at
## least 2.5 m), so even a lamp post gives a short swing. The ground is read 5 m and 12 m out from the wall the anchor sits on (a ray straight down at the wall itself meets ledges, cornices and
## awnings); the higher of the two counts. No ground found = the street at y 0.
static func max_rope(anchor_pos: Vector3, normal: Vector3, space: PhysicsDirectSpaceState3D) -> float:
	var out := Vector3(normal.x, 0.0, normal.z)
	out = out.normalized() if out.length() > 0.2 else Vector3.ZERO
	var gy := -INF
	for off in ([0.0] if out == Vector3.ZERO else [5.0, 12.0]):
		var from := anchor_pos + out * float(off) + Vector3(0.0, -0.3, 0.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -260.0, 0.0), Game.L_WORLD))
		gy = maxf(gy, (hit["position"] as Vector3).y if not hit.is_empty() else 0.0)
	var h := anchor_pos.y - gy
	return h - clampf(h * 0.45, 2.5, CLEAR)


func _anchor_now() -> Vector3:
	if anchor_node != null and is_instance_valid(anchor_node) and anchor_node.is_inside_tree():
		anchor = anchor_node.global_transform * anchor_local
	return anchor


func is_hanging() -> bool:
	return active and phase == &"hang"


## Let go. `boost` false = a plain drop (button released too late, the anchor vanished). Returns the speed after the release.
func release(p: Player, boost := true, why: StringName = &"hand") -> float:
	if not active:
		return 0.0
	var v := p.velocity
	var sp := v.length()
	if phase == &"hang" and boost and sp > 3.0:
		var k := SnakePower.release_boost() + float(mini(chain, SnakePower.CHAIN_MAX)) * SnakePower.chain_bonus()
		var nv := v * k
		if v.y > -3.0:
			nv.y += clampf(sp * 0.1, 1.2, RELEASE_KICK + 2.0)
		var cap := SnakePower.speed_cap() * 1.15
		if nv.length() > cap:
			nv = nv.normalized() * cap
		p.velocity = nv
		sp = nv.length()
	last_release_speed = sp
	last_arc_len = _arc_len_acc
	releases += 1
	if phase == &"hang":
		log.append({"t": snappedf(time, 0.01), "rope": snappedf(rope, 0.1), "dy": snappedf(anchor.y - _attach_pos.y, 0.1), "peak": snappedf(_peak_v, 0.1), "rel": snappedf(sp, 0.1), "arc": snappedf(_arc_len_acc, 0.1), "angle": snappedf(rope_angle, 0.01), "why": why, "hang": snappedf(_hang_t, 0.01), "fan": st.anchors.stats.duplicate(true)})
		if log.size() > 40:
			log.pop_front()
	if tendril != null:
		tendril.retract(0.14)
		tendril = null
	var was_hang := phase == &"hang"
	active = false
	phase = &"none"
	st.on_swing_released(was_hang, sp)
	return sp


## One physics tick while active. `wish` is the world move direction from the stick (length 0..1), `hold` the SNAKE button, `jump_pressed` an edge of JUMP.
## Returns true while the swing still owns the body.
func tick(p: Player, dt: float, wish: Vector3, hold: bool, jump_pressed: bool) -> bool:
	if not active:
		return false
	time += dt
	if tendril != null and not tendril.is_alive():
		tendril = null
	if phase == &"travel":
		return _tick_travel(p, dt, wish, hold)
	return _tick_hang(p, dt, wish, hold, jump_pressed)


func _tick_travel(p: Player, dt: float, wish: Vector3, hold: bool) -> bool:
	# the hero flies on while the head travels; a released button cancels the shot
	if not hold:
		cancel()
		active = false
		return false
	_travel_left -= dt
	st.free_air(p, dt, wish)
	if tendril != null and tendril.state == SnakeTendril.State.ATTACHED or _travel_left <= -0.12:
		_bite(p)
	if tendril == null and phase == &"travel":
		cancel()
		return false
	return true


func _bite(p: Player) -> void:
	_anchor_now()
	var c := p.global_position + Vector3(0.0, BODY_CENTRE, 0.0)
	var d := c.distance_to(anchor)
	if d < 3.0 or not is_finite(d):
		cancel()
		return
	phase = &"hang"
	rope = clampf(d, MIN_ROPE, SnakePower.range_m() + 8.0)
	rope_goal = clampf(minf(rope, max_rope(anchor, _hit.get("normal", Vector3.ZERO) as Vector3, p.get_world_3d().direct_space_state)), MIN_ROPE, rope) if reel_on else rope
	var towards := (anchor - c) / d
	var outward := -p.velocity.dot(towards)
	# the yank: a short pull along the rope so the swing starts with energy even from a standstill
	p.velocity += towards * ATTACH_PULL
	if outward < 0.0:
		pass
	swings += 1
	chain += 1
	best_chain = maxi(best_chain, chain)
	_attach_pos = c
	_hang_t = 0.0
	_ground_t = 0.0
	_arc_len_acc = 0.0
	_peak_v = 0.0
	_last_pos = p.global_position
	st.energy_spend(SnakePower.cost(4.0))
	st.on_swing_attached(anchor)


func _tick_hang(p: Player, dt: float, wish: Vector3, hold: bool, jump_pressed: bool) -> bool:
	_anchor_now()
	_hang_t += dt
	if rope > rope_goal:
		rope = maxf(rope_goal, rope - REEL_SPEED * dt)
	var c := p.global_position + Vector3(0.0, BODY_CENTRE, 0.0)
	var r := c - anchor
	var d := maxf(r.length(), 0.001)
	var rn := r / d
	var v := p.velocity
	v.y -= GRAVITY * dt
	var speed := v.length()
	# steering across the rope and pumping along the motion
	if wish.length() > 0.05:
		var side := wish - rn * wish.dot(rn)
		if side.length() > 0.01:
			v += side.normalized() * STEER_ACC * minf(wish.length(), 1.0) * dt
		if speed > 4.0:
			var along := Vector3(v.x, 0.0, v.z).normalized()
			var push := wish.dot(along)
			if push > 0.0:
				v += along * PUMP_ACC * push * dt
	if st.assist and speed > 3.0:
		v += (v / maxf(speed, 0.01)) * (assist_acc if v.y < 1.5 else (assist_rise if speed > 8.0 else 0.0)) * dt
	v *= 1.0 - DRAG * dt
	if st.assist:
		v = _avoid_walls(p, v, dt)
	if d >= rope - 0.03:
		var vr := v.dot(rn)
		if vr > 0.0:
			v -= rn * vr
	var cap := SnakePower.speed_cap() * (1.0 + float(mini(chain, SnakePower.CHAIN_MAX)) * SnakePower.chain_bonus() * 0.5)
	if v.length() > cap:
		v = v.normalized() * cap
	p.velocity = v
	p.move_and_slide()
	v = p.velocity
	# back onto the rope sphere
	var c2 := p.global_position + Vector3(0.0, BODY_CENTRE, 0.0)
	var r2 := c2 - anchor
	var d2 := r2.length()
	if d2 > rope:
		var corr := anchor + r2 / d2 * rope - c2
		p.move_and_collide(corr)
		var rn2 := (p.global_position + Vector3(0.0, BODY_CENTRE, 0.0) - anchor).normalized()
		var vr2 := v.dot(rn2)
		if vr2 > 0.0:
			v -= rn2 * vr2
		p.velocity = v
	var moved := p.global_position.distance_to(_last_pos)
	_arc_len_acc += moved
	_last_pos = p.global_position
	var sp := p.velocity.length()
	max_speed = maxf(max_speed, sp)
	_peak_v = maxf(_peak_v, sp)
	# state of the rope
	var rr := p.global_position + Vector3(0.0, BODY_CENTRE, 0.0) - anchor
	var rd := maxf(rr.length(), 0.001)
	tension = clampf((rd - (rope - 1.5)) / 1.5, 0.0, 1.0)
	var hz := Vector3(rr.x, 0.0, rr.z)
	var ahead := hz.dot(Vector3(p.velocity.x, 0.0, p.velocity.z))
	rope_angle = atan2(hz.length(), maxf(-rr.y, 0.0001)) * (1.0 if ahead >= 0.0 else -1.0)
	if tendril != null:
		tendril.tension = lerpf(tendril.tension, 0.35 + 0.65 * tension, 1.0 - exp(-12.0 * dt))
	var vh := Vector3(p.velocity.x, 0.0, p.velocity.z)
	if vh.length() > 3.0:
		swing_dir = vh.normalized()
	# ground contact
	if p.is_on_floor():
		_ground_t += dt
		if _ground_t > 0.25 and sp < 9.0:
			release(p, false, &"ground")
			return false
	else:
		_ground_t = 0.0
	if sp < 2.0:
		_slow_t += dt
		if _slow_t > 1.2:
			release(p, true, &"stalled")
			return false
	else:
		_slow_t = 0.0
	# the end of the swing
	if jump_pressed:
		release(p, true, &"jump")
		return false
	if not hold:
		release(p, true, &"button")
		return false
	if _hang_t > MAX_HANG:
		release(p, true, &"time")
		return false
	if st.assist and _hang_t > 0.45:
		var lim := lerpf(rel_slow, rel_fast, clampf((sp - 14.0) / 26.0, 0.0, 1.0))
		if rope_angle > lim and p.velocity.y > 0.5 and (sp > 22.0 or st.chain_anchor_ready(p) or _gap_below(p) > 22.0):
			release(p, true, &"chain")                        # past the bottom and still fast: let go, the next snake leaves when an anchor shows (or the hero flies on his speed)
			return false
		if rope_angle > MAX_ANGLE and p.velocity.y > -1.0:
			release(p, true, &"max_angle")                    # as far as the rope goes: let go (the chain scans for the next anchor, else the hero falls)
			return false
		if sp < 7.0 and _hang_t > 1.2 and rope_angle > 0.35:
			release(p, false, &"dead")                        # a dead swing at the top of its arc: drop, the chain looks for the next anchor on the way down
			return false
	return true


func _gap_below(p: Player) -> float:
	_rq.collision_mask = Game.L_WORLD
	_rq.exclude = [p.get_rid()]
	_rq.from = p.global_position + Vector3(0.0, 0.5, 0.0)
	_rq.to = p.global_position + Vector3(0.0, -60.0, 0.0)
	var hit := p.get_world_3d().direct_space_state.intersect_ray(_rq)
	if hit.is_empty():
		return 60.0
	return p.global_position.y - (hit["position"] as Vector3).y


## Steer away from walls near the swing: a short ray along the motion and one to each side push the hero off a facade instead of letting him scrape along it.
func _avoid_walls(p: Player, v: Vector3, dt: float) -> Vector3:
	var vh := Vector3(v.x, 0.0, v.z)
	var sh := vh.length()
	if sh < 5.0:
		return v
	var fwd := vh / sh
	var side := fwd.cross(Vector3.UP)
	var from := p.global_position + Vector3(0.0, BODY_CENTRE, 0.0)
	var space := p.get_world_3d().direct_space_state
	_rq.collision_mask = Game.L_WORLD
	_rq.exclude = [p.get_rid()]
	var out := v
	for k in 3:
		var dir := fwd if k == 0 else (side if k == 1 else -side)
		var reach := (sh * 0.5 + 2.5) if k == 0 else 3.2
		_rq.from = from
		_rq.to = from + dir * reach
		var hit := space.intersect_ray(_rq)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if n.y > 0.55:
			continue
		var nh := Vector3(n.x, 0.0, n.z)
		if nh.length() < 0.1:
			continue
		nh = nh.normalized()
		var dist := from.distance_to(hit["position"] as Vector3)
		var close := 1.0 - clampf(dist / reach, 0.0, 1.0)
		out += nh * (34.0 if k == 0 else 20.0) * close * dt
		walls_avoided += 1
	return out
