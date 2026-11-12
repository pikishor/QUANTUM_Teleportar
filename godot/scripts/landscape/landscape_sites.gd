class_name LandscapeSites
extends RefCounted
## The features of the landscape that change the ground (wave 112): the WATERFALLS (a cliff that is already in the terrain, a stream trench above its lip, a plunge pool at its foot and
## an outflow trench) and the grass AIRSTRIPS (a flat, drivable strip with a graded blend). Data and carving only; the meshes, particles and sounds are Landscape / FallWorld.
##
## Sites are FOUND, not hand-placed: `ensure()` searches fixed regions (around rivers, roads and the foothills) of the pre-carve terrain (`TerrainHeight.height_pre`) for the steepest
## cliff face with a plateau above and a bench below (waterfalls) and for the flattest corridor (airstrips). Pure functions of the terrain: deterministic, and they follow any change of
## the land. `carve(x, z, h)` is the outermost link of `TerrainHeight.height_at`; it costs one distance test per feature away from the sites. Call `ensure()` on the main thread
## (TerrainHeight.warm does) before worker threads sample.
##   LandscapeSites.falls()   [{id, name, lip, lip_y, dir, base, base_y, pool, pool_r, pool_y, width, drop, up (flow order, far upstream -> lip), up_y, out (pool -> downstream), out_y}]
##   LandscapeSites.strips()  [{id, name, c, u (unit vector along the strip), len, wid, y}]
##   pool_level(x, z)         y of the water in a plunge pool at that point, NO_WATER outside (TerrainHeight.water_level_for asks)
##   inside_strip(x, z, m)    true on an airstrip plus margin m (vegetation, rails and props keep off it)
##   hooks()                  mission hooks of the sites ({id, kind, name, pos, ...}) like OutskirtsSites.hooks()

const NO_WATER := -1.0e9
const POOL_DEPTH := 3.2
const FALL_REGIONS := [
	{"name": "HIGHLINE FALLS", "src": &"river", "idx": 0, "at": 96, "r": 190.0},
	{"name": "NORTH CREEK FALLS", "src": &"river", "idx": 2, "at": 14, "r": 190.0},
	{"name": "EASTWATER FALLS", "src": &"river", "idx": 1, "at": 58, "r": 200.0},
	{"name": "RIDGE VEIL", "src": &"point", "c": Vector2(1700.0, -1560.0), "r": 210.0},
	{"name": "MIRROR CASCADE", "src": &"point", "c": Vector2(-300.0, -2060.0), "r": 210.0},
]
const STRIP_REGIONS := [
	{"name": "DUNE STRIP", "c": Vector2(1560.0, 280.0), "r": 420.0},
	{"name": "HIGHLAND STRIP", "c": Vector2(1600.0, -1100.0), "r": 420.0},
	{"name": "SOUTH STRIP", "c": Vector2(1150.0, 1560.0), "r": 340.0},
]
const STRIP_LEN := 360.0
const STRIP_WID := 34.0
const STRIP_BLEND := 38.0
const STRIP_FLAT := 8.5                              ## the largest height range (m) under a strip that the grading will still take

static var built := false
static var debug_flat := {}                          ## strip region name -> flattest corridor found (tests and look-dev)
static var _falls: Array = []
static var _strips: Array = []
static var _fbound := PackedFloat32Array()            ## per fall: cx, cz, r^2 (everything the fall carves lies inside)
static var _sbound := PackedFloat32Array()            ## per strip: cx, cz, r^2


static func falls() -> Array:
	ensure()
	return _falls


static func strips() -> Array:
	ensure()
	return _strips


static func ensure() -> void:
	if built:
		return
	built = true
	_falls.clear()
	_strips.clear()
	_fbound = PackedFloat32Array()
	_sbound = PackedFloat32Array()
	for reg: Dictionary in FALL_REGIONS:
		var c := _region_centre(reg)
		var f := _find_fall(c, float(reg["r"]), String(reg["name"]))
		if not f.is_empty():
			var dup := false
			for g: Dictionary in _falls:
				if (g["lip"] as Vector2).distance_to(f["lip"]) < 220.0:
					dup = true                                      # two search regions found the same cliff
			if dup:
				continue
			f["id"] = StringName(String(reg["name"]).to_lower().replace(" ", "_"))
			_falls.append(f)
	for f: Dictionary in _falls:
		var pts: Array = [f["lip"], f["pool"]]
		var cx := 0.0
		var cz := 0.0
		var n := 0
		for arr: PackedVector2Array in [f["up"], f["out"]]:
			for q in arr:
				cx += q.x
				cz += q.y
				n += 1
		cx = (cx + (f["lip"] as Vector2).x + (f["pool"] as Vector2).x) / float(n + 2)
		cz = (cz + (f["lip"] as Vector2).y + (f["pool"] as Vector2).y) / float(n + 2)
		var r := 0.0
		for arr: PackedVector2Array in [f["up"], f["out"]]:
			for q in arr:
				r = maxf(r, Vector2(cx, cz).distance_to(q))
		for q: Vector2 in pts:
			r = maxf(r, Vector2(cx, cz).distance_to(q))
		r += float(f["pool_r"]) + 24.0
		_fbound.append_array(PackedFloat32Array([cx, cz, r * r]))
	for reg: Dictionary in STRIP_REGIONS:
		var s := _find_strip(reg["c"], float(reg["r"]), String(reg["name"]))
		if not s.is_empty():
			s["id"] = StringName(String(reg["name"]).to_lower().replace(" ", "_"))
			_strips.append(s)
	for s: Dictionary in _strips:
		var c2: Vector2 = s["c"]
		var rr := STRIP_LEN * 0.5 + STRIP_BLEND + 16.0
		_sbound.append_array(PackedFloat32Array([c2.x, c2.y, rr * rr]))


static func _region_centre(reg: Dictionary) -> Vector2:
	if StringName(reg["src"]) == &"river":
		var paths := WaterLayout.paths
		var pi := int(reg["idx"])
		if pi < paths.size():
			var pos: PackedVector2Array = paths[pi]["pos"]
			return pos[clampi(int(reg["at"]), 0, pos.size() - 1)]
	return reg.get("c", Vector2.ZERO)


static func _h(x: float, z: float) -> float:
	return TerrainHeight.height_pre(x, z)


# --- waterfalls -----------------------------------------------------------------------------------------------------------------------------

## Heights along `dir` from `p` at 2 m steps, t = -30 .. +90 m (61 samples).
static func _profile(p: Vector2, dir: Vector2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(61)
	for k in 61:
		var q := p + dir * (-30.0 + 2.0 * float(k))
		out[k] = _h(q.x, q.y)
	return out


## The steep run through sample 15 (t = 0) of a profile: [top index, bottom index] or [] when there is no cliff.
static func _run(prof: PackedFloat32Array) -> Array:
	var top := 15
	while top > 0 and (prof[top - 1] - prof[top]) / 2.0 >= 0.42:
		top -= 1
	var bot := 15
	while bot < 60 and (prof[bot] - prof[bot + 1]) / 2.0 >= 0.42:
		bot += 1
	return [top, bot]


static func _find_fall(c: Vector2, rad: float, label: String) -> Dictionary:
	var best := {}
	var best_score := 0.0
	var step := 14.0
	var n := int(rad / step)
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var p := c + Vector2(float(i), float(j)) * step
			if p.distance_to(c) > rad or absf(p.x) > TerrainHeight.WORLD_HALF - 120.0 or absf(p.y) > TerrainHeight.WORLD_HALF - 120.0:
				continue
			var h0 := _h(p.x, p.y)
			if h0 < 28.0:
				continue
			var g := Vector2((_h(p.x + 6.0, p.y) - _h(p.x - 6.0, p.y)) / 12.0, (_h(p.x, p.y + 6.0) - _h(p.x, p.y - 6.0)) / 12.0)
			if g.length() < 0.9:
				continue
			var dir := (-g).normalized()
			var prof := _profile(p, dir)
			var run := _run(prof)
			var top: int = run[0]
			var bot: int = run[1]
			var drop := prof[top] - prof[bot]
			if drop < 15.0 or drop > 120.0 or (bot - top) * 2.0 > 70.0:
				continue
			# the face must be wide: the same drop 6 and 12 m to both sides
			var side := Vector2(-dir.y, dir.x)
			var wide := true
			for off: float in [-12.0, -6.0, 6.0, 12.0]:
				var q := p + side * off
				var d2 := _h(q.x + dir.x * (-30.0 + 2.0 * float(top)), q.y + dir.y * (-30.0 + 2.0 * float(top))) - _h(q.x + dir.x * (-30.0 + 2.0 * float(bot)), q.y + dir.y * (-30.0 + 2.0 * float(bot)))
				if d2 < drop * 0.55:
					wide = false
					break
			if not wide:
				continue
			var lip := p + dir * (-30.0 + 2.0 * float(top))
			var base := p + dir * (-30.0 + 2.0 * float(bot))
			# a plateau above (a stream can come from there) and a bench below (a pool can sit there)
			var above := lip - dir * 26.0
			if _h(above.x, above.y) < prof[top] - 2.5 or _h(above.x, above.y) > prof[top] + 28.0:
				continue
			var pool_c := base + dir * 9.0
			var rd := TerrainRoads.nearest(pool_c.x, pool_c.y)
			var rdl := TerrainRoads.nearest(lip.x, lip.y)
			var road_d := minf(float(rd[0]), float(rdl[0]))
			if road_d < 40.0 or OutskirtsSites.inside(pool_c.x, pool_c.y, 30.0) >= 0 or OutskirtsSites.inside(lip.x, lip.y, 20.0) >= 0:
				continue
			if _h(pool_c.x, pool_c.y) < TerrainHeight.SEA_LEVEL + 6.0 or TerrainHeight.water_level_for(pool_c.x, pool_c.y, _h(pool_c.x, pool_c.y)) != TerrainHeight.NO_WATER:
				continue
			var peak := 0.0
			for k in range(top, bot):
				peak = maxf(peak, (prof[k] - prof[k + 1]) / 2.0)
			var score := drop * minf(peak, 2.2) * (1.0 + 0.6 * maxf(0.0, 1.0 - road_d / 520.0))
			if score > best_score:
				best_score = score
				best = {"p": p, "dir": dir, "lip": lip, "base": base, "lip_y": prof[top], "base_y": prof[bot], "drop": drop}
	if best.is_empty():
		return {}
	return _make_fall(best, label)


static func _make_fall(b: Dictionary, label: String) -> Dictionary:
	var dir: Vector2 = b["dir"]
	var lip: Vector2 = b["lip"]
	var base: Vector2 = b["base"]
	var drop: float = b["drop"]
	var f := {"name": label, "dir": dir, "lip": lip, "lip_y": float(b["lip_y"]), "base": base, "base_y": float(b["base_y"]), "drop": drop}
	f["width"] = clampf(7.0 + 0.11 * drop, 8.0, 15.0)
	var pr := clampf(9.0 + 0.07 * drop, 10.0, 15.0)
	f["pool_r"] = pr
	var pc := base + dir * (pr * 0.62)
	f["pool"] = pc
	# the water stands at the mean rim height minus half a metre (the downhill rim is built up to a dam by the carve, the uphill one cut)
	var mean_rim := 0.0
	for k in 16:
		var a := TAU * float(k) / 16.0
		var q := pc + Vector2(cos(a), sin(a)) * pr
		mean_rim += _h(q.x, q.y)
	mean_rim /= 16.0
	f["pool_y"] = minf(mean_rim - 0.5, float(b["base_y"]) - 0.4)
	# the stream above: traced uphill from the lip, then stored in flow order
	var up: Array[Vector2] = [lip]
	var cur := lip
	var d := -dir
	for k in 12:
		var best_a := 0.0
		var best_h := -1.0e9
		for a: float in [-0.7, -0.35, 0.0, 0.35, 0.7]:
			var dd := d.rotated(a)
			var q := cur + dd * 6.0
			var hq := _h(q.x, q.y)
			if hq > best_h:
				best_h = hq
				best_a = a
		d = (d * 0.55 + d.rotated(best_a) * 0.45).normalized()
		cur += d * 6.0
		up.append(cur)
	up.reverse()
	var up_pts := PackedVector2Array()
	var up_y := PackedFloat32Array()
	var bed := 1.0e9
	for q in up:
		var g := _h(q.x, q.y)
		bed = minf(bed - 0.04, g - 0.65)
		up_pts.append(q)
		up_y.append(bed)
	up_y[up_y.size() - 1] = minf(up_y[up_y.size() - 1], float(b["lip_y"]) - 0.55)
	f["up"] = up_pts
	f["up_y"] = up_y
	# the outflow: steepest descent from the pool's downhill rim, until the sea, a river or 150 m
	var out_pts := PackedVector2Array()
	var out_y := PackedFloat32Array()
	var oc := pc
	var od := dir
	var obed: float = float(f["pool_y"]) - 0.25
	out_pts.append(oc)
	out_y.append(obed)
	for k in 26:
		var best_a2 := 0.0
		var best_h2 := 1.0e9
		for a: float in [-0.8, -0.4, 0.0, 0.4, 0.8]:
			var dd2 := od.rotated(a)
			var q2 := oc + dd2 * 6.0
			var hq2 := _h(q2.x, q2.y)
			if hq2 < best_h2:
				best_h2 = hq2
				best_a2 = a
		od = (od * 0.6 + od.rotated(best_a2) * 0.4).normalized()
		oc += od * 6.0
		var g2 := _h(oc.x, oc.y)
		if g2 < TerrainHeight.SEA_LEVEL + 4.0 or WaterLayout.surface_at(oc.x, oc.y) != NO_WATER:
			break
		obed = minf(obed - 0.03, g2 - 0.45)
		out_pts.append(oc)
		out_y.append(obed)
	f["out"] = out_pts
	f["out_y"] = out_y
	return f


# --- airstrips ------------------------------------------------------------------------------------------------------------------------------

static func _find_strip(c: Vector2, rad: float, label: String) -> Dictionary:
	var best := {}
	var best_score := 1.0e9
	var step := 50.0
	var n := int(rad / step)
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var p := c + Vector2(float(i), float(j)) * step
			if p.distance_to(c) > rad or TerrainHeight.city_distance(p.x, p.y) < 300.0 or absf(p.x) > TerrainHeight.WORLD_HALF - 400.0 or absf(p.y) > TerrainHeight.WORLD_HALF - 400.0:
				continue
			var h0 := _h(p.x, p.y)
			if h0 < 6.0 or h0 > 110.0:
				continue
			for hd in 8:
				var ang := PI * float(hd) / 8.0
				var u := Vector2(cos(ang), sin(ang))
				var v := Vector2(-u.y, u.x)
				var lo := 1.0e9
				var hi := -1.0e9
				var ok := true
				var sum := 0.0
				var cnt := 0
				for ia in 11:
					var a := (float(ia) / 10.0 - 0.5) * (STRIP_LEN + 30.0)
					for ib: float in [-1.0, 0.0, 1.0]:
						var q := p + u * a + v * (ib * (STRIP_WID * 0.5 + 8.0))
						var hq := _h(q.x, q.y)
						if TerrainHeight.water_level_for(q.x, q.y, hq) != TerrainHeight.NO_WATER or OutskirtsSites.inside(q.x, q.y, 24.0) >= 0 or Airport.inside(q.x, q.y, 80.0):
							ok = false
							break
						lo = minf(lo, hq)
						hi = maxf(hi, hq)
						sum += hq
						cnt += 1
					if not ok:
						break
				if not ok:
					continue
				debug_flat[label] = minf(float(debug_flat.get(label, 1.0e9)), hi - lo)
				if hi - lo > STRIP_FLAT:
					continue
				# keep clear of roads, the railway and the sites: probe the rectangle's border
				var near_road := false
				for ia in 7:
					var a2 := (float(ia) / 6.0 - 0.5) * (STRIP_LEN + 60.0)
					for ib: float in [-1.0, 1.0]:
						var q2 := p + u * a2 + v * (ib * (STRIP_WID * 0.5 + STRIP_BLEND))
						if float(TerrainRoads.nearest(q2.x, q2.y)[0]) < 30.0:
							near_road = true
				if near_road:
					continue
				var score := (hi - lo) + 0.0006 * p.distance_to(c)
				if score < best_score:
					best_score = score
					best = {"name": label, "c": p, "u": u, "len": STRIP_LEN, "wid": STRIP_WID, "y": sum / float(cnt)}
	return best


static func inside_strip(x: float, z: float, margin := 0.0) -> bool:
	for s: Dictionary in _strips:
		var c: Vector2 = s["c"]
		var u: Vector2 = s["u"]
		var dx := x - c.x
		var dz := z - c.y
		if dx * dx + dz * dz > 330.0 * 330.0:
			continue
		var a := absf(dx * u.x + dz * u.y)
		var b := absf(-dx * u.y + dz * u.x)
		if a <= float(s["len"]) * 0.5 + margin and b <= float(s["wid"]) * 0.5 + 6.0 + margin:
			return true
	return false


# --- carving (the outermost link of TerrainHeight.height_at) --------------------------------------------------------------------------------

static func carve(x: float, z: float, h: float) -> float:
	if not built:
		return h
	var nf := _fbound.size() / 3
	for i in nf:
		var dx := x - _fbound[i * 3]
		var dz := z - _fbound[i * 3 + 1]
		if dx * dx + dz * dz < _fbound[i * 3 + 2]:
			h = _carve_fall(_falls[i], x, z, h)
	var ns := _sbound.size() / 3
	for i in ns:
		var dx2 := x - _sbound[i * 3]
		var dz2 := z - _sbound[i * 3 + 1]
		if dx2 * dx2 + dz2 * dz2 < _sbound[i * 3 + 2]:
			h = _carve_strip(_strips[i], x, z, h)
	return h


static func _carve_fall(f: Dictionary, x: float, z: float, h: float) -> float:
	var pc: Vector2 = f["pool"]
	var pr: float = f["pool_r"]
	var py: float = f["pool_y"]
	var d := Vector2(x, z).distance_to(pc)
	if d < pr + 11.0:
		if d >= pr * 0.96:                                   # the rim: built up to a little above the water so the pool holds it, fading into the land
			var w := 1.0 - smoothstep(pr * 0.98, pr + 10.0, d)
			h = lerpf(h, maxf(h, py + 0.45), w)
		if d < pr:
			var k := d / pr
			h = minf(h, py - POOL_DEPTH * (1.0 - k * k))
	var p2 := Vector2(x, z)
	h = _trench(f["up"], f["up_y"], p2, 5.2, 1.9, h)
	h = _trench(f["out"], f["out_y"], p2, 5.0, 1.8, h)
	return h


## Cuts a trench along a polyline: the bed height per point, fully carved within `core` metres of the line, fading out at `reach`.
static func _trench(pts: PackedVector2Array, bed: PackedFloat32Array, p: Vector2, reach: float, core: float, h: float) -> float:
	var best_d := 1.0e9
	var best_bed := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var ab := pts[i + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
		var dd := p.distance_to(a + ab * t)
		if dd < best_d:
			best_d = dd
			best_bed = lerpf(bed[i], bed[i + 1], t)
	if best_d >= reach:
		return h
	var w := 1.0 - smoothstep(core, reach, best_d)
	return minf(h, lerpf(h, best_bed, w))


## True within `margin` metres of a plunge pool or of one of the stream trenches of a waterfall (plants, rocks and props keep clear).
static func near_feature(x: float, z: float, margin := 2.0) -> bool:
	var nf := _fbound.size() / 3
	for i in nf:
		var dx := x - _fbound[i * 3]
		var dz := z - _fbound[i * 3 + 1]
		if dx * dx + dz * dz >= _fbound[i * 3 + 2]:
			continue
		var f: Dictionary = _falls[i]
		var p := Vector2(x, z)
		if p.distance_to(f["pool"]) < float(f["pool_r"]) + margin + 1.5:
			return true
		for key in ["up", "out"]:
			var pts: PackedVector2Array = f[key]
			for k in pts.size() - 1:
				var a := pts[k]
				var ab := pts[k + 1] - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
				if p.distance_to(a + ab * t) < margin + 2.2:
					return true
	return false


static func pool_level(x: float, z: float) -> float:
	var nf := _fbound.size() / 3
	for i in nf:
		var f: Dictionary = _falls[i]
		var pc: Vector2 = f["pool"]
		var r: float = f["pool_r"]
		var dx := x - pc.x
		var dz := z - pc.y
		if dx * dx + dz * dz < r * r:
			return float(f["pool_y"])
	return NO_WATER


static func _carve_strip(s: Dictionary, x: float, z: float, h: float) -> float:
	var c: Vector2 = s["c"]
	var u: Vector2 = s["u"]
	var dx := x - c.x
	var dz := z - c.y
	var a := absf(dx * u.x + dz * u.y)
	var b := absf(-dx * u.y + dz * u.x)
	var ex := maxf(a - float(s["len"]) * 0.5, 0.0)
	var ey := maxf(b - (float(s["wid"]) * 0.5 + 6.0), 0.0)
	var dist := sqrt(ex * ex + ey * ey)
	if dist >= STRIP_BLEND:
		return h
	return lerpf(h, float(s["y"]), 1.0 - smoothstep(0.0, STRIP_BLEND, dist))


## Mission hooks (the same idea as OutskirtsSites.hooks()).
static func hooks() -> Array:
	ensure()
	var out: Array = []
	for f: Dictionary in _falls:
		var pc: Vector2 = f["pool"]
		out.append({"id": f["id"], "kind": &"waterfall", "name": f["name"], "pos": Vector3(pc.x, float(f["pool_y"]), pc.y), "r": float(f["pool_r"]) + 8.0, "reward": 60, "tag": &"fall"})
	for s: Dictionary in _strips:
		var c: Vector2 = s["c"]
		out.append({"id": s["id"], "kind": &"airstrip", "name": s["name"], "pos": Vector3(c.x, float(s["y"]), c.y), "r": float(s["len"]) * 0.5, "reward": 80, "tag": &"strip"})
	return out
