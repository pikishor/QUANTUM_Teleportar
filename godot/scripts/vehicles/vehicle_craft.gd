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
const MIN_DEPTH := 0.6               ## boats: water must be this much deeper than the draft under the hull and the bow, else they run aground

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
	var air: RefCounted               ## the flight state of an aircraft (AircraftFlight.Air: pitch, roll, thrust, stall), created on first use
	var sea := false                  ## a boat on the real water of the world (WaterWorld), not in the flooded quarter
	var wy := 0.0                     ## surface height under the hull (sea mode)
	var wpitch := 0.0                 ## the waves' pitch / roll under the hull (WaterWorld.buoyancy)
	var wroll := 0.0
	var depth := 0.0
	var last_wet := Vector3.INF       ## the last position that was deep enough (an aground boat is put back here)
	var groundings := 0               ## times it ran aground (tests)
	var planing := 0.0                ## 0..1 how far the hull has lifted onto the plane
	var ring_t := 0.0
	var trail: BoatWake               ## the foam ribbon behind the hull (created when the boat is near the player)

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
		if trail != null:
			trail.clear()


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
	var gy := AircraftFlight.ground_y_at(p.x, p.z, v.base_y)                     # the terrain outside the city plateau (the airport, the mountains), the rest height inside
	if p.y <= gy + 0.05 or not v.is_inside_tree():
		c.agl = maxf(0.0, p.y - gy)
		return
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0.0, 0.5, 0.0), p - Vector3(0.0, 400.0, 0.0), Game.L_WORLD)
	q.exclude = [v.get_rid()]
	var r := v.get_world_3d().direct_space_state.intersect_ray(q)
	c.agl = maxf(0.0, p.y - maxf(float(r["position"].y) if not r.is_empty() else gy, gy))


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
			var Ai := AircraftFlight.air(c)                                       # an unmanned craft levels out and cuts the engines
			Ai.pitch = lerpf(Ai.pitch, 0.0, 1.0 - exp(-2.0 * dt))
			Ai.roll = lerpf(Ai.roll, 0.0, 1.0 - exp(-2.0 * dt))
			Ai.thrust = 0.0
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
				_keep_afloat(v, dt)


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
	AircraftFlight.heli(v, dt, thr, steer, lift)                    # scripts/vehicles/aircraft_flight.gd


# --- plane ---------------------------------------------------------------------------------------------------------------------------

static func _plane(v: Vehicle, dt: float, thr: float, steer: float, lift: float) -> void:
	AircraftFlight.plane(v, dt, thr, steer, lift)


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
	var gy := AircraftFlight.ground_y(v)                              # the finished terrain is a floor too, where its collider has not streamed in yet (the far mountains, a fast jet)
	if v.global_position.y < gy - 0.01:
		if c.airborne:
			c.hard = maxf(-c.vy, 0.0)
			c.landings += 1
			if c.hard > LAND_SAFE:
				v.damage((c.hard - LAND_SAFE) * LAND_DAMAGE)
		v.global_position.y = gy
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
	_keep_afloat(v, dt)


## Where a boat floats. In the FLOODED QUARTER (city canals) the water is the flat plane over the streets and the boat stays inside its rect. Anywhere else it rides the world's real water
## (ocean, rivers, lakes: WaterWorld): the hull must find MIN_DEPTH metres under its centre and its bow, else it runs aground, is put back on its last good spot and loses its speed.
## The height, pitch and roll come from the waves under the hull (WaterWorld.buoyancy), a current carries it, and at speed the hull rises onto the plane.
static func _keep_afloat(v: Vehicle, dt := 0.016) -> void:
	var c := v.craft
	var p := v.global_position
	if FloodZone.contains(p.x, p.z, 1.0):
		c.sea = false
		c.last_wet = p
		return
	var draft := float(v.spec.get("draft", 0.35))
	var half := float(v.spec["len"]) * 0.5
	var fwd := v.forward()
	var d0 := TerrainHeight.depth_at(p.x, p.z)
	var d1 := TerrainHeight.depth_at(p.x + fwd.x * half, p.z + fwd.z * half)
	var ok := d0 >= draft + MIN_DEPTH and d1 >= draft + MIN_DEPTH * 0.5
	if not ok:
		if c.last_wet.is_finite():
			if c.last_wet.distance_to(p) > 0.05:
				c.groundings += 1
			v.global_position = Vector3(c.last_wet.x, p.y, c.last_wet.z)
			v.vel *= -0.2
			v.speed = v.vel.dot(v.forward())
		return
	c.last_wet = p
	c.sea = true
	c.depth = d0
	var bu := WaterWorld.buoyancy(p, v.heading, half, float(v.spec["wid"]) * 0.5)
	if not bu["water"]:
		return
	var flow: Vector2 = bu["flow"]
	if flow.length_squared() > 0.0001:
		v.vel += Vector3(flow.x, 0.0, flow.y) * 0.5 * dt                       # a river carries the hull downstream
	c.wy = float(bu["y"])
	c.wpitch = lerpf(c.wpitch, float(bu["pitch"]), 1.0 - exp(-6.0 * dt))
	c.wroll = lerpf(c.wroll, float(bu["roll"]), 1.0 - exp(-6.0 * dt))
	var top := float(v.spec["max"])
	var sp := clampf(absf(v.speed) / top, 0.0, 1.0)
	c.planing = lerpf(c.planing, smoothstep(0.35, 0.8, sp), 1.0 - exp(-2.5 * dt))
	var target := c.wy - draft + c.planing * 0.22
	v.global_position.y = lerpf(p.y, target, 1.0 - exp(-12.0 * dt)) if absf(p.y - target) < 2.5 else target


## Sets the height of a boat that was just put at `v.global_position` (VehicleManager spawns and the tests): on the real water it floats at the surface, in the flooded quarter at the flood level.
static func place_boat(v: Vehicle) -> void:
	var c := v.craft
	var p := v.global_position
	c.last_wet = p
	c.wpitch = 0.0
	c.wroll = 0.0
	c.planing = 0.0
	if FloodZone.contains(p.x, p.z):
		c.sea = false
		v.global_position.y = v.base_y
		return
	var w := WaterWorld.surface_y(p.x, p.z)
	if w != TerrainHeight.NO_WATER:
		c.sea = true
		c.wy = w
		v.global_position.y = w - float(v.spec.get("draft", 0.35))


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
	var want_pitch := clampf(atan2(d.y, maxf(flat, 1.0)), GUN_PITCH_MIN, float(v.spec.get("gun_max", GUN_PITCH_MAX)))      # artillery and anti-air guns elevate far above a tank's
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
	var up := float(T["hgt"]) * (float(T.get("gun_h", 0.8)) if v.cls == &"tank" else 0.45)
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
		return v.global_position + Vector3(0.0, float(T["hgt"]) * (float(T.get("gun_h", 0.8)) + 0.02), 0.0) + d * float(T.get("gun_len", 3.4))
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
			var Ah := AircraftFlight.air(c)
			c.pitch = Ah.pitch
			c.roll = Ah.roll
			c.bob_t += dt
			var bob := sin(c.bob_t * 2.1) * 0.06 * (1.0 if c.airborne else 0.0)
			vis.model.rotation = Vector3(c.pitch, 0.0, c.roll)
			vis.model.position = Vector3(0.0, bob, 0.0)
			if v.driver_is_player:
				AircraftFlight.tick_guide(v, dt)
		&"plane":
			if near:
				_blades(vis, "Prop", c.spool * 70.0, c.ang, Vector3(0.0, 0.0, 1.0))
			c.ang = fposmod(c.ang + c.spool * 70.0 * dt, TAU)
			var Ap := AircraftFlight.air(c)
			c.pitch = Ap.pitch
			c.roll = Ap.roll
			vis.model.rotation = Vector3(c.pitch, 0.0, c.roll)
			vis.model.position = Vector3.ZERO
			var burner := vis.parts.get("Burner") as Node3D
			if burner != null:                                                         # the afterburner cone grows with the thrust and shows above 55 % of it
				var th := clampf((Ap.thrust - 0.55) / 0.45, 0.0, 1.0)
				burner.visible = near and th > 0.02 and not v.wreck
				burner.scale = Vector3(1.0, 1.0 + 3.0 * th, 1.0) * (0.7 + 0.5 * th)
				burner.position.z = float(v.spec["len"]) * 0.5 + 0.35 + 1.0 * (1.0 + 3.0 * th) * 0.5
			if v.driver_is_player:
				AircraftFlight.tick_guide(v, dt)
		&"boat":
			c.bob_t += dt
			var sp := clampf(absf(v.speed) / float(v.spec["max"]), 0.0, 1.0)
			var calm := 0.35 if c.sea else 1.0                                         # on the real waves the water does the bobbing (pitch / roll come from them)
			c.bob = (sin(c.bob_t * 2.4 + float(v.get_instance_id() % 9)) * 0.05 + sin(c.bob_t * 5.3) * 0.02) * calm
			c.pitch = lerpf(c.pitch, 0.1 * sp * (0.6 + 0.8 * c.planing) + sin(c.bob_t * 1.7) * 0.02 * calm + c.wpitch, 1.0 - exp(-3.0 * dt))
			c.roll = lerpf(c.roll, clampf(-v.slip * 0.03 + v.yaw_rate * sp * 0.08 * (1.0 + float(v.cls == &"jetski") * 1.4), -0.4, 0.4) + sin(c.bob_t * 1.3) * 0.015 * calm + c.wroll, 1.0 - exp(-3.0 * dt))
			vis.model.rotation = Vector3(c.pitch, 0.0, c.roll)
			vis.model.position = Vector3(0.0, c.bob, 0.0)
			_wake(v, dt, sp)
		&"tank":
			var turret := vis.parts.get("Turret") as Node3D
			if turret != null:
				turret.rotation = Vector3(0.0, c.turret_yaw - v.heading, 0.0)
				var gun := turret.get_node_or_null("Gun") as Node3D                               # the procedural tanks elevate their gun on its trunnion (the art tank has one piece)
				if gun != null:
					gun.rotation = Vector3(c.gun_pitch, 0.0, 0.0)
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


## The wake of a boat: a pale spray behind the stern and a short white foam along the sides, a bow wave at speed and a ring of ripples on the surface every few tenths of a second, only near the player.
static func _wake(v: Vehicle, dt: float, sp: float) -> void:
	var c := v.craft
	c.wake_t -= dt
	c.ring_t -= dt
	var near := v.driver_is_player or v._dist < 60.0
	var y := (c.wy if c.sea else FloodZone.LEVEL) + 0.1
	var rel := Vector3(0.0, y - v.global_position.y, 0.0)
	var wid := float(v.spec["wid"])
	var ln := float(v.spec["len"])
	if near:                                                                   # the foam ribbon (one draw call) follows the stern
		if c.trail == null:
			c.trail = BoatWake.new()
			v.add_child(c.trail)
		c.trail.update(dt, v.global_position - v.forward() * ln * 0.45 + Vector3(0.0, y - v.global_position.y - 0.04, 0.0), wid * 0.4, sp)
	elif c.trail != null and c.trail.visible:
		c.trail.clear()
	if sp < 0.1 or not near:
		return
	if c.wake_t <= 0.0:
		c.wake_t = WAKE_EVERY
		var back := -v.forward() * ln * 0.42
		var side := v.right() * wid * 0.3
		var col := Color(0.88, 0.95, 1.0, 0.7)
		FX.burst(v.global_position + back + side + rel, col, 2, 1.0 + 2.0 * sp, 0.9, 1.5, 1.4)
		FX.burst(v.global_position + back - side + rel, col, 2, 1.0 + 2.0 * sp, 0.9, 1.5, 1.4)
		if sp > 0.4:                                                           # the bow wave: two fans of spray thrown out and back from the stem
			var bow := v.global_position + v.forward() * ln * 0.4 + rel
			FX.burst(bow + v.right() * wid * 0.25, col, 2, 2.4 + 2.0 * sp, 0.55, 2.6, 1.0)
			FX.burst(bow - v.right() * wid * 0.25, col, 2, 2.4 + 2.0 * sp, 0.55, 2.6, 1.0)
		if sp > 0.7:                                                           # a rooster tail behind a fast hull
			FX.burst(v.global_position + back * 1.1 + rel + Vector3(0.0, 0.3, 0.0), Color(0.95, 0.98, 1.0, 0.8), 3, 3.0 + 3.0 * sp, 0.8, 4.0, 1.6)
	if c.ring_t <= 0.0 and FX.marks != null:
		c.ring_t = 0.32
		FX.marks.ripple(v.global_position - v.forward() * ln * 0.45 + rel, 1.2 + wid)
