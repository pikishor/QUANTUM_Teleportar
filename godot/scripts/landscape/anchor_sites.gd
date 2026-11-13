class_name AnchorSites
extends RefCounted
## Where the tall anchors of the outskirts stand (wave 112): wind turbine fields, pylon lines, radio masts and quarry cranes. Pure functions of the terrain (like LandscapeSites):
## candidates are tried in fixed order against the finished ground and kept only on dry, gentle, clear land, so they follow any change of the terrain. Data only; the meshes and the
## collision are AnchorWorld.
##   AnchorSites.turbines()  [{id, name, pos (base, y = ground), yaw}]  per field: fields() = [{id, name, centre, turbines: [indices]}]
##   AnchorSites.pylon_lines()  [{id, name, pylons: [{pos, yaw}]}]      masts()  [{id, name, pos}]      cranes()  [{id, name, pos, yaw}]
##   AnchorSites.arches()  [{id, name, pos (centre of the span at the ground), yaw, variant (0 wide, 1 tall), layer (terrain texture layer of the rock)}]: natural rock arches you can drive through
##   AnchorSites.all_anchors()  every anchor as {id, kind (turbine, pylon, mast, crane, arch, cliff), name, pos (the top, where a rope can be fixed), base, height, radius}; the cliffs are the
##   lips of the waterfalls (LandscapeSites), the arches stand on dry flat ground; towers have a collider pool in AnchorWorld, arches have their own mesh collider, cliffs are the terrain

const FIELDS := [
	{"name": "EASTWIND FARM", "road": "DESERT ROAD", "from": 560.0, "to": 1500.0, "step": 190.0, "offs": [170.0, 300.0]},
	{"name": "PASS RIDGE FARM", "road": "PASS ROAD", "from": 150.0, "to": 1000.0, "step": 170.0, "offs": [140.0, 270.0]},
	{"name": "COAST BREEZE FARM", "road": "COAST ROAD", "from": 500.0, "to": 1500.0, "step": 190.0, "offs": [150.0, 280.0]},
]
const LINES := [
	{"name": "EAST TRANSMISSION LINE", "via": [Vector2(1120.0, -330.0), Vector2(1500.0, -170.0), Vector2(1950.0, 130.0), Vector2(2350.0, 400.0)]},
	{"name": "SOUTH FEEDER LINE", "via": [Vector2(1120.0, 640.0), Vector2(1480.0, 1010.0), Vector2(1880.0, 1280.0)]},
	{"name": "WEST FEEDER LINE", "via": [Vector2(-1120.0, 300.0), Vector2(-1250.0, 700.0), Vector2(-1180.0, 1180.0)]},
]
const MAST_REGIONS := [
	{"name": "HOLLOW RELAY", "c": Vector2(-1000.0, -700.0), "r": 420.0, "hint": Vector2(-1320.0, -460.0)},
	{"name": "NORTH RELAY", "c": Vector2(450.0, -1750.0), "r": 340.0, "hint": Vector2(410.0, -1910.0)},
	{"name": "MESA RELAY", "c": Vector2(1950.0, -250.0), "r": 340.0, "hint": Vector2(2150.0, -130.0)},
]
const ARCH_REGIONS := [
	{"name": "SUNGATE ARCH", "c": Vector2(1750.0, 650.0), "r": 340.0, "variant": 0, "layer": 8, "hint": Vector2(1568.0, 520.0)},
	{"name": "TIDEMARK ARCH", "c": Vector2(-1500.0, 480.0), "r": 420.0, "variant": 1, "layer": 4, "coast": true, "hint": Vector2(-1448.0, 870.0)},
	{"name": "MESA GATE", "c": Vector2(1100.0, -1100.0), "r": 330.0, "variant": 0, "layer": 8, "hint": Vector2(1308.0, -918.0)},
]
const ARCH_H := [16.0, 18.0]                          ## crown height of the two arch meshes (tools/landscape/rocks.py arch())
const ARCH_HALF := [11.0, 7.6]                        ## half span of the centre line of the two meshes
const PYLON_SPACING := 135.0
const TURBINE_H := 64.0
const PYLON_H := 41.0
const MAST_H := 79.0
const CRANE_H := 58.0
const HARBOUR_CRANE_H := 33.0                          ## the harbour's gantry cranes (HarbourKit): top of the boom girders above the quay

static var built := false
static var _part := 0
static var _busy := false
const PARTS := 5
static var _turbines: Array = []
static var _fields: Array = []
static var _lines: Array = []
static var _masts: Array = []
static var _cranes: Array = []
static var _arches: Array = []


static func turbines() -> Array:
	ensure()
	return _turbines


static func fields() -> Array:
	ensure()
	return _fields


static func pylon_lines() -> Array:
	ensure()
	return _lines


static func masts() -> Array:
	ensure()
	return _masts


static func cranes() -> Array:
	ensure()
	return _cranes


static func arches() -> Array:
	ensure()
	return _arches


## Everything at once (the first query of any list does it); the live world's staged wake calls `ensure_step()` once per frame instead, so no frame pays for all five parts.
static func ensure() -> void:
	if _busy:
		return
	while not built:
		ensure_step()


## One of the five parts of `ensure()` (fields, lines, masts, cranes, arches); true while parts are left.
static func ensure_step() -> bool:
	if built or _busy:
		return false
	_busy = true                                                 # the parts only read terrain and roads, but a list accessor called from inside one must not start a second build
	if _part == 0:
		TerrainHeight.warm()
	match _part:
		0: _build_fields()
		1: _build_lines()
		2: _build_masts()
		3: _build_cranes()
		4: _build_arches()
	_part += 1
	built = _part >= PARTS
	_busy = false
	return not built


## Dry, gentle, clear land: no water, no road corridor, no site pad, no airstrip, not on the beach.
static func _valid(x: float, z: float, margin: float, max_slope := 0.3) -> bool:
	if absf(x) > TerrainHeight.WORLD_HALF - 80.0 or absf(z) > TerrainHeight.WORLD_HALF - 80.0 or TerrainHeight.city_distance(x, z) < 20.0:
		return false
	var h := TerrainHeight.height_at(x, z)
	if h < TerrainHeight.SEA_LEVEL + 4.0 or TerrainHeight.water_level_for(x, z, h) != TerrainHeight.NO_WATER:
		return false
	if float(TerrainRoads.nearest(x, z)[0]) < 24.0 + margin * 0.3:
		return false
	if OutskirtsSites.inside(x, z, margin) >= 0 or Airport.inside(x, z, margin + 20.0) or LandscapeSites.inside_strip(x, z, margin + 30.0) or LandscapeSites.near_feature(x, z, margin):
		return false
	return TerrainHeight.slope_at(x, z) <= max_slope


static func _road(name: String) -> Dictionary:
	for r: Dictionary in TerrainRoads.roads():
		if String(r["name"]) == name:
			return r
	return {}


static func _build_fields() -> void:
	for fi in FIELDS.size():
		var fd: Dictionary = FIELDS[fi]
		var rd := _road(String(fd["road"]))
		if rd.is_empty():
			continue
		var pos: PackedVector2Array = rd["pos"]
		var idx: Array = []
		var k := 0
		var s := float(fd["from"])
		while s <= float(fd["to"]):
			var i := clampi(int(s / TerrainRoads.STEP), 1, pos.size() - 2)
			var tg := (pos[i + 1] - pos[i - 1]).normalized()
			var nr := Vector2(-tg.y, tg.x)
			for oi in (fd["offs"] as Array).size():
				var side := 1.0 if (k + oi) % 2 == 0 else -1.0
				var p: Vector2 = pos[i] + nr * float((fd["offs"] as Array)[oi]) * side + tg * float(oi) * 70.0
				if _valid(p.x, p.y, 30.0, 0.36):
					var wind_yaw := 0.0
					_turbines.append({"id": StringName("t%d_%d" % [fi, _turbines.size()]), "name": String(fd["name"]), "pos": Vector3(p.x, TerrainHeight.height_at(p.x, p.y), p.y), "yaw": wind_yaw})
					idx.append(_turbines.size() - 1)
			s += float(fd["step"])
			k += 1
		if idx.is_empty():
			continue
		var c := Vector3.ZERO
		for ti in idx:
			c += (_turbines[ti]["pos"] as Vector3)
		c /= float(idx.size())
		_fields.append({"id": StringName("field%d" % fi), "name": String(fd["name"]), "centre": c, "turbines": idx})


static func _build_lines() -> void:
	for li in LINES.size():
		var ld: Dictionary = LINES[li]
		var via: Array = ld["via"]
		var pylons: Array = []
		for vi in via.size() - 1:
			var a: Vector2 = via[vi]
			var b: Vector2 = via[vi + 1]
			var total := a.distance_to(b)
			var n := int(total / PYLON_SPACING)
			var dir := (b - a).normalized()
			for k in n + (1 if vi == via.size() - 2 else 0):
				var p := a + dir * (float(k) * total / float(maxi(n, 1)))
				var placed := false
				for shift in [0.0, 18.0, -18.0, 36.0, -36.0]:
					var q: Vector2 = p + Vector2(-dir.y, dir.x) * float(shift) + dir * float(shift) * 0.4
					if _valid(q.x, q.y, 10.0, 0.7):
						pylons.append({"pos": Vector3(q.x, TerrainHeight.height_at(q.x, q.y), q.y), "yaw": atan2(dir.x, dir.y)})
						placed = true
						break
				if not placed:
					pylons.append({"gap": true})
		_lines.append({"id": StringName("line%d" % li), "name": String(ld["name"]), "pylons": pylons})


static func _build_masts() -> void:
	for mi in MAST_REGIONS.size():
		var md: Dictionary = MAST_REGIONS[mi]
		var c: Vector2 = md["c"]
		var rad := float(md["r"])
		var best := Vector3.ZERO
		var best_h := -1.0e9
		var from_hint := false
		var hint = md.get("hint", Vector2.INF)                  # the highest valid spot of the last full search (that one costs 70 ms): the same test at that one spot is a millisecond
		if hint is Vector2 and (hint as Vector2).is_finite() and not LandscapeSites.ignore_hints:
			var hp := hint as Vector2
			if _valid(hp.x, hp.y, 30.0, 0.22):
				var hh := TerrainHeight.height_at(hp.x, hp.y)
				if hh < 230.0:
					best_h = hh
					best = Vector3(hp.x, hh, hp.y)
					from_hint = true
		var step := 40.0
		var n := int(rad / step)
		for j in range(-n, n + 1):
			if from_hint:
				break
			for i in range(-n, n + 1):
				var p := c + Vector2(float(i), float(j)) * step
				if p.distance_to(c) > rad or not _valid(p.x, p.y, 30.0, 0.22):
					continue
				var h := TerrainHeight.height_at(p.x, p.y)
				if h > best_h and h < 230.0:
					best_h = h
					best = Vector3(p.x, h, p.y)
		if best_h > -1.0e8:
			_masts.append({"id": StringName("mast%d" % mi), "name": String(md["name"]), "pos": best})


static func _build_cranes() -> void:
	var c := Vector2(2000.0, -700.0)
	var found := 0
	var first_ang := -10.0
	for k in 24:
		if found >= 2:
			break
		var ang := TAU * float(k) / 24.0 + 0.3
		for rad in [120.0, 150.0, 185.0, 225.0]:
			var p: Vector2 = c + Vector2(cos(ang), sin(ang)) * float(rad)
			if not _valid(p.x, p.y, 22.0, 0.32):
				continue
			if found == 1 and absf(angle_difference(first_ang, ang)) < 1.7:
				continue
			_cranes.append({"id": StringName("crane%d" % found), "name": "QUARRY CRANE %d" % (found + 1), "pos": Vector3(p.x, TerrainHeight.height_at(p.x, p.y), p.y), "yaw": ang + 0.8 * float(found)})
			if found == 0:
				first_ang = ang
			found += 1
			break


## One arch per region: the flattest 40 x 20 m footprint on dry, gentle, clear ground (4 orientations tried), for the coastal one the nearest to the sea. The full search is 0.75 s on a
## desktop, so every region carries a HINT (the position of the last search): the same test at that one spot takes a millisecond; the whole region is searched only when the hint is no longer valid.
static func _arch_spot(p: Vector2, rd: Dictionary) -> Dictionary:
	if not _valid(p.x, p.y, 44.0, 0.14):
		return {}
	var h0 := TerrainHeight.height_at(p.x, p.y)
	if h0 > 140.0:
		return {}
	var best := {}
	var best_score := 1.0e9
	for k in 4:
		var yaw := PI * float(k) / 4.0
		var u := Vector2(cos(yaw), sin(yaw))
		var v := Vector2(-u.y, u.x)
		var lo := 1.0e9
		var hi := -1.0e9
		for a: float in [-17.0, -8.0, 0.0, 8.0, 17.0]:
			for b: float in [-9.0, 0.0, 9.0]:
				var q := p + u * a + v * b
				var hq := TerrainHeight.height_at(q.x, q.y)
				lo = minf(lo, hq)
				hi = maxf(hi, hq)
		if hi - lo > 3.2:
			continue
		var score := (hi - lo) * 3.0
		if bool(rd.get("coast", false)):
			score += maxf(0.0, TerrainHeight.coast_distance(p.x, p.y) - TerrainHeight.city_distance(p.x, p.y)) * 0.02       # the distance inland of the coastline
		if score < best_score:
			best_score = score
			best = {"p": p, "yaw": yaw, "y": lo + 0.3, "score": score}
	return best


static func _build_arches() -> void:
	for ai in ARCH_REGIONS.size():
		var rd: Dictionary = ARCH_REGIONS[ai]
		var best := {}
		var hint = rd.get("hint", Vector2.INF)
		if hint is Vector2 and (hint as Vector2).is_finite() and not LandscapeSites.ignore_hints:
			best = _arch_spot(hint, rd)
		if best.is_empty():
			var c: Vector2 = rd["c"]
			var rad := float(rd["r"])
			var step := 26.0
			var n := int(rad / step)
			var best_score := 1.0e9
			for j in range(-n, n + 1):
				for i in range(-n, n + 1):
					var p := c + Vector2(float(i), float(j)) * step
					if p.distance_to(c) > rad:
						continue
					var cand := _arch_spot(p, rd)
					if not cand.is_empty() and float(cand["score"]) < best_score:
						best_score = float(cand["score"])
						best = cand
		if best.is_empty():
			continue
		var bp: Vector2 = best["p"]
		_arches.append({"id": StringName("arch%d" % ai), "name": String(rd["name"]), "pos": Vector3(bp.x, float(best["y"]), bp.y), "yaw": float(best["yaw"]) , "variant": int(rd["variant"]), "layer": int(rd["layer"]), "hint": bp})


static var _all_cache: Array = []


## `all_anchors()` built once (the data does not change after ensure(); the towns' anchors are appended by SettlementData): the cheap list a per-frame query walks.
static func anchors_cached() -> Array:
	if _all_cache.is_empty():
		_all_cache = all_anchors()
	return _all_cache


static func all_anchors() -> Array:
	ensure()
	var out: Array = []
	for t: Dictionary in _turbines:
		var b: Vector3 = t["pos"]
		out.append({"id": t["id"], "kind": &"turbine", "name": t["name"], "pos": b + Vector3(0, TURBINE_H, 0), "base": b, "height": TURBINE_H, "radius": 2.4})
	for l: Dictionary in _lines:
		for p: Dictionary in l["pylons"]:
			if p.has("gap"):
				continue
			var b2: Vector3 = p["pos"]
			out.append({"id": l["id"], "kind": &"pylon", "name": l["name"], "pos": b2 + Vector3(0, PYLON_H, 0), "base": b2, "height": PYLON_H, "radius": 3.2})
	for m: Dictionary in _masts:
		var b3: Vector3 = m["pos"]
		out.append({"id": m["id"], "kind": &"mast", "name": m["name"], "pos": b3 + Vector3(0, MAST_H, 0), "base": b3, "height": MAST_H, "radius": 1.8})
	for cr: Dictionary in _cranes:
		var b4: Vector3 = cr["pos"]
		out.append({"id": cr["id"], "kind": &"crane", "name": cr["name"], "pos": b4 + Vector3(0, CRANE_H, 0), "base": b4, "height": CRANE_H, "radius": 2.8})
	for ar: Dictionary in _arches:
		var b5: Vector3 = ar["pos"]
		var hh: float = ARCH_H[int(ar["variant"])]
		out.append({"id": ar["id"], "kind": &"arch", "name": ar["name"], "pos": b5 + Vector3(0, hh, 0), "base": b5, "height": hh, "radius": 4.0})
	var hl: Dictionary = Harbour.layout()
	var hci := 0
	for hc: Dictionary in hl.get("cranes", []):                                          # the gantry cranes of the harbour (HarbourKit builds them, HarbourWorld has their colliders)
		hci += 1
		var hb: Vector3 = hc["pos"]
		out.append({"id": StringName("harbour_crane%d" % hci), "kind": &"crane", "name": "HARBOUR CRANE %d" % hci, "pos": hb + Vector3(0, HARBOUR_CRANE_H, 0), "base": hb, "height": HARBOUR_CRANE_H, "radius": 2.6})
	for f: Dictionary in LandscapeSites.falls():
		var lp: Vector2 = f["lip"]
		var bp2: Vector2 = f["base"]
		out.append({"id": f["id"], "kind": &"cliff", "name": String(f["name"]), "pos": Vector3(lp.x, float(f["lip_y"]), lp.y), "base": Vector3(bp2.x, float(f["base_y"]), bp2.y), "height": float(f["drop"]), "radius": 6.0})
	out.append_array(SettlementData.anchors())                                             # the water towers, silos, church towers, cranes, windmills and masts of the outskirts towns (wave 112, scripts/settlements)
	return out
