class_name RoadLanes
extends RefCounted
## Driving data of the roads outside the city grid (round 6: "highways and outskirts roads are empty"): the four highways, the harbour road and the dirt tracks of TerrainRoads as lanes a car can follow.
## A road is a polyline of samples (`pts`, x / z), its profile height (`prof`) and the cumulative length (`cum`); a car drives in the lane to the right of its direction of travel at `lane` metres from the centre
## line. Pure functions after `ensure()` (TerrainRoads builds first). Used by RoadTraffic (the cars of the ring around the hero), PathDriver (a promoted car that drives itself) and the parked-car placers.
##   RoadLanes.sample(road, s, out)      fills out = [x, z, tangent x, tangent z, height] at distance `s` along the road
##   RoadLanes.random_near(c, rmin, rmax, rng)   a [road, sample] within the ring, [-1, -1] when no road lies there
##   RoadLanes.nearest(x, z, hint) -> [road, s, distance]

const CELL := 160.0

## Per road kind: lane offset from the centre line, cruise range of its traffic (m/s), share of the density a stretch of it gets.
const KIND := {
	"highway": {"lane": 3.0, "cmin": 17.0, "cmax": 25.0, "density": 1.0, "gap": 55.0},
	"track": {"lane": 1.4, "cmin": 7.0, "cmax": 12.0, "density": 0.3, "gap": 110.0},
}

static var built := false
static var roads: Array[Dictionary] = []            ## {id, name, kind, pts, prof, cum, len, lane, cmin, cmax, density, gap, wide}
static var _cells := {}                             ## cell key -> PackedInt32Array of (road * 100000 + sample)
static var _scratch := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])


static func _key(cx: int, cz: int) -> int:
	return (cx + 40) * 1000 + (cz + 40)


static func ensure() -> void:
	if built:
		return
	var src := TerrainRoads.roads()
	if src.size() < TerrainRoads.DEFS.size():
		return
	built = true
	roads.clear()
	_cells.clear()
	for ri in src.size():
		var r: Dictionary = src[ri]
		var pts: PackedVector2Array = r["pos"]
		var cum := PackedFloat32Array()
		cum.resize(pts.size())
		var acc := 0.0
		for i in range(1, pts.size()):
			acc += pts[i].distance_to(pts[i - 1])
			cum[i] = acc
		var k: Dictionary = KIND[String(r["kind"])]
		var d := {"id": ri, "name": String(r["name"]), "kind": String(r["kind"]), "pts": pts, "prof": r["prof"], "cum": cum, "len": acc, "lane": float(k["lane"]) * (1.25 if bool(r.get("wide", false)) else 1.0),
				"cmin": float(k["cmin"]), "cmax": float(k["cmax"]), "density": float(k["density"]), "gap": float(k["gap"])}
		roads.append(d)
		for i in pts.size():
			var key := _key(int(floor(pts[i].x / CELL)), int(floor(pts[i].y / CELL)))
			var arr: PackedInt32Array = _cells.get(key, PackedInt32Array())
			arr.append(ri * 100000 + i)
			_cells[key] = arr


static func count() -> int:
	ensure()
	return roads.size()


## Index of the last sample at or before distance `s` (binary search on the cumulative length).
static func _seg(cum: PackedFloat32Array, s: float) -> int:
	var lo := 0
	var hi := cum.size() - 2
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	return lo


## The road point at distance `s` (clamped to the road): fills `out` with x, z, unit tangent x, z, profile height and returns it.
static func sample(road: int, s: float, out: PackedFloat32Array = PackedFloat32Array()) -> PackedFloat32Array:
	if out.size() < 5:
		out = _scratch
	var r: Dictionary = roads[road]
	var cum: PackedFloat32Array = r["cum"]
	var pts: PackedVector2Array = r["pts"]
	var prof: PackedFloat32Array = r["prof"]
	s = clampf(s, 0.0, float(r["len"]))
	var i := _seg(cum, s)
	var seg := maxf(cum[i + 1] - cum[i], 0.001)
	var t := clampf((s - cum[i]) / seg, 0.0, 1.0)
	var a := pts[i]
	var b := pts[i + 1]
	var tg := (b - a) / seg
	out[0] = a.x + (b.x - a.x) * t
	out[1] = a.y + (b.y - a.y) * t
	out[2] = tg.x
	out[3] = tg.y
	out[4] = prof[i] + (prof[i + 1] - prof[i]) * t
	return out


## A road sample within [rmin, rmax] of `c` (x, z), picked at random among the samples of the ring: Vector2i(road, sample index), (-1, -1) when none.
static func random_near(c: Vector2, rmin: float, rmax: float, rng: RandomNumberGenerator) -> Vector2i:
	ensure()
	var cands: Array[int] = []
	for gx in range(int(floor((c.x - rmax) / CELL)), int(floor((c.x + rmax) / CELL)) + 1):
		for gz in range(int(floor((c.y - rmax) / CELL)), int(floor((c.y + rmax) / CELL)) + 1):
			var arr = _cells.get(_key(gx, gz))
			if arr == null:
				continue
			for code: int in (arr as PackedInt32Array):
				var ri := code / 100000
				var si := code % 100000
				var p: Vector2 = (roads[ri]["pts"] as PackedVector2Array)[si]
				var d := p.distance_to(c)
				if d >= rmin and d <= rmax:
					cands.append(code)
	if cands.is_empty():
		return Vector2i(-1, -1)
	var pick: int = cands[rng.randi() % cands.size()]
	return Vector2i(pick / 100000, pick % 100000)


## Distance along road `road` of the sample nearest to (x, z), searched within `window` samples of the one at `hint_s` (a car that already knows where it is).
static func nearest_s(road: int, x: float, z: float, hint_s: float, window := 12) -> float:
	var r: Dictionary = roads[road]
	var cum: PackedFloat32Array = r["cum"]
	var pts: PackedVector2Array = r["pts"]
	var i0 := _seg(cum, hint_s)
	var best := INF
	var bs := hint_s
	var p := Vector2(x, z)
	for i in range(maxi(i0 - window, 0), mini(i0 + window, pts.size() - 2) + 1):
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
		var d := p.distance_squared_to(a + ab * t)
		if d < best:
			best = d
			bs = cum[i] + (cum[i + 1] - cum[i]) * t
	return bs


## The road nearest to (x, z) over the whole network: [road, s, distance] ([-1, 0, INF] when none within 200 m).
static func nearest(x: float, z: float) -> Array:
	ensure()
	var best := INF
	var out := [-1, 0.0, INF]
	var p := Vector2(x, z)
	for gx in range(int(floor((x - 200.0) / CELL)), int(floor((x + 200.0) / CELL)) + 1):
		for gz in range(int(floor((z - 200.0) / CELL)), int(floor((z + 200.0) / CELL)) + 1):
			var arr = _cells.get(_key(gx, gz))
			if arr == null:
				continue
			for code: int in (arr as PackedInt32Array):
				var ri := code / 100000
				var si := code % 100000
				var pts: PackedVector2Array = roads[ri]["pts"]
				if si >= pts.size() - 1:
					continue
				var a := pts[si]
				var ab := pts[si + 1] - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
				var d := p.distance_to(a + ab * t)
				if d < best:
					best = d
					var cum: PackedFloat32Array = roads[ri]["cum"]
					out = [ri, cum[si] + (cum[si + 1] - cum[si]) * t, d]
	return out


## World position, unit forward (along the direction of travel `dir`), heading and height of the lane point at distance `s`: [Vector2 pos, Vector2 forward, float height].
static func lane_point(road: int, s: float, dir: int) -> Array:
	var sm := sample(road, s)
	var f := Vector2(sm[2], sm[3]) * float(dir)
	var right := Vector2(-f.y, f.x)
	return [Vector2(sm[0], sm[1]) + right * float(roads[road]["lane"]), f, sm[4]]
