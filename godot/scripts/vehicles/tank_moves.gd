class_name TankMoves
extends RefCounted
## OWN MOVES of the odd military vehicles (wave 129, w129-tankmis). Until now the hover tank, the walker and the amphibious carrier drove exactly like a tracked tank (VehicleCraft._tank):
##   HOVER  (spec `hover`)   it floats: the hull keeps part of its sideways speed through a turn (it DRIFTS and slides out, HOVER_GRIP), it rides HOVER_LIFT above the ground with a slow bob,
##                           and it glides over water as over land (the river bed is not its floor)
##   WALKER (spec `legs`)    it walks: the speed rises and falls with each stride (GAIT, a step every STRIDE m), it turns in place step by step (the legs move when it pivots, TankModels),
##                           the body sways up and down with the gait
##   SWIMMER (t_amphib)      it swims: in water deeper than SWIM_DEPTH it floats at the surface (SWIM_DRAFT under it, rocking on the waves), its water jets push it at SWIM_MAX m/s and it
##                           turns slower, a wake splashes behind it; where the bottom comes up again it climbs out on its tracks
## VehicleCraft._tank calls `drive` for the speed and the turn and `after_move` once the hull has moved. W129TM_OLD=1 (or TankMoves.on = false): the tracked-tank moves for all of them.

const HOVER_GRIP := 1.5                 ## 1/s: how fast the sideways slide of a hover tank dies away (a tracked tank: at once)
const HOVER_LIFT := 0.55
const STRIDE := 2.6                     ## m per step of the walker
const GAIT := 0.35                      ## share of the walker's speed that rises and falls with each step
const SWIM_DEPTH := 1.3
const SWIM_DRAFT := 1.05                ## m of hull under the surface
const SWIM_MAX := 5.5
const SWIM_ACC := 2.4
const SWIM_TURN := 0.55

static var on := OS.get_environment("W129TM_OLD") != "1"


static func mode(v: Vehicle) -> StringName:
	if not on:
		return &""
	if bool(v.spec.get("hover", false)):
		return &"hover"
	if bool(v.spec.get("legs", false)):
		return &"walker"
	if v.kind == &"t_amphib":
		return &"swim"
	return &""


## True while the amphibious carrier is afloat (deep water under its centre, outside the city plateau).
static func swimming(v: Vehicle) -> bool:
	var p := v.global_position
	if absf(p.x) <= TerrainHeight.CITY_HALF and absf(p.z) <= TerrainHeight.CITY_HALF:
		return false
	return TerrainHeight.depth_at(p.x, p.z) > SWIM_DEPTH and not Bridges.on_deck(p.x, p.z, p.y)


## The top speed and acceleration for this tick (the swimmer is slow in the water). [vmax, acc, yaw_scale]
static func limits(v: Vehicle, vmax: float, acc: float) -> Array:
	match mode(v):
		&"swim":
			if swimming(v):
				return [minf(vmax, SWIM_MAX), minf(acc, SWIM_ACC), SWIM_TURN]
		&"walker":
			return [vmax, acc, 0.55 + 0.45 * gait(v)]                            # it turns in steps (the speed pulses in `velocity`)
	return [vmax, acc, 1.0]


## The walker's step: 1 at the push-off of a stride, 0 between two (from the distance it walked, so it matches the legs of TankModels).
static func gait(v: Vehicle) -> float:
	var walked := float(v.get_meta(&"tm_walk", 0.0))
	return absf(sin(walked / STRIDE * PI))


## The velocity of the hull after the turn (`fwd` the new nose, `vf` the speed along it). A hover tank keeps a fading share of its old sideways speed: it drifts.
static func velocity(v: Vehicle, fwd: Vector3, vf: float, dt: float) -> Vector3:
	match mode(v):
		&"hover":
			var right := Vector3(-fwd.z, 0.0, fwd.x)
			var lat := v.vel.dot(right) * exp(-HOVER_GRIP * dt)
			var out := fwd * vf + right * lat
			v.set_meta(&"tm_slip", absf(lat))
			return out
		&"walker":
			v.set_meta(&"tm_walk", float(v.get_meta(&"tm_walk", 0.0)) + (absf(vf) + absf(v.yaw_rate) * 1.6) * dt)
			var pulse := (1.0 - GAIT) + GAIT * gait(v) * PI * 0.5                # it pushes off on each step and slows between steps (the mean stays the drive speed)
			v.set_meta(&"tm_vf", vf)
			v.set_meta(&"tm_pulse", pulse)
			return fwd * vf * pulse
	return fwd * vf


## The speed the driver holds (the walker's steps pulse round it; everything else: its speed along the nose).
static func base_speed(v: Vehicle, fwd: Vector3) -> float:
	if mode(v) == &"walker" and v.has_meta(&"tm_vf"):
		return float(v.get_meta(&"tm_vf"))
	return v.vel.dot(fwd)


## After the hull moved: the hover tank and the swimmer take their height from the water, the walker sways with its steps.
static func after_move(v: Vehicle, dt: float) -> void:
	match mode(v):
		&"hover":
			var p := v.global_position
			if absf(p.x) > TerrainHeight.CITY_HALF or absf(p.z) > TerrainHeight.CITY_HALF:
				var s := WaterWorld.surface_y(p.x, p.z)
				if s != TerrainHeight.NO_WATER and s > TerrainHeight.height_at(p.x, p.z):
					var want := s + 0.15
					v.global_position.y = v.base_y + want                           # the ground step put it on the bed: it hovers on the waves instead
					v.ground_pitch = lerpf(v.ground_pitch, 0.0, 1.0 - exp(-4.0 * dt))
					v.ground_roll = lerpf(v.ground_roll, 0.0, 1.0 - exp(-4.0 * dt))
					_wake(v, s, dt, 0.5)
		&"swim":
			if swimming(v):
				var p2 := v.global_position
				var s2 := WaterWorld.surface_y(p2.x, p2.z)
				if s2 != TerrainHeight.NO_WATER:
					var want2 := s2 - SWIM_DRAFT + sin(float(Time.get_ticks_msec()) * 0.0019) * 0.06
					var was := float(v.get_meta(&"tm_y", p2.y - v.base_y))           # the ground step put it on the bed: it settles into the water from where it floated last tick
					var y2 := lerpf(was, want2, 1.0 - exp(-3.0 * dt))
					v.set_meta(&"tm_y", y2)
					v.global_position.y = v.base_y + y2
					var bu := WaterWorld.buoyancy(p2, v.heading, float(v.spec["len"]) * 0.5, float(v.spec["wid"]) * 0.5)
					v.ground_pitch = lerpf(v.ground_pitch, clampf(float(bu.get("pitch", 0.0)) + v.speed * 0.012, -0.2, 0.2), 1.0 - exp(-3.0 * dt))      # the bow rides up with speed
					v.ground_roll = lerpf(v.ground_roll, clampf(float(bu.get("roll", 0.0)), -0.2, 0.2), 1.0 - exp(-3.0 * dt))
					v.surface = &"water"
					_wake(v, s2, dt, 1.0)
					v.set_meta(&"tm_swim", true)
			elif v.has_meta(&"tm_swim"):
				v.remove_meta(&"tm_swim")
				v.remove_meta(&"tm_y")                                       # out on the bank: the tracks bite again (Vehicle._terrain_step rides the ground)
		&"walker":
			if v.has_meta(&"tm_vf"):                                                # a wall or a car stopped the hull: the held speed drops with it
				var pulse := maxf(float(v.get_meta(&"tm_pulse", 1.0)), 0.1)
				var real := v.vel.dot(v.forward())
				var held := float(v.get_meta(&"tm_vf"))
				if absf(real) < absf(held) * pulse - 0.5:
					v.set_meta(&"tm_vf", real / pulse)
			var vis := v.visual
			if vis != null and vis.model != null:
				var g := gait(v)
				var moving := clampf((absf(v.speed) + absf(v.yaw_rate) * 2.0) / 2.0, 0.0, 1.0)
				vis.model.position.y = lerpf(vis.model.position.y, (g * 0.16 - 0.05) * moving, 1.0 - exp(-12.0 * dt))
				vis.model.rotation.z = lerpf(vis.model.rotation.z, sin(float(v.get_meta(&"tm_walk", 0.0)) / STRIDE * PI * 0.5) * 0.035 * moving, 1.0 - exp(-8.0 * dt))


static func _wake(v: Vehicle, surface: float, dt: float, strength: float) -> void:
	if absf(v.speed) < 1.5 or v._dist > 80.0:
		return
	var t := float(v.get_meta(&"tm_wake", 0.0)) - dt
	if t <= 0.0:
		t = 0.45
		WaterWorld.splash(Vector3(v.global_position.x, surface, v.global_position.z) - v.forward() * float(v.spec["len"]) * 0.5, strength * clampf(absf(v.speed) / 6.0, 0.4, 1.2))
	v.set_meta(&"tm_wake", t)
