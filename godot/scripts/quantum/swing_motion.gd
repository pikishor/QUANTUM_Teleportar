class_name SwingMotion
extends RefCounted
## WAVE 117: THE MOTION OF THE SNAKE SWING (owner round 7: "just like spiderman ... our hero can jump"; "it behaves abnormally"). Static functions that work on a SnakeSwing
## (`s`): SnakeSwing keeps the state, the counters, the rope's look and its old (wave 116) motion behind `SnakeSwing.old_motion`.
##
## What was abnormal (measured by real fingers, tests/test_swing_w117.gd with SWING_OLD=1): the rope hung from a point on a facade BESIDE the street, so the free pendulum pulled the
## hero 11 m sideways into that building in 1.4 s; the release multiplied the speed (10 to 47 m/s in one chain); the rope sphere moved the body up to 1.4 m in a tick; a held
## button looked beside and behind for the next anchor (the chain turned back on itself); a tap was a 0.55 s twitch that dropped him on the street; nothing braked a release.
##
## The model now:
##   PLANE   the pendulum swings in the vertical plane of the travel direction (`s.swing_dir`: the camera's heading at the bite, bent by the stick). Its centre `s.pivot` is the
##           anchor moved sideways into that plane, so the rope still ends on the building (`s.anchor`, drawn by the rope) and keeps its drawn length, but nothing pulls the hero
##           sideways: a trapeze, not a wrecking ball. The stick steers left / right (the plane turns with him), back brakes, forward pumps.
##   ROPE    its length is kept; it only ever gets SHORTER: the snake takes up slack (a hero who flies toward the anchor is not snapped back when the rope goes taut) and reels in
##           at REEL m/s when the lowest point of the arc would be nearer the street than CLEAR_* (read under the whole arc at the bite, and under the hero each tick).
##   SPEED   gravity does the work (v^2 = v0^2 + 2 g h). The assist only tops the speed up toward the speed a swing with `bottom_speed()` at its lowest point has at this height
##           (so a chain does not die and every release is alike) and trims what is over it; V_HARD is a hard cap. No multiplier anywhere.
##   LET GO  finger up = the hero flies on along his velocity, with a small upward help near the front of the arc (HELP_UP). JUMP = the same with JUMP_BOOST and JUMP_UP.
##           Button held (or a TAP: a finger that left within TAP_WINDOW): the swing lets go by itself at the front of the arc (REL_FRONT rad, rising).
##   NEVER   through a wall (a body against a facade for WALL_TIME lets go and is pushed off it), on the street (floor contact lets go), stuck (a rope slower than STILL_SPEED
##           for STILL_TIME lowers the hero at LOWER_SPEED and lets go over the ground), flung (MAX_CORR metres of rope correction a tick).

const ROPE_MIN := 6.0
const ROPE_MAX := 36.0                  ## a longer rope is reeled in to this
const ROPE_GOOD := 28.0                 ## the anchor score likes ropes up to this (rhythm: 1 to 1.5 s a swing; a rope capped at 28 m lifted the hero 12 m a swing, up to the roofline)
const REEL := 16.0                      ## m/s the rope shortens when it has to
const CLEAR_MIN := 2.2                  ## air under the feet at the lowest point: a quarter of the anchor's height, between these
const CLEAR_MAX := 4.5
const REL_FRONT := 0.62                 ## rad past the lowest point at which a held / tapped swing lets go (36 degrees: a throw forward and up)
const REL_MAX := 1.25
const TAP_WINDOW := 0.25                ## a finger that leaves the button this soon after the bite tapped: the swing runs to the front of its arc
const TAP_MAX := 1.9                    ## ... or this long
const STILL_SPEED := 2.5
const STILL_TIME := 0.7
const LOWER_SPEED := 7.0
const LOWER_MAX := 5.0                  ## seconds of lowering before the rope lets go wherever the hero is
const V_HARD := 42.0
const JUMP_BOOST := 1.12
const JUMP_UP := 5.0
const HELP_UP := 1.5
const STEER := 12.0                     ## m/s^2 sideways at full stick
const SIDE_DAMP := 2.5                  ## 1/s: sideways drift dies when the stick is idle
const BRAKE := 14.0                     ## m/s^2 with the stick pulled back
const ASSIST := 14.0                    ## m/s^2 at most toward the target speed
const TRIM := 6.0
const DRAG := 0.02
const MAX_CORR := 0.3                   ## metres the rope may move the body in one tick
const WALL_TIME := 0.2
const ABOVE_MIN := 2.5                   ## an anchor this little above the eye will do (the old search wanted 4.5 m: a hero thrown to the roofline found nothing); the reel keeps the arc off the street
const AUTO_WHYS: Array[StringName] = [&"chain", &"max_angle"]
## Critic 117 (measured by real fingers on three streets): a held chain gained about 10 m a swing (32 to 47 m up after five swings, ropes of 7 to 10 m at the roofline that
## lasted 0.6 s, then free falls of 1.5 to 2 s; more than half of the time off the rope). A swing let go 0.62 rad past its lowest point throws the hero 6 to 7 m up, and the
## anchor score liked ropes that point steeply up (the arc's lowest point is then barely under the hero). Now the chain LEVELS OFF: the higher over the street the hero is,
## the flatter a held swing lets go (REL_HIGH at CRUISE_HI and above), and the anchor score likes ropes that give a DIVE back down to cruise height (flat, long ropes).
## `level_chain = false` is the builders' state (tests/test_critic_w117.gd shows its checks failing on it).
static var level_chain := true
const CRUISE_LO := 9.0                  ## metres over the street: under this a swing is as before
const CRUISE_HI := 20.0
const REL_HIGH := 0.2                   ## rad past the lowest point at which a held swing lets go when high
static var scan_h := 0.0                ## height of the eye over the street in the anchor search that is running (SnakeAnchors.find_swing sets it)
## Critic 117: in a held chain the next rope is fired by the game with the thumb already down; a thumb lifted within TAP_WINDOW of THAT bite was read as a tap ("one whole
## swing") and the rope let go a second later. Only a fresh press can be a tap. `tap_needs_press = false` is the builders' state.
static var tap_needs_press := true


## The angle past the lowest point at which a held / tapped swing lets go, for a hero `h` metres over the street.
static func rel_front(h: float) -> float:
	if not level_chain:
		return REL_FRONT
	return lerpf(REL_FRONT, REL_HIGH, clampf((h - CRUISE_LO) / (CRUISE_HI - CRUISE_LO), 0.0, 1.0))


## The speed of a swing at its lowest point that the assist holds (m/s): NORMAL 29.7, STORY 34, HARD 25.3.
static func bottom_speed() -> float:
	return clampf(SnakePower.speed_cap() * 0.55, 24.0, 34.0)


static func plane_normal(dir: Vector3) -> Vector3:
	return dir.cross(Vector3.UP).normalized()


## The anchor moved sideways into the vertical plane through `c` along `dir`, and at least 1.5 m ahead of `c`.
static func pivot_for(anchor: Vector3, c: Vector3, dir: Vector3) -> Vector3:
	var n := plane_normal(dir)
	var pv := anchor - n * (anchor - c).dot(n)
	var f := (pv - c).dot(dir)
	if f < 1.5:
		pv += dir * (1.5 - f)
	return pv


## The longest rope on `pivot` whose lowest point keeps the feet clear of everything under the arc (the street, cars, kiosks, low roofs).
static func clear_rope(space: PhysicsDirectSpaceState3D, pivot: Vector3, dir: Vector3, rope: float, exclude: Array[RID]) -> float:
	var gy := -INF
	var span := minf(rope, ROPE_MAX)
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = Game.L_WORLD
	q.exclude = exclude
	for k: float in [-0.5, -0.25, 0.0, 0.25, 0.5]:
		q.from = pivot + dir * (span * k) + Vector3(0.0, -1.0, 0.0)
		q.to = q.from + Vector3(0.0, -260.0, 0.0)
		var hit := space.intersect_ray(q)
		gy = maxf(gy, (hit["position"] as Vector3).y if not hit.is_empty() else 0.0)
	var h := pivot.y - gy
	return h - SnakeSwing.BODY_CENTRE - clampf(h * 0.25, CLEAR_MIN, CLEAR_MAX)


# --- the bite ----------------------------------------------------------------------------------------------------------------------------

static func bite(s: SnakeSwing, p: Player) -> void:
	s._anchor_now()
	var c := p.global_position + Vector3(0.0, SnakeSwing.BODY_CENTRE, 0.0)
	var d0: Vector3 = s._hit.get("dir", Vector3.ZERO)
	d0 = Vector3(d0.x, 0.0, d0.z)
	if d0.length() < 0.1:
		d0 = Vector3(s.anchor.x - c.x, 0.0, s.anchor.z - c.z)
	if d0.length() < 0.1:
		d0 = s.swing_dir
	d0 = d0.normalized()
	var vh := Vector3(p.velocity.x, 0.0, p.velocity.z)
	if vh.length() > 6.0 and vh.normalized().dot(d0) > 0.2:
		d0 = (d0 * 0.7 + vh.normalized() * 0.3).normalized()
	s.swing_dir = d0
	s.pivot = pivot_for(s.anchor, c, d0)
	var d := c.distance_to(s.pivot)
	if not is_finite(d) or s.pivot.y - c.y < 2.0:
		s.cancel()
		return
	s.phase = &"hang"
	s.rope = maxf(d, ROPE_MIN)
	s.rope_goal = clampf(minf(minf(s.rope, ROPE_MAX), clear_rope(p.get_world_3d().direct_space_state, s.pivot, d0, s.rope, [p.get_rid()])), ROPE_MIN, s.rope)
	s.swings += 1
	s.chain += 1
	s.best_chain = maxi(s.best_chain, s.chain)
	s._attach_pos = c
	s._hang_t = 0.0
	s._ground_t = 0.0
	s._slow_t = 0.0
	s._wall_t = 0.0
	s._lower_t = 0.0
	s._commit = false
	s._hold_prev = true
	s.lowering = false
	s._anchor_prev = s.anchor
	s._arc_len_acc = 0.0
	s._peak_v = 0.0
	s._last_pos = p.global_position
	s.st.energy_spend(SnakePower.cost(4.0))
	s.st.on_swing_attached(s.anchor)


# --- one tick on the rope ----------------------------------------------------------------------------------------------------------------

## Returns true while the swing still owns the body.
static func tick_hang(s: SnakeSwing, p: Player, dt: float, wish: Vector3, hold: bool, jump_pressed: bool) -> bool:
	var a_prev := s._anchor_prev
	s._anchor_now()
	s.pivot += s.anchor - a_prev                          # a rope on a car or an aircraft: the pendulum's centre rides along
	s._anchor_prev = s.anchor
	s._hang_t += dt
	if not hold and s._hang_t <= TAP_WINDOW and (s.fresh_press or not tap_needs_press):
		s._commit = true                                  # a tap: the swing is the player's whole order, it runs to the front of its arc
	if hold and not s._hold_prev:
		s._commit = false                                 # the thumb is back on the button: from now on lifting it lets go
	s._hold_prev = hold
	if s.lowering:
		return _tick_lower(s, p, dt, hold, jump_pressed)
	var space := p.get_world_3d().direct_space_state
	var c := p.global_position + Vector3(0.0, SnakeSwing.BODY_CENTRE, 0.0)
	var r := c - s.pivot
	var d := maxf(r.length(), 0.001)
	# the rope: slack is taken up, a rope too long for the street is reeled in; it never grows
	if d < s.rope:
		s.rope = maxf(d, ROPE_MIN)
	var v := p.velocity
	s._rq.collision_mask = Game.L_WORLD
	s._rq.exclude = [p.get_rid()]
	s._rq.from = c + Vector3(v.x, 0.0, v.z) * 0.25
	s._rq.to = s._rq.from + Vector3(0.0, -30.0, 0.0)
	var under := space.intersect_ray(s._rq)
	if not under.is_empty() and v.y < 0.0:
		var feet := c.y - SnakeSwing.BODY_CENTRE + v.y * 0.25 - (under["position"] as Vector3).y
		if feet < CLEAR_MIN:                              # something under the arc that the bite did not see (a car, an awning): pull up
			s.rope_goal = maxf(ROPE_MIN, minf(s.rope_goal, s.rope) - 14.0 * dt)
	s.height = (c.y - SnakeSwing.BODY_CENTRE - (under["position"] as Vector3).y) if not under.is_empty() else 30.0
	if s.rope > s.rope_goal:
		if d <= s.rope + 1.0:
			s.rope = maxf(s.rope_goal, s.rope - REEL * dt)
	else:
		s.rope_goal = s.rope
	var rn := r / d
	v.y -= SnakeSwing.GRAVITY * dt
	# the plane of the swing follows the way he moves (the stick turns it)
	var vh := Vector3(v.x, 0.0, v.z)
	if vh.length() > 5.0:
		var vd := vh.normalized()
		if vd.dot(s.swing_dir) < 0.0:
			vd = -vd
		s.swing_dir = (s.swing_dir + (vd - s.swing_dir) * minf(1.0, 6.0 * dt)).normalized()
	var n := plane_normal(s.swing_dir)
	var w_f := wish.dot(s.swing_dir)
	var w_s := wish.dot(n)
	if absf(w_s) > 0.1:
		v += n * (w_s * STEER * dt)
	else:
		v -= n * (v.dot(n) * minf(1.0, SIDE_DAMP * dt))
	# speed: gravity, and the assist toward the speed this height has in a swing of bottom_speed()
	var sp := v.length()
	var want := sqrt(maxf(pow(bottom_speed() * (1.1 if w_f > 0.5 else 1.0), 2.0) - 2.0 * SnakeSwing.GRAVITY * maxf(c.y - (s.pivot.y - s.rope), 0.0), 64.0))
	if w_f < -0.4:
		if sp > 0.01:
			v -= v / sp * minf(sp, BRAKE * dt)
	elif s.st.assist and sp > 1.0 and v.dot(s.swing_dir) > 0.0 and sp < want:
		v += v / sp * minf(ASSIST * dt, want - sp)
	elif sp > want * 1.1:
		v -= v / sp * minf(TRIM * dt, sp - want * 1.1)
	v *= 1.0 - DRAG * dt
	if s.st.assist:
		v = s._avoid_walls(p, v, dt)
	if d >= s.rope - 0.03:
		var vr := v.dot(rn)
		if vr > 0.0:
			v -= rn * vr
	if v.length() > V_HARD:
		v = v.normalized() * V_HARD
	p.velocity = v
	p.move_and_slide()
	v = p.velocity
	# the centre of the pendulum stays in the plane of the hero; the body goes back onto the rope
	var c2 := p.global_position + Vector3(0.0, SnakeSwing.BODY_CENTRE, 0.0)
	n = plane_normal(s.swing_dir)
	s.pivot += n * (c2 - s.pivot).dot(n)
	var r2 := c2 - s.pivot
	var d2 := r2.length()
	if d2 > s.rope:
		var corr := s.pivot + r2 / d2 * s.rope - c2
		var room := clampf(0.7 - v.length() * dt, 0.1, MAX_CORR)       # move + pull stay under 0.7 m a tick (42 m/s)
		if corr.length() > room:
			corr = corr.normalized() * room
		p.move_and_collide(corr)
		var rn2 := (p.global_position + Vector3(0.0, SnakeSwing.BODY_CENTRE, 0.0) - s.pivot).normalized()
		var vr2 := v.dot(rn2)
		if vr2 > 0.0:
			v -= rn2 * vr2
		p.velocity = v
	s._arc_len_acc += p.global_position.distance_to(s._last_pos)
	s._last_pos = p.global_position
	sp = p.velocity.length()
	s.max_speed = maxf(s.max_speed, sp)
	s._peak_v = maxf(s._peak_v, sp)
	# what the pose, the camera and the rope read
	var rr := p.global_position + Vector3(0.0, SnakeSwing.BODY_CENTRE, 0.0) - s.pivot
	var rd := maxf(rr.length(), 0.001)
	s.tension = clampf((rd - (s.rope - 1.5)) / 1.5, 0.0, 1.0)
	s.rope_angle = atan2(Vector3(rr.x, 0.0, rr.z).dot(s.swing_dir), maxf(-rr.y, 0.0001))
	if s.tendril != null:
		s.tendril.tension = lerpf(s.tendril.tension, 0.35 + 0.65 * s.tension, 1.0 - exp(-12.0 * dt))
	# --- the ends of a swing
	if jump_pressed:
		s.release(p, true, &"jump")
		return false
	if p.is_on_floor():
		s._ground_t += dt
		if s._ground_t > 0.1:
			s.release(p, false, &"ground")
			return false
	else:
		s._ground_t = 0.0
	if p.is_on_wall():
		s._wall_t += dt
		if s._wall_t > WALL_TIME:
			var wn := p.get_wall_normal()
			p.velocity += Vector3(wn.x, 0.0, wn.z).normalized() * 3.5      # off the facade, never left scraping along it
			s.release(p, false, &"wall")
			return false
	else:
		s._wall_t = maxf(0.0, s._wall_t - dt * 0.5)
	s._block_n += 1
	if s._block_n % 4 == 0:                               # the drawn rope (hand to the building) must not pass through a corner of a building ...
		var to := s.anchor + (c2 - s.anchor).normalized() * 0.6
		s._rq.from = c2
		s._rq.to = to
		var cut := space.intersect_ray(s._rq) if c2.distance_to(s.anchor) > 2.0 else {}
		if not cut.is_empty():                            # ... the rope lies round that corner now: its end moves there (the pendulum's centre does not: the swing goes on)
			s.anchor = (cut["position"] as Vector3) + (cut["normal"] as Vector3) * 0.1
			s.anchor_node = null
			s._anchor_prev = s.anchor
			s.wraps += 1
	if sp < STILL_SPEED:
		s._slow_t += dt
		if s._slow_t > STILL_TIME:
			s.lowering = true                              # a rope that stopped swinging: down he goes
			s._lower_t = 0.0
	else:
		s._slow_t = maxf(0.0, s._slow_t - dt * 2.0)
	var auto := hold or s._commit
	if not auto:
		s.release(p, true, &"button")
		return false
	if s._hang_t > SnakeSwing.MAX_HANG:
		s.release(p, true, &"time")
		return false
	if s._commit and s._hang_t > TAP_MAX:
		s.release(p, true, &"chain")
		return false
	if s.st.assist or s._commit:
		var vy := p.velocity.y
		if s.rope_angle >= (REL_FRONT if s.fresh_press else rel_front(s.height)) and vy > 0.5:      # critic 117: only a rope the held chain fired lets go flatter when high; a swing the player pressed for keeps its whole arc (he lets go when he likes)
			s.release(p, true, &"chain")
			return false
		if s.rope_angle > 0.25 and vy > 0.0 and sp < 10.0 and s._hang_t > 0.4:
			s.release(p, true, &"chain")                    # a weak arc at its top: go on from here
			return false
		if s.rope_angle > REL_MAX:
			s.release(p, true, &"max_angle")
			return false
	return true


## A still rope lowers the hero and lets go just over the ground (or after LOWER_MAX seconds, or when the finger lifts, or on JUMP).
static func _tick_lower(s: SnakeSwing, p: Player, dt: float, hold: bool, jump_pressed: bool) -> bool:
	s._lower_t += dt
	var v := p.velocity
	p.velocity = Vector3(v.x * 0.9, -LOWER_SPEED, v.z * 0.9)
	p.move_and_slide()
	var c := p.global_position + Vector3(0.0, SnakeSwing.BODY_CENTRE, 0.0)
	s.rope = maxf(s.rope, c.distance_to(s.pivot))
	s.rope_goal = s.rope
	s.tension = 1.0
	s.rope_angle = 0.0
	s._arc_len_acc += p.global_position.distance_to(s._last_pos)
	s._last_pos = p.global_position
	s._rq.collision_mask = Game.L_WORLD
	s._rq.exclude = [p.get_rid()]
	s._rq.from = p.global_position + Vector3(0.0, 0.5, 0.0)
	s._rq.to = p.global_position + Vector3(0.0, -1.6, 0.0)
	var near := not p.get_world_3d().direct_space_state.intersect_ray(s._rq).is_empty()
	if jump_pressed:
		s.release(p, true, &"jump")
		return false
	if near or p.is_on_floor() or s._lower_t > LOWER_MAX or (not hold and not s._commit):
		s.release(p, false, &"still")
		return false
	return true


# --- letting go --------------------------------------------------------------------------------------------------------------------------

## The velocity the hero leaves the rope with.
static func release_velocity(s: SnakeSwing, v: Vector3, boost: bool, why: StringName) -> Vector3:
	if why == &"jump" and s.phase == &"travel":
		return Vector3(v.x, maxf(v.y, 0.0) + JUMP_UP, v.z)      # JUMP while the snake is still on its way: the shot is called off, the hop is his
	if not boost or s.phase != &"hang" or s.lowering:
		return v
	var nv := v
	if why == &"jump":
		nv = v * JUMP_BOOST
		nv.y = maxf(nv.y, 0.0) + JUMP_UP
	elif s.rope_angle > 0.15 and v.y > -1.0:
		nv.y += HELP_UP * clampf(s.rope_angle / 0.6, 0.0, 1.0)
	if nv.length() > V_HARD:
		nv = nv.normalized() * V_HARD
	return nv


# --- would this anchor give a clear swing? -----------------------------------------------------------------------------------------------

## Seconds until the planar swing on `anchor` along `dir` meets geometry (INF: clear until the front of the arc or for `horizon` seconds).
static func arc_clear_time(space: PhysicsDirectSpaceState3D, sq: PhysicsShapeQueryParameters3D, c: Vector3, v0: Vector3, anchor: Vector3, dir: Vector3, horizon: float) -> float:
	var n := plane_normal(dir)
	var pv := pivot_for(anchor, c, dir)
	var rope := maxf(c.distance_to(pv), ROPE_MIN)
	var goal := minf(rope, ROPE_MAX)
	var pos := c
	var v := v0 - n * v0.dot(n)
	var dt := 0.1
	var t := 0.0
	while t < horizon:
		v.y -= SnakeSwing.GRAVITY * dt
		var r := pos - pv
		var d := maxf(r.length(), 0.001)
		if d < rope:
			rope = maxf(d, ROPE_MIN)
		rope = maxf(minf(rope, goal), rope - REEL * dt)
		if d >= rope - 0.05:
			var rn := r / d
			var vr := v.dot(rn)
			if vr > 0.0:
				v -= rn * vr
		var motion := v * dt
		sq.transform = Transform3D(Basis.IDENTITY, pos)
		sq.motion = motion
		var res := space.cast_motion(sq)
		if res.size() >= 2 and res[0] < 0.999:
			return t + dt * res[0]
		pos += motion
		var r2 := pos - pv
		var d2 := r2.length()
		if d2 > rope:
			pos = pv + r2 / d2 * rope
			r2 = pos - pv
		if atan2(Vector3(r2.x, 0.0, r2.z).dot(dir), maxf(-r2.y, 0.0001)) >= REL_FRONT and v.y > 0.0:
			return INF
		t += dt
	return INF


## Score of a ray hit as an anchor of the planar swing along `heading` (unit, horizontal) from the eye `o`; -INF: not an anchor.
static func score(o: Vector3, pos: Vector3, heading: Vector3, reach: float, crosshair: bool, kind: StringName) -> float:
	var d := o.distance_to(pos)
	var dy := pos.y - o.y
	if d < SnakeAnchors.MIN_DIST or d > reach or dy < ABOVE_MIN:
		return -INF
	var horiz := Vector3(pos.x - o.x, 0.0, pos.z - o.z)
	var f := horiz.dot(heading)
	var side := (horiz - heading * f).length()
	if f < 3.0 or side > 30.0:
		return -INF                                          # beside or behind: the rope would not carry him forward
	if kind == &"roof" and dy < 12.0:
		return -INF
	var elev := atan2(dy, f)
	if elev < 0.3:
		return -INF                                          # too flat: a drag along the street, not a swing
	var rope := sqrt(f * f + dy * dy)
	var sc := 3.0 - absf(elev - 1.05) * 1.6 - maxf(0.0, rope - ROPE_GOOD) / 12.0 - maxf(0.0, 16.0 - rope) / 5.0 - side / 30.0 * 0.8 + clampf(dy / 30.0, 0.0, 1.0) * 0.6
	if level_chain and scan_h > CRUISE_LO + 3.0:
		# critic 117: high over the street the best rope is the one that brings him back DOWN: its lowest point (rope - dy under the eye) near cruise height, so a long
		# rope to an anchor well ahead (a dive), not the steep short one of a swing from the street
		var k := clampf((scan_h - (CRUISE_LO + 3.0)) / 6.0, 0.0, 1.0)
		var drop := rope - dy
		var want_drop := clampf(scan_h - CRUISE_LO, 1.0, 26.0)
		var dive := 3.0 - absf(drop - want_drop) / 4.0 - maxf(0.0, 14.0 - rope) / 3.0 - maxf(0.0, rope - 32.0) / 3.0 - side / 30.0 * 0.8
		sc = lerpf(sc, dive, k)
		if rope < 10.0:
			return -INF                                      # no twitch on a rope of a few metres up here: there is time to wait for a real one
	if crosshair:
		sc += 1.2
	if kind == &"vehicle":
		sc -= 0.8
	if kind == &"ceiling":
		sc -= 0.4
	return sc
