extends RefCounted
## w123-clutter: shared door-lane analysis for the probe and the permanent check. A door's lane is the sidewalk strip in front of it, from the wall out to the kerb,
## 2.4 m wide (the hero is 0.9 m wide; a door is 1.8 to 2.4 m). Blockers are the city's pooled prop collider sources (lamps, planters, benches, bins, kit props ...)
## and the kerb cars of ParkedCars whose body reaches into the lane.

const HALF_W := 1.2          ## half lane width
const CAR_HALF := Vector2(1.0, 2.45)   ## parked car half width / half length


## Distance from a wall point along n to the road edge (the kerb), capped at 12 m.
static func kerb_out(wall: Vector3, n: Vector3) -> float:
	var o := 0.0
	while o < 12.0:
		var q := wall + n * o
		if _in_road(q.x) or _in_road(q.z):
			return o
		o += 0.25
	return 12.0


static func _in_road(c: float) -> bool:
	var k := roundf((c + CityLayout.HALF) / CityLayout.PITCH)
	return absf(c - (-CityLayout.HALF + k * CityLayout.PITCH)) < CityLayout.ROAD * 0.5


## Every walk-in or USE door within `r` of `from`: {what, wall, n, kerb}.
static func doors_near(from: Vector3, r: float) -> Array:
	var out: Array = []
	var city = Game.world
	var seen := {}
	if TowerFloors.instance != null:
		for tw: Dictionary in TowerFloors.instance.towers:
			var w := TowerFloors.door_pos(tw, 0.0)
			if w.distance_to(from) > r:
				continue
			var n := (TowerFloors.door_pos(tw, 1.0) - w).normalized()
			seen[(tw["lot"] as CityLayout.Lot).index] = true
			out.append({"what": "tower %s lot %d" % [tw["kind"], (tw["lot"] as CityLayout.Lot).index], "wall": w, "n": n})
	for d: Dictionary in city.doors:
		var lot_i := int(d["id"])
		if seen.has(lot_i):
			continue
		var n2: Vector3 = d["normal"]
		var w2: Vector3 = (d["pos"] as Vector3) - n2 * 1.3
		if w2.distance_to(from) > r:
			continue
		out.append({"what": "%s door lot %d" % ["shop" if d.get("walk_in", false) else "USE", lot_i], "wall": w2, "n": n2})
	for e in out:
		e["kerb"] = kerb_out(e["wall"], e["n"])
	return out


## Props and kerb cars standing in the lane of door `d`. Returns Array of strings.
static func blockers(d: Dictionary) -> Array:
	var out: Array = []
	var w: Vector3 = d["wall"]
	var n: Vector3 = d["n"]
	var t := Vector3(-n.z, 0.0, n.x)
	var kerb: float = d["kerb"]
	var pc = Game.world.prop_colliders()
	var ids := {}
	var o := 0.0
	while o <= kerb + 0.5:
		var q := w + n * o
		for dx in [-3.0, 0.0, 3.0]:
			for dz in [-3.0, 0.0, 3.0]:
				for id in (pc._grid.get(pc._key(q.x + dx, q.z + dz), PackedInt32Array()) as PackedInt32Array):
					ids[id] = true
		o += 2.0
	for id in ids:
		var xf: Transform3D = pc._xf[id]
		if absf(xf.origin.y) > 1.5:
			continue
		var rel := xf.origin - w
		var along := rel.dot(t)
		var out_d := rel.dot(n)
		var spec: Array = pc._spec_list[pc._spec[id]]
		var sz: Vector3 = spec[1]
		var half := maxf(sz.x, sz.z) * 0.5 if int(spec[0]) == 0 else sz.x     # box: half of the longest side; capsule / cylinder: radius
		if out_d > -0.2 and out_d < kerb - 0.3 and absf(along) < HALF_W + half:
			out.append("%s at %.1f out %.1f side" % [spec[3], out_d, along])
	var pk := ParkedCars.instance
	if pk != null:
		for i in pk._n:
			if pk._alive[i] != 1:
				continue
			var rel2 := Vector3(pk._x[i], 0.0, pk._z[i]) - Vector3(w.x, 0.0, w.z)
			var along2 := rel2.dot(t)
			var out2 := rel2.dot(n)
			# the car's extent along the kerb (it parks parallel to the kerb)
			if out2 > -0.2 and out2 < kerb + 2.2 and absf(along2) < HALF_W + CAR_HALF.y:
				out.append("parked car kind %d at %.1f out %.1f side (kerb %.1f)" % [pk._kind[i], out2, along2, kerb])
	return out
