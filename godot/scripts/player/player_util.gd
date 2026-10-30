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
