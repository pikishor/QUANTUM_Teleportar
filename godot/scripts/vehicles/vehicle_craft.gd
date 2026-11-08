class_name VehicleCraft
extends RefCounted
## The roster vehicles with their own drive code (docs/DESIGN.md: any vehicle): HELICOPTER (arcade flight: lift, pitch, yaw, hover, landing), small PLANE (takeoff, stall, landing), BOAT (floats on the
## flooded quarter, drifts, leaves a wake) and TANK (tracks turn on the spot, the turret slews to the crosshair). Everything is arcade: easy to fly with one thumb on the stick and one on UP / DOWN.
## The Vehicle node keeps its role (layer 8, mask world, damage, entry and exit, weapons); this class owns the per-craft State, the physics step, the visual sync and the aim.
##
## Controls (touch and keyboard share the actions): stick forward / back = throttle (plane: a lever that stays where you leave it) or forward speed (helicopter), stick left / right = yaw,
## UP (`jump`, Space) climbs or pulls the nose up, DOWN (`crouch`, Ctrl) descends or pushes the nose down, `fire` shoots the mounted weapon.
## API: step(v, dt, thr, steer, up, boost) · sync(v, dt) · aim_dir(v) · muzzle(v) · can_exit(v) · altitude(v) · is_craft(cls) · State

const CLASSES: Array[StringName] = [&"heli", &"plane", &"boat", &"tank"]

# --- helicopter ---
const SPOOL_TIME := 1.6               ## s for the rotor to come up to speed (lift needs SPOOL_READY of it)
const SPOOL_READY := 0.85
const HELI_CLIMB := 11.0              ## m/s
const HELI_DESCENT := 9.0
const HELI_VERT_ACC := 7.0            ## m/s2: how fast the vertical speed follows the stick (a flare needs a steady rate, not a lag)
const PLANE_VERT_ACC := 10.0
const HELI_YAW := 1.7                 ## rad/s at full stick
const HELI_GROUND_SPEED := 5.0        ## m/s: top speed on the skids
# --- plane ---
const LEVER_UP := 0.7                 ## throttle lever per second with the stick forward
const LEVER_DOWN := 1.2
const PLANE_CLIMB := 15.0
const PLANE_DIVE := 20.0
const PLANE_SINK := 18.0              ## m/s the plane drops at when it has no lift at all
const PLANE_YAW := 1.1
const PLANE_BRAKE := 18.0             ## wheel brake m/s2 on the ground (stick back with the lever at zero)
const TAKEOFF_AT := 0.9               ## share of the stall speed from which UP lifts the nose off the runway
# --- landing and crashes ---
const LAND_SAFE := 6.5                ## m/s of sink a landing survives without a scratch
const LAND_DAMAGE := 26.0             ## hp per m/s of sink above LAND_SAFE
const WALL_HIT := 5.0                 ## m/s into a wall above which it hurts
const WALL_DAMAGE := 3.2              ## hp per m/s of wall impact (air craft)
# --- boat ---
const BOAT_YAW := 2.0
const BOAT_DRAG := 0.45
const WAKE_EVERY := 0.07
# --- tank ---
const TANK_YAW := 1.05                ## rad/s: the tracks turn it on the spot
const TURRET_RATE := 1.7              ## rad/s the turret slews at
const TANK_DRAG := 1.6
const GUN_PITCH_MIN := -0.12
const GUN_PITCH_MAX := 0.55
const BLUR_SPIN := 22.0               ## rad/s above which the blades are swapped for the soft blur disc


class State extends RefCounted:
	var vy := 0.0                     ## vertical speed m/s
	var lever := 0.0                  ## plane throttle lever 0..1
	var spool := 0.0                  ## rotor / propeller speed 0..1
	var ang := 0.0                    ## blade angle rad
	var tail_ang := 0.0
	var airborne := false
	var pitch := 0.0                  ## body pitch for the model (+ = nose up)
	var roll := 0.0
	var bob := 0.0
	var bob_t := 0.0
	var turret_yaw := 0.0             ## world yaw of the turret (Node3D convention, positive turns left)
	var gun_pitch := 0.0
	var down_in := 0.0                ## DOWN as an input (tests set it; a driving player reads the `crouch` action)
	var wake_t := 0.0
	var takeoffs := 0
	var landings := 0
	var max_alt := 0.0                ## highest point since entering (tests, stats)
	var hard := 0.0                   ## last landing sink speed (tests)
	var agl := 0.0                    ## height above whatever is below it (street or roof), from a ray each tick

	func reset(heading: float) -> void:
		vy = 0.0
		lever = 0.0
		spool = 0.0
		airborne = false
		pitch = 0.0
		roll = 0.0
		turret_yaw = heading
		gun_pitch = 0.0
		down_in = 0.0
		max_alt = 0.0
		hard = 0.0


static func is_craft(cls: StringName) -> bool:
	return cls in CLASSES


## Metres above whatever is below the craft (the street, a roof): 0 on the ground and on a boat. Measured by a ray once per tick while it flies (State.agl).
static func altitude(v: Vehicle) -> float:
	if v.craft != null and (v.cls == &"heli" or v.cls == &"plane"):
		return v.craft.agl
	return maxf(0.0, v.global_position.y - v.base_y)


static func _measure_agl(v: Vehicle) -> void:
	var c := v.craft
	var p := v.global_position
	if p.y <= v.base_y + 0.05 or not v.is_inside_tree():
		c.agl = maxf(0.0, p.y - v.base_y)
		return
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0.0, 0.5, 0.0), p - Vector3(0.0, 400.0, 0.0), Game.L_WORLD)
	q.exclude = [v.get_rid()]
	var r := v.get_world_3d().direct_space_state.intersect_ray(q)
	c.agl = maxf(0.0, p.y - (float(r["position"].y) if not r.is_empty() else 0.0))


## One physics tick of a driven (or test-driven) craft. `up` = the UP input (`jump`), DOWN is read from the crouch action while the player drives, or from State.down_in.
static func step(v: Vehicle, dt: float, thr: float, steer: float, up: bool, boost: bool) -> void:
	var c := v.craft
	var down := c.down_in
	if v.driver_is_player and Input.is_action_pressed(&"crouch"):
		down = 1.0
	var lift := (1.0 if up else 0.0) - clampf(down, 0.0, 1.0)
	if v.cls == &"heli" or v.cls == &"plane":
		_measure_agl(v)
	match v.cls:
		&"heli":
			_heli(v, dt, thr, steer, lift)
		&"plane":
			_plane(v, dt, thr, steer, lift)
		&"boat":
			_boat(v, dt, thr, steer, up, boost)
		&"tank":
			_tank(v, dt, thr, steer, up)
	c.max_alt = maxf(c.max_alt, c.agl if (v.cls == &"heli" or v.cls == &"plane") else 0.0)


## An unmanned craft: a helicopter or plane that nobody flies settles to the ground (a heli sinks gently, a plane glides down), a boat drifts to a stop, a tank stops.
static func idle(v: Vehicle, dt: float) -> void:
	var c := v.craft
	c.spool = move_toward(c.spool, 0.0, dt / (SPOOL_TIME * 2.0))
	c.lever = 0.0
	if v.cls == &"heli" or v.cls == &"plane":
		_measure_agl(v)
	match v.cls:
		&"heli", &"plane":
			v.vel *= exp(-(0.4 if c.airborne else 3.0) * dt)
			if c.airborne:
				c.vy = move_toward(c.vy, -6.0, 6.0 * dt)
			_move_air(v, dt)
			v.speed = v.vel.dot(v.forward())
		_:
			v.vel *= exp(-1.2 * dt)
			v._move(dt)
			v.speed = v.vel.dot(v.forward())
			if v.cls == &"boat":
				_keep_afloat(v)


## Can the hero get out here? A flying craft must be down (a helicopter or plane standing still-ish on the ground or a roof).
static func can_exit(v: Vehicle) -> bool:
	if v.craft == null or not (v.cls == &"heli" or v.cls == &"plane"):
		return true
	return not v.craft.airborne and absf(v.speed) < 9.0


## The sink rate an easy landing allows at `agl` metres: the speed from which a steady deceleration of `decel` m/s2 stops it at the ground (+ a little), so the last metres are a soft flare.
static func _flare(agl: float, decel: float) -> float:
	return sqrt(2.0 * decel * maxf(agl, 0.0)) + 1.4


# --- helicopter -------------------------------------------------------------------------------------------------------------------------

static func _heli(v: Vehicle, dt: float, thr: float, steer: float, lift: float) -> void:
	var c := v.craft
	var T := v.spec
	c.spool = move_toward(c.spool, 1.0, dt / SPOOL_TIME)
	var ready := c.spool >= SPOOL_READY
	var vmax := float(T["max"])
	var want := 0.0
	if ready:
		want = lift * HELI_CLIMB if lift > 0.0 else -minf(HELI_DESCENT, _flare(altitude(v), 3.0)) * (-lift)      # the last metres are a soft flare: a landing never hurts
	elif c.airborne:
		want = -HELI_DESCENT * 1.6
	c.vy = move_toward(c.vy, want, (HELI_VERT_ACC if ready else 4.0) * dt)
	if not c.airborne:
		c.vy = maxf(c.vy, 0.0)
		if lift > 0.1 and ready:
			c.airborne = true
			c.takeoffs += 1
	var fwd := v.forward()
	var rgt := v.right()
	var vf := v.vel.dot(fwd)
	var vl := v.vel.dot(rgt)
	var cap := vmax if c.airborne else HELI_GROUND_SPEED
	if ready and thr > 0.05:
		vf += float(T["acc"]) * thr * (1.0 - maxf(vf, 0.0) / cap) * dt
	elif ready and thr < -0.05:
		vf += float(T["acc"]) * 0.8 * thr * dt
	else:
		vf *= exp(-(0.55 if c.airborne else 3.0) * dt)
	vf = clampf(vf, -cap * 0.3, cap)
	vl *= exp(-float(T["grip"]) * dt)
	if ready:
		v.heading -= steer * HELI_YAW * (1.0 if c.airborne else 0.5) / (1.0 + absf(vf) / 70.0) * dt
	fwd = v.forward()
	rgt = v.right()
	v.vel = fwd * vf + rgt * vl
	v.speed = vf
	v.slip = vl
	v.steer_in = steer
	v.braking = false
	v.yaw_rate = -steer * HELI_YAW
	_move_air(v, dt)


# --- plane ---------------------------------------------------------------------------------------------------------------------------

static func _plane(v: Vehicle, dt: float, thr: float, steer: float, lift: float) -> void:
	var c := v.craft
	var T := v.spec
	var vmax := float(T["max"])
	var stall := float(T["stall"])
	if thr > 0.05:
		c.lever = minf(1.0, c.lever + LEVER_UP * thr * dt)
	elif thr < -0.05:
		c.lever = maxf(0.0, c.lever + LEVER_DOWN * thr * dt)
	c.spool = lerpf(c.spool, 0.25 + 0.75 * c.lever, 1.0 - exp(-2.0 * dt))
	var fwd := v.forward()
	var vf := v.vel.dot(fwd)
	var drag := 0.4 + vf * vf * 0.0005
	vf += (float(T["acc"]) * c.lever * (1.0 - clampf(vf / vmax, 0.0, 1.3)) - drag) * dt
	if not c.airborne and thr < -0.05 and c.lever < 0.05:
		vf -= PLANE_BRAKE * dt
	vf = maxf(vf, 0.0)
	var L := clampf((vf - stall * 0.75) / (stall * 0.25), 0.0, 1.0)
	var yaw := 0.0
	if not c.airborne:
		c.vy = 0.0
		yaw = steer * 0.85 * clampf(vf / 6.0, 0.0, 1.0)
		if vf > stall * TAKEOFF_AT and lift > 0.3:
			c.airborne = true
			c.vy = 3.0
			c.takeoffs += 1
	else:
		var target := 0.0
		if lift > 0.0:
			target = lift * PLANE_CLIMB * L
		elif lift < 0.0:
			target = -minf(PLANE_DIVE, _flare(altitude(v), 5.0)) * (-lift)
		if L < 1.0 and lift >= 0.0:
			target = minf(target, -minf((1.0 - L) * PLANE_SINK, _flare(altitude(v), 5.0)))
		c.vy = move_toward(c.vy, target, PLANE_VERT_ACC * dt)
		vf += -c.vy * 0.16 * dt                              # climbing costs speed, a dive gains it
		yaw = steer * PLANE_YAW * (0.5 + 0.5 * L)
		if v.global_position.y > float(T["ceil"]) and c.vy > 0.0:
			c.vy = 0.0
	v.heading -= yaw * dt
	fwd = v.forward()
	v.vel = fwd * vf
	v.speed = vf
	v.slip = 0.0
	v.steer_in = steer
	v.braking = not c.airborne and thr < -0.05
	v.yaw_rate = -yaw
	_move_air(v, dt)


# --- the shared 3D move of the two aircraft ---------------------------------------------------------------------------------------------

## Moves by velocity + vertical speed against the world (buildings, roofs, the ground): a floor contact is a landing (a hard one hurts), a wall contact bounces with damage, a ceiling stops the climb.
static func _move_air(v: Vehicle, dt: float) -> void:
	var c := v.craft
	if v._heading_set != v.heading:
		v.rotation.y = v.heading
		v._heading_set = v.heading
	var grounded := not c.airborne
	var motion := Vector3(v.vel.x, c.vy if not grounded else -0.06 / maxf(dt, 0.0001), v.vel.z) * dt
	var col := v.move_and_collide(motion)
	if col != null:
		var n := col.get_normal()
		if n.y > 0.6:                                                  # a floor: the ground or a roof
			if c.airborne:
				var sink := -c.vy
				c.hard = sink
				c.landings += 1
				if sink > LAND_SAFE:
					v.damage((sink - LAND_SAFE) * LAND_DAMAGE)
					FX.burst(v.global_position + Vector3(0.0, 0.4, 0.0), Color(1.0, 0.75, 0.38), 8, 5.0, 0.4, 8.0, 0.3)
					Sfx.play_at(&"hit", v.global_position, -3.0)
					if v.driver_is_player:
						FX.shake(minf(1.0, sink / 20.0))
			c.airborne = false
			c.vy = 0.0
		elif n.y < -0.6:                                               # a ceiling (an overhang)
			c.vy = minf(c.vy, 0.0)
		else:                                                          # a wall
			var nf := Vector3(n.x, 0.0, n.z)
			if nf.length_squared() > 1e-6:
				nf = nf.normalized()
				var vn := v.vel.dot(nf)
				if vn < 0.0:
					v.vel -= 1.3 * vn * nf
					var impact := -vn
					if impact > WALL_HIT:
						v.hits += 1
						v.damage(impact * WALL_DAMAGE)
						FX.burst(col.get_position(), Color(1.0, 0.75, 0.38), 8, 5.0, 0.3, 8.0, 0.3)
						Sfx.play_at(&"hit", v.global_position, -4.0)
						if v.driver_is_player:
							FX.shake(minf(1.0, impact / 25.0))
		var rem := col.get_remainder()
		rem -= n * rem.dot(n)
		if rem.length_squared() > 1e-8:
			v.move_and_collide(rem)
	elif grounded and v.global_position.y > v.base_y + 0.08:          # the ground fell away under it (a roof edge): flying again
		c.airborne = true
	if v.global_position.y < v.base_y - 0.01:
		v.global_position.y = v.base_y
		if c.vy < 0.0:
			c.vy = 0.0
		c.airborne = false


# --- boat -----------------------------------------------------------------------------------------------------------------------------

static func _boat(v: Vehicle, dt: float, thr: float, steer: float, brake: bool, boost: bool) -> void:
	var T := v.spec
	var vmax := float(T["max"])
	var acc_k := 1.0
	v.boosting = boost and thr > 0.05 and v.nitro > (0.0 if v.boosting else VehicleSpecs.NITRO_MIN)
	if v.boosting:
		v.nitro = maxf(0.0, v.nitro - VehicleSpecs.NITRO_DRAIN * dt)
		v._nitro_wait = VehicleSpecs.NITRO_DELAY
		vmax *= VehicleSpecs.NITRO_SPEED
		acc_k = VehicleSpecs.NITRO_ACC
		if v.nitro <= 0.0:
			v.boosting = false
	else:
		v._nitro_wait -= dt
		if v._nitro_wait <= 0.0:
			v.nitro = minf(1.0, v.nitro + VehicleSpecs.NITRO_REGEN * dt)
	var fwd := v.forward()
	var rgt := v.right()
	var vf := v.vel.dot(fwd)
	var vl := v.vel.dot(rgt)
	if thr > 0.05:
		vf += float(T["acc"]) * acc_k * thr * (1.0 - maxf(vf, 0.0) / vmax) * dt
	elif thr < -0.05:
		vf += (-float(T["brake"]) if vf > 0.5 else -float(T["acc"]) * 0.45) * -thr * dt
	else:
		vf *= exp(-BOAT_DRAG * dt)
	if brake:
		vf *= exp(-1.8 * dt)
	var base_max := float(T["max"])
	if not v.boosting and vf > base_max:
		vf = maxf(base_max, vf - VehicleSpecs.NITRO_COOL * dt)
	vf = clampf(vf, -base_max * 0.3, vmax)
	var auth := (0.25 + clampf(absf(vf) / 5.0, 0.0, 1.0)) / (1.0 + absf(vf) / 34.0)
	v.heading -= steer * BOAT_YAW * float(T.get("steer", 1.0)) * auth * (1.0 if vf >= -0.5 else -1.0) * dt
	vl *= exp(-float(T["grip"]) * dt)
	fwd = v.forward()
	rgt = v.right()
	v.vel = fwd * vf + rgt * vl
	v.speed = vf
	v.slip = vl
	v.braking = brake
	v.steer_in = steer
	v.yaw_rate = -steer * BOAT_YAW * auth
	v._move(dt)
	v.speed = v.vel.dot(fwd)
	_keep_afloat(v)


## A boat stays inside the water: past the edge of the flooded quarter it is put back and loses its speed.
static func _keep_afloat(v: Vehicle) -> void:
	var p := v.global_position
	if not FloodZone.contains(p.x, p.z, 1.0):
		var q := FloodZone.clamp_inside(p, 1.2)
		v.global_position = Vector3(q.x, v.global_position.y, q.z)
		v.vel *= -0.25
		v.speed = v.vel.dot(v.forward())


# --- tank ------------------------------------------------------------------------------------------------------------------------------

static func _tank(v: Vehicle, dt: float, thr: float, steer: float, brake: bool) -> void:
	var c := v.craft
	var T := v.spec
	var vmax := float(T["max"])
	var fwd := v.forward()
	var vf := v.vel.dot(fwd)
	if thr > 0.05:
		vf += float(T["acc"]) * thr * (1.0 - maxf(vf, 0.0) / vmax) * dt
	elif thr < -0.05:
		vf += (-float(T["brake"]) if vf > 0.5 else -float(T["acc"]) * 0.6) * -thr * dt
	else:
		vf *= exp(-TANK_DRAG * dt)
	if brake:
		vf *= exp(-3.0 * dt)
	vf = clampf(vf, -vmax * 0.4, vmax)
	var yr := steer * TANK_YAW * float(T.get("steer", 1.0)) * (1.0 - 0.45 * clampf(absf(vf) / vmax, 0.0, 1.0))
	v.heading -= yr * dt
	fwd = v.forward()
	v.vel = fwd * vf
	v.speed = vf
	v.slip = 0.0
	v.braking = brake
	v.steer_in = steer
	v.yaw_rate = -yr
	v._move(dt)
	v.speed = v.vel.dot(v.forward())
	_slew_turret(v, dt)


## The turret follows the crosshair of the driving player (or a test's `aim_at`), limited by TURRET_RATE.
static func _slew_turret(v: Vehicle, dt: float) -> void:
	var c := v.craft
	var target := aim_point(v)
	var muzzle := muzzle_origin(v)
	var d := target - muzzle
	if d.length() < 1.0:
		return
	var want_yaw := atan2(-d.x, -d.z)
	var flat := Vector2(d.x, d.z).length()
	var want_pitch := clampf(atan2(d.y, maxf(flat, 1.0)), GUN_PITCH_MIN, GUN_PITCH_MAX)
	var dy := wrapf(want_yaw - c.turret_yaw, -PI, PI)
	c.turret_yaw += clampf(dy, -TURRET_RATE * dt, TURRET_RATE * dt)
	c.gun_pitch = move_toward(c.gun_pitch, want_pitch, 1.1 * dt)


# --- aim -----------------------------------------------------------------------------------------------------------------------------------

## Where the crosshair of the driving player points (a test can set the meta `aim_at` on the vehicle); a point far ahead of the nose when nobody aims.
static func aim_point(v: Vehicle) -> Vector3:
	if v.has_meta(&"aim_at"):
		return v.get_meta(&"aim_at") as Vector3
	if v.driver_is_player and is_instance_valid(Game.player) and Game.player.has_method(&"get_aim"):
		var a: Dictionary = Game.player.call(&"get_aim")
		if a.has("hit"):
			return a["hit"] as Vector3
	return v.global_position + v.forward() * 80.0 + Vector3(0.0, 1.0, 0.0)


static func muzzle_origin(v: Vehicle) -> Vector3:
	var T := v.spec
	var up := float(T["hgt"]) * (0.8 if v.cls == &"tank" else 0.45)
	return v.global_position + Vector3(0.0, up, 0.0)


## The direction a mounted weapon fires in: the tank's turret direction, otherwise the line to the crosshair kept within a cone around the nose (the gunner leads a little, the nose still matters).
static func aim_dir(v: Vehicle) -> Vector3:
	var c := v.craft
	if v.cls == &"tank":
		var cp := cos(c.gun_pitch)
		return Vector3(-sin(c.turret_yaw) * cp, sin(c.gun_pitch), -cos(c.turret_yaw) * cp).normalized()
	var fwd := v.forward()
	var from := muzzle(v)
	var d := aim_point(v) - from
	if d.length() < 2.0:
		return fwd
	d = d.normalized()
	var cone := float(v.spec.get("aim_cone", 0.45))
	var ang := fwd.angle_to(d)
	if ang <= cone:
		return d
	return fwd.slerp(d, cone / maxf(ang, 0.001)).normalized()


## The muzzle: the tank's gun tip, the nose of an aircraft or boat.
static func muzzle(v: Vehicle) -> Vector3:
	var T := v.spec
	if v.cls == &"tank":
		var c := v.craft
		var cp := cos(c.gun_pitch)
		var d := Vector3(-sin(c.turret_yaw) * cp, sin(c.gun_pitch), -cos(c.turret_yaw) * cp)
		return v.global_position + Vector3(0.0, float(T["hgt"]) * 0.82, 0.0) + d * 3.4
	return v.global_position + v.forward() * float(T["len"]) * 0.5 + Vector3(0.0, float(T["hgt"]) * 0.4, 0.0)


# --- visual sync ---------------------------------------------------------------------------------------------------------------------------

## Per tick, after the step (or while unmanned): blade angle, blur discs, body attitude, bob, wake, turret. Cheap enough to run for every live craft.
static func sync(v: Vehicle, dt: float) -> void:
	var c := v.craft
	var vis := v.visual
	var near := v.driver_is_player or v._dist < 90.0
	var top := float(v.spec["max"])
	v.rpm = clampf(0.28 + 0.6 * c.spool if v.cls == &"heli" else (0.25 + 0.75 * c.lever if v.cls == &"plane" else 0.2 + 0.7 * absf(v.speed) / top), 0.0, 1.0)
	match v.cls:
		&"heli":
			c.ang = fposmod(c.ang + c.spool * 38.0 * dt, TAU)
			c.tail_ang = fposmod(c.tail_ang + c.spool * 60.0 * dt, TAU)
			if near:
				_blades(vis, "Rotor", c.spool * 38.0, c.ang, Vector3.UP)
				_blades(vis, "TailRotor", c.spool * 60.0, c.tail_ang, Vector3.RIGHT)
			var vf := v.speed
			c.pitch = lerpf(c.pitch, -clampf(vf / float(v.spec["max"]), -0.3, 1.0) * 0.2 + clampf(c.vy * 0.004, -0.04, 0.04), 1.0 - exp(-4.0 * dt))
			c.roll = lerpf(c.roll, clampf(v.yaw_rate * 0.2 - v.slip * 0.012, -0.35, 0.35) * (1.0 if c.airborne else 0.0), 1.0 - exp(-4.0 * dt))
			c.bob_t += dt
			var bob := sin(c.bob_t * 2.1) * 0.06 * (1.0 if c.airborne else 0.0)
			vis.model.rotation = Vector3(c.pitch, 0.0, c.roll)
			vis.model.position = Vector3(0.0, bob, 0.0)
		&"plane":
			if near:
				_blades(vis, "Prop", c.spool * 70.0, c.ang, Vector3(0.0, 0.0, 1.0))
			c.ang = fposmod(c.ang + c.spool * 70.0 * dt, TAU)
			var tp := clampf(c.vy / maxf(v.speed, 14.0), -0.6, 0.6) if c.airborne else (0.06 if v.speed > float(v.spec["stall"]) * 0.8 else 0.0)
			c.pitch = lerpf(c.pitch, tp, 1.0 - exp(-3.0 * dt))
			c.roll = lerpf(c.roll, clampf(v.yaw_rate * 0.6, -0.7, 0.7) * (1.0 if c.airborne else 0.0), 1.0 - exp(-3.0 * dt))
			vis.model.rotation = Vector3(c.pitch, 0.0, c.roll)
			vis.model.position = Vector3.ZERO
		&"boat":
			c.bob_t += dt
			var sp := clampf(absf(v.speed) / float(v.spec["max"]), 0.0, 1.0)
			c.bob = sin(c.bob_t * 2.4 + float(v.get_instance_id() % 9)) * 0.05 + sin(c.bob_t * 5.3) * 0.02
			c.pitch = lerpf(c.pitch, 0.1 * sp + sin(c.bob_t * 1.7) * 0.02, 1.0 - exp(-3.0 * dt))
			c.roll = lerpf(c.roll, clampf(-v.slip * 0.03 + v.yaw_rate * sp * 0.08, -0.25, 0.25) + sin(c.bob_t * 1.3) * 0.015, 1.0 - exp(-3.0 * dt))
			vis.model.rotation = Vector3(c.pitch, 0.0, c.roll)
			vis.model.position = Vector3(0.0, c.bob, 0.0)
			_wake(v, dt, sp)
		&"tank":
			var turret := vis.parts.get("Turret") as Node3D
			if turret != null:
				turret.rotation = Vector3(0.0, c.turret_yaw - v.heading, 0.0)
			var acc := (v.speed - v._last_vf) / maxf(dt, 0.0001)
			c.pitch = lerpf(c.pitch, clampf(acc * 0.004, -0.05, 0.05), 1.0 - exp(-5.0 * dt))
			vis.model.rotation = Vector3(c.pitch, 0.0, 0.0)
			vis.model.position = Vector3.ZERO


## Blades turn about `axis` until they blur: then the node is hidden and the soft disc shows.
static func _blades(vis: VehicleVisual, nm: String, spin: float, ang: float, axis: Vector3) -> void:
	var blades := vis.parts.get(nm) as Node3D
	if blades == null:
		return
	var disc := vis.parts.get(nm + "Disc") as Node3D
	var blur := spin >= BLUR_SPIN
	blades.visible = not blur
	if disc != null:
		disc.visible = blur
	blades.rotation = axis * ang


## The wake of a boat: a pale spray behind the stern and a short white foam along the sides, only near the player and only when moving.
static func _wake(v: Vehicle, dt: float, sp: float) -> void:
	var c := v.craft
	c.wake_t -= dt
	if c.wake_t > 0.0 or sp < 0.12 or not (v.driver_is_player or v._dist < 60.0):
		return
	c.wake_t = WAKE_EVERY
	var back := -v.forward() * float(v.spec["len"]) * 0.42
	var side := v.right() * float(v.spec["wid"]) * 0.3
	var y := FloodZone.LEVEL + 0.1
	var col := Color(0.88, 0.95, 1.0, 0.7)
	FX.burst(v.global_position + back + side + Vector3(0.0, y - v.global_position.y, 0.0), col, 2, 1.0 + 2.0 * sp, 0.9, 1.5, 1.4)
	FX.burst(v.global_position + back - side + Vector3(0.0, y - v.global_position.y, 0.0), col, 2, 1.0 + 2.0 * sp, 0.9, 1.5, 1.4)
	if sp > 0.5:
		FX.burst(v.global_position + v.forward() * float(v.spec["len"]) * 0.4 + Vector3(0.0, y - v.global_position.y, 0.0), col, 2, 2.0, 0.6, 3.0, 1.2)
