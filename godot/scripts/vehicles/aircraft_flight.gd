class_name AircraftFlight
extends RefCounted
## The flight models of the roster aircraft (wave 106): an ARCADE PLANE with a throttle lever, a pitch angle, a bank angle and a stall that recovers by itself, and an ARCADE HELICOPTER with a
## collective, a cyclic (nose-down in forward flight), a tail rotor, hover assist and a rotor wash. VehicleCraft hands `_plane` / `_heli` to `plane()` / `heli()` here; the body (collision, landing,
## damage, exit rules) stays in VehicleCraft._move_air. Every number that makes one aircraft differ from the next is a key of its VehicleSpecs entry ("max", "acc", "stall", "ceil", "climb", "agile").
##
## Controls (touch and keyboard share the actions, see touch_controls.gd): stick forward / back = throttle lever (plane) or forward speed (helicopter), stick left / right = bank and turn (plane) or yaw
## (helicopter), UP (`jump`) / DOWN (`crouch`) = nose up / down (plane) or collective up / down (helicopter), `fire` = guns, `aim` = rockets or missiles on the kinds that carry them.
##
## PLANE: V (the speed along the flight path, v.speed) is driven by the thrust of the lever, drag, and the climb (a climb costs speed, a dive gains it). Lift needs V above 0.75 x `stall`; below it the nose
## falls and the plane sinks, and the dive brings the speed back (stall-safe: no spin, no dead end). The pitch angle follows the stick with a limit that keeps the climb at or under `climb` m/s; the bank angle
## follows the stick and the turn comes from the bank (coordinated turn, a speed-sensitive rate). The last metres of a descent are a flare (the sink is capped by the height), so a landing never hurts unless
## the nose is down, the wings are banked or the speed of the descent is far over LAND_SAFE. On the ground the wheels steer, the brake is the stick back with the lever at zero.
## HELICOPTER: the rotor spools up in SPOOL_TIME; the collective sets the climb rate with a soft landing flare, no input holds the height (hover assist) and stops the drift; the cyclic tilts the nose down
## with the speed; the rotor throws dust and spray under the machine within 14 m of the ground.
## `info(v)` is what the flight HUD draws (speed, altitude, vertical speed, attitude, throttle, stall, landing guide).

const G := 9.8
# --- plane ---
const LEVER_UP := 0.7                       ## throttle lever per second with the stick forward
const LEVER_DOWN := 1.2
const ROTATE_AT := 1.0                      ## share of the stall speed from which UP lifts the nose off the runway
const ROLL_MAX := 0.85                      ## rad of bank at full stick
const TURN_MAX := 1.05                      ## rad/s of heading change at full bank (agile 1)
const PITCH_DOWN := 0.55                    ## rad of nose-down at full DOWN
const SINK_STALL := 13.0                    ## m/s a plane with no lift at all sinks on top of the pitch
const WING_STRIKE_ROLL := 0.45              ## a touchdown with more bank than this scrapes a wing
const NOSE_DIVE := -0.32                    ## a touchdown with the nose lower than this (rad) is a crash landing
# --- helicopter ---
const HOVER_DAMP := 1.5                     ## 1/s drift damping with the sticks released (hover assist)
const WASH_RANGE := 15.0                    ## metres above the ground within which the rotor throws dust
# --- shared ---
const CRASH_SINK := 21.0                    ## a touchdown faster than this (m/s of sink) wrecks the craft
const CRASH_DAMAGE := 40.0                  ## hp per m/s of sink above LAND_SAFE in a crash landing (bad attitude)


## The per-craft flight state (VehicleCraft.State.air).
class Air extends RefCounted:
	var pitch := 0.0                        ## body / flight path pitch in rad (+ = nose up)
	var roll := 0.0                         ## model roll in rad (negative = right wing down, as Node3D.rotation.z)
	var thrust := 0.0                       ## 0..1 how hard the engines push (HUD, afterburner)
	var stalled := false
	var stall_time := 0.0                   ## seconds spent stalled (the HUD warns, a test reads it)
	var wash_t := 0.0
	var crashes := 0                        ## crash landings (tests)
	var wing_strikes := 0
	var vspeed := 0.0                       ## m/s, as measured last tick
	var rocket_cd := 0.0
	var guide_t := 0.0
	var guide: Dictionary = {}              ## the landing guide, refreshed a few times a second


static func air(c: VehicleCraft.State) -> Air:
	if c.air == null:
		c.air = Air.new()
	return c.air as Air


## The ground level under (x, z) for an aircraft: the city plateau is the node's rest height, outside it the finished terrain (with the airport apron, the pads and the runways carved in).
static func ground_y_at(x: float, z: float, base_y: float) -> float:
	if absf(x) <= TerrainHeight.CITY_HALF and absf(z) <= TerrainHeight.CITY_HALF:
		return base_y
	return maxf(base_y, TerrainHeight.height_at(x, z))


static func ground_y(v: Vehicle) -> float:
	return ground_y_at(v.global_position.x, v.global_position.z, v.base_y)


# --- plane --------------------------------------------------------------------------------------------------------------------------------

static func plane(v: Vehicle, dt: float, thr: float, steer: float, lift: float) -> void:
	var c := v.craft
	var A := air(c)
	var T := v.spec
	var vmax := float(T["max"])
	var stall := float(T["stall"])
	var agile := float(T.get("agile", 1.0))
	var climb := float(T.get("climb", 15.0))
	var acc := float(T["acc"])
	var jet := bool(T.get("jet", false))
	if thr > 0.05:
		c.lever = minf(1.0, c.lever + LEVER_UP * thr * dt)
	elif thr < -0.05:
		c.lever = maxf(0.0, c.lever + LEVER_DOWN * thr * dt)
	c.spool = lerpf(c.spool, 0.25 + 0.75 * c.lever, 1.0 - exp(-2.0 * dt))
	A.thrust = lerpf(A.thrust, c.lever, 1.0 - exp(-3.0 * dt))
	var V := maxf(v.speed, 0.0)
	var drag := 0.35 + V * V * (0.00028 if jet else 0.0004) * 11.0 / maxf(acc, 6.0)
	var thrust := acc * c.lever * (1.0 - clampf(V / vmax, 0.0, 1.3))
	var brake := not c.airborne and thr < -0.05 and c.lever < 0.05
	V += (thrust - drag - G * sin(A.pitch) * 0.5) * dt
	if not c.airborne:
		if c.lever < 0.05:                                          # idling on the wheels: rolling resistance, and the brake with the stick back
			V -= (1.2 + (float(T["brake"]) * 0.7 if brake else 0.0)) * dt
	V = maxf(V, 0.0)
	var L := clampf((V - stall * 0.75) / (stall * 0.25), 0.0, 1.0)
	var yaw_rate := 0.0
	if not c.airborne:
		c.vy = 0.0
		A.pitch = lerpf(A.pitch, 0.0, 1.0 - exp(-8.0 * dt))
		A.roll = lerpf(A.roll, 0.0, 1.0 - exp(-8.0 * dt))
		A.stalled = false
		yaw_rate = -steer * 0.85 * clampf(V / 6.0, 0.0, 1.0) / (1.0 + V / 60.0)
		if V > stall * ROTATE_AT and lift > 0.3:
			c.airborne = true
			c.vy = 2.5
			c.takeoffs += 1
			A.pitch = 0.06
	else:
		var lim_up := asin(clampf(climb / maxf(V, stall * 0.8), 0.05, 0.72))
		var pt := 0.0
		if lift > 0.0:
			pt = lift * lim_up
		elif lift < 0.0:
			pt = lift * PITCH_DOWN
		A.stalled = L < 0.85
		if A.stalled:
			A.stall_time += dt
			pt = minf(pt, -0.34 * (1.0 - L))                  # the nose falls and the dive brings the speed back
		else:
			A.stall_time = maxf(A.stall_time - dt * 2.0, 0.0)
		var agl := VehicleCraft.altitude(v)
		if pt < 0.0 and agl < 40.0:                                # the flare: the descent rate allowed shrinks with the height
			pt = maxf(pt, -asin(clampf(VehicleCraft._flare(agl, 5.0) / maxf(V, 1.0), 0.0, 0.9)))
		A.pitch = move_toward(A.pitch, pt, (1.0 + 1.5 * agile) * dt)
		c.vy = V * sin(A.pitch) - (1.0 - L) * SINK_STALL * 0.6
		var sink_cap := VehicleCraft._flare(agl, 5.0) if lift <= 0.0 and agl < 40.0 else 99.0
		if -c.vy > sink_cap and A.pitch < 0.0:                    # a steady stick near the ground never dives into it
			c.vy = -sink_cap
		if v.global_position.y > float(T["ceil"]) and c.vy > 0.0:
			c.vy = 0.0
		var rt := -steer * ROLL_MAX * (0.45 + 0.55 * L)
		A.roll = lerpf(A.roll, rt, 1.0 - exp(-3.2 * agile * dt))
		yaw_rate = sin(A.roll) / sin(ROLL_MAX) * TURN_MAX * sqrt(agile) * L / (1.0 + V / 260.0)
	v.heading += yaw_rate * dt
	var fwd := v.forward()
	var ch := cos(A.pitch)
	v.vel = fwd * V * ch
	v.speed = V
	v.slip = 0.0
	v.steer_in = steer
	v.braking = brake
	v.yaw_rate = yaw_rate
	var landings0 := c.landings
	VehicleCraft._move_air(v, dt)
	A.vspeed = c.vy
	if c.landings > landings0:
		_touchdown(v, A)
	if c.airborne:
		V = maxf(Vector2(v.vel.x, v.vel.z).length() / maxf(ch, 0.3), 0.0)         # a wall took some of the speed
		v.speed = V


## A plane that touches down: the attitude decides what it costs (the sink speed itself was handled by VehicleCraft._move_air).
static func _touchdown(v: Vehicle, A: Air) -> void:
	var c := v.craft
	var sink := c.hard
	var bad := A.pitch < NOSE_DIVE or absf(A.roll) > WING_STRIKE_ROLL
	if A.pitch < NOSE_DIVE:
		A.crashes += 1
		v.damage(maxf(0.0, sink - VehicleCraft.LAND_SAFE * 0.5) * CRASH_DAMAGE * 0.6 + 40.0)
		_crash_fx(v)
	elif absf(A.roll) > WING_STRIKE_ROLL:
		A.wing_strikes += 1
		v.damage((absf(A.roll) - WING_STRIKE_ROLL) * 160.0 + sink * 3.0)
		_crash_fx(v)
	if sink > CRASH_SINK:
		A.crashes += 1
		v.damage(v.max_hp)
		_crash_fx(v)
	if not bad and sink <= VehicleCraft.LAND_SAFE:
		FX.burst(v.global_position + Vector3(0.0, 0.1, 0.0), Color(0.82, 0.82, 0.78, 0.6), 6, 3.0, 0.6, 1.0, 1.4)     # the tyres' puff of dust
	A.pitch = 0.0
	A.roll = 0.0


static func _crash_fx(v: Vehicle) -> void:
	FX.burst(v.global_position + Vector3(0.0, 0.6, 0.0), Color(1.0, 0.7, 0.3), 14, 7.0, 0.5, 8.0, 0.5)
	Sfx.play_at(&"hit", v.global_position, 0.0)
	if v.driver_is_player:
		FX.shake(0.7)


# --- helicopter ---------------------------------------------------------------------------------------------------------------------------

static func heli(v: Vehicle, dt: float, thr: float, steer: float, lift: float) -> void:
	var c := v.craft
	var A := air(c)
	var T := v.spec
	var climb := float(T.get("climb", VehicleCraft.HELI_CLIMB))
	var agile := float(T.get("agile", 1.0))
	c.spool = move_toward(c.spool, 1.0, dt / VehicleCraft.SPOOL_TIME)
	var ready := c.spool >= VehicleCraft.SPOOL_READY
	var vmax := float(T["max"])
	var agl := VehicleCraft.altitude(v)
	var want := 0.0
	if ready:
		if lift > 0.0:
			want = lift * climb
		elif lift < 0.0:
			want = -minf(VehicleCraft.HELI_DESCENT, VehicleCraft._flare(agl, 3.0)) * (-lift)     # the last metres are a soft flare: a landing never hurts
	elif c.airborne:
		want = -VehicleCraft.HELI_DESCENT * 1.6
	c.vy = move_toward(c.vy, want, (VehicleCraft.HELI_VERT_ACC if ready else 4.0) * dt)
	if not c.airborne:
		c.vy = maxf(c.vy, 0.0)
		if lift > 0.1 and ready:
			c.airborne = true
			c.takeoffs += 1
	var fwd := v.forward()
	var rgt := v.right()
	var vf := v.vel.dot(fwd)
	var vl := v.vel.dot(rgt)
	var cap := vmax if c.airborne else VehicleCraft.HELI_GROUND_SPEED
	var sticks := absf(thr) > 0.05 or absf(steer) > 0.05
	if ready and thr > 0.05:
		vf += float(T["acc"]) * thr * (1.0 - maxf(vf, 0.0) / cap) * dt
	elif ready and thr < -0.05:
		vf += float(T["acc"]) * 0.8 * thr * dt
	else:
		vf *= exp(-((HOVER_DAMP if sticks == false else 0.7) if c.airborne else 3.0) * dt)      # hover assist: sticks released = the drift is stopped
	vf = clampf(vf, -cap * 0.3, cap)
	vl *= exp(-float(T["grip"]) * 1.4 * dt)
	var yaw := 0.0
	if ready:
		var torque := clampf(c.spool, 0.0, 1.0)
		yaw = steer * VehicleCraft.HELI_YAW * agile * (1.0 if c.airborne else 0.5) / (1.0 + absf(vf) / 70.0) * torque
		v.heading -= yaw * dt
	fwd = v.forward()
	rgt = v.right()
	v.vel = fwd * vf + rgt * vl
	v.speed = vf
	v.slip = vl
	v.steer_in = steer
	v.braking = false
	v.yaw_rate = -yaw
	A.thrust = clampf(0.4 + 0.6 * absf(thr), 0.0, 1.0) if c.airborne else 0.0
	# the attitude: the nose goes down with the speed (the cyclic), the machine leans into a turn
	var tp := -clampf(vf / vmax, -0.3, 1.0) * 0.24 + clampf(c.vy * 0.004, -0.04, 0.04)
	A.pitch = lerpf(A.pitch, tp, 1.0 - exp(-4.0 * dt))
	var tr := clampf(-yaw * 0.22 - vl * 0.012, -0.4, 0.4) * (1.0 if c.airborne else 0.0)
	A.roll = lerpf(A.roll, tr, 1.0 - exp(-4.0 * dt))
	var landings0 := c.landings
	VehicleCraft._move_air(v, dt)
	A.vspeed = c.vy
	if c.landings > landings0:
		A.pitch = 0.0
		A.roll = 0.0
	_wash(v, A, dt, agl)


## The rotor wash: dust (or spray over water) thrown out under a machine low over the ground, only close to the player.
static func _wash(v: Vehicle, A: Air, dt: float, agl: float) -> void:
	A.wash_t -= dt
	if A.wash_t > 0.0 or v.craft.spool < 0.55 or agl > WASH_RANGE:
		return
	if not (v.driver_is_player or v._dist < 80.0):
		return
	A.wash_t = 0.11
	var k := 1.0 - agl / WASH_RANGE
	var p := v.global_position
	var gy := ground_y(v)
	var water := TerrainHeight.water_level_at(p.x, p.z) != TerrainHeight.NO_WATER and (absf(p.x) > TerrainHeight.CITY_HALF or absf(p.z) > TerrainHeight.CITY_HALF)
	var col := Color(0.86, 0.94, 1.0, 0.5) if water else Color(0.74, 0.68, 0.56, 0.45)
	var r := float(v.spec.get("rotor_r", 3.6)) * 0.8
	for i in 2:
		var a := randf() * TAU
		var q := Vector3(p.x + cos(a) * r, (TerrainHeight.water_level_at(p.x, p.z) if water else gy) + 0.2, p.z + sin(a) * r)
		FX.burst(q, col, 2, 3.0 + 6.0 * k, 0.9, 0.5, 1.6 + k)
	if water and FX.marks != null:
		FX.marks.ripple(Vector3(p.x, TerrainHeight.water_level_at(p.x, p.z), p.z), 2.0 + r * 0.3)


# --- what the HUD shows ------------------------------------------------------------------------------------------------------------------

## The flight data of an aircraft for the HUD and the tests: speed (m/s), altitude above the ground and above the sea, vertical speed, heading (rad), pitch, roll, throttle, thrust, stall warning, the
## landing guide (Airport.guide, refreshed 4 times a second) and a plain next-step line.
static func info(v: Vehicle) -> Dictionary:
	var c := v.craft
	var A := air(c)
	var T := v.spec
	var d := {}
	d["speed"] = v.speed
	d["agl"] = VehicleCraft.altitude(v)
	d["alt"] = v.global_position.y
	d["vspeed"] = A.vspeed
	d["heading"] = v.heading
	d["pitch"] = A.pitch
	d["roll"] = A.roll
	d["throttle"] = c.lever if v.cls == &"plane" else clampf(absf(v.speed) / maxf(float(T["max"]), 1.0), 0.0, 1.0)
	d["spool"] = c.spool
	d["airborne"] = c.airborne
	d["stalled"] = A.stalled and c.airborne
	d["stall_speed"] = float(T.get("stall", 0.0))
	d["plane"] = v.cls == &"plane"
	d["guide"] = A.guide
	d["hint"] = hint(v, A)
	return d


## The next thing to do, in plain words.
static func hint(v: Vehicle, A: Air) -> String:
	var c := v.craft
	if v.cls == &"plane":
		var stall := float(v.spec["stall"])
		if A.stalled and c.airborne:
			return "TOO SLOW: NOSE DOWN AND THROTTLE UP"
		if not c.airborne:
			if c.lever < 0.3 and v.speed < 3.0:
				return "STICK UP FOR THROTTLE"
			if v.speed < stall * ROTATE_AT:
				return "SPEED UP"
			return "HOLD UP TO TAKE OFF"
		if VehicleCraft.altitude(v) < 60.0 and A.vspeed < -4.0:
			return "PULL UP"
		if A.guide.has("on") and bool(A.guide["on"]):
			return "LANDING: FOLLOW THE GUIDE, THROTTLE DOWN"
		return ""
	if c.spool < VehicleCraft.SPOOL_READY:
		return "ROTOR SPINNING UP"
	if not c.airborne:
		return "HOLD UP TO LIFT OFF"
	if VehicleCraft.altitude(v) < 4.0 and A.vspeed < -2.5:
		return "EASY: LET IT SETTLE"
	return ""


## Refresh the landing guide a few times a second (called from VehicleCraft.sync for the driven plane).
static func tick_guide(v: Vehicle, dt: float) -> void:
	var A := air(v.craft)
	A.guide_t -= dt
	if A.guide_t > 0.0:
		return
	A.guide_t = 0.25
	if v.cls != &"plane":
		A.guide = {}
		return
	A.guide = Airport.guide(v.global_position, v.heading, v.speed, VehicleCraft.altitude(v))
