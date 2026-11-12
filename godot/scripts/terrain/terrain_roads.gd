class_name TerrainRoads
extends RefCounted
## The roads from the city to the outskirts: four highways out of the city gates (north PASS ROAD, east DESERT ROAD, south COAST ROAD, west FOREST ROAD) and two dirt tracks
## (MOUNTAIN TRACK to the high country, the QUARRY TRACK off the desert road), as splines on the terrain. Data and carving only: the ribbon meshes come from `build_ribbon`.
##
## A road is a Catmull-Rom spline through control points, resampled every STEP metres. Its vertical PROFILE is the smoothed natural land, lifted where it has to clear a river
## (a causeway one metre above the water: the bridges come later) and limited to a maximum grade. `carve(x, z, h)` cuts the road bench into the finished land: flat across
## `bench` metres either side of the centre line, blended into the land over `shoulder` more. TerrainHeight.height_at calls it AFTER the rivers are carved, so everybody
## (terrain meshes, colliders, vehicles, the hero's feet) sees the same road. Pure functions after `ensure()`; call `ensure()` on the main thread before worker threads sample.

const STEP := 10.0
const CELL := 64.0
const ROAD_W := 20.0                      ## width of the city's own roads: the highways flare to this at the gates
const FLARE := 90.0                       ## metres over which a highway narrows from the city road width to its own
const KINDS := {
	"highway": {"w": 12.0, "bench": 15.0, "shoulder": 30.0, "grade": 0.07},
	"track": {"w": 5.0, "bench": 8.0, "shoulder": 16.0, "grade": 0.14},
}
## name, kind, via points (x, z): the router (`_route`, A* on a 40 m grid with a grade limit) finds the way between consecutive via points through the valleys. A road with `branch`
## [parent name, metres from its start] begins on that road. from_city: starts on the plateau edge (profile starts at y = 0).
const DEFS := [
	{"name": "PASS ROAD", "kind": "highway", "from_city": true, "via": [Vector2(0, -1090), Vector2(0, -1230), Vector2(-150, -1950)]},
	{"name": "DESERT ROAD", "kind": "highway", "from_city": true, "via": [Vector2(1090, 0), Vector2(1230, 0), Vector2(1750, 500), Vector2(1850, 1100), Vector2(1500, 1450)]},
	{"name": "COAST ROAD", "kind": "highway", "from_city": true, "via": [Vector2(0, 1090), Vector2(0, 1230), Vector2(-700, 1400), Vector2(-1300, 1000), Vector2(-1550, 300)]},
	{"name": "FOREST ROAD", "kind": "highway", "from_city": true, "via": [Vector2(-1090, 0), Vector2(-1230, 0), Vector2(-1450, -800), Vector2(-1100, -1450)]},
	{"name": "MOUNTAIN TRACK", "kind": "track", "from_city": false, "branch": ["PASS ROAD", 700.0], "via": [Vector2(1500, -1700), Vector2(1900, -1300)]},
	{"name": "QUARRY TRACK", "kind": "track", "from_city": false, "branch": ["DESERT ROAD", 600.0], "via": [Vector2(1860, -540)]},
	{"name": "HARBOUR ROAD", "kind": "highway", "from_city": false, "branch": ["COAST ROAD", 480.0], "via": [Vector2(-300, 1338)]},          # to the harbour apron (wave 105); the rest of it is HarbourKit's road on the quay
	{"name": "SUMMIT ROAD", "kind": "track", "from_city": false, "branch": ["PASS ROAD", 1190.0], "wide": true, "via": [Vector2(-300, -2090), Vector2(-420, -2180), Vector2(-540, -2220)]},         # the switchbacks up to the MOUNTAIN OBSERVATORY (OutskirtsSites, wave 105: the site stands where this road ends)
	{"name": "RIDGE TRACK", "kind": "track", "from_city": false, "branch": ["MOUNTAIN TRACK", 2300.0], "wide": true, "via": [Vector2(1700, -1560), Vector2(1860, -1500)]},      # the climb to the RADIO TOWER
]
const BRIDGE_CLEAR := 3.6                 ## metres of clearance between the water and the underside of the deck where a road crosses a river or lake (wave 105: bridges)
const SPAN_MARGIN := 2                    ## samples either side of the wet ones that the bridge deck covers, so its ends stand on the banks
const GRID := 40.0                        ## router cell (metres)
const CORRIDOR := 900.0                   ## the router looks this far either side of the straight line between two via points

static var built := false
static var _roads: Array = []                     ## per road: {name, kind, pos PackedVector2Array, prof PackedFloat32Array, len, w, bench, shoulder, from_city}
static var _sp := PackedVector2Array()            ## every sample of every road
static var _sh := PackedFloat32Array()            ## its profile height
static var _sr := PackedInt32Array()              ## its road index
static var _sn := PackedInt32Array()              ## index of the next sample of the same road, -1 at the end
static var _sb := PackedByteArray()               ## 1 on a sample under a bridge deck: the road bench is not cut there (the river runs through), Bridges builds the deck
static var _grid := {}                            ## cell key -> sample indices whose influence circle touches the cell


static func _key(cx: int, cz: int) -> int:
	return (cx + 200) * 1000 + (cz + 200)


static func roads() -> Array:
	ensure()
	return _roads


## How many roads are built so far (OutskirtsSites waits for all of them).
static func roads_built() -> int:
	return _roads.size()


static func ensure() -> void:
	if built:
		return
	built = true
	TerrainHeight.warm()                          # builds the rivers (WaterLayout) the causeways must clear
	_roads.clear()
	_sp = PackedVector2Array()
	_sh = PackedFloat32Array()
	_sr = PackedInt32Array()
	_sn = PackedInt32Array()
	_sb = PackedByteArray()
	_grid.clear()
	for ri in DEFS.size():
		_build_road(ri)
	for i in _sp.size():
		var k: Dictionary = KINDS[_roads[_sr[i]]["kind"]]
		var r: float = float(k["bench"]) + float(k["shoulder"]) + STEP
		for cx in range(int(floor((_sp[i].x - r) / CELL)), int(floor((_sp[i].x + r) / CELL)) + 1):
			for cz in range(int(floor((_sp[i].y - r) / CELL)), int(floor((_sp[i].y + r) / CELL)) + 1):
				var key := _key(cx, cz)
				if not _grid.has(key):
					_grid[key] = PackedInt32Array()
				var arr: PackedInt32Array = _grid[key]
				arr.append(i)
				_grid[key] = arr
	RailNet.ensure()                                  # the railway (wave 106) crosses these roads: it is routed and profiled once they are complete
	OutskirtsSites.ensure()                       # the sites stand where some of the roads end (wave 105)
	LandscapeSites.ensure()                       # wave 112: waterfalls and airstrips are found once the roads and the site pads exist


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


static func _smooth(a: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var out := a.duplicate()
	var n := a.size()
	for i in n:
		var acc := 0.0
		var cnt := 0
		for j in range(maxi(0, i - radius), mini(n, i + radius + 1)):
			acc += a[j]
			cnt += 1
		out[i] = acc / float(cnt)
	return out


static func _build_road(ri: int) -> void:
	var def: Dictionary = DEFS[ri]
	var kind: Dictionary = KINDS[def["kind"]]
	var via: Array = (def["via"] as Array).duplicate()
	var anchor_h := 0.0                                  ## the profile height the road starts at when it branches off another road
	if def.has("branch"):
		var par := _find_road(String(def["branch"][0]))
		var pp: PackedVector2Array = _roads[par]["pos"]
		var k := clampi(int(float(def["branch"][1]) / STEP), 0, pp.size() - 1)
		via.push_front(pp[k])
		anchor_h = float((_roads[par]["prof"] as PackedFloat32Array)[k])
	var nodes := PackedVector2Array()
	var wide := bool(def.get("wide", false))              # 16 directions instead of 8: a road that has to gain height across a steep hillside (hairpins) needs the finer headings
	for k in via.size() - 1:
		var seg := _route(via[k], via[k + 1], float(kind["grade"]), wide)
		if not nodes.is_empty() and not seg.is_empty():
			seg = seg.slice(1)
		nodes.append_array(seg)
	for _i in 3:                                          # relax the grid path
		var sm := nodes.duplicate()
		for i in range(1, nodes.size() - 1):
			sm[i] = (nodes[i - 1] + nodes[i] * 2.0 + nodes[i + 1]) * 0.25
		nodes = sm
	var pts := PackedVector2Array()
	for i in nodes.size() - 1:
		var p1: Vector2 = nodes[i]
		var p2: Vector2 = nodes[i + 1]
		var p0: Vector2 = nodes[maxi(i - 1, 0)]
		var p3: Vector2 = nodes[mini(i + 2, nodes.size() - 1)]
		var n := maxi(1, int(ceil(p1.distance_to(p2) / STEP)))
		for k in n:
			pts.append(_catmull(p0, p1, p2, p3, float(k) / float(n)))
	pts.append(nodes[nodes.size() - 1])
	var n := pts.size()
	var nat := PackedFloat32Array()
	var need := PackedFloat32Array()
	nat.resize(n)
	need.resize(n)
	for i in n:
		nat[i] = TerrainBase.height(pts[i].x, pts[i].y)
		var tg := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var nrm := Vector2(-tg.y, tg.x)
		var w := TerrainHeight.NO_WATER
		for off in [-26.0, -13.0, 0.0, 13.0, 26.0]:
			w = maxf(w, WaterLayout.surface_at(pts[i].x + nrm.x * off, pts[i].y + nrm.y * off))
		need[i] = w + BRIDGE_CLEAR if w != TerrainHeight.NO_WATER else -1.0e9
	var start_h := 0.0 if bool(def["from_city"]) else (anchor_h if def.has("branch") else nat[0])
	var prof := _smooth(_smooth(nat, 3), 2)
	var gk: float = float(kind["grade"])
	var seg := PackedFloat32Array()                      # metres between consecutive samples: the grade limit is per metre, not per sample
	seg.resize(n)
	for i in range(1, n):
		seg[i] = maxf(pts[i].distance_to(pts[i - 1]), 1.0)
	prof[0] = start_h
	for _pass in 2:                                       # cut and fill: the grade limit holds both ways, the start height is fixed (the city gate / the parent road)
		prof[0] = start_h
		for i in range(1, n):
			prof[i] = clampf(prof[i], prof[i - 1] - gk * seg[i], prof[i - 1] + gk * seg[i])
		for i in range(n - 2, 0, -1):
			prof[i] = clampf(prof[i], prof[i + 1] - gk * seg[i + 1], prof[i + 1] + gk * seg[i + 1])
	for i in range(1, n):                                 # clear of the rivers (causeway), ramps up to it
		prof[i] = maxf(prof[i], need[i])
	for _pass in 2:
		for i in range(1, n):
			prof[i] = maxf(prof[i], prof[i - 1] - gk * seg[i])
		for i in range(n - 2, 0, -1):
			prof[i] = maxf(prof[i], prof[i + 1] - gk * seg[i + 1])
	var total := 0.0
	for i in range(1, n):
		total += pts[i].distance_to(pts[i - 1])
	var wet := PackedByteArray()                          # samples with open river or lake water within the carriageway: the BRIDGE spans (runs of wet samples, a margin each side)
	wet.resize(n)
	var half_w: float = float(kind["w"]) * 0.5
	for i in range(1, n - 1):
		var tg2 := (pts[i + 1] - pts[i - 1]).normalized()
		var nr2 := Vector2(-tg2.y, tg2.x)
		for off in [-half_w, 0.0, half_w]:
			if WaterLayout.surface_at(pts[i].x + nr2.x * off, pts[i].y + nr2.y * off) != TerrainHeight.NO_WATER:
				wet[i] = 1
	var spans: Array[Vector2i] = []
	var i2 := 0
	while i2 < n:
		if wet[i2] == 0:
			i2 += 1
			continue
		var j2 := i2
		while j2 + 1 < n:                                 # the run goes on while another wet sample is within four steps
			var more := false
			for k in range(1, 5):
				if j2 + k < n and wet[j2 + k] == 1:
					more = true
			if not more:
				break
			j2 += 1
		var a := maxi(i2 - SPAN_MARGIN, 1)
		var b := mini(j2 + SPAN_MARGIN, n - 2)
		if not spans.is_empty() and a <= spans[spans.size() - 1].y + 1:
			spans[spans.size() - 1].y = b
		else:
			spans.append(Vector2i(a, b))
		i2 = j2 + 1
	var base := _sp.size()
	for i in n:
		_sp.append(pts[i])
		_sh.append(prof[i])
		_sr.append(ri)
		_sn.append(base + i + 1 if i < n - 1 else -1)
		_sb.append(0)
	for sp in spans:
		for i in range(sp.x, sp.y + 1):
			_sb[base + i] = 1
	_roads.append({"name": def["name"], "kind": def["kind"], "pos": pts, "prof": prof, "len": total, "w": float(kind["w"]), "bench": float(kind["bench"]),
		"shoulder": float(kind["shoulder"]), "from_city": bool(def["from_city"]), "spans": spans, "base": base})


static func _find_road(road_name: String) -> int:
	for i in _roads.size():
		if _roads[i]["name"] == road_name:
			return i
	return 0


## Grade-limited route between two points: A* over a GRID m lattice in a corridor around the straight line. A step costs its length, plus a steep penalty above 60 % of the road's grade,
## is forbidden above 1.6 x the grade, and the sea and open water cost a lot (a crossing happens only when it saves a detour: the profile then becomes a causeway).
static func _route(a: Vector2, b: Vector2, grade: float, wide := false) -> PackedVector2Array:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(CORRIDOR, CORRIDOR)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(CORRIDOR, CORRIDOR)
	var lim := TerrainHeight.WORLD_HALF - 120.0
	lo = Vector2(maxf(lo.x, -lim), maxf(lo.y, -lim))
	hi = Vector2(minf(hi.x, lim), minf(hi.y, lim))
	var w := int(ceil((hi.x - lo.x) / GRID)) + 1
	var h := int(ceil((hi.y - lo.y) / GRID)) + 1
	var heights := PackedFloat32Array()
	var penal := PackedFloat32Array()
	heights.resize(w * h)
	penal.resize(w * h)
	for j in h:
		for i in w:
			var x := lo.x + float(i) * GRID
			var z := lo.y + float(j) * GRID
			var hh := TerrainBase.height(x, z)
			heights[j * w + i] = hh
			var pen := 0.0
			if hh < TerrainHeight.SEA_LEVEL + 1.0:
				pen = 1.0e5                                  # beach and sea: never
			elif WaterLayout.surface_at(x, z) != TerrainHeight.NO_WATER:
				pen = 160.0
			elif TerrainHeight.city_distance(x, z) <= 0.0:
				pen = 0.0
			penal[j * w + i] = pen
	var ia := Vector2i(clampi(int(round((a.x - lo.x) / GRID)), 0, w - 1), clampi(int(round((a.y - lo.y) / GRID)), 0, h - 1))
	var ib := Vector2i(clampi(int(round((b.x - lo.x) / GRID)), 0, w - 1), clampi(int(round((b.y - lo.y) / GRID)), 0, h - 1))
	var n := w * h
	var gscore := PackedFloat32Array()
	var came := PackedInt32Array()
	var closed := PackedByteArray()
	gscore.resize(n)
	gscore.fill(1.0e12)
	came.resize(n)
	came.fill(-1)
	closed.resize(n)
	var open: Array = []                                  # binary heap of [f, node]
	var start := ia.y * w + ia.x
	var goal := ib.y * w + ib.x
	gscore[start] = 0.0
	_heap_push(open, [float(ia.distance_to(ib)) * GRID, start])
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	if wide:
		dirs.append_array([Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1), Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)])
	var found := false
	var best_node := start
	var best_d := 1.0e12
	while not open.is_empty():
		var cur: int = _heap_pop(open)[1]
		if cur == goal:
			found = true
			break
		if closed[cur] == 1:
			continue
		closed[cur] = 1
		var cx := cur % w
		var cy := cur / w
		var dg := float(Vector2i(cx, cy).distance_squared_to(ib))
		if dg < best_d:
			best_d = dg
			best_node = cur
		for d: Vector2i in dirs:
			var nx := cx + d.x
			var ny := cy + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var nb := ny * w + nx
			if closed[nb] == 1 or penal[nb] >= 1.0e5:
				continue
			var dist := GRID * Vector2(d).length()
			var slope := absf(heights[nb] - heights[cur]) / dist
			if slope > grade * 1.12:
				continue
			var cost := dist * (1.0 + 14.0 * maxf(0.0, slope - grade * 0.6) * maxf(0.0, slope - grade * 0.6) / maxf(grade * grade, 1.0e-4)) + penal[nb]
			var gs: float = gscore[cur] + cost
			if gs < gscore[nb]:
				gscore[nb] = gs
				came[nb] = cur
				_heap_push(open, [gs + float(Vector2i(nx, ny).distance_to(ib)) * GRID, nb])
	var out := PackedVector2Array()
	var cur2 := goal if found else best_node                  # no route to the goal under the grade limit: the road ends where it gets closest (a dead end at the foot of the range)
	var rev: Array[Vector2] = []
	while cur2 >= 0:
		rev.append(Vector2(lo.x + float(cur2 % w) * GRID, lo.y + float(cur2 / w) * GRID))
		cur2 = came[cur2]
	rev.reverse()
	rev[0] = a
	if found:
		rev[rev.size() - 1] = b
	for p in rev:
		out.append(p)
	return out


static func _heap_push(hp: Array, item: Array) -> void:
	hp.append(item)
	var i := hp.size() - 1
	while i > 0:
		var par := (i - 1) / 2
		if (hp[par] as Array)[0] <= (hp[i] as Array)[0]:
			break
		var t = hp[par]
		hp[par] = hp[i]
		hp[i] = t
		i = par


static func _heap_pop(hp: Array) -> Array:
	var top: Array = hp[0]
	var last: Array = hp.pop_back()
	if not hp.is_empty():
		hp[0] = last
		var i := 0
		var n := hp.size()
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < n and (hp[l] as Array)[0] < (hp[m] as Array)[0]:
				m = l
			if r < n and (hp[r] as Array)[0] < (hp[m] as Array)[0]:
				m = r
			if m == i:
				break
			var t = hp[m]
			hp[m] = hp[i]
			hp[i] = t
			i = m
	return top


## [distance to the nearest road centre line, road index, profile height there, 1 when that part of the road is a bridge span] or [1e9, -1, 0, 0] when no road reaches (x, z).
static func nearest(x: float, z: float) -> Array:
	var cand = _grid.get(_key(int(floor(x / CELL)), int(floor(z / CELL))))
	if cand == null:
		return [1.0e9, -1, 0.0, 0]
	var best := 1.0e9
	var bi := -1
	var bh := 0.0
	var bs := 0
	var p := Vector2(x, z)
	for i: int in (cand as PackedInt32Array):
		var a := _sp[i]
		var nx := _sn[i]
		var d: float
		var h: float
		if nx < 0:
			d = p.distance_to(a)
			h = _sh[i]
		else:
			var b := _sp[nx]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
			d = p.distance_to(a + ab * t)
			h = lerpf(_sh[i], _sh[nx], t)
		if d < best:
			best = d
			bi = _sr[i]
			bh = h
			bs = 1 if (_sb[i] == 1 and (nx < 0 or _sb[nx] == 1)) else 0
	return [best, bi, bh, bs]


## `h` (the land with rivers) with the road bench cut in. Fast out when no road is near.
static func carve(x: float, z: float, h: float) -> float:
	if not built:
		return h
	var cand = _grid.get(_key(int(floor(x / CELL)), int(floor(z / CELL))))
	if cand == null:
		return h
	var r := nearest(x, z)
	var ri: int = r[1]
	if ri < 0:
		return h
	if int(r[3]) == 1:                                    # under a bridge deck: the river bed and the banks stay as they are
		return h
	var road: Dictionary = _roads[ri]
	var bench: float = road["bench"]
	var d: float = r[0]
	if d >= bench + float(road["shoulder"]):
		return h
	var w := 1.0 - smoothstep(bench, bench + float(road["shoulder"]), d)
	return lerpf(h, float(r[2]), w)


## 0..1 how much of the point is road surface (1 on the carriageway, 0 beyond its edge plus a little): the terrain shader paints the gravel verge with it.
static func shoulder_weight(x: float, z: float) -> float:
	if not built:
		return 0.0
	var r := nearest(x, z)
	var ri: int = r[1]
	if ri < 0:
		return 0.0
	var road: Dictionary = _roads[ri]
	return 1.0 - smoothstep(float(road["w"]) * 0.5 + 1.0, float(road["w"]) * 0.5 + 4.0, float(r[0]))


## True when (x, z) lies under a bridge deck of a road (the road bench is not cut there).
static func in_span(x: float, z: float) -> bool:
	var r := nearest(x, z)
	return int(r[1]) >= 0 and int(r[3]) == 1 and float(r[0]) <= float(_roads[int(r[1])]["bench"]) + float(_roads[int(r[1])]["shoulder"])


static func name_at(x: float, z: float, within := 12.0) -> String:
	var r := nearest(x, z)
	if int(r[1]) >= 0 and float(r[0]) <= within:
		return String(_roads[int(r[1])]["name"])
	return ""


static func on_road(x: float, z: float, slack := 0.0) -> bool:
	var r := nearest(x, z)
	return int(r[1]) >= 0 and float(r[0]) <= float(_roads[int(r[1])]["w"]) * 0.5 + slack


## One ribbon mesh for road `ri`: positions follow the finished terrain +LIFT, UV x across 0..1, UV y metres along the road.
## width tapers to the city road width at the gate for roads that start on the plateau.
const LIFT := 0.07


static func build_ribbon(ri: int) -> ArrayMesh:
	ensure()
	var road: Dictionary = _roads[ri]
	var pts: PackedVector2Array = road["pos"]
	var n := pts.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var run := 0.0
	var half: float = float(road["w"]) * 0.5
	var verge := 2.6 if String(road["kind"]) == "highway" else 1.3                  # wave 112: a gravel verge on each side of the asphalt that the shader fades out (COLOR.g = the asphalt half width / 16)
	for i in n:
		if i > 0:
			run += pts[i].distance_to(pts[i - 1])
		var tg := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var nrm := Vector2(-tg.y, tg.x)
		var hw := half
		if bool(road["from_city"]):
			hw = lerpf(ROAD_W * 0.5, half, smoothstep(0.0, FLARE, run))
		var l := pts[i] + nrm * (hw + verge)
		var r := pts[i] - nrm * (hw + verge)
		var c := pts[i]
		var yc := TerrainHeight.height_at(c.x, c.y) + LIFT
		verts.append(Vector3(l.x, minf(TerrainHeight.height_at(l.x, l.y) + LIFT, yc + 0.4), l.y))
		verts.append(Vector3(r.x, minf(TerrainHeight.height_at(r.x, r.y) + LIFT, yc + 0.4), r.y))
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
		cols.append(Color(2.0 * (hw + verge) / 32.0, hw / 16.0, 0.0, 1.0))
		cols.append(Color(2.0 * (hw + verge) / 32.0, hw / 16.0, 0.0, 1.0))
		uvs.append(Vector2(0.0, run))
		uvs.append(Vector2(1.0, run))
		if i < n - 1 and _sb[int(road["base"]) + i] == 0 and _sb[int(road["base"]) + i + 1] == 0:          # a bridge span has its own deck (Bridges: one sample more at each end), the ribbon would lie in the river bed
			var b := i * 2
			idx.append_array(PackedInt32Array([b, b + 1, b + 2, b + 1, b + 3, b + 2]))                     # clockwise seen from above = front face (the old order made the road a back face: its normal was flipped, the sun never lit it)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
