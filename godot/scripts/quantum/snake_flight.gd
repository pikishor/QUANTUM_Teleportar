class_name SnakeFlight
extends RefCounted
## SNAKE FLIGHT: sustained flight on twin snake wings (two tendrils from the shoulder blades). Owned by SnakeTraversal (`player.snake.flight`).
## Controls (phone): the camera look steers (the heading turns toward where the camera looks, with a turn rate that falls with speed, so a fast flight has weight); the stick forward gives thrust
## (cruise), released it hovers (the speed bleeds to zero), back brakes, left / right strafe and bank; JUMP climbs, CROUCH (or looking down with the stick forward) dives; SNAKE held is BOOST; the FLY / LAND
## button toggles flight; a quick double tap of the stick sideways, or `roll()`, is a BARREL ROLL (a sideways dodge with a full roll). Phases: takeoff, power (cruise / boost / dive), hover, glide (no energy:
## the wings spread, the hero sinks slowly and recharges), landing (controlled descent and a roll) and crash (stun after a hard hit: the hero is thrown back along the surface and recovers).
## Energy: the snake energy pool drains by SnakePower.fly_cost_per_s() (hover a third of it, boost 3.6 times), generous on STORY, unlimited in HERO MODE. Landing: LAND or touching the ground slowly ends flight;
## a fast low pass skims in a landing roll; a steep dive into the street is a crash (never fatal on STORY and NORMAL).
## Flying under bridges and between towers works with the player's capsule (move_and_slide); the world edge pushes back (PLAY_HALF). Records: best_speed, max_alt, distance, flights (counters for tests).

const TAKEOFF_TIME := 0.55
const TAKEOFF_LIFT := 12.5
const BANK_MAX := 0.85
const STRAFE_SPEED := 13.0
const CLIMB_SPEED := 11.0
const DESCEND_SPEED := 15.0
const TURN_HI := 4.6
const TURN_LO := 1.5
const GLIDE_SPEED := 17.0
const GLIDE_SINK := 3.0
const DIVE_GAIN := 24.0
const DIVE_MAX := 62.0
const ACCEL := 15.0
const DECEL := 9.0
const CRASH_SPEED := 14.0
const LAND_RANGE := 2.4
const ROLL_TIME := 0.7
const BOUNDS := 90.0
const REGEN_GLIDE := 5.0
const LOW_START := 3.2                    ## metres over the ground under which a flight that starts in the air takes off like one from the ground

var st: SnakeTraversal
var active := false
var phase: StringName = &"none"           ## takeoff, power, hover, glide, landing, crash
var dir := Vector3.FORWARD
var speed := 0.0
var bank := 0.0
var bank_target := 0.0
var pitch := 0.0                          ## heading pitch (radians), for the pose
var roll_t := 0.0                         ## > 0 while a barrel roll runs (seconds left)
var roll_dir := 1.0
var boosting := false
var stun := 0.0
var time := 0.0
var phase_t := 0.0
var flights := 0                          ## counters
var landings := 0
var crashes := 0
var boosts := 0
var rolls := 0
var best_speed := 0.0
var max_alt := 0.0
var distance := 0.0
var wing_spread := 0.0                    ## 0..1 how far the wings are spread (hover and glide spread them, a fast flight sweeps them back)
var roll_land_t := 0.0                    ## > 0 while the landing roll plays after touching down
var wings: Array[SnakeTendril] = []
static var record_speed := 0.0            ## the hero's speed record of the session (the HUD shows it)
static var low_start := true              ## a flight started low over the ground is a take-off (a test switches it off to show the old behaviour)
static var clip_wings := true             ## the wing tips stop at walls (a look-dev bot and a test switch it off to show the old look)
var _tip_frame: Array[int] = [-1, -1]      ## the clipped wing tips of this frame (left, right): see _keep_out_of_walls
var _tip_cache: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _side_tap_t := 0.0
var _side_last := 0.0
var _prev_pos := Vector3.ZERO
var _land_req := false
var _ground_t := 0.0
var _boost_was := false
var _rq := PhysicsRayQueryParameters3D.new()


func _init(owner_st: SnakeTraversal = null) -> void:
	st = owner_st


func cancel() -> void:
	_kill_wings()
	active = false
	phase = &"none"
	speed = 0.0
	boosting = false
	roll_t = 0.0
	stun = 0.0


func _kill_wings() -> void:
	for w in wings:
		if w != null:
			w.retract(0.12)
	wings.clear()


func _ray(p: Player, from: Vector3, to: Vector3) -> Dictionary:
	_rq.from = from
	_rq.to = to
	_rq.collision_mask = Game.L_WORLD
	_rq.exclude = [p.get_rid()]
	return p.get_world_3d().direct_space_state.intersect_ray(_rq)


## The wings leave the back: `aim` is the look direction at take-off.
func begin(p: Player, aim: Vector3) -> bool:
	if not SnakePower.flight_unlocked():
		Game.say("WING POWER LOCKED", 1.4)
		return false
	if st.energy < 8.0 and not SnakePower.unlimited():
		Game.say("OUT OF SNAKE ENERGY", 1.2)
		return false
	active = true
	flights += 1
	time = 0.0
	phase_t = 0.0
	stun = 0.0
	roll_t = 0.0
	_land_req = false
	_ground_t = 0.0
	dir = aim.normalized()
	var from_ground := p.is_on_floor()
	# wave 116 (touch probe): FLY shows 0.3 s into a jump and the jump is over 0.4 s later; a thumb that pressed FLY on the way down (0.8 m up, falling) got 15 ticks of flight and stood on the
	# street again, as if the button had done nothing. A start this low is a take-off like the one from the ground: the lift carries him up and the ground cannot end the flight during it.
	var low := not from_ground and low_start and _ground_gap(p) < LOW_START
	if from_ground or low:
		phase = &"takeoff"
		p.velocity.y = maxf(p.velocity.y, TAKEOFF_LIFT)
		dir = Vector3(aim.x, maxf(aim.y, 0.35), aim.z).normalized()
		speed = maxf(SnakePower.fly_cruise() * 0.5, p.velocity.length() * 0.9 if low else 0.0)
	else:
		phase = &"power"
		speed = maxf(p.velocity.length() * 0.9, SnakePower.fly_cruise() * 0.6)
		dir = (p.velocity.normalized() * 0.4 + aim.normalized() * 0.6).normalized() if p.velocity.length() > 4.0 else dir
	bank = 0.0
	bank_target = 0.0
	_prev_pos = p.global_position
	_spawn_wings(p)
	st.on_flight_started(from_ground)
	return true


func _spawn_wings(p: Player) -> void:
	_kill_wings()
	for side in [-1, 1]:
		var s: int = side
		var t := SnakeTendril.fire(st.back_callable(s), Callable(self, "_wing_tip").bind(p, s), {"travel": 0.14, "wriggle": 0.3 if FlightView.old_look else 0.12, "tension": 0.5, "thickness": FlightView.wing_thickness(), "host": p, "color": Color(0.2, 0.85, 1.0)})
		t.user["keep"] = true
		wings.append(t)


## Where the tip of a wing is now (world): spread up and out when hovering and gliding, swept back and long when fast; the span follows the bank.
func _wing_tip(p: Player, side: int) -> Vector3:
	var fwd := dir
	var up := Vector3.UP
	var right := fwd.cross(up)
	right = right.normalized() if right.length() > 0.05 else Vector3.RIGHT
	if roll_t > 0.0:                                                  # critic 115 look: a barrel roll turned the hero but not his wings (SnakePose rolls the body, the wings stayed level like a gyroscope): they roll with him
		var rb := Basis(fwd, roll_dir * (1.0 - roll_t / ROLL_TIME) * TAU)
		right = rb * right
		up = rb * up
	var spd := clampf(speed / maxf(SnakePower.fly_boost(), 1.0), 0.0, 1.0)
	var spread := wing_spread
	var shape := FlightView.wing_shape(spread, spd, bank, side)        # wave 116 (owner round 7): the wings were 3 to 4.8 m a side, arched 2 m up, and crossed the whole screen: FlightView keeps them at the hero's shoulders
	var span := shape.x
	var lift := shape.y
	var back := shape.z
	var chest := p.global_position + Vector3(0.0, 1.15, 0.0)
	var tip := chest - fwd * back + right * (float(side) * span) + up * lift
	return _keep_out_of_walls(p, chest, tip, side)


## Critic 115 look: a wing 5 m long went straight through the facade the hero flew along (the left wing vanished into the building in the render of the city run). One ray per wing and frame (cached,
## the tendril asks for the tip more than once a frame): the tip stops 35 cm short of the first wall, never nearer than 0.6 m to the chest.
func _keep_out_of_walls(p: Player, chest: Vector3, tip: Vector3, side: int) -> Vector3:
	var frame := Engine.get_process_frames()
	var slot := 0 if side < 0 else 1
	if _tip_frame[slot] == frame:
		return _tip_cache[slot]
	var out := tip
	var reach := chest.distance_to(tip)
	if clip_wings and reach > 0.7 and p.is_inside_tree():
		_rq.collision_mask = Game.L_WORLD
		_rq.from = chest
		_rq.to = tip
		var hit := p.get_world_3d().direct_space_state.intersect_ray(_rq)
		if not hit.is_empty():
			var at := chest.distance_to(hit["position"] as Vector3)
			out = chest + (tip - chest) / reach * clampf(at - 0.35, 0.6, reach)
	_tip_frame[slot] = frame
	_tip_cache[slot] = out
	return out


func roll_request(side: float) -> void:
	if roll_t <= 0.0 and active and phase != &"landing" and stun <= 0.0:
		roll_dir = signf(side) if side != 0.0 else 1.0
		roll_t = ROLL_TIME
		rolls += 1
		st.on_flight_roll()


func land_request() -> void:
	if active and phase != &"landing":
		_land_req = true
		phase = &"landing"
		phase_t = 0.0


## End flight: `to_ground` true when the hero touched down (a landing roll), false for a drop out of the sky (he simply falls with his speed).
func end(p: Player, to_ground: bool) -> void:
	if not active:
		return
	_kill_wings()
	var v := p.velocity
	active = false
	boosting = false
	if to_ground:
		landings += 1
		roll_land_t = 0.55
		p.velocity = Vector3(v.x, 0.0, v.z).limit_length(14.0)
		FX.burst(p.global_position + Vector3(0.0, 0.1, 0.0), Color(0.5, 1.0, 1.0), 12, 6.0, 0.45, 4.0, 1.0)
		FX.shake(0.15)
		p.camera_rig.bump(0.35)
	else:
		p.velocity = v.limit_length(40.0)
	phase = &"none"
	st.on_flight_ended(to_ground)


## One physics tick. Returns true while flight still owns the body.
func tick(p: Player, dt: float, iv: Vector2, aim: Vector3, jump_held: bool, crouch_held: bool, boost_held: bool, fly_pressed: bool) -> bool:
	if not active:
		return false
	time += dt
	phase_t += dt
	roll_land_t = maxf(0.0, roll_land_t - dt)
	if fly_pressed and time > 0.35:
		if phase == &"landing":
			phase = &"power"                              # a second press cancels a landing
			_land_req = false
		else:
			land_request()
	var fwd_in := -iv.y
	var side_in := iv.x
	# double tap sideways = barrel roll
	_side_tap_t = maxf(0.0, _side_tap_t - dt)
	if absf(side_in) > 0.8 and absf(_side_last) <= 0.8:
		if _side_tap_t > 0.0 and signf(side_in) == signf(_side_dir_last):
			roll_request(side_in)
			_side_tap_t = 0.0
		else:
			_side_tap_t = 0.28
			_side_dir_last = signf(side_in)
	_side_last = side_in
	stun = maxf(0.0, stun - dt)
	var energy_ok := SnakePower.unlimited() or st.energy > 0.5
	var powered := energy_ok and stun <= 0.0
	if phase == &"glide" and st.energy >= 24.0:
		phase = &"power"
		Game.say("WINGS RECHARGED", 0.9)
	if powered == false and phase != &"landing" and phase != &"crash":
		if phase != &"glide":
			phase = &"glide"
			phase_t = 0.0
			if stun <= 0.0:
				Game.say("OUT OF SNAKE ENERGY  GLIDING", 1.2)
	elif stun > 0.0 and phase != &"crash":
		phase = &"crash"
	elif phase == &"crash" and stun <= 0.0:
		phase = &"power"
	if phase == &"takeoff" and phase_t > TAKEOFF_TIME:
		phase = &"power"
	boosting = powered and boost_held and phase != &"landing" and phase != &"takeoff" and (SnakePower.unlimited() or st.energy > 4.0)
	if boosting and not _boost_was:
		boosts += 1
		st.on_flight_boost()
	_boost_was = boosting
	var cruise := SnakePower.fly_cruise()
	var boost_v := SnakePower.fly_boost()
	# ---- speed
	var target := 0.0
	var hover := false
	if phase == &"glide":
		target = GLIDE_SPEED
	elif phase == &"landing":
		target = minf(speed, cruise * 0.45)
	elif phase == &"takeoff":
		target = cruise * 0.7
	elif phase == &"crash":
		target = 4.0
	elif boosting:
		target = boost_v
	elif fwd_in > 0.12:
		target = lerpf(cruise * 0.45, cruise, clampf(fwd_in, 0.0, 1.0))
	elif fwd_in < -0.35:
		target = 0.0
		hover = true
	elif absf(side_in) > 0.15 and speed < 20.0:
		target = 0.0
		hover = true
	else:
		target = 0.0
		hover = true
	var dive := maxf(-dir.y, 0.0)
	var dive_bonus := dive * DIVE_GAIN * (1.0 if powered or phase == &"glide" else 0.0) * (1.0 if fwd_in > 0.1 or phase == &"glide" or boosting else 0.0)
	var want_speed := minf(target + dive_bonus, DIVE_MAX)
	speed = move_toward(speed, want_speed, (ACCEL if want_speed > speed else DECEL * (1.4 if hover else 1.0)) * dt)
	if hover and speed < 3.0:
		phase = &"hover" if phase == &"power" or phase == &"hover" else phase
	elif phase == &"hover":
		phase = &"power"
	# ---- heading: turns toward the look direction with a turn rate that falls with speed
	var turn := lerpf(TURN_HI, TURN_LO, clampf((speed - 12.0) / 45.0, 0.0, 1.0))
	if speed < 4.0 or phase == &"hover":
		turn = 9.0
	if stun > 0.0:
		turn = 0.5
	var ang := dir.angle_to(aim)
	var prev_dir := dir
	if ang > 0.0001:
		dir = dir.slerp(aim, clampf(turn * dt / ang, 0.0, 1.0)).normalized()
	var yaw_rate := angle_difference(atan2(-prev_dir.x, -prev_dir.z), atan2(-dir.x, -dir.z)) / maxf(dt, 0.0001)
	bank_target = clampf(-yaw_rate * 0.32 + side_in * 0.34, -BANK_MAX, BANK_MAX)
	bank = PlayerUtil.damp(bank, bank_target, 7.0, dt)
	pitch = asin(clampf(dir.y, -1.0, 1.0))
	wing_spread = PlayerUtil.damp(wing_spread, 1.0 if (phase == &"hover" or phase == &"glide" or phase == &"takeoff") else (0.15 if boosting else 0.0), 5.0, dt)
	var spd_k := clampf(speed / maxf(SnakePower.fly_boost(), 1.0), 0.0, 1.0)
	var wing_up := Vector3.UP if roll_t <= 0.0 else Basis(dir, roll_dir * (1.0 - roll_t / ROLL_TIME) * TAU) * Vector3.UP        # the arch of a wing follows the roll too
	for wi in wings.size():
		var w := wings[wi]
		if w == null or not w.is_alive():
			continue
		w.tension = 0.85
		w.bow = FlightView.wing_bow(wing_up, dir, spd_k, wing_spread, bank, wi)
		w.flutter = FlightView.wing_flutter(wing_spread, spd_k)
	# ---- velocity
	var right_h := Vector3(-dir.z, 0.0, dir.x)
	right_h = right_h.normalized() if right_h.length() > 0.05 else Vector3.RIGHT
	var vt := dir * speed + right_h * (side_in * STRAFE_SPEED * (0.6 if stun > 0.0 else 1.0))
	if roll_t > 0.0:
		roll_t = maxf(0.0, roll_t - dt)
		vt += right_h * roll_dir * 16.0 * sin(PI * (1.0 - roll_t / ROLL_TIME))
	if jump_held and stun <= 0.0 and phase != &"landing":
		vt.y += CLIMB_SPEED
	if crouch_held and stun <= 0.0:
		vt.y -= DESCEND_SPEED
	if phase == &"glide":
		vt.y -= GLIDE_SINK
	elif phase == &"landing":
		vt.y = minf(vt.y, -9.0)
		vt = Vector3(vt.x * 0.9, vt.y, vt.z * 0.9)
	if phase == &"takeoff":
		vt.y += TAKEOFF_LIFT * (1.0 - phase_t / TAKEOFF_TIME) * 0.8
	# the world edge pushes back
	var lim := CityLayout.PLAY_HALF - BOUNDS
	var gp := p.global_position
	if absf(gp.x) > lim:
		vt.x -= signf(gp.x) * (absf(gp.x) - lim) * 0.8
	if absf(gp.z) > lim:
		vt.z -= signf(gp.z) * (absf(gp.z) - lim) * 0.8
	var before := p.velocity
	p.velocity = before.lerp(vt, 1.0 - exp(-4.2 * dt))
	var vbefore := p.velocity
	p.move_and_slide()
	# ---- collisions: a hard hit is a crash
	var worst := 0.0
	var wn := Vector3.UP
	for i in p.get_slide_collision_count():
		var c := p.get_slide_collision(i)
		var n := c.get_normal()
		var into := maxf(-vbefore.dot(n), -dir.dot(n) * speed if n.y < 0.7 else 0.0)        # a hero pressed into a wall by the thrust crashes even though the wall keeps his actual speed low
		if into > worst:
			worst = into
			wn = n
	var on_floor := p.is_on_floor()
	if worst > CRASH_SPEED and (not on_floor or worst > 24.0) and stun <= 0.0 and phase != &"landing":
		_crash(p, worst, wn)
	# ---- energy
	if not SnakePower.unlimited():
		if phase == &"glide":
			st.energy_gain(REGEN_GLIDE * dt)
		elif phase == &"landing" or phase == &"crash":
			pass
		else:
			var k := 3.6 if boosting else (0.35 if hover else 1.0)
			st.energy_spend(SnakePower.fly_cost_per_s() * k * dt)
	# ---- records
	var sp := p.velocity.length()
	if sp > best_speed:
		best_speed = sp
	if sp > record_speed:
		record_speed = sp
	max_alt = maxf(max_alt, p.global_position.y)
	distance += p.global_position.distance_to(_prev_pos)
	_prev_pos = p.global_position
	# ---- the ground
	if phase == &"takeoff":
		return true
	var near := _ground_gap(p)
	if on_floor:
		_ground_t += dt
		var hs := Vector2(p.velocity.x, p.velocity.z).length()
		if phase == &"landing" or hs < 20.0 or _ground_t > 0.35:
			end(p, true)
			return false
	else:
		_ground_t = 0.0
		if phase == &"landing" and near < 0.6:
			end(p, true)
			return false
	if phase == &"landing" and near < LAND_RANGE:
		p.velocity.y = maxf(p.velocity.y, -5.0 - near * 2.0)
	return true


var _side_dir_last := 0.0


func _ground_gap(p: Player) -> float:
	var h := _ray(p, p.global_position + Vector3(0.0, 0.3, 0.0), p.global_position + Vector3(0.0, -40.0, 0.0))
	if h.is_empty():
		return 40.0
	return maxf(p.global_position.y - (h["position"] as Vector3).y, 0.0)


func _crash(p: Player, into: float, n: Vector3) -> void:
	crashes += 1
	stun = clampf(0.35 + (into - CRASH_SPEED) * 0.025, 0.4, 1.1)
	speed *= 0.25
	var out := n * clampf(into * 0.3, 4.0, 11.0)
	p.velocity = out + Vector3(0.0, 2.0, 0.0)
	var dmg := maxf(0.0, into - CRASH_SPEED) * 0.9 * (0.0 if Difficulty.current <= 1 else 1.0)
	if dmg > 0.0 and p.hp > dmg + 2.0:
		p.damage(dmg, p.global_position - n)
	FX.shake(clampf(into / 40.0, 0.2, 0.6))
	FX.burst(p.global_position + Vector3(0.0, 1.0, 0.0) - n * 0.3, Color(1.0, 0.8, 0.5), 14, 7.0, 0.4, 6.0, 1.0)
	p.camera_rig.bump(clampf(into / 30.0, 0.3, 0.9))
	st.on_flight_crash(into)
