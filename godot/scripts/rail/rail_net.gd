class_name RailNet
extends RefCounted
## THE RAILWAY NETWORK (wave 106, railways and ships): data, vertical profile, terrain carving and queries. No nodes: RailKit builds the meshes, RailWorld the nodes, Train the rolling stock.
##
## Three double-track lines (a route is a Catmull-Rom spline resampled every STEP metres, routed by the roads' own A*):
##   MAGLEV           an elevated line on a box-girder viaduct over the street z = -640 through the whole city, from the WEST TERMINAL to the DESERT TERMINAL (five stations)
##   MOUNTAIN LINE    NORTH STATION on the plain north of the city, over NORTH CREEK, through the foothills (tunnels under the spurs) to MOUNT STATION (three stations)
##   COAST LINE       GREENWAY (west edge of the city) south along the coast and over the FOREST ROAD to HARBOUR STATION (three stations)
## The VERTICAL PROFILE of a line is the terrain followed within a grade limit (cut and fill balanced: the average of the lower and the upper grade-limited envelope), lifted 5 m over water,
## pinned flat at stations and at level crossings (the rail takes the road's height), pinned at ELEV over the city plateau for the maglev. Every sample then gets a MODE: GROUND (the bench is
## carved into the terrain: embankment or cutting), VIADUCT (over water, valleys, streets and road overpasses: the terrain stays as it is) or TUNNEL (the terrain stands 7.5 m or more over the
## track: the terrain stays, the tube is built inside it, portals stand where the cutting ends).
## TUNNEL / VIADUCT samples are not carved; `carve(x, z, h)` is called by TerrainHeight.height_at AFTER the roads and before the harbour.
##
## A route is a Dictionary: {id, name, style (&"rail" | &"maglev"), speed, pos (PackedVector2Array), y (PackedFloat32Array: the track bed top), s (metres from the start), k (lane spread 0..1: the two
## tracks run together at a terminal station), mode (PackedByteArray), len, stations, crossings, signals, tunnels, viaducts, trains}.
## Train lanes: the track of travel direction `dir` (+1 = growing s) is at lateral `dir * HALF_SEP * k` along `right_of(tangent)`; the rails are 1.435 m apart.

const STEP := 8.0
const SEP := 4.6                               ## metres between the two track centre lines
const HALF_SEP := 2.3
const GAUGE := 1.435
const BED_HW := 4.9                            ## ballast half width at its foot
const BENCH := 5.8                             ## flat half width of the carved bench
const BENCH_STATION := 10.0
const ELEV := 11.0                             ## track bed height of the elevated maglev over the city plateau
const CLEAR := 5.2                             ## metres of clearance between the water and the bed of a viaduct
const OVERPASS := 6.2                          ## bed height over a road it crosses on a bridge
const TUNNEL_D := 7.5                          ## terrain this far over the bed: a tunnel (the arch is 6.9 m high)
const VIADUCT_D := 5.5                         ## bed this far over the terrain: a viaduct
const CELL := 64.0
const SHOULDER_MAX := 46.0
const MODE_GROUND := 0
const MODE_VIADUCT := 1
const MODE_TUNNEL := 2
const RAIL_TOP := 0.17                         ## rail head over the bed
const FLOOR_Y := 1.15                          ## car floor over the bed
const PLATFORM_Y := 1.1

const DEFS := [
	{"id": &"maglev", "name": "MAGLEV", "style": &"maglev", "grade": 0.05, "speed": 56.0, "elev": true, "straight": [0],
		"via": [Vector2(-1290.0, -640.0), Vector2(1600.0, -640.0)],
		"stations": [{"name": "WEST TERMINAL", "at": Vector2(-1200.0, -640.0), "terminal": true}, {"name": "OLD TOWN", "at": Vector2(-680.0, -640.0)},
			{"name": "CENTRAL", "at": Vector2(40.0, -640.0)}, {"name": "EAST SIDE", "at": Vector2(680.0, -640.0)}, {"name": "DESERT TERMINAL", "at": Vector2(1500.0, -640.0), "terminal": true}],
		"trains": [{"kind": &"maglev", "phase": 0.0}, {"kind": &"maglev", "phase": 0.5}]},
	{"id": &"mountain", "name": "MOUNTAIN LINE", "style": &"rail", "grade": 0.055, "speed": 32.0, "elev": false, "straight": [0],
		"via": [Vector2(-330.0, -1290.0), Vector2(-150.0, -1293.0), Vector2(60.0, -1315.0), Vector2(420.0, -1410.0), Vector2(600.0, -1490.0), Vector2(700.0, -1535.0), Vector2(780.0, -1650.0), Vector2(930.0, -1760.0),
			Vector2(800.0, -1860.0), Vector2(700.0, -1970.0), Vector2(620.0, -2080.0)],
		"stations": [{"name": "NORTH STATION", "s": 120.0, "terminal": true}, {"name": "FOOTHILLS", "at": Vector2(500.0, -1450.0)}, {"name": "MOUNT STATION", "at": Vector2(930.0, -1752.0)},
			{"name": "SUMMIT STATION", "s": -120.0, "terminal": true}],
		"trains": [{"kind": &"express", "phase": 0.0}, {"kind": &"ore", "phase": 0.5}]},
	{"id": &"coast", "name": "COAST LINE", "style": &"rail", "grade": 0.05, "speed": 27.0, "elev": false, "straight": [0],
		"via": [Vector2(-1195.0, -500.0), Vector2(-1195.0, -330.0), Vector2(-1190.0, 300.0), Vector2(-1180.0, 900.0), Vector2(-1000.0, 1160.0), Vector2(-500.0, 1195.0), Vector2(-250.0, 1195.0), Vector2(-100.0, 1195.0)],
		"stations": [{"name": "GREENWAY", "s": 120.0, "terminal": true}, {"name": "SOUTH HALT", "at": Vector2(-1180.0, 760.0)}, {"name": "HARBOUR STATION", "s": -120.0, "terminal": true}],
		"trains": [{"kind": &"regional", "phase": 0.0}, {"kind": &"container", "phase": 0.5}]},
]

static var built := false
static var _building := false
static var _routes: Array[Dictionary] = []
static var _sp := PackedVector2Array()         ## every sample of every route
static var _sy := PackedFloat32Array()
static var _sm := PackedByteArray()
static var _sb := PackedFloat32Array()         ## bench half width of the sample
static var _sn := PackedInt32Array()           ## next sample of the same route, -1 at the end
static var _sr := PackedInt32Array()
static var _grid := {}
static var diag: Array[String] = []


static func _key(cx: int, cz: int) -> int:
	return (cx + 200) * 1000 + (cz + 200)


static func routes() -> Array[Dictionary]:
	ensure()
	return _routes


static func route(id: StringName) -> Dictionary:
	ensure()
	for r in _routes:
		if r["id"] == id:
			return r
	return {}


static func ensure() -> void:
	if built or _building:
		return
	_building = true
	TerrainHeight._ensure()
	TerrainBase.warm()
	WaterLayout.ensure()
	TerrainRoads.ensure()
	_routes.clear()
	_sp = PackedVector2Array()
	_sy = PackedFloat32Array()
	_sm = PackedByteArray()
	_sb = PackedFloat32Array()
	_sn = PackedInt32Array()
	_sr = PackedInt32Array()
	_grid.clear()
	diag.clear()
	for ri in DEFS.size():
		_build(ri)
	for i in _sp.size():
		var r := BENCH_STATION + SHOULDER_MAX + STEP
		for cx in range(int(floor((_sp[i].x - r) / CELL)), int(floor((_sp[i].x + r) / CELL)) + 1):
			for cz in range(int(floor((_sp[i].y - r) / CELL)), int(floor((_sp[i].y + r) / CELL)) + 1):
				var key := _key(cx, cz)
				var arr: PackedInt32Array = _grid.get(key, PackedInt32Array())
				arr.append(i)
				_grid[key] = arr
	built = true
	_building = false


# --- building a route ---------------------------------------------------------------------------------------------------------------

## Points every `step` metres or less along the polyline (the Catmull-Rom spline runs at an even speed only between evenly spaced nodes).
static func _densify(nodes: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in nodes.size() - 1:
		var a := nodes[i]
		var b := nodes[i + 1]
		var m := maxi(1, int(ceil(a.distance_to(b) / step)))
		for k in m:
			out.append(a.lerp(b, float(k) / float(m)))
	out.append(nodes[nodes.size() - 1])
	return out


static func _smooth_pts(nodes: PackedVector2Array, passes: int) -> PackedVector2Array:
	for _i in passes:
		var sm := nodes.duplicate()
		for i in range(1, nodes.size() - 1):
			sm[i] = (nodes[i - 1] + nodes[i] * 2.0 + nodes[i + 1]) * 0.25
		nodes = sm
	return nodes


static func _envelope(g: PackedFloat32Array, gs: PackedFloat32Array, fill_bias: float) -> PackedFloat32Array:
	var n := g.size()
	var lo := g.duplicate()
	var hi := g.duplicate()
	for i in range(1, n):
		lo[i] = minf(lo[i], lo[i - 1] + gs[i])
		hi[i] = maxf(hi[i], hi[i - 1] - gs[i])
	for i in range(n - 2, -1, -1):
		lo[i] = minf(lo[i], lo[i + 1] + gs[i + 1])
		hi[i] = maxf(hi[i], hi[i + 1] - gs[i + 1])
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = lerpf(lo[i], hi[i], fill_bias)
	return out


## Grade limit with fixed samples (pins): the unpinned ones are clamped against their neighbours, forwards and backwards, a few times.
static func _relimit(y: PackedFloat32Array, pin: PackedFloat32Array, gs: PackedFloat32Array) -> void:
	var n := y.size()
	for i in n:
		if not is_nan(pin[i]):
			y[i] = pin[i]
	for _it in 5:
		for i in range(1, n):
			if is_nan(pin[i]):
				y[i] = clampf(y[i], y[i - 1] - gs[i], y[i - 1] + gs[i])
		for i in range(n - 2, -1, -1):
			if is_nan(pin[i]):
				y[i] = clampf(y[i], y[i + 1] - gs[i + 1], y[i + 1] + gs[i + 1])


static func _smoothstep01(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)


static func _build(ri: int) -> void:
	var def: Dictionary = DEFS[ri]
	var via: Array = def["via"]
	var grade: float = def["grade"]
	var straight: Array = def.get("straight", [])
	var nodes := PackedVector2Array()
	for k in via.size() - 1:
		var seg: PackedVector2Array
		if k in straight or (k == via.size() - 2 and def.get("straight_end", true)):
			seg = PackedVector2Array([via[k], via[k + 1]])
		else:
			seg = TerrainRoads._route(via[k], via[k + 1], 0.09)
		if not nodes.is_empty() and not seg.is_empty():
			seg = seg.slice(1)
		nodes.append_array(seg)
	nodes = _densify(nodes, 24.0)
	nodes = _smooth_pts(nodes, 7 if not bool(def.get("elev", false)) else 1)
	var pts := PackedVector2Array()
	for i in nodes.size() - 1:
		var p1: Vector2 = nodes[i]
		var p2: Vector2 = nodes[i + 1]
		var p0: Vector2 = nodes[maxi(i - 1, 0)]
		var p3: Vector2 = nodes[mini(i + 2, nodes.size() - 1)]
		var n := maxi(1, int(ceil(p1.distance_to(p2) / STEP)))
		for k in n:
			pts.append(TerrainRoads._catmull(p0, p1, p2, p3, float(k) / float(n)))
	pts.append(nodes[nodes.size() - 1])
	var n := pts.size()
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(1, n):
		s[i] = s[i - 1] + maxf(pts[i].distance_to(pts[i - 1]), 0.5)
	var total := s[n - 1]
	var gs := PackedFloat32Array()
	gs.resize(n)
	for i in n:
		gs[i] = grade * (s[i] - s[i - 1] if i > 0 else STEP)

	# terrain, water
	var g := PackedFloat32Array()
	var need := PackedFloat32Array()
	var wet := PackedByteArray()
	g.resize(n)
	need.resize(n)
	wet.resize(n)
	for i in n:
		g[i] = TerrainHeight.height_at(pts[i].x, pts[i].y)
		var tg := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var nr := Vector2(-tg.y, tg.x)
		var w := TerrainHeight.NO_WATER
		for off in [-16.0, -8.0, 0.0, 8.0, 16.0]:
			var q: Vector2 = pts[i] + nr * float(off)
			var hh := g[i] if off == 0.0 else TerrainHeight.height_at(q.x, q.y)
			w = maxf(w, TerrainHeight.water_level_for(q.x, q.y, hh))
		if w != TerrainHeight.NO_WATER:
			need[i] = w + CLEAR
			wet[i] = 1
		else:
			need[i] = -1.0e9
	var ge := g.duplicate()
	for i in n:
		ge[i] = maxf(g[i], need[i])
	var y := _envelope(ge, gs, float(def.get("fill", 0.12)))
	for _p in 2:                                          # smooth the vertical curve without breaking the grade limit (an average of Lipschitz functions is Lipschitz)
		var sm := y.duplicate()
		for i in n:
			var acc := 0.0
			var cnt := 0
			for j in range(maxi(0, i - 3), mini(n, i + 4)):
				acc += y[j]
				cnt += 1
			sm[i] = acc / float(cnt)
		y = sm
	for i in n:
		y[i] = maxf(y[i], need[i])
	for _pass in 2:
		for i in range(1, n):
			y[i] = maxf(y[i], y[i - 1] - gs[i])
		for i in range(n - 2, -1, -1):
			y[i] = maxf(y[i], y[i + 1] - gs[i + 1])

	# the lane spread: the two tracks run together at a terminal station
	var stations := _stations(def, pts, s, total)
	var k := PackedFloat32Array()
	k.resize(n)
	for i in n:
		var kk := 1.0
		for st: Dictionary in stations:
			if bool(st["terminal"]):
				var d := absf(s[i] - float(st["s"])) - float(st["len"]) * 0.5 - 8.0
				kk = minf(kk, smoothstep(0.0, 90.0, d))
		k[i] = kk

	# pins: the elevated city section, stations, level crossings
	var pin := PackedFloat32Array()
	pin.resize(n)
	pin.fill(NAN)
	var elev: bool = bool(def.get("elev", false))
	if elev:
		var on_plateau := PackedByteArray()
		on_plateau.resize(n)
		for i in n:
			if TerrainHeight.city_distance(pts[i].x, pts[i].y) <= 0.0:
				on_plateau[i] = 1
				pin[i] = ELEV
		var last_in := -1
		for i in n:
			if on_plateau[i] == 1:
				last_in = i
		var first_in := n
		for i in range(n - 1, -1, -1):
			if on_plateau[i] == 1:
				first_in = i
		for i in n:                                        # the deck comes down from the plateau at 90 % of the grade limit (so the station beyond it is level with it)
			var dout := 0.0
			if i < first_in:
				dout = s[first_in] - s[i]
			elif i > last_in:
				dout = s[i] - s[last_in]
			if dout > 0.0:
				y[i] = maxf(y[i], ELEV - 0.9 * grade * dout)
	for st: Dictionary in stations:
		var ic: int = int(st["ic"])
		var yc := y[ic] if is_nan(pin[ic]) else pin[ic]
		if elev and is_nan(pin[ic]):                       # an elevated terminal beyond the plateau: the platform sits on the ramp, a little under the plateau deck
			var dpl := 1.0e9
			for i in n:
				if not is_nan(pin[i]) and pin[i] >= ELEV - 0.01:
					dpl = minf(dpl, absf(s[i] - float(st["s"])))
			if dpl < 500.0:
				yc = maxf(yc, ELEV - 0.7 * grade * maxf(dpl - float(st["len"]) * 0.5 - 16.0, 0.0))
		st["y"] = yc
		for i in n:
			if absf(s[i] - float(st["s"])) <= float(st["len"]) * 0.5 + 16.0:
				pin[i] = yc
	for q in range(1, stations.size()):                 # neighbouring station zones must be reachable within the grade limit
		var a: Dictionary = stations[q - 1]
		var b: Dictionary = stations[q]
		var gap := (float(b["s"]) - float(b["len"]) * 0.5 - 16.0) - (float(a["s"]) + float(a["len"]) * 0.5 + 16.0)
		var allow := grade * maxf(gap, 1.0) * 0.8
		var dy := float(b["y"]) - float(a["y"])
		if absf(dy) > allow:
			b["y"] = float(a["y"]) + signf(dy) * allow
			for i in n:
				if absf(s[i] - float(b["s"])) <= float(b["len"]) * 0.5 + 16.0:
					pin[i] = float(b["y"])
	var crossings := _crossings(ri, def, pts, s, y, pin, stations)
	_relimit(y, pin, gs)
	var over_mask := PackedByteArray()
	over_mask.resize(n)
	for c: Dictionary in crossings:
		if not bool(c["level"]):
			for i in range(maxi(int(c["i"]) - 3, 0), mini(int(c["i"]) + 4, n)):
				over_mask[i] = 1
				y[i] = maxf(y[i], float(c["road_y"]) + OVERPASS)
	if not crossings.is_empty():
		for _pass in 2:
			for i in range(1, n):
				if is_nan(pin[i]):
					y[i] = maxf(y[i], y[i - 1] - gs[i])
			for i in range(n - 2, -1, -1):
				if is_nan(pin[i]):
					y[i] = maxf(y[i], y[i + 1] - gs[i + 1])

	# modes
	var mode := PackedByteArray()
	mode.resize(n)
	var deep := PackedFloat32Array()
	deep.resize(n)
	for i in n:
		var d := g[i] - y[i]
		deep[i] = d
		if wet[i] == 1 or y[i] - g[i] > VIADUCT_D or over_mask[i] == 1:
			mode[i] = MODE_VIADUCT
		elif d >= TUNNEL_D:
			mode[i] = MODE_TUNNEL
	_filter_runs(mode, MODE_TUNNEL, 70.0, wet, deep, true)
	_filter_runs(mode, MODE_VIADUCT, 40.0, wet, deep, false)
	# the elevated city section is always a viaduct
	for i in n:
		if elev and not is_nan(pin[i]) and pin[i] >= ELEV - 0.1:
			mode[i] = MODE_VIADUCT
		elif elev and y[i] - g[i] > 2.0 and i > 0 and mode[i - 1] == MODE_VIADUCT and TerrainHeight.city_distance(pts[i].x, pts[i].y) < 140.0:
			mode[i] = MODE_VIADUCT                           # the ramp down from the plateau stays on piers until it is near the ground
	# a station is in the open, unless the hill over it is deep: then it is an underground station (wide cavern, platforms inside the tube)
	for st: Dictionary in stations:
		var ic2: int = int(st["ic"])
		st["underground"] = deep[ic2] >= TUNNEL_D + 3.0 and mode[ic2] == MODE_TUNNEL
		if not bool(st["underground"]):
			for i in n:
				if absf(s[i] - float(st["s"])) <= float(st["len"]) * 0.5 + 24.0 and (mode[i] == MODE_TUNNEL or (mode[i] == MODE_VIADUCT and wet[i] == 0 and not (elev and TerrainHeight.city_distance(pts[i].x, pts[i].y) <= 0.0))):
					mode[i] = MODE_GROUND                      # a station stands on the ground (a bench cut into the hill or an embankment), not on a viaduct, except over the city streets

	var base := _sp.size()
	var r := {"id": def["id"], "name": def["name"], "style": def["style"], "speed": float(def["speed"]), "grade": grade, "elev": elev, "pos": pts, "y": y, "s": s, "k": k, "mode": mode, "len": total,
		"ground": g, "base": base, "stations": stations, "crossings": crossings, "signals": [], "tunnels": [], "viaducts": [], "trains": def["trains"], "ri": ri}
	_runs(r)
	_signals(r)
	for i in n:
		_sp.append(pts[i])
		_sy.append(y[i])
		_sm.append(mode[i])
		var bw := BENCH
		for st: Dictionary in stations:
			if absf(s[i] - float(st["s"])) <= float(st["len"]) * 0.5 + 24.0:
				bw = BENCH_STATION
		_sb.append(bw)
		_sn.append(base + i + 1 if i < n - 1 else -1)
		_sr.append(ri)
	_routes.append(r)


## Short runs of a mode revert to ground (a tunnel under 70 m is a deep cutting, a viaduct under 40 m a high embankment) unless the viaduct crosses water; runs separated by a short gap merge.
static func _filter_runs(mode: PackedByteArray, which: int, min_len: float, wet: PackedByteArray, deep: PackedFloat32Array, is_tunnel: bool) -> void:
	var n := mode.size()
	var gap := 3
	var i := 0
	var runs: Array[Vector2i] = []
	while i < n:
		if mode[i] != which:
			i += 1
			continue
		var j := i
		while j + 1 < n and mode[j + 1] == which:
			j += 1
		runs.append(Vector2i(i, j))
		i = j + 1
	var merged: Array[Vector2i] = []
	for rr in runs:
		if not merged.is_empty() and rr.x - merged[merged.size() - 1].y <= gap + 1:
			merged[merged.size() - 1].y = rr.y
		else:
			merged.append(rr)
	for rr in merged:
		if is_tunnel:
			for q in range(rr.x, rr.y + 1):
				mode[q] = which
		var keep := float(rr.y - rr.x + 1) * STEP >= min_len
		if not keep and not is_tunnel:
			for q in range(rr.x, rr.y + 1):
				if wet[q] == 1:
					keep = true
		if not keep:
			for q in range(rr.x, rr.y + 1):
				mode[q] = MODE_GROUND
		else:
			for q in range(rr.x, rr.y + 1):
				mode[q] = which


static func _runs(r: Dictionary) -> void:
	var mode: PackedByteArray = r["mode"]
	var s: PackedFloat32Array = r["s"]
	var pts: PackedVector2Array = r["pos"]
	var wet_check := r["ground"] as PackedFloat32Array
	var n := mode.size()
	var i := 0
	while i < n:
		if mode[i] == MODE_GROUND:
			i += 1
			continue
		var m := int(mode[i])
		var j := i
		while j + 1 < n and mode[j + 1] == m:
			j += 1
		var run := {"i0": i, "i1": j, "s0": s[i], "s1": s[j], "len": s[j] - s[i]}
		if m == MODE_TUNNEL:
			(r["tunnels"] as Array).append(run)
		else:
			var over_water := false
			for q in range(i, j + 1):
				if TerrainHeight.water_level_for(pts[q].x, pts[q].y, wet_check[q]) != TerrainHeight.NO_WATER:
					over_water = true
			run["water"] = over_water
			run["city"] = bool(r["elev"]) and TerrainHeight.city_distance(pts[(i + j) / 2].x, pts[(i + j) / 2].y) <= 0.0
			if over_water:
				var q0 := pts[(i + j) / 2]
				var wb := WaterLayout.body_at(q0.x, q0.y)
				var nm := Bridges._body_name(wb).replace(" BRIDGE", "")
				run["name"] = (nm if nm != "" else String(r["name"])) + " VIADUCT"
			(r["viaducts"] as Array).append(run)
		i = j + 1


static func _stations(def: Dictionary, pts: PackedVector2Array, s: PackedFloat32Array, total: float) -> Array:
	var out: Array = []
	var plat := 100.0 if def["style"] == &"maglev" else 130.0
	for sd: Dictionary in def["stations"]:
		var sc := 0.0
		if sd.has("at"):
			var best := 1.0e12
			for i in pts.size():
				var d := pts[i].distance_squared_to(sd["at"])
				if d < best:
					best = d
					sc = s[i]
		else:
			sc = float(sd["s"]) if float(sd["s"]) >= 0.0 else total + float(sd["s"])
		var ic := 0
		for i in pts.size():
			if absf(s[i] - sc) < absf(s[ic] - sc):
				ic = i
		out.append({"name": sd["name"], "s": s[ic], "ic": ic, "len": plat, "terminal": bool(sd.get("terminal", false)), "underground": false, "pos": Vector3(pts[ic].x, 0.0, pts[ic].y), "y": 0.0})
	return out


## Road crossings: local minima of the distance to a road centre line, for roads that really cross (not run beside the route). Level when the rail and the road are within 2.2 m of each other.
static func _crossings(ri: int, def: Dictionary, pts: PackedVector2Array, s: PackedFloat32Array, y: PackedFloat32Array, pin: PackedFloat32Array, stations: Array) -> Array:
	var out: Array = []
	var n := pts.size()
	var prev_d := 1.0e9
	var d_arr := PackedFloat32Array()
	d_arr.resize(n)
	var yr := PackedFloat32Array()
	yr.resize(n)
	var rr := PackedInt32Array()
	rr.resize(n)
	for i in n:
		var nr := TerrainRoads.nearest(pts[i].x, pts[i].y)
		d_arr[i] = nr[0]
		yr[i] = nr[2]
		rr[i] = nr[1]
	for i in range(2, n - 2):
		if d_arr[i] > 12.0 or rr[i] < 0 or d_arr[i] > d_arr[i - 1] or d_arr[i] > d_arr[i + 1]:
			continue
		if bool(def.get("elev", false)) and TerrainHeight.city_distance(pts[i].x, pts[i].y) <= 0.0:
			continue
		var in_station := false
		for st: Dictionary in stations:
			if absf(s[i] - float(st["s"])) <= float(st["len"]) * 0.5 + 40.0:
				in_station = true
		if in_station:
			continue
		var road: Dictionary = TerrainRoads.roads()[rr[i]]
		var rpos: PackedVector2Array = road["pos"]
		var bj := 0
		var bd := 1.0e12
		for j in rpos.size():
			var dd := rpos[j].distance_squared_to(pts[i])
			if dd < bd:
				bd = dd
				bj = j
		var rt := (rpos[mini(bj + 1, rpos.size() - 1)] - rpos[maxi(bj - 1, 0)]).normalized()
		var tg := (pts[i + 1] - pts[i - 1]).normalized()
		var ang := absf(rt.cross(tg))                     # sin of the crossing angle
		if ang < 0.42:
			diag.append("%s: runs beside %s at s=%.0f (sin %.2f)" % [def["name"], road["name"], s[i], ang])
			continue
		var level := absf(y[i] - yr[i]) <= 2.2 and is_nan(pin[i])
		var entry := {"route": ri, "i": i, "u": s[i], "pos": Vector3(pts[i].x, yr[i], pts[i].y), "dir": tg, "road": road["name"], "road_dir": rt, "road_w": float(road["w"]), "level": level, "road_y": yr[i], "ang": ang}
		if level:
			for q in range(maxi(i - 3, 0), mini(i + 4, n)):
				pin[q] = yr[i]
		out.append(entry)
	return out


## Signals: both directions at the throat of every station and along the line every 700 m. {route, u, dir, kind}.
static func _signals(r: Dictionary) -> void:
	var out: Array = r["signals"]
	var mode: PackedByteArray = r["mode"]
	var s: PackedFloat32Array = r["s"]
	var total: float = r["len"]
	for st: Dictionary in r["stations"]:
		for d in [1, -1]:
			var u: float = float(st["s"]) - float(d) * (float(st["len"]) * 0.5 + 46.0)
			if u > 30.0 and u < total - 30.0:
				out.append({"u": u, "dir": d, "kind": &"station", "station": st["name"]})
	var u2 := 350.0
	while u2 < total - 100.0:
		var near_station := false
		for st: Dictionary in r["stations"]:
			if absf(u2 - float(st["s"])) < 260.0:
				near_station = true
		if not near_station and mode[clampi(int(u2 / STEP), 0, mode.size() - 1)] == MODE_GROUND:
			out.append({"u": u2, "dir": 1 if int(u2 / 700.0) % 2 == 0 else -1, "kind": &"block", "station": ""})
		u2 += 700.0


# --- queries ---------------------------------------------------------------------------------------------------------------------------

static func right_of(t: Vector3) -> Vector3:
	return Vector3(-t.z, 0.0, t.x)


## Index of the sample at or before distance `u` and the fraction to the next one.
static func locate(r: Dictionary, u: float) -> Vector2:
	var n: int = (r["pos"] as PackedVector2Array).size()
	var s: PackedFloat32Array = r["s"]
	u = clampf(u, 0.0, float(r["len"]))
	var i := clampi(int(u / STEP), 0, n - 2)
	while i > 0 and s[i] > u:
		i -= 1
	while i < n - 2 and s[i + 1] < u:
		i += 1
	var l := maxf(s[i + 1] - s[i], 0.001)
	return Vector2(float(i), clampf((u - s[i]) / l, 0.0, 1.0))


## The centre line at distance u: [Vector3 position (y = bed top), Vector3 unit tangent (with the slope), float lane spread k].
static func point_at(r: Dictionary, u: float) -> Array:
	var pos: PackedVector2Array = r["pos"]
	var y: PackedFloat32Array = r["y"]
	var k: PackedFloat32Array = r["k"]
	var lc := locate(r, u)
	var i := int(lc.x)
	var f := lc.y
	var a := pos[i]
	var b := pos[i + 1]
	var p := Vector3(lerpf(a.x, b.x, f), lerpf(y[i], y[i + 1], f), lerpf(a.y, b.y, f))
	var i0 := maxi(i - 1, 0)
	var i1 := mini(i + 2, pos.size() - 1)
	var t := Vector3(pos[i1].x - pos[i0].x, y[i1] - y[i0], pos[i1].y - pos[i0].y).normalized()
	return [p, t, lerpf(k[i], k[i + 1], f)]


## Position and heading of a track: lane `dir` (+1 / -1), at distance u: [Vector3 position, Vector3 tangent].
static func lane_point(r: Dictionary, u: float, dir: int) -> Array:
	var pa := point_at(r, u)
	var t: Vector3 = pa[1]
	var h := Vector3(t.x, 0.0, t.z).normalized()
	return [(pa[0] as Vector3) + right_of(h) * (float(dir) * HALF_SEP * float(pa[2])), t]


static func mode_at(r: Dictionary, u: float) -> int:
	return int((r["mode"] as PackedByteArray)[int(locate(r, u).x)])


## [distance to the nearest track centre line, route index, bed height there, mode of that part] or [1e9, -1, 0, 0].
static func nearest(x: float, z: float) -> Array:
	if not built:
		return [1.0e9, -1, 0.0, 0]
	var cand = _grid.get(_key(int(floor(x / CELL)), int(floor(z / CELL))))
	if cand == null:
		return [1.0e9, -1, 0.0, 0]
	var best := 1.0e9
	var bi := -1
	var bh := 0.0
	var bm := 0
	var bb := BENCH
	var p := Vector2(x, z)
	for i: int in (cand as PackedInt32Array):
		var a := _sp[i]
		var nx := _sn[i]
		var d: float
		var h: float
		var m := int(_sm[i])
		if nx < 0:
			d = p.distance_to(a)
			h = _sy[i]
		else:
			var b := _sp[nx]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
			d = p.distance_to(a + ab * t)
			h = lerpf(_sy[i], _sy[nx], t)
			if _sm[nx] != _sm[i] and t > 0.5:
				m = int(_sm[nx])
		if d < best:
			best = d
			bi = _sr[i]
			bh = h
			bm = m
			bb = _sb[i]
	return [best, bi, bh, bm, bb]


## `h` (the land with rivers and roads) with the track bench cut in: embankments and cuttings on the GROUND samples. Viaducts and tunnels leave the land alone.
static func carve(x: float, z: float, h: float) -> float:
	if not built:
		return h
	var r := nearest(x, z)
	if int(r[1]) < 0 or int(r[3]) != MODE_GROUND:
		return h
	var d: float = r[0]
	var bench: float = r[4]
	var rd := TerrainRoads.nearest(x, z)                      # a road keeps its own bench: the embankment of a railway beside or over it never lifts the carriageway
	if int(rd[1]) >= 0 and float(rd[0]) < float(TerrainRoads.roads()[int(rd[1])]["bench"]):
		return h
	var delta := absf(h - float(r[2]))
	var shoulder := clampf(delta * 2.4, 8.0, SHOULDER_MAX)
	if d >= bench + shoulder:
		return h
	return lerpf(h, float(r[2]), 1.0 - smoothstep(bench, bench + shoulder, d))


static func on_track(x: float, z: float, slack := 0.0) -> bool:
	var r := nearest(x, z)
	return int(r[1]) >= 0 and float(r[0]) <= BED_HW + slack


## The station whose platform is nearest to `p`: [station Dictionary, route Dictionary, metres] or [{}, {}, INF].
static func nearest_station(p: Vector3) -> Array:
	ensure()
	var best: Dictionary = {}
	var br: Dictionary = {}
	var bd := INF
	for r in _routes:
		for st: Dictionary in r["stations"]:
			var sp := point_at(r, float(st["s"]))
			var d := Vector2((sp[0] as Vector3).x - p.x, (sp[0] as Vector3).z - p.z).length()
			if d < bd:
				bd = d
				best = st
				br = r
	return [best, br, bd]


## World position of the middle of a station platform (the track bed height).
static func station_pos(r: Dictionary, st: Dictionary) -> Vector3:
	return (point_at(r, float(st["s"])))[0]


## Stats for tests: {routes, length, stations, crossings, tunnels, viaducts, max_grade}.
static func stats() -> Dictionary:
	ensure()
	var length := 0.0
	var st := 0
	var cr := 0
	var tu := 0
	var vi := 0
	var mg := 0.0
	for r in _routes:
		length += float(r["len"])
		st += (r["stations"] as Array).size()
		cr += (r["crossings"] as Array).size()
		tu += (r["tunnels"] as Array).size()
		vi += (r["viaducts"] as Array).size()
		var y: PackedFloat32Array = r["y"]
		var s: PackedFloat32Array = r["s"]
		for i in range(1, y.size()):
			mg = maxf(mg, absf(y[i] - y[i - 1]) / maxf(s[i] - s[i - 1], 0.5))
	return {"routes": _routes.size(), "length": length, "stations": st, "crossings": cr, "tunnels": tu, "viaducts": vi, "max_grade": mg}


## Rail bridges for Bridges.list: one per viaduct run over water (the bridge kit builds the trestle and the deck collider, RailKit leaves them out).
static func water_bridges() -> Array[Dictionary]:
	ensure()
	var out: Array[Dictionary] = []
	for r in _routes:
		var pos: PackedVector2Array = r["pos"]
		var y: PackedFloat32Array = r["y"]
		for v: Dictionary in r["viaducts"]:
			if not bool(v.get("water", false)):
				continue
			var pts := PackedVector3Array()
			for i in range(maxi(int(v["i0"]) - 1, 0), mini(int(v["i1"]) + 2, pos.size())):
				pts.append(Vector3(pos[i].x, y[i], pos[i].y))
			if pts.size() < 2:
				continue
			out.append({"id": StringName("rail_%s_%d" % [r["id"], int(v["i0"])]), "name": String(v["name"]), "kind": &"rail", "pts": pts, "w": 2.0 * (HALF_SEP + 2.6), "road_w": 2.0 * HALF_SEP + 1.6, "piers": 24.0, "road": "", "sep": SEP,
				"route": r["id"], "i0": int(v["i0"]), "i1": int(v["i1"])})
	return out
