class_name EnemyCover
extends RefCounted
## Cover search for the enemies: the world's pooled prop colliders (Game.world.prop_colliders().bodies, the StaticBodies the City keeps around the player: crates, cars,
## barriers, bins) are the cover. A body counts when its shape is at least MIN_HEIGHT tall (a box, capsule or cylinder) and is not parked (its shape is enabled).
## find() returns the spot BEHIND the nearest suitable body as seen from the threat (one body radius + STAND_OFF further from the threat), or Vector3.INF.
## Spots another enemy already holds (its `_cover` within 1.7 m) are skipped, and so are spots inside a building or closer than MIN_THREAT_DIST to the threat.

const MIN_HEIGHT := 0.9
const STAND_OFF := 0.75
const MIN_THREAT_DIST := 6.0


## The nearest cover spot for `who` (an Operative) against the point `threat`, within `radius` metres of who, or Vector3.INF.
static func find(who: Node3D, threat: Vector3, radius := 22.0) -> Vector3:
	var city := Game.world
	if not is_instance_valid(city) or not city.has_method(&"prop_colliders"):
		return Vector3.INF
	var cols: Object = city.call(&"prop_colliders")
	if cols == null:
		return Vector3.INF
	var bodies: Array = cols.get(&"bodies")
	var from := who.global_position
	var best := Vector3.INF
	var best_d := INF
	for b: Variant in bodies:
		var body := b as StaticBody3D
		if body == null or not is_instance_valid(body):
			continue
		var info := body_info(body)
		if info.is_empty():
			continue
		var c: Vector3 = info["center"]
		if Vector2(c.x - from.x, c.z - from.z).length() > radius + float(info["radius"]):
			continue
		var away := Vector3(c.x - threat.x, 0.0, c.z - threat.z)
		if away.length() < 0.5:
			continue
		var spot := c + away.normalized() * (float(info["radius"]) + STAND_OFF)
		spot.y = from.y
		var dt := Vector2(spot.x - threat.x, spot.z - threat.z).length()
		var dd := Vector2(spot.x - from.x, spot.z - from.z).length()
		if dt < MIN_THREAT_DIST or dd > radius or dt < dd * 0.35:       # never run into the threat's lap
			continue
		if city.has_method(&"is_inside_building") and bool(city.call(&"is_inside_building", Vector3(spot.x, 1.0, spot.z))):
			continue
		if _held_by_other(who, spot):
			continue
		if dd < best_d:
			best_d = dd
			best = spot
	return best


## {center, radius, height} of the body's active collision shape, {} when it is parked / disabled / too low to hide behind.
static func body_info(body: StaticBody3D) -> Dictionary:
	for ch in body.get_children():
		var cs := ch as CollisionShape3D
		if cs == null or cs.disabled or cs.shape == null:
			continue
		var h := 0.0
		var r := 0.0
		var sh := cs.shape
		if sh is BoxShape3D:
			var sz := (sh as BoxShape3D).size
			h = sz.y
			r = maxf(sz.x, sz.z) * 0.5
		elif sh is CapsuleShape3D:
			h = (sh as CapsuleShape3D).height
			r = (sh as CapsuleShape3D).radius
		elif sh is CylinderShape3D:
			h = (sh as CylinderShape3D).height
			r = (sh as CylinderShape3D).radius
		else:
			continue
		if h < MIN_HEIGHT:
			return {}
		return {"center": cs.global_position, "radius": r, "height": h}
	return {}


static func _held_by_other(who: Node3D, spot: Vector3) -> bool:
	var mgr := Game.enemies as EnemyManager
	if mgr == null:
		return false
	for e in mgr.list:
		if e == who or e.dead or not e.active or not (e is Operative):
			continue
		var cp: Vector3 = (e as Operative).cover_point()
		if cp.is_finite() and Vector2(cp.x - spot.x, cp.z - spot.z).length() < 1.7:
			return true
	return false
