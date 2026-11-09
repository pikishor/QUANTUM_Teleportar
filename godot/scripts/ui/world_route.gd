class_name WorldRoute
extends RefCounted
## GPS for the big world (wave 109b). `MapRoute` is the staircase over the city grid; outside the city it is meaningless, so the world has three route modes:
##   car   the roads: from the start along the city grid to a gate (MapRoute), over the highways and tracks of `TerrainRoads` (a graph of their samples, branches joined, the gates joined
##         through the city), then along the city grid / straight off the last road to the goal. Two points close together in the open are one straight line.
##   air   one straight line (a plane or a helicopter flies where it likes).
##   boat  the sea and the rivers: A* on the coarse water mask of the world map (`TerrainMap.water_mask`, 47 m cells), pulled straight where the line of sight is clear. Without the mask (the world map
##         is still being built) or without a water link the route is the straight line and `info["direct"]` says so.
## `route(a, b, mode)` returns the polyline (Vector3, y = 0), `length` its metres, `eta(m, mode)` the seconds at a plain speed per mode, `mode_for(vehicle)` the mode a vehicle uses.
## Pure functions plus one cache; no nodes.

const MODES: Array[StringName] = [&"car", &"air", &"boat"]
const SPEED := {&"foot": 6.5, &"car": 20.0, &"air": 55.0, &"boat": 14.0}
const MODE_WORD := {&"car": "CAR", &"air": "AIR", &"boat": "BOAT"}
const NODE_STEP := 5                    ## every 5th road sample (50 m) is a graph node
const JOIN_R := 90.0                    ## metres: a road end this close to another road joins it
const OFF_ROAD := 1.7                   ## cost factor of metres driven off the roads
const DIRECT_M := 260.0                 ## closer than this outside the city: one straight line
const CITY_R := 1060.0                  ## |x|, |z| within this is the city grid (CityLayout.HALF + a margin)

static var info := {"direct": false, "mode": &"car"}
static var _nodes := PackedVector2Array()
static var _adj: Array = []              ## per node: Array of [neighbour, cost]
static var _gates: Array[int] = []       ## the first node of each road that starts at the city edge
static var _built := false
static var _cache_key := ""
static var _cache := PackedVector3Array()


static func mode_for(veh: Object) -> StringName:
	if veh == null:
		return &"car"
	var cls: Variant = veh.get("cls")
	if cls == &"heli" or cls == &"plane":
		return &"air"
	if cls == &"boat":
		return &"boat"
	return &"car"


static func in_city(p: Vector3) -> bool:
	return absf(p.x) <= CITY_R and absf(p.z) <= CITY_R


static func length(poly: PackedVector3Array) -> float:
	return MapRoute.length(poly)


static func eta(metres: float, mode: StringName) -> float:
	return metres / float(SPEED.get(mode, 6.5))


## "1:05" for 65 seconds; "0:42"; capped at "99:59".
static func clock(seconds: float) -> String:
	var t := clampi(roundi(seconds), 0, 99 * 60 + 59)
	return "%d:%02d" % [t / 60, t % 60]


## "840 M" under a kilometre, "1.2 KM" above.
static func dist_text(metres: float) -> String:
	return "%d M" % roundi(metres) if metres < 1000.0 else "%.1f KM" % (metres / 1000.0)


## The cached route: rebuilt when the mode, the goal or the start (within 24 m) changed.
static func route(a: Vector3, b: Vector3, mode: StringName) -> PackedVector3Array:
	var key := "%s|%d,%d|%d,%d" % [mode, roundi(a.x / 24.0), roundi(a.z / 24.0), roundi(b.x / 6.0), roundi(b.z / 6.0)]
	if key == _cache_key and not _cache.is_empty():
		return _cache
	_cache = build(a, b, mode)
	_cache_key = key
	return _cache


static func clear_cache() -> void:
	_cache_key = ""
	_cache = PackedVector3Array()


## Builds a route without the cache (tests).
static func build(a: Vector3, b: Vector3, mode: StringName) -> PackedVector3Array:
	info = {"direct": false, "mode": mode}
	a.y = 0.0
	b.y = 0.0
	match mode:
		&"air":
			return PackedVector3Array([a, b])
		&"boat":
			return _boat(a, b)
	return _car(a, b)


# --- car -------------------------------------------------------------------------------------------------------------

static func _graph() -> bool:
	if _built:
		return not _nodes.is_empty()
	if not TerrainRoads.built or TerrainRoads.roads().is_empty():
		return false
	_built = true
	_nodes = PackedVector2Array()
	_adj = []
	_gates = []
	var firsts: Array[int] = []
	var lasts: Array[int] = []
	var road_of := PackedInt32Array()
	var ri := 0
	for r: Dictionary in TerrainRoads.roads():
		var pts: PackedVector2Array = r["pos"]
		if pts.size() < 2:
			ri += 1
			continue
		var prev := -1
		var i := 0
		while true:
			var id := _nodes.size()
			_nodes.append(pts[i])
			_adj.append([])
			road_of.append(ri)
			if prev >= 0:
				var cost := _nodes[prev].distance_to(pts[i])
				(_adj[prev] as Array).append([id, cost])
				(_adj[id] as Array).append([prev, cost])
			else:
				firsts.append(id)
				if bool(r.get("from_city", false)):
					_gates.append(id)
			prev = id
			if i >= pts.size() - 1:
				break
			i = mini(i + NODE_STEP, pts.size() - 1)
		lasts.append(prev)
		ri += 1
	for end_id: int in firsts + lasts:                        # road ends join the nearest node of another road (branches start on their parent)
		var best := -1
		var bd := JOIN_R
		for j in _nodes.size():
			if road_of[j] == road_of[end_id]:
				continue
			var d := _nodes[j].distance_to(_nodes[end_id])
			if d < bd:
				bd = d
				best = j
		if best >= 0:
			(_adj[end_id] as Array).append([best, bd])
			(_adj[best] as Array).append([end_id, bd])
	return not _nodes.is_empty()


static func _car(a: Vector3, b: Vector3) -> PackedVector3Array:
	var ac := in_city(a)
	var bc := in_city(b)
	if ac and bc:
		return MapRoute.route(a, b)
	var straight := Vector2(a.x - b.x, a.z - b.z).length()
	if straight < DIRECT_M and not (ac or bc):
		info["direct"] = true
		return PackedVector3Array([a, b])
	if not _graph():
		info["direct"] = true
		return PackedVector3Array([a, b])
	var n := _nodes.size()
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var open: Array = []                                     # [cost, node] kept sorted by a simple heap
	for e: Array in _entries(a, ac):
		var id: int = e[0]
		if float(e[1]) < dist[id]:
			dist[id] = e[1]
			_push(open, [float(e[1]), id])
	var exits := {}
	for e: Array in _entries(b, bc):
		exits[int(e[0])] = float(e[1])
	var best_total := INF
	var best_node := -1
	while not open.is_empty():
		var top: Array = _pop(open)
		var u: int = top[1]
		if float(top[0]) > dist[u] + 0.01:
			continue
		if float(top[0]) >= best_total:
			break
		if exits.has(u) and dist[u] + float(exits[u]) < best_total:
			best_total = dist[u] + float(exits[u])
			best_node = u
		for edge: Array in (_adj[u] as Array):
			var v: int = edge[0]
			var nd: float = dist[u] + float(edge[1])
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = u
				_push(open, [nd, v])
		if _gates.has(u):                                    # the city joins every gate to every other (the staircase length)
			for g: int in _gates:
				if g == u:
					continue
				var gc := absf(_nodes[u].x - _nodes[g].x) + absf(_nodes[u].y - _nodes[g].y)
				var gd: float = dist[u] + gc
				if gd < dist[g]:
					dist[g] = gd
					prev[g] = -2 - u                         # a city hop: encoded as -2 - from
					_push(open, [gd, g])
	if best_node < 0:
		info["direct"] = true
		return PackedVector3Array([a, b])
	var chain: Array[int] = []
	var cur := best_node
	while cur != -1:
		chain.append(cur)
		var pv := prev[cur]
		cur = pv if pv >= 0 else (-2 - pv if pv <= -2 else -1)
	chain.reverse()
	var out := PackedVector3Array()
	out.append(a)
	if ac:
		var g0 := Vector3(_nodes[chain[0]].x, 0.0, _nodes[chain[0]].y)
		for p: Vector3 in MapRoute.route(a, g0):
			_join(out, p)
	for i in chain.size():
		var np := Vector3(_nodes[chain[i]].x, 0.0, _nodes[chain[i]].y)
		if i > 0 and prev[chain[i]] <= -2:                   # a hop through the city
			var from := Vector3(_nodes[chain[i - 1]].x, 0.0, _nodes[chain[i - 1]].y)
			for p: Vector3 in MapRoute.route(from, np):
				_join(out, p)
		else:
			_join(out, np)
	if bc:
		var gl := Vector3(_nodes[chain[chain.size() - 1]].x, 0.0, _nodes[chain[chain.size() - 1]].y)
		for p: Vector3 in MapRoute.route(gl, b):
			_join(out, p)
	_join(out, b)
	return out


static func _join(out: PackedVector3Array, p: Vector3) -> void:
	if out.is_empty() or Vector2(out[out.size() - 1].x - p.x, out[out.size() - 1].z - p.z).length() > 0.5:
		out.append(Vector3(p.x, 0.0, p.z))


## The graph nodes a point joins the roads at: inside the city every gate (the city grid length to it), outside its three nearest nodes (off-road metres cost more).
static func _entries(p: Vector3, in_c: bool) -> Array:
	var out: Array = []
	if in_c:
		for g: int in _gates:
			out.append([g, absf(p.x - _nodes[g].x) + absf(p.z - _nodes[g].y)])
		return out
	var cand: Array = []
	for i in _nodes.size():
		cand.append([Vector2(p.x, p.z).distance_to(_nodes[i]), i])
	cand.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	for k in mini(3, cand.size()):
		out.append([int(cand[k][1]), float(cand[k][0]) * OFF_ROAD])
	return out


static func _push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if float((h[p] as Array)[0]) <= float((h[i] as Array)[0]):
			break
		var t: Array = h[p]
		h[p] = h[i]
		h[i] = t
		i = p


static func _pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < h.size() and float((h[l] as Array)[0]) < float((h[m] as Array)[0]):
				m = l
			if r < h.size() and float((h[r] as Array)[0]) < float((h[m] as Array)[0]):
				m = r
			if m == i:
				break
			var t: Array = h[m]
			h[m] = h[i]
			h[i] = t
			i = m
	return top


# --- boat ------------------------------------------------------------------------------------------------------------

static func _cell(p: Vector3) -> Vector2i:
	var n := TerrainMap.WATER_N
	var e := TerrainMap.extent()
	return Vector2i(clampi(int((p.x + e) / (2.0 * e) * n), 0, n - 1), clampi(int((p.z + e) / (2.0 * e) * n), 0, n - 1))


static func _centre(c: Vector2i) -> Vector3:
	var n := TerrainMap.WATER_N
	var e := TerrainMap.extent()
	return Vector3((float(c.x) + 0.5) / n * 2.0 * e - e, 0.0, (float(c.y) + 0.5) / n * 2.0 * e - e)


static func _wet(c: Vector2i) -> bool:
	var n := TerrainMap.WATER_N
	return c.x >= 0 and c.y >= 0 and c.x < n and c.y < n and TerrainMap.water_mask[c.y * n + c.x] == 1


static func _nearest_wet(c: Vector2i) -> Vector2i:
	if _wet(c):
		return c
	for r in range(1, 14):
		var best := Vector2i(-1, -1)
		var bd := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := c + Vector2i(dx, dy)
				if _wet(q) and float(dx * dx + dy * dy) < bd:
					bd = float(dx * dx + dy * dy)
					best = q
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


static func _clear(a: Vector3, b: Vector3) -> bool:
	var steps := maxi(2, int(Vector2(a.x - b.x, a.z - b.z).length() / 20.0))
	for i in range(steps + 1):
		if not _wet(_cell(a.lerp(b, float(i) / steps))):
			return false
	return true


static func _boat(a: Vector3, b: Vector3) -> PackedVector3Array:
	if TerrainMap.water_mask.is_empty():
		info["direct"] = true
		return PackedVector3Array([a, b])
	var ca := _nearest_wet(_cell(a))
	var cb := _nearest_wet(_cell(b))
	if ca.x < 0 or cb.x < 0:
		info["direct"] = true
		return PackedVector3Array([a, b])
	var sa := a if _wet(_cell(a)) else _centre(ca)
	var sb := b if _wet(_cell(b)) else _centre(cb)
	if _clear(sa, sb):
		return _wrap(a, b, [sa, sb])
	var n := TerrainMap.WATER_N
	var g := PackedFloat32Array()
	g.resize(n * n)
	g.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n * n)
	prev.fill(-1)
	var open: Array = []
	var start := ca.y * n + ca.x
	var goal := cb.y * n + cb.x
	g[start] = 0.0
	_push(open, [_octile(ca, cb), start])
	var found := false
	while not open.is_empty():
		var top: Array = _pop(open)
		var u: int = top[1]
		if u == goal:
			found = true
			break
		var ux := u % n
		var uy := u / n
		if float(top[0]) > g[u] + _octile(Vector2i(ux, uy), cb) + 0.01:
			continue
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var q := Vector2i(ux + dx, uy + dy)
				if not _wet(q):
					continue
				if dx != 0 and dy != 0 and not (_wet(Vector2i(ux + dx, uy)) and _wet(Vector2i(ux, uy + dy))):
					continue                                  # no squeezing diagonally between two land corners
				var qi := q.y * n + q.x
				var ng: float = g[u] + (1.4142 if dx != 0 and dy != 0 else 1.0)
				if ng < g[qi]:
					g[qi] = ng
					prev[qi] = u
					_push(open, [ng + _octile(q, cb), qi])
	if not found:
		info["direct"] = true
		return PackedVector3Array([a, b])
	var cells: Array[Vector3] = []
	var cur := goal
	while cur != -1:
		cells.append(_centre(Vector2i(cur % n, cur / n)))
		cur = prev[cur]
	cells.reverse()
	cells[0] = sa
	cells[cells.size() - 1] = sb
	var kept: Array[Vector3] = [cells[0]]                    # string pulling: from each kept point the farthest point still in sight
	var i := 0
	while i < cells.size() - 1:
		var j := cells.size() - 1
		while j > i + 1 and not _clear(cells[i], cells[j]):
			j -= 1
		kept.append(cells[j])
		i = j
	return _wrap(a, b, kept)


static func _octile(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return float(maxi(dx, dy)) + 0.4142 * float(mini(dx, dy))


static func _wrap(a: Vector3, b: Vector3, mid: Array[Vector3]) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.append(a)
	for p: Vector3 in mid:
		_join(out, p)
	_join(out, b)
	return out
