class_name HitZones
extends RefCounted
## Where a bullet meets a person: a head sphere plus a standing body capsule from the feet to the shoulders, so the hit area is the shape on screen (the old chest sphere
## missed the feet and was 20 cm too fat on each side). Zones: &"head", &"body", &"legs". `ray` is pure maths (tests need no scene); `of` asks any enemy node.
## Drones and other round things keep their sphere (zone &"body", &"head" in the upper third, as before).

const HEAD := &"head"
const BODY := &"body"
const LEGS := &"legs"
const LEGS_BELOW := 0.47                  ## of the height: below this a hit is a leg hit (the hips)
const NECK := 0.83                        ## of the height: the body capsule ends here, the head sphere sits on it
const LEG_MULT := 0.85                    ## a leg shot hurts a little less than a torso shot
const HEAD_MULT := 2.0                    ## the generic head multiplier (weapons with a `crit` damage use that instead)


## Damage multiplier of a zone for things without a weapon `crit` number (citizens, melee).
static func damage_mult(zone: StringName) -> float:
	match zone:
		HEAD:
			return HEAD_MULT
		LEGS:
			return LEG_MULT
	return 1.0


## Ray (unit direction `d` from `o`) against a standing person whose feet are at `feet`: {t, zone, point} of the first hit, {} for a miss.
## `height` is the full height, `body_r` the torso radius, `head_r` the head radius.
static func ray(o: Vector3, d: Vector3, feet: Vector3, height: float, body_r: float, head_r: float) -> Dictionary:
	var top := height * NECK
	var best := INF
	var zone := BODY
	# the head: a sphere resting on the shoulders
	var hc := feet + Vector3(0.0, height - head_r - 0.01, 0.0)
	var th := PlayerUtil.ray_sphere(o, d, hc, head_r)
	if th < best:
		best = th
		zone = HEAD
	# the body: a vertical capsule, feet to shoulders
	var tb := _ray_capsule(o, d, feet + Vector3(0.0, body_r, 0.0), feet + Vector3(0.0, maxf(top - body_r, body_r), 0.0), body_r)
	if tb < best:
		best = tb
		zone = BODY
	if best == INF:
		return {}
	var pt := o + d * best
	if zone == BODY and pt.y - feet.y < height * LEGS_BELOW:
		zone = LEGS
	return {"t": best, "zone": zone, "point": pt}


## First hit of a ray on a vertical capsule (axis a -> b, a below b), INF for a miss. Starting inside gives the exit point like PlayerUtil.ray_sphere.
static func _ray_capsule(o: Vector3, d: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var best := INF
	# the cylinder part (infinite in y, then clipped to the segment)
	var ox := o.x - a.x
	var oz := o.z - a.z
	var dd := d.x * d.x + d.z * d.z
	if dd > 1.0e-9:
		var bq := ox * d.x + oz * d.z
		var cq := ox * ox + oz * oz - r * r
		var disc := bq * bq - dd * cq
		if disc >= 0.0:
			var s := sqrt(disc)
			for t: float in [(-bq - s) / dd, (-bq + s) / dd]:
				if t > 0.0:
					var y := o.y + d.y * t
					if y >= a.y and y <= b.y:
						best = minf(best, t)
						break
	# the two caps
	best = minf(best, PlayerUtil.ray_sphere(o, d, a, r))
	best = minf(best, PlayerUtil.ray_sphere(o, d, b, r))
	return best


## The hit of a ray on an enemy node: {t, zone, point}, {} for a miss. A node with `hit_ray()` (Drone and its people) answers for itself; anything else with `center()` and `radius` is a sphere.
static func of(target: Object, o: Vector3, d: Vector3) -> Dictionary:
	if target.has_method(&"hit_ray"):
		return target.call(&"hit_ray", o, d)
	if not target.has_method(&"center"):
		return {}
	var r := PlayerWeapon._radius_of(target)
	if r <= 0.0:
		return {}
	var c: Vector3 = target.call(&"center")
	var t := PlayerUtil.ray_sphere(o, d, c, r)
	if t == INF:
		return {}
	var pt := o + d * t
	return {"t": t, "zone": HEAD if pt.y > c.y + r * PlayerWeapon.CRIT_HEIGHT else BODY, "point": pt}
