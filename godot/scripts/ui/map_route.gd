class_name MapRoute
extends RefCounted
## GPS for the map and the minimap (owner round 3: "objective route line following roads"). The city is a full grid of roads (CityLayout.road_center(0..N), PITCH apart), so the
## shortest drive between two points is a staircase over the road centre lines; this returns it with the fewest turns:
##   route(a, b)        polyline from a to b: a -> the nearest road -> along road centre lines -> the nearest road of b -> b (Vector3, y = 0)
##   length(poly)       its length in metres
##   goal(custom)       the one place to guide to: the player's own map waypoint, else the scripted step's goal, else the offered / active side contract; Vector3.INF when none
##   clip_to_circle(pts, centre, r)   the parts of a screen-space polyline inside a circle (the minimap rim), cut exactly at the rim instead of clamped onto it
## Pure functions, no nodes; the minimap caches a route and recomputes it when the player or the goal moved (REFRESH_M).

const REFRESH_M := 12.0            ## metres the player may move before the cached route is rebuilt


## Nearest point on the road centre-line network and which axis it lies on (0: on a road running along x, i.e. z is a road centre; 1: along z).
static func snap(p: Vector3) -> Dictionary:
	var ox := CityLayout.road_offset(p.x)
	var oz := CityLayout.road_offset(p.z)
	if absf(oz) <= absf(ox):
		return {"pos": Vector3(p.x, 0.0, p.z - oz), "axis": 0}
	return {"pos": Vector3(p.x - ox, 0.0, p.z), "axis": 1}


static func _road_index(v: float) -> int:
	return clampi(roundi((v + CityLayout.HALF) / CityLayout.PITCH), 0, CityLayout.N)


## The vertical road (index) to cross on: any road between the two x values costs the same; none between them means the nearest one outside.
static func _cross_road(xa: float, xb: float) -> float:
	var lo := minf(xa, xb)
	var hi := maxf(xa, xb)
	var mid := (lo + hi) * 0.5
	var i := _road_index(mid)
	var c := CityLayout.road_center(i)
	if c >= lo - 0.5 and c <= hi + 0.5:
		return c
	# no road strictly between: step to the nearer road on either side of the span
	var below := CityLayout.road_center(_road_index(lo))
	var above := CityLayout.road_center(_road_index(hi))
	return below if absf(below - mid) <= absf(above - mid) else above


static func _push(pts: PackedVector3Array, p: Vector3) -> void:
	if pts.is_empty() or Vector2(pts[pts.size() - 1].x - p.x, pts[pts.size() - 1].z - p.z).length() > 0.25:
		pts.append(Vector3(p.x, 0.0, p.z))


## Polyline along the roads from a to b (both are included as the first and the last point).
static func route(a: Vector3, b: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	_push(out, a)
	var sa := snap(a)
	var sb := snap(b)
	var pa: Vector3 = sa["pos"]
	var pb: Vector3 = sb["pos"]
	_push(out, pa)
	var axa: int = sa["axis"]
	var axb: int = sb["axis"]
	if axa == 0 and axb == 0:                         # both on roads running along x
		if absf(pa.z - pb.z) > 0.5:
			var cx := _cross_road(pa.x, pb.x)
			_push(out, Vector3(cx, 0.0, pa.z))
			_push(out, Vector3(cx, 0.0, pb.z))
	elif axa == 1 and axb == 1:                       # both on roads running along z
		if absf(pa.x - pb.x) > 0.5:
			var cz := _cross_road(pa.z, pb.z)
			_push(out, Vector3(pa.x, 0.0, cz))
			_push(out, Vector3(pb.x, 0.0, cz))
	elif axa == 0:                                    # a on a road along x, b on a road along z: they meet at (b.x, a.z)
		_push(out, Vector3(pb.x, 0.0, pa.z))
	else:
		_push(out, Vector3(pa.x, 0.0, pb.z))
	_push(out, pb)
	_push(out, b)
	return out


static func length(poly: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(1, poly.size()):
		l += Vector2(poly[i].x - poly[i - 1].x, poly[i].z - poly[i - 1].z).length()
	return l


## Where the route points: the map waypoint the player placed (`custom`, finite), else the running scripted step, else the next step, else the side contract. Vector3.INF when none.
static func goal(custom := Vector3.INF) -> Vector3:
	if custom.is_finite():
		return custom
	var m: Node = Game.missions if is_instance_valid(Game.missions) else null
	if m == null:
		return Vector3.INF
	var camp: Object = m.get("campaign")
	if camp != null:
		var wp: Dictionary = camp.call(&"waypoint")
		if wp.has("pos") and (wp["pos"] as Vector3).is_finite():
			return wp["pos"]
		var g: Variant = camp.get("guide")
		if g is MissionGuide:
			var gw: Dictionary = (g as MissionGuide).waypoint()
			if gw.has("pos") and (gw["pos"] as Vector3).is_finite():
				return gw["pos"]
	var con: Object = m.get("contracts")
	if con != null and StringName(con.get("state")) in [&"offered", &"active"]:
		var cp: Variant = con.get("pos")
		if cp is Vector3 and (cp as Vector3).is_finite():
			return cp
	return Vector3.INF


## The parts of `pts` (screen px) inside the circle (centre, r), cut where the line crosses the rim. Returns an array of polylines.
static func clip_to_circle(pts: PackedVector2Array, centre: Vector2, r: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var cur := PackedVector2Array()
	for i in pts.size():
		var p := pts[i]
		var inside := p.distance_to(centre) <= r
		if i == 0:
			if inside:
				cur.append(p)
			continue
		var q := pts[i - 1]
		var q_in := q.distance_to(centre) <= r
		if inside and q_in:
			cur.append(p)
		elif inside and not q_in:                       # entering
			cur = PackedVector2Array()
			var t := _circle_hit(q, p, centre, r, true)
			cur.append(q.lerp(p, t))
			cur.append(p)
		elif q_in and not inside:                       # leaving
			var t2 := _circle_hit(q, p, centre, r, false)
			cur.append(q.lerp(p, t2))
			if cur.size() >= 2:
				out.append(cur)
			cur = PackedVector2Array()
		else:                                           # both outside: the segment may still cut a chord
			var ts := _chord(q, p, centre, r)
			if ts.size() == 2:
				out.append(PackedVector2Array([q.lerp(p, ts[0]), q.lerp(p, ts[1])]))
	if cur.size() >= 2:
		out.append(cur)
	return out


## Parameter t (0..1) where the segment q -> p crosses the circle; `entering` picks the crossing into the circle, else the one out of it.
static func _circle_hit(q: Vector2, p: Vector2, centre: Vector2, r: float, entering: bool) -> float:
	var ts := _chord(q, p, centre, r, true)
	if ts.is_empty():
		return 0.0 if entering else 1.0
	if ts.size() == 1:
		return ts[0]
	return ts[0] if entering else ts[1]


## The t values (sorted) where the infinite line q + t (p - q) meets the circle; with `any` the values may lie outside 0..1.
static func _chord(q: Vector2, p: Vector2, centre: Vector2, r: float, any := false) -> Array[float]:
	var d := p - q
	var f := q - centre
	var a := d.dot(d)
	var out: Array[float] = []
	if a < 1e-9:
		return out
	var b := 2.0 * f.dot(d)
	var c := f.dot(f) - r * r
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return out
	var sq := sqrt(disc)
	var t0 := (-b - sq) / (2.0 * a)
	var t1 := (-b + sq) / (2.0 * a)
	for t in [t0, t1]:
		if any or (t >= 0.0 and t <= 1.0):
			out.append(clampf(t, 0.0, 1.0))
	if not any and out.size() == 1:
		out.clear()
	return out
