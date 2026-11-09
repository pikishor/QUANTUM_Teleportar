class_name WorldSites
extends RefCounted
## WHERE the missions and free-roam activities of the big world happen (wave 107: air and vehicle missions). Data and terrain queries only, no nodes: WorldMissions turns these places into
## mission recipes, WorldRoam into the free-roam courses. Everything is derived from the finished terrain (TerrainHeight), the rivers (WaterLayout), the roads (TerrainRoads), the outskirt
## sites (OutskirtsSites) and the harbour, so a place never drifts away from the land it sits on.
##
##   airport()                   the airport: {name, gate, strip, strip_h, hangar, real}. When the airport wave's `Airport.hooks()` exists its terminal / hangar / runway entries are used (contract in
##                               the ARCHITECTURE section), else the AIRSTRIP and HELIPAD spawn points of the city stand in for it (`real` false).
##   landing_fields()            flat pads a plane can set down on: the villages and farms of the outskirts (+ the airport strip)
##   heli_pads()                 flat pads in the mountains a helicopter can land on (lodge, hunters, observatory, radio tower)
##   road_route(name)            a mountain road as a polyline Vector3 (x, road height, z)
##   river_route(i, a, b, step)  a river centre line as a polyline at the water surface
##   canyon_gates(...)           air race gates that follow a river gorge, high enough to clear its walls
##   treasure_spots()            the hidden caches the scanner hunt uses (deterministic, on dry land near the outskirt sites)
##   hooks()                     one list of all of it for the Mission Board and the map: {id, kind, name, pos, r}

const HELI_PAD_IDS: Array[StringName] = [&"lodge", &"hunters", &"observatory", &"radio_tower"]
const FIELD_IDS: Array[StringName] = [&"dust_wells", &"south_farm", &"pine_hollow", &"north_farm"]
const CHASE_ROADS: Array[String] = ["SUMMIT ROAD", "RIDGE TRACK", "QUARRY TRACK", "MOUNTAIN TRACK"]
const ROUTE_STEP := 14.0                ## metres between the points of a river or road route

## The two canyon courses of the air race: river, the stretch of its centre line (indices into the 12 m samples), the pad a helicopter waits on and where the course starts from the pad.
const CANYONS: Array[Dictionary] = [
	{"id": &"eastwater", "name": "EASTWATER CANYON", "river": 1, "from": 74, "to": 12, "pad": &"dust_wells", "up_and_back": true},
	{"id": &"highline", "name": "HIGHLINE GORGE", "river": 0, "from": 52, "to": 128, "pad": &"lodge", "up_and_back": false},
]


# --- the airport -------------------------------------------------------------------------------------------------------------

static func _airport_script() -> GDScript:
	if ResourceLoader.exists("res://scripts/world/airport.gd"):
		return load("res://scripts/world/airport.gd") as GDScript
	return null


## The airport. `gate` is the walk-up point (the terminal apron), `strip` the start of the runway with `strip_h` the heading a plane stands at, `hangar` where its guards stand.
static func airport() -> Dictionary:
	var out := {"name": "AIRPORT", "gate": Vector3.INF, "strip": Vector3.INF, "strip_h": 0.0, "hangar": Vector3.INF, "heli": Vector3.INF, "real": false}
	var sc := _airport_script()
	if sc != null and sc.has_method(&"hooks"):
		var hk: Variant = sc.call(&"hooks")
		if hk is Array:
			for e: Variant in hk as Array:
				if not (e is Dictionary) or not (e as Dictionary).has("pos"):
					continue
				var d := e as Dictionary
				var k := StringName(str(d.get("kind", "")))
				var p: Vector3 = d["pos"]
				match k:
					&"terminal", &"gate":
						out["gate"] = p
						if str(d.get("name", "")) != "":
							out["name"] = str(d["name"]).trim_suffix(" TERMINAL")
					&"hangar":
						out["hangar"] = p
					&"runway", &"strip":
						out["strip"] = p
						out["strip_h"] = float(d.get("heading", 0.0))
					&"helipad", &"heli":
						out["heli"] = p
			if (out["gate"] as Vector3).is_finite() and (out["strip"] as Vector3).is_finite():
				if not (out["hangar"] as Vector3).is_finite():
					out["hangar"] = out["gate"]
				if not (out["heli"] as Vector3).is_finite():
					out["heli"] = out["gate"]
				out["real"] = true
				return out
	var strip := VehicleSpawns.point(&"airstrip")
	var pad := VehicleSpawns.point(&"heli_pad")
	var sp: Vector3 = strip["pos"] if not strip.is_empty() else Vector3(340.0, 0.0, 0.0)
	out["strip"] = sp
	out["strip_h"] = float(strip["h"]) if not strip.is_empty() else -PI * 0.5
	out["gate"] = pad["pos"] if not pad.is_empty() else Vector3(105.0, 0.0, 25.0)
	out["heli"] = out["gate"]
	out["hangar"] = sp + Vector3(150.0, 0.0, 0.0)        # the avenue beyond the strip's start: the guards stand there
	return out


static func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, TerrainHeight.height_at(p.x, p.z), p.z)


# --- pads and fields ---------------------------------------------------------------------------------------------------------

static func _pad(id: StringName) -> Dictionary:
	var s := OutskirtsSites.by_id(id)
	if s.is_empty():
		return {}
	var p: Vector3 = s["pos"]
	return {"id": id, "name": String(s["name"]), "pos": p, "r": float(s["r"]), "yaw": float(s["yaw"])}


static func landing_fields() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in FIELD_IDS:
		var d := _pad(id)
		if not d.is_empty():
			out.append(d)
	return out


static func heli_pads() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in HELI_PAD_IDS:
		var d := _pad(id)
		if not d.is_empty():
			out.append(d)
	return out


static func pad(id: StringName) -> Dictionary:
	return _pad(id)


## A landing field at least `min_d` metres from `from` (a delivery has to go somewhere): the nearest one, or with `r` a seeded pick among the fields up to twice as far (variety between offers).
static func far_field(from: Vector3, min_d := 700.0, avoid: StringName = &"", r: RandomNumberGenerator = null) -> Dictionary:
	var cands: Array[Dictionary] = []
	for f in landing_fields():
		if f["id"] == avoid:
			continue
		var p: Vector3 = f["pos"]
		var d := Vector2(p.x - from.x, p.z - from.z).length()
		if d >= min_d:
			var e: Dictionary = f.duplicate()
			e["d"] = d
			cands.append(e)
	if cands.is_empty():
		for f in landing_fields():
			var p2: Vector3 = f["pos"]
			var d2 := Vector2(p2.x - from.x, p2.z - from.z).length()
			if f["id"] != avoid and d2 > 100.0:
				var e2: Dictionary = f.duplicate()
				e2["d"] = d2
				cands.append(e2)
	if cands.is_empty():
		return {}
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	var pool := cands.filter(func(e: Dictionary) -> bool: return float(e["d"]) <= float(cands[0]["d"]) * 2.0)
	return pool[r.randi() % pool.size()] if r != null else pool[0]


# --- roads and rivers --------------------------------------------------------------------------------------------------------

static func road_route(road_name: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	for r in TerrainRoads.roads():
		if String(r["name"]) != road_name:
			continue
		var pts: PackedVector2Array = r["pos"]
		var prof: PackedFloat32Array = r["prof"]
		var acc := 0.0
		for i in pts.size():
			if i > 0:
				acc += pts[i].distance_to(pts[i - 1])
				if acc < ROUTE_STEP and i < pts.size() - 1:
					continue
				acc = 0.0
			out.append(Vector3(pts[i].x, prof[i], pts[i].y))
		return out
	return out


## Metres of a route.
static func length_of(route: PackedVector3Array) -> float:
	var n := 0.0
	for i in route.size() - 1:
		n += Vector2(route[i + 1].x - route[i].x, route[i + 1].z - route[i].z).length()
	return n


## A river's centre line at the water surface from sample `a` to sample `b` (either order: a > b runs upstream), thinned to about `step` metres.
static func river_route(river: int, a: int, b: int, step := ROUTE_STEP) -> PackedVector3Array:
	WaterLayout.ensure()
	var out := PackedVector3Array()
	if river < 0 or river >= WaterLayout.paths.size():
		return out
	var p: Dictionary = WaterLayout.paths[river]
	var pos: PackedVector2Array = p["pos"]
	var surf: PackedFloat32Array = p["surface"]
	var n := pos.size()
	var ia := clampi(a, 0, n - 1)
	var ib := clampi(b, 0, n - 1)
	var dir := 1 if ib >= ia else -1
	var every := maxi(int(round(step / WaterLayout.STEP)), 1)
	var i := ia
	while (i - ib) * dir <= 0:
		out.append(Vector3(pos[i].x, surf[i], pos[i].y))
		i += dir * every
	var last := Vector3(pos[ib].x, surf[ib], pos[ib].y)
	if out.is_empty() or out[out.size() - 1].distance_to(last) > 1.0:
		out.append(last)
	return out


## Half width of the river at sample i.
static func river_half_width(river: int, i: int) -> float:
	WaterLayout.ensure()
	var p: Dictionary = WaterLayout.paths[river]
	var hw: PackedFloat32Array = p["hw"]
	return hw[clampi(i, 0, hw.size() - 1)]


## A point of the water beside the bank of a river sample, on the side of `toward` and `inset` metres inside the edge: where a boat is left for the hero to step into.
static func bank_water(river: int, i: int, toward: Vector3, inset := 2.4) -> Vector3:
	WaterLayout.ensure()
	var p: Dictionary = WaterLayout.paths[river]
	var pos: PackedVector2Array = p["pos"]
	var surf: PackedFloat32Array = p["surface"]
	var hw: PackedFloat32Array = p["hw"]
	var k := clampi(i, 1, pos.size() - 2)
	var t := (pos[k + 1] - pos[k - 1]).normalized()
	var nrm := Vector2(-t.y, t.x)
	var c := pos[k]
	if (Vector2(toward.x, toward.z) - c).dot(nrm) < 0.0:
		nrm = -nrm
	var q := c + nrm * maxf(hw[k] - inset, 0.0)
	return Vector3(q.x, surf[k], q.y)


## The terrain peak within `r` metres of (x, z) (a few samples), so a gate never sits inside a hill.
static func peak_around(x: float, z: float, r: float) -> float:
	var m := TerrainHeight.height_at(x, z)
	for k in 8:
		var a := TAU * float(k) / 8.0
		m = maxf(m, TerrainHeight.height_at(x + cos(a) * r, z + sin(a) * r))
		m = maxf(m, TerrainHeight.height_at(x + cos(a) * r * 0.5, z + sin(a) * r * 0.5))
	return m


## Air race gates down (or up and back along) a river gorge: `n` gates spread over the stretch, each `clear` metres over the highest ground within `wall` metres, so the line is open all the way.
## Returns Array[Vector3]; the last gate of an up-and-back course is the pad it started from.
static func canyon_gates(def: Dictionary, n := 9, clear := 16.0, wall := 34.0) -> Array[Vector3]:
	var route := river_route(int(def["river"]), int(def["from"]), int(def["to"]), 12.0 * 5.0)
	var out: Array[Vector3] = []
	if route.size() < 2:
		return out
	var total := length_of(route)
	var pr := PathFollow.new(route)
	var legs := n if not bool(def.get("up_and_back", false)) else int(ceil(float(n) * 0.5))
	for k in legs:
		var d := total * float(k + 1) / float(legs)
		var p := pr.point_at(d)
		out.append(Vector3(p.x, maxf(peak_around(p.x, p.z, wall), p.y) + clear, p.z))
	if bool(def.get("up_and_back", false)):
		var back: Array[Vector3] = []
		for k in range(legs - 2, -1, -1):
			var q := out[k]
			back.append(Vector3(q.x, q.y + 4.0, q.z))
		var pad := _pad(StringName(def["pad"]))
		if not pad.is_empty():
			var pp: Vector3 = pad["pos"]
			back.append(Vector3(pp.x, pp.y + 10.0, pp.z))
		out.append_array(back)
	return out


# --- the scanner hunt --------------------------------------------------------------------------------------------------------

## Hidden caches: offsets around the crash site, the old mine, the observatory and the two cabins, each moved to dry, gently sloped land. Deterministic.
const CACHE_DEFS: Array[Dictionary] = [
	{"site": &"crash", "off": Vector2(-34.0, 22.0), "name": "CORE FRAGMENT"},
	{"site": &"crash", "off": Vector2(40.0, -18.0), "name": "SHIP DEBRIS"},
	{"site": &"mine", "off": Vector2(-48.0, 30.0), "name": "ORE STASH"},
	{"site": &"observatory", "off": Vector2(42.0, 26.0), "name": "SURVEY CACHE"},
	{"site": &"hunters", "off": Vector2(-52.0, -20.0), "name": "HUNTER STASH"},
	{"site": &"lodge", "off": Vector2(56.0, 30.0), "name": "LAKE CACHE"},
]


static func treasure_spots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in CACHE_DEFS:
		var s := OutskirtsSites.by_id(StringName(d["site"]))
		if s.is_empty():
			continue
		var sp: Vector3 = s["pos"]
		var off: Vector2 = d["off"]
		var x := sp.x + off.x
		var z := sp.z + off.y
		var tries := 0
		while tries < 8 and TerrainHeight.depth_at(x, z) > 0.0:                # never under water
			x += 9.0
			z += 6.0
			tries += 1
		out.append({"id": StringName("cache_%d" % out.size()), "name": String(d["name"]), "site": d["site"], "pos": Vector3(x, TerrainHeight.height_at(x, z), z)})
	return out


# --- the lists the board and the map read ------------------------------------------------------------------------------------

## {id, kind, name, pos, r}: kinds airport, heliport, field, road, river, harbour, canyon.
static func hooks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ap := airport()
	out.append({"id": &"airport", "kind": &"airport", "name": String(ap["name"]), "pos": ap["gate"], "r": 40.0})
	for d in heli_pads():
		out.append({"id": d["id"], "kind": &"heliport", "name": d["name"], "pos": d["pos"], "r": maxf(float(d["r"]) * 0.7, 14.0)})
	for d in landing_fields():
		out.append({"id": d["id"], "kind": &"field", "name": d["name"], "pos": d["pos"], "r": 60.0})
	for rn in CHASE_ROADS:
		var rt := road_route(rn)
		if rt.size() > 1:
			out.append({"id": StringName(rn.to_lower().replace(" ", "_")), "kind": &"road", "name": rn, "pos": rt[0], "r": 20.0})
	for c in CANYONS:
		var pd := _pad(StringName(c["pad"]))
		if not pd.is_empty():
			out.append({"id": c["id"], "kind": &"canyon", "name": c["name"], "pos": pd["pos"], "r": 30.0})
	out.append({"id": &"harbour", "kind": &"harbour", "name": "HARBOUR", "pos": Harbour.center(), "r": 80.0})
	return out


## The hook nearest to `from` of a kind (an empty dictionary when there is none): {id, kind, name, pos, r} and `d` the distance in metres.
static func nearest_of(kind: StringName, from: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for h in hooks():
		if h["kind"] != kind:
			continue
		var p: Vector3 = h["pos"]
		var d := Vector2(p.x - from.x, p.z - from.z).length()
		if d < bd:
			bd = d
			best = h.duplicate()
			best["d"] = d
	return best
