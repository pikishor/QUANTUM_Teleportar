class_name PlayerUtil
extends RefCounted
## Small allocation-free math helpers shared by the player scripts (ported from src/util.js).


## Frame-rate independent exponential approach: a moves toward b with rate k (1/s).
static func damp(a: float, b: float, k: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-k * dt))


## Same for angles (radians), taking the shortest way round.
static func damp_angle(a: float, b: float, k: float, dt: float) -> float:
	return a + angle_difference(a, b) * (1.0 - exp(-k * dt))


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
