class_name PlayerUtil
extends RefCounted
## Small allocation-free math helpers shared by the player scripts (ported from src/util.js).


## Frame-rate independent exponential approach: a moves toward b with rate k (1/s).
static func damp(a: float, b: float, k: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-k * dt))


## Same for angles (radians), taking the shortest way round.
static func damp_angle(a: float, b: float, k: float, dt: float) -> float:
	return a + angle_difference(a, b) * (1.0 - exp(-k * dt))


## Critically damped spring, exact solution (stable for any dt). state = (value, velocity); returns the new state.
## omega is the natural frequency in rad/s: the spring settles in roughly 4 / omega seconds, without overshoot.
static func spring(state: Vector2, target: float, omega: float, dt: float) -> Vector2:
	var x := state.x - target
	var c := state.y + omega * x
	var e := exp(-omega * dt)
	return Vector2(target + (x + c * dt) * e, (state.y - omega * c * dt) * e)


## Ray (origin o, unit direction d) against a sphere: distance along the ray, or INF.
## Starting inside the sphere returns the exit point, like the prototype.
static func ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var k := oc.dot(oc) - r * r
	var disc := b * b - k
	if disc < 0.0:
		return INF
	var s := sqrt(disc)
	var t := -b - s
	if t > 0.0:
		return t
	var t2 := -b + s
	return t2 if t2 > 0.0 else INF


## Yaw (radians, forward = (-sin yaw, 0, -cos yaw), i.e. Node3D.rotation.y) of a world-space forward vector.
static func yaw_of(forward: Vector3) -> float:
	return atan2(-forward.x, -forward.z)


## Yaw and pitch (x = yaw, y = pitch; positive pitch looks up) of a world-space direction.
static func yaw_pitch_of(dir: Vector3) -> Vector2:
	var d := dir.normalized()
	return Vector2(atan2(-d.x, -d.z), asin(clampf(d.y, -1.0, 1.0)))


## Unit forward vector of a yaw / pitch pair (inverse of yaw_pitch_of).
static func forward_of(yaw: float, pitch: float) -> Vector3:
	var cp := cos(pitch)
	return Vector3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)


## Smooth, cheap pseudo noise in -1..1 (two sines), for camera shake and sway. No allocations.
static func wobble(t: float, f1: float, f2: float, seed_offset: float) -> float:
	return sin(t * f1 + seed_offset) * 0.6 + sin(t * f2 + seed_offset * 2.7 + 1.9) * 0.4


## Seconds since engine start, the time base of Player.last_hit_time and friends.
static func now() -> float:
	return Time.get_ticks_msec() * 0.001


## --- valid ground for teleports --------------------------------------------------------------------------------------------------------
## The walkable square is |x|, |z| <= CityLayout.WALK (the inner faces of the invisible border walls). A blink or any other teleport must land on valid ground inside it:
## `safe_spot` clamps the XZ, drops the point onto the floor or roof below it (physics ray on the world layer, else the city's ground_height) and moves a point that is
## inside a building volume out to the nearest street. `outside_city` is the rescue test (outside the walls, below the floor, not a number).
const SAFE_MARGIN := 3.0
const MAX_AIR := 60.0


static func outside_city(p: Vector3) -> bool:
	return not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)) or absf(p.x) > CityLayout.WALK + 1.0 or absf(p.z) > CityLayout.WALK + 1.0 or p.y < -6.0


## The street point nearest to p (y = 0): p's x or z snapped onto the nearest road centre line, whichever is closer.
static func nearest_street(p: Vector3) -> Vector3:
	var ox := CityLayout.road_offset(p.x)
	var oz := CityLayout.road_offset(p.z)
	var q := Vector3(p.x - ox, 0.0, p.z) if absf(ox) <= absf(oz) else Vector3(p.x, 0.0, p.z - oz)
	q.x = clampf(q.x, -CityLayout.HALF, CityLayout.HALF)
	q.z = clampf(q.z, -CityLayout.HALF, CityLayout.HALF)
	return q


## `p` made valid (see above). `world` is the City (Game.world) or null (then only the clamp and the floor of y = 0 apply). `space` (optional) is a physics space for the floor ray.
static func safe_spot(p: Vector3, world: Node = null, space: PhysicsDirectSpaceState3D = null) -> Vector3:
	var q := p
	if not (is_finite(q.x) and is_finite(q.y) and is_finite(q.z)):
		return Game.SPAWN
	var lim := CityLayout.WALK - SAFE_MARGIN
	var clamped := absf(q.x) > lim or absf(q.z) > lim
	q.x = clampf(q.x, -lim, lim)
	q.z = clampf(q.z, -lim, lim)
	if world != null and world.has_method(&"is_inside_building") and q.y >= 0.0 and world.call(&"is_inside_building", Vector3(q.x, maxf(q.y + 0.4, 0.05), q.z)):
		q = nearest_street(q)
		clamped = true
	var floor_y := 0.0
	if space != null:
		var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, maxf(q.y, 0.0) + 2.0, q.z), Vector3(q.x, -20.0, q.z), Game.L_WORLD)
		var hit := space.intersect_ray(rq)
		if not hit.is_empty():
			floor_y = (hit["position"] as Vector3).y
	if world != null and world.has_method(&"ground_height") and (space == null or floor_y == 0.0):
		floor_y = maxf(floor_y, float(world.call(&"ground_height", q.x, q.z, maxf(q.y, 0.0) + 0.5)))
	if clamped or q.y < floor_y - 0.5 or q.y < -1.0:
		q.y = floor_y
	q.y = minf(q.y, floor_y + MAX_AIR)                        # a blink into the sky ends a few metres up at most, never 900 m in the air
	return q
