class_name SettlementData
extends RefCounted
## The static side of the towns (wave 112): the plan of every town (built once, cached), the doors of all their houses (the interior gameplay appends them to Game.world.doors), the quantum snake
## anchors, the parked-car slots, the helipads, the mission hooks and the map pins of the sub-places. Nothing here needs the scene tree: it reads OutskirtsSites (kind &"town") and TerrainRoads.
##   SettlementData.towns()                    the OutskirtsSites entries of kind town
##   SettlementData.plan_of(site)              the SettlementPlan (cached; town frame)
##   SettlementData.doors()                    every enterable door of every town: {id (>= DOOR_BASE), type, name, wall, pos, normal, yaw, face_yaw, width, town, kind}
##   SettlementData.anchors()                  the AnchorSites format {id, kind, name, pos (top), base, height, radius}
##   SettlementData.parked_slots(site)         ParkedCars slots [x, z, heading, kind] in the site frame
##   SettlementData.helipads()                 world positions of the helipads {id, name, pos, r}
##   SettlementData.hooks()                    mission hooks {id, kind, name, pos, r, reward, tag}

const DOOR_BASE := 100000
const DOOR_STEP := 1000

static var _plans := {}
static var _doors: Array[Dictionary] = []
static var _doors_built := false


static func reset() -> void:
	_plans.clear()
	_doors.clear()
	_doors_built = false
	SettlementKit.reset_cache()


static func towns() -> Array[Dictionary]:
	OutskirtsSites.ensure()
	var out: Array[Dictionary] = []
	for s in OutskirtsSites.list:
		if s["kind"] == &"town":
			out.append(s)
	return out


## The road samples of the town's main street in the town frame (x across, z along), ordered by z, from -len-30 to +len+30.
static func street_of(site: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var roads := TerrainRoads.roads()
	var sp: Vector3 = site["pos"]
	var yaw: float = site["yaw"]
	var sn := sin(yaw)
	var cs := cos(yaw)
	var ln: float = float(site["len"]) + 30.0
	for r in roads:
		if String(r["name"]) != String(site["on_road"]):
			continue
		var pts: PackedVector2Array = r["pos"]
		var tmp: Array[Vector2] = []
		for q in pts:
			var dx := q.x - sp.x
			var dz := q.y - sp.z
			var lx := dx * cs - dz * sn
			var lz := dx * sn + dz * cs
			if absf(lz) <= ln and absf(lx) < 60.0:
				tmp.append(Vector2(lx, lz))
		tmp.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
		for q in tmp:
			if out.is_empty() or q.y - out[out.size() - 1].y > 3.0:
				out.append(q)
	return out


static func plan_of(site: Dictionary) -> SettlementPlan:
	var id: StringName = site["id"]
	if _plans.has(id):
		return _plans[id]
	var plan := SettlementPlan.build(site, street_of(site))
	for it in plan.items:                                                      # the tall things of the specials are the quantum snake anchors
		if it["kind"] != &"special":
			continue
		var part := SettlementKit.part_of(it)
		if part.has("anchor"):
			var a: Dictionary = part["anchor"]
			var o := Basis(Vector3.UP, float(it["yaw"])) * (a.get("at", Vector3.ZERO) as Vector3)
			plan.add_anchor(a["kind"], String(a["name"]), float(it["x"]) + o.x, float(it["z"]) + o.z, float(a["height"]), float(a["radius"]))
	_plans[id] = plan
	return plan


## World position of a point in the town frame, on the ground (pad height).
static func to_world(site: Dictionary, x: float, z: float, y_up := 0.0) -> Vector3:
	var w := OutskirtsSites.to_world(site, Vector3(x, 0.0, z))
	w.y = float(site["pad_y"]) + y_up
	return w


static func doors() -> Array[Dictionary]:
	if _doors_built:
		return _doors
	var ts := towns()
	if ts.is_empty():
		return _doors
	_doors_built = true
	var ti := 0
	for s in ts:
		var plan := plan_of(s)
		var yaw: float = s["yaw"]
		var k := 0
		var seen := {}
		for it in plan.items:
			var interior: StringName = it["interior"]
			if interior == &"":
				continue
			var part := SettlementKit.part_of(it)
			var locals: Array = []
			if it["kind"] == &"house":
				for dx in SettlementHouses.door_list(it["spec"]):
					locals.append(Vector3(dx, 0.0, -float(it["d"]) * 0.5))
			elif part.has("door"):
				locals.append(part["door"])
			for lp: Vector3 in locals:
				var b := Basis(Vector3.UP, float(it["yaw"]))
				var tf := b * lp
				var wx := float(it["x"]) + tf.x
				var wz := float(it["z"]) + tf.z
				var nl := b * Vector3(0.0, 0.0, -1.0)
				var wall := to_world(s, wx, wz)
				var nw := Basis(Vector3.UP, yaw) * nl
				var nrm := Vector3(nw.x, 0.0, nw.z).normalized()
				var pos := wall + nrm * 1.3
				pos.y = TerrainHeight.height_at(pos.x, pos.z)
				wall.y = pos.y
				var id := DOOR_BASE + ti * DOOR_STEP + k
				k += 1
				var yaw_w := atan2(nrm.x, nrm.z)                                      # (Basis(UP, yaw) * BACK = the outward normal, the CityDoors convention)
				_doors.append({"id": id, "type": interior, "name": InteriorCountry.door_name(interior, id), "wall": wall, "pos": pos, "normal": nrm, "yaw": yaw_w,
					"face_yaw": atan2(-nrm.x, -nrm.z), "width": 2.0, "town": s["id"], "kind": it["kind"]})
		ti += 1
	return _doors


## Doors of one town.
static func doors_of(town_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in doors():
		if d["town"] == town_id:
			out.append(d)
	return out


## Quantum snake anchors of all the towns (the format of AnchorSites.all_anchors: pos = the top, base = the foot).
static func anchors() -> Array:
	var out: Array = []
	for s in towns():
		var plan := plan_of(s)
		var ai := 0
		for an in plan.anchors:
			var base := to_world(s, float(an["x"]), float(an["z"]))
			out.append({"id": StringName("%s_a%d" % [s["id"], ai]), "kind": an["kind"], "name": "%s: %s" % [s["name"], an["name"]], "pos": base + Vector3(0.0, float(an["height"]), 0.0), "base": base,
				"height": float(an["height"]), "radius": float(an["radius"])})
			ai += 1
	return out


static func parked_slots(site: Dictionary) -> Array:
	var plan := plan_of(site)
	var out: Array = []
	for a in plan.parked:
		out.append([a[0], a[1], a[2], a[3]])
	return out


static func helipads() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in towns():
		var plan := plan_of(s)
		var k := 0
		for h in plan.helipads:
			out.append({"id": StringName("%s_pad%d" % [s["id"], k]), "name": "%s HELIPAD" % String(s["name"]), "pos": to_world(s, float(h["x"]), float(h["z"]), float(h.get("y", 0.1))), "r": float(h.get("r", 9.0))})
			k += 1
		for it in plan.items:
			if it["kind"] == &"special" and it["type"] == &"hotel":
				var part := SettlementKit.part_of(it)
				if part.has("helipad"):
					var hp: Vector3 = Basis(Vector3.UP, float(it["yaw"])) * (part["helipad"] as Vector3)
					var w := to_world(s, float(it["x"]) + hp.x, float(it["z"]) + hp.z, hp.y)
					out.append({"id": StringName("%s_roof" % s["id"]), "name": "%s ROOF PAD" % String(s["name"]), "pos": w, "r": 8.5})
	return out


## Ground height at the foot of a town-frame point.
static func ground_at(site: Dictionary, x: float, z: float) -> float:
	var w := OutskirtsSites.to_world(site, Vector3(x, 0.0, z))
	return TerrainHeight.height_at(w.x, w.z)
