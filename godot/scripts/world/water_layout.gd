class_name WaterLayout
extends RefCounted
## Where the inland water is: three rivers from the mountains to the sea and three lakes, as data, plus the carving that cuts their beds and banks into the terrain
## (TerrainHeight.height_at calls `carve`, so every consumer of the height function sees the valleys). Pure functions, no nodes.
##
## A river is a spline of control points (x, z). `ensure()` samples it every STEP metres, nudges the line into the nearest valley, then gives it a water surface
## that never rises downstream (running minimum of the land under the centre line, smoothed, at least SEA_LEVEL + 0.1), a width and depth that grow towards
## the mouth and a current speed from the fall. The bed is a parabola `surface - depth * (1 - (d / half_width)^2)`, the banks rise at 0.22 from the waterline and
## blend into the land over `bank` metres (wider where the river cuts through high ground, so gorges get walls, not cliffs).
## A lake is a circle: its level is the lowest land on its rim minus 0.25 m, the bowl is a parabola, the rim blends into the land.
##
## Queries use a 64 m grid of segment lists, so a height sample costs one dictionary lookup and a few segments, not the whole river.

const STEP := 12.0
const CELL := 64.0
const RIVERS := [
	{"name": "HIGHLINE RIVER", "w": [6.0, 34.0], "depth": [2.0, 5.5],
		"pts": [Vector2(800, -2650), Vector2(520, -2150), Vector2(80, -1850), Vector2(-420, -1700), Vector2(-900, -1500), Vector2(-1250, -1250),
			Vector2(-1550, -950), Vector2(-1800, -700)]},
	{"name": "EASTWATER", "w": [6.0, 28.0], "depth": [2.0, 5.0],
		"pts": [Vector2(2450, -300), Vector2(2050, 100), Vector2(1650, 500), Vector2(1450, 1000), Vector2(1300, 1450), Vector2(1150, 1900), Vector2(1000, 2250)]},
	{"name": "NORTH CREEK", "w": [4.0, 11.0], "depth": [1.4, 2.6], "joins": 0,
		"pts": [Vector2(1700, -1500), Vector2(1250, -1450), Vector2(700, -1560), Vector2(80, -1850)]},
]
const LAKES := [
	{"name": "MIRROR LAKE", "c": Vector2(-250, -2150), "r": 150.0, "depth": 9.0},
	{"name": "QUARRY LAKE", "c": Vector2(2000, -700), "r": 95.0, "depth": 7.0},
	{"name": "HIGH TARN", "c": Vector2(900, -2500), "r": 70.0, "depth": 5.0},
]
static var EMPTY := PackedFloat32Array()

static var built := false
static var paths: Array = []                    ## per river: {name, pos PackedVector2Array, surface, hw, depth, speed (PackedFloat32Array), dir PackedVector2Array}
static var lake_level := PackedFloat32Array()
static var lake_reach := PackedFloat32Array()   ## radius where the bowl has blended back into the land
static var _sa := PackedVector2Array()          ## segment start / end, per segment
static var _sb := PackedVector2Array()
static var _s_surf := PackedVector2Array()      ## surface at start / end (x, y)
static var _s_hw := PackedVector2Array()
static var _s_depth := PackedVector2Array()
static var _s_reach := PackedVector2Array()     ## influence radius at start / end
static var _s_speed := PackedFloat32Array()
static var _grid := {}


static func _key(cx: int, cz: int) -> int:
	return (cx + 200) * 1000 + (cz + 200)


static func ensure() -> void:
	if built:
		return
	built = true
	paths.clear()
	for ri in RIVERS.size():
		_build_river(ri)
	_build_lakes()


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


static func _build_river(ri: int) -> void:
	var def: Dictionary = RIVERS[ri]
	var ctl: Array = def["pts"]
	var pts := PackedVector2Array()
	for i in ctl.size() - 1:
		var p1: Vector2 = ctl[i]
		var p2: Vector2 = ctl[i + 1]
		var p0: Vector2 = ctl[maxi(i - 1, 0)]
		var p3: Vector2 = ctl[mini(i + 2, ctl.size() - 1)]
		var n := maxi(1, int(ceil(p1.distance_to(p2) / STEP)))
		for k in n:
			pts.append(_catmull(p0, p1, p2, p3, float(k) / float(n)))
	pts.append(ctl[ctl.size() - 1])
	# a river must reach the sea even when the land was reshaped under it: carry on along the last heading (up to 900 m) until the ground is at the waterline
	var wl := TerrainHeight.SEA_LEVEL + TerrainHeight.BEACH_TOP + 0.05
	if not def.has("joins") and TerrainHeight.base_height(pts[pts.size() - 1].x, pts[pts.size() - 1].y) > wl:
		var heading := (pts[pts.size() - 1] - pts[pts.size() - 4]).normalized()
		for _k in 75:
			var q := pts[pts.size() - 1] + heading * STEP
			pts.append(q)
			if TerrainHeight.base_height(q.x, q.y) <= wl:
				break
	# valley seeking: slide each point sideways towards lower land, then relax the line
	for _it in 6:
		var moved := pts.duplicate()
		for i in range(2, pts.size() - 2):
			var tg := (pts[i + 1] - pts[i - 1]).normalized()
			var nrm := Vector2(-tg.y, tg.x)
			var h0 := TerrainHeight.base_height(pts[i].x, pts[i].y)
			var hl := TerrainHeight.base_height(pts[i].x + nrm.x * 45.0, pts[i].y + nrm.y * 45.0)
			var hr := TerrainHeight.base_height(pts[i].x - nrm.x * 45.0, pts[i].y - nrm.y * 45.0)
			if hl < h0 - 1.0 and hl <= hr:
				moved[i] = pts[i] + nrm * 12.0
			elif hr < h0 - 1.0:
				moved[i] = pts[i] - nrm * 12.0
		for i in range(2, pts.size() - 2):
			pts[i] = moved[i] * 0.5 + (moved[i - 1] + moved[i + 1]) * 0.25
	# the river ends at the waterline of the sea (plus a few samples so the mouth overlaps the ocean)
	var last := pts.size() - 1
	for i in pts.size():
		if TerrainHeight.base_height(pts[i].x, pts[i].y) <= TerrainHeight.SEA_LEVEL + TerrainHeight.BEACH_TOP + 0.05:
			last = mini(i + 3, pts.size() - 1)
			break
	pts = pts.slice(0, last + 1)
	var n := pts.size()
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = TerrainHeight.base_height(pts[i].x, pts[i].y) - 0.5
	var surf := raw.duplicate()
	for i in range(1, n):
		surf[i] = minf(surf[i - 1], surf[i])
	_land_the_end(def, pts, surf)
	for _p in 4:
		var sm := surf.duplicate()
		for i in n:
			var acc := 0.0
			var cnt := 0
			for j in range(maxi(0, i - 5), mini(n, i + 6)):
				acc += surf[j]
				cnt += 1
			sm[i] = acc / float(cnt)
		surf = sm
		for i in range(1, n):
			surf[i] = minf(surf[i - 1], surf[i])
	_land_the_end(def, pts, surf)
	var lowest := TerrainHeight.SEA_LEVEL + 0.1
	var total := 0.0
	var run := PackedFloat32Array()
	run.resize(n)
	for i in n:
		surf[i] = maxf(surf[i], lowest)
		if i > 0:
			total += pts[i].distance_to(pts[i - 1])
		run[i] = total
	var hw := PackedFloat32Array()
	var dep := PackedFloat32Array()
	var spd := PackedFloat32Array()
	var dir := PackedVector2Array()
	var cut := PackedFloat32Array()
	hw.resize(n)
	dep.resize(n)
	spd.resize(n)
	dir.resize(n)
	cut.resize(n)
	var w: Array = def["w"]
	var d: Array = def["depth"]
	for i in n:
		var k := smoothstep(0.0, 1.0, run[i] / maxf(total, 1.0))
		hw[i] = lerpf(float(w[0]), float(w[1]), k) * 0.5
		dep[i] = lerpf(float(d[0]), float(d[1]), k)
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		dir[i] = (b - a).normalized()
		var fall := (surf[maxi(i - 3, 0)] - surf[mini(i + 3, n - 1)]) / maxf(a.distance_to(b) * (float(mini(i + 3, n - 1) - maxi(i - 3, 0)) / 2.0), 1.0)
		spd[i] = clampf(0.8 + fall * 40.0, 0.8, 4.5)
		cut[i] = maxf(0.0, TerrainHeight.base_height(pts[i].x, pts[i].y) - surf[i])
	paths.append({"name": def["name"], "pos": pts, "surface": surf, "hw": hw, "depth": dep, "speed": spd, "dir": dir, "length": total})
	# segments and their grid cells
	for i in n - 1:
		var si := _sa.size()
		_sa.append(pts[i])
		_sb.append(pts[i + 1])
		_s_surf.append(Vector2(surf[i], surf[i + 1]))
		_s_hw.append(Vector2(hw[i], hw[i + 1]))
		_s_depth.append(Vector2(dep[i], dep[i + 1]))
		var ra := hw[i] + _bank(hw[i], cut[i])
		var rb := hw[i + 1] + _bank(hw[i + 1], cut[i + 1])
		_s_reach.append(Vector2(ra, rb))
		_s_speed.append((spd[i] + spd[i + 1]) * 0.5)
		var rr := maxf(ra, rb)
		var lo := Vector2(minf(pts[i].x, pts[i + 1].x) - rr, minf(pts[i].y, pts[i + 1].y) - rr)
		var hi := Vector2(maxf(pts[i].x, pts[i + 1].x) + rr, maxf(pts[i].y, pts[i + 1].y) + rr)
		for cx in range(int(floor(lo.x / CELL)), int(floor(hi.x / CELL)) + 1):
			for cz in range(int(floor(lo.y / CELL)), int(floor(hi.y / CELL)) + 1):
				var key := _key(cx, cz)
				if not _grid.has(key):
					_grid[key] = PackedInt32Array()
				var arr: PackedInt32Array = _grid[key]
				arr.append(si)
				_grid[key] = arr


## The last 300 m of a river settle on where it ends: the sea level for a river that reaches the sea, the surface of the river it flows into for a tributary.
static func _land_the_end(def: Dictionary, pts: PackedVector2Array, surf: PackedFloat32Array) -> void:
	var n := surf.size()
	var target := TerrainHeight.SEA_LEVEL + 0.1
	if def.has("joins"):
		var other: Dictionary = paths[int(def["joins"])]
		var op: PackedVector2Array = other["pos"]
		var os: PackedFloat32Array = other["surface"]
		var bd := 1.0e18
		for k in op.size():
			var d := op[k].distance_squared_to(pts[n - 1])
			if d < bd:
				bd = d
				target = os[k]
	target = minf(target, surf[n - 1])                   # a tributary never runs uphill to its river: if the river is higher it just ends at its own level
	var span := mini(25, n - 1)
	for k in span + 1:
		var i := n - 1 - k
		surf[i] = lerpf(target, surf[i], smoothstep(0.0, 1.0, float(k) / float(span)))


static func _bank(hw: float, cut: float) -> float:
	return 10.0 + hw * 0.7 + minf(cut, 70.0) * 1.2


static func _build_lakes() -> void:
	lake_level.resize(LAKES.size())
	lake_reach.resize(LAKES.size())
	for i in LAKES.size():
		var c: Vector2 = LAKES[i]["c"]
		var r: float = LAKES[i]["r"]
		var lo := 1.0e9
		var hi := -1.0e9
		for k in 16:
			var a := TAU * float(k) / 16.0
			var h := TerrainHeight.base_height(c.x + cos(a) * r, c.y + sin(a) * r)
			lo = minf(lo, h)
			hi = maxf(hi, h)
		lake_level[i] = lo - 0.25
		lake_reach[i] = r + 30.0 + minf(hi - lo, 80.0) * 1.2


## Nearest river segment to (x, z) that reaches it: [distance, half width, surface, depth, reach, dir x, dir z, speed], EMPTY when none does.
static func _query(x: float, z: float) -> PackedFloat32Array:
	var key := _key(int(floor(x / CELL)), int(floor(z / CELL)))
	if not _grid.has(key):
		return EMPTY
	var segs: PackedInt32Array = _grid[key]
	var best := 1.0e18
	var bi := -1
	var bt := 0.0
	var p := Vector2(x, z)
	for si in segs:
		var a := _sa[si]
		var ab := _sb[si] - a
		var l2 := ab.length_squared()
		var t := clampf((p - a).dot(ab) / maxf(l2, 1.0e-6), 0.0, 1.0)
		var d2 := p.distance_squared_to(a + ab * t)
		if d2 < best:
			best = d2
			bi = si
			bt = t
	if bi < 0:
		return EMPTY
	var d := sqrt(best)
	var reach := lerpf(_s_reach[bi].x, _s_reach[bi].y, bt)
	if d >= reach:
		return EMPTY
	var dir := (_sb[bi] - _sa[bi]).normalized()
	var out := PackedFloat32Array()
	out.resize(8)
	out[0] = d
	out[1] = lerpf(_s_hw[bi].x, _s_hw[bi].y, bt)
	out[2] = lerpf(_s_surf[bi].x, _s_surf[bi].y, bt)
	out[3] = lerpf(_s_depth[bi].x, _s_depth[bi].y, bt)
	out[4] = reach
	out[5] = dir.x
	out[6] = dir.y
	out[7] = _s_speed[bi]
	return out


## `h` (the land) with every river and lake in reach carved into it.
static func carve(x: float, z: float, h: float) -> float:
	ensure()
	var q := _query(x, z)
	if q.size() > 0:
		var d := q[0]
		var hw := q[1]
		var s := q[2]
		var beta := 1.0 - smoothstep(hw * 0.9, q[4], d)
		var target: float
		if d < hw:
			var k := d / hw
			target = s - q[3] * (1.0 - k * k)
		else:
			target = s + (d - hw) * 0.22
		h = lerpf(h, target, beta)
	for i in LAKES.size():
		var c: Vector2 = LAKES[i]["c"]
		var dx := x - c.x
		var dz := z - c.y
		var reach := lake_reach[i]
		var d2 := dx * dx + dz * dz
		if d2 >= reach * reach:
			continue
		var d := sqrt(d2)
		var r: float = LAKES[i]["r"]
		var L := lake_level[i]
		var beta := 1.0 - smoothstep(r * 0.9, reach, d)
		var target: float
		if d < r:
			var k := d / r
			target = L - float(LAKES[i]["depth"]) * (1.0 - k * k)
		else:
			target = L + (d - r) * 0.3
		h = minf(h, lerpf(h, target, beta))               # a lake only digs: no berm round it where the land falls away
	return h


## Surface y of the river or lake water over (x, z), NO_WATER outside every water footprint (the ocean is TerrainHeight's: it follows from the ground height).
static func surface_at(x: float, z: float) -> float:
	ensure()
	var best := TerrainHeight.NO_WATER
	var q := _query(x, z)
	if q.size() > 0 and q[0] < q[1]:
		best = q[2]
	for i in LAKES.size():
		var c: Vector2 = LAKES[i]["c"]
		var dx := x - c.x
		var dz := z - c.y
		var r: float = LAKES[i]["r"]
		if dx * dx + dz * dz < r * r and lake_level[i] > best:
			best = lake_level[i]
	return best


## The current of a river at (x, z) in m/s, ZERO off the rivers (lakes and the sea are still). Slower towards the banks.
static func flow_at(x: float, z: float) -> Vector2:
	ensure()
	var q := _query(x, z)
	if q.size() == 0 or q[0] >= q[1]:
		return Vector2.ZERO
	var k := q[0] / q[1]
	return Vector2(q[5], q[6]) * q[7] * (1.0 - 0.6 * k * k)


## Distance in metres from (x, z) to the nearest river water edge or lake shore within `max_d` (0 inside the water); INF when none is that near. Cheap enough for a few
## calls per second (ambient sound, hints): it walks the grid cells around the point.
static func inland_distance(x: float, z: float, max_d := 120.0) -> float:
	ensure()
	var best := INF
	var p := Vector2(x, z)
	var r := int(ceil(max_d / CELL))
	var cx := int(floor(x / CELL))
	var cz := int(floor(z / CELL))
	for ix in range(cx - r, cx + r + 1):
		for iz in range(cz - r, cz + r + 1):
			var key := _key(ix, iz)
			if not _grid.has(key):
				continue
			for si in (_grid[key] as PackedInt32Array):
				var a := _sa[si]
				var ab := _sb[si] - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
				var d := p.distance_to(a + ab * t) - lerpf(_s_hw[si].x, _s_hw[si].y, t)
				best = minf(best, maxf(d, 0.0))
	for i in LAKES.size():
		var c: Vector2 = LAKES[i]["c"]
		best = minf(best, maxf(p.distance_to(c) - float(LAKES[i]["r"]), 0.0))
	return best if best <= max_d else INF


## Which river (index into RIVERS) or lake (index + 100) holds (x, z), -1 for neither: used for names on the map and for sounds.
static func body_at(x: float, z: float) -> int:
	ensure()
	var q := _query(x, z)
	if q.size() > 0 and q[0] < q[1]:
		var p := Vector2(x, z)
		for ri in paths.size():
			for pt: Vector2 in (paths[ri]["pos"] as PackedVector2Array):
				if pt.distance_squared_to(p) < (q[1] + STEP * 2.0) * (q[1] + STEP * 2.0):
					return ri
		return 0
	for i in LAKES.size():
		var c: Vector2 = LAKES[i]["c"]
		var r: float = LAKES[i]["r"]
		if Vector2(x, z).distance_squared_to(c) < r * r:
			return 100 + i
	return -1
