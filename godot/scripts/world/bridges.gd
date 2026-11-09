class_name Bridges
extends RefCounted
## THE BRIDGES (wave 105): data and queries. Every place where a road crosses a river or a lake is a road bridge (TerrainRoads marks the spans: the bench is not cut there, the river runs
## through, the deck rides the road profile 3.6 m over the water), plus the HARBOUR GATE suspension bridge over the harbour basin (the landmark), footbridges over two rivers, and a rail
## trestles carrying the railway over rivers (RailNet.water_bridges: wave 106).
## A bridge is a Dictionary: {id, name, kind (&"road" | &"track" | &"suspension" | &"foot" | &"rail"), pts (PackedVector3Array: the centre line with the deck height as y), w (deck width with
## parapets, m), road_w (carriageway), len (m), piers (m between bents, 0 = none)}. The meshes and colliders are built by BridgeKit / BridgeWorld from this data, nothing here is a node.
##
## Queries: `deck_y(x, z, y_hint)` = the deck height under (x, z) for a vehicle at height y_hint (NO_WATER when there is no deck, or the vehicle is far under it), `on_deck`, `nearest(p)`.

const NONE := TerrainHeight.NO_WATER
const CELL := 48.0
const PARAPET := 0.9                       ## metres each side of the carriageway: kerb and parapet
const SUSPENSION := {"x0": -250.0, "x1": 380.0, "z": 1604.0, "y_end": 1.3, "y_span": 9.0, "tower_x0": -110.0, "tower_x1": 170.0}

static var built := false
static var list: Array[Dictionary] = []
static var _grid := {}                      ## cell key -> PackedInt32Array of (bridge << 12 | segment)


static func _key(cx: int, cz: int) -> int:
	return (cx + 300) * 1000 + (cz + 300)


static func ensure() -> void:
	if built:
		return
	built = true
	list.clear()
	_grid.clear()
	TerrainHeight.warm()
	for road: Dictionary in TerrainRoads.roads():
		var pos: PackedVector2Array = road["pos"]
		var prof: PackedFloat32Array = road["prof"]
		var spans: Array = road["spans"]
		for sp: Vector2i in spans:
			var pts := PackedVector3Array()
			for i in range(maxi(sp.x - 1, 0), mini(sp.y + 1, pos.size() - 1) + 1):
				pts.append(Vector3(pos[i].x, prof[i], pos[i].y))
			if pts.size() < 2:
				continue
			var mid := pts[pts.size() / 2]
			var body := WaterLayout.body_at(mid.x, mid.z)
			var nm := _body_name(body)
			if nm == "BRIDGE":
				nm = String(road["name"]) + " BRIDGE"
			var kind := &"road" if road["kind"] == "highway" else &"track"
			var rw := float(road["w"])
			_add({"id": StringName("%s_%d" % [String(road["name"]).to_lower().replace(" ", "_"), list.size()]), "name": nm, "kind": kind, "pts": pts, "w": rw + PARAPET * 2.0, "road_w": rw, "piers": 26.0 if kind == &"road" else 20.0,
				"road": String(road["name"])})
	_add_suspension()
	_add_foot_and_rail()
	for bi in list.size():
		var pts: PackedVector3Array = list[bi]["pts"]
		var w: float = list[bi]["w"]
		for s in pts.size() - 1:
			var a := pts[s]
			var b := pts[s + 1]
			var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z)) - Vector2(w, w)
			var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z)) + Vector2(w, w)
			for cx in range(int(floor(lo.x / CELL)), int(floor(hi.x / CELL)) + 1):
				for cz in range(int(floor(lo.y / CELL)), int(floor(hi.y / CELL)) + 1):
					var key := _key(cx, cz)
					var arr: PackedInt32Array = _grid.get(key, PackedInt32Array())
					arr.append((bi << 12) | s)
					_grid[key] = arr


static func _body_name(body: int) -> String:
	var n := ""
	if body >= 100 and body - 100 < WaterLayout.LAKES.size():
		n = String(WaterLayout.LAKES[body - 100]["name"])
	elif body >= 0 and body < WaterLayout.RIVERS.size():
		n = String(WaterLayout.RIVERS[body]["name"])
	n = n.replace(" RIVER", "").replace(" CREEK", "")
	return (n + " BRIDGE") if n != "" else "BRIDGE"


static func _add(b: Dictionary) -> void:
	var pts: PackedVector3Array = b["pts"]
	var l := 0.0
	for i in range(1, pts.size()):
		l += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
	b["len"] = l
	list.append(b)


## The HARBOUR GATE: a suspension bridge over the harbour basin, from the harbour road on the west headland to the lighthouse plaza on the east one. Two towers stand on the quay edges,
## the deck climbs to the main span (11 m over the water) over the headlands on piers.
static func _add_suspension() -> void:
	var S := SUSPENSION
	var z: float = S["z"]
	var pts := PackedVector3Array([Vector3(float(S["x0"]), float(S["y_end"]), z), Vector3(float(S["tower_x0"]), float(S["y_span"]), z), Vector3(float(S["tower_x1"]), float(S["y_span"]), z),
		Vector3(float(S["x1"]), float(S["y_end"]), z)])
	_add({"id": &"harbour_gate", "name": "HARBOUR GATE BRIDGE", "kind": &"suspension", "pts": pts, "w": 12.0 + PARAPET * 2.0 + 3.0, "road_w": 12.0, "piers": 30.0, "road": "HARBOUR ROAD"})


## A point on river `ri` at fraction `t` of its path with the unit direction.
static func river_point(ri: int, t: float) -> Array:
	WaterLayout.ensure()
	var pos: PackedVector2Array = WaterLayout.paths[ri]["pos"]
	var i := clampi(int(t * float(pos.size() - 1)), 2, pos.size() - 3)
	return [pos[i], (pos[i + 1] - pos[i - 1]).normalized(), float((WaterLayout.paths[ri]["hw"] as PackedFloat32Array)[i]), float((WaterLayout.paths[ri]["surface"] as PackedFloat32Array)[i])]


## Footbridges over EASTWATER (the desert) and NORTH CREEK (the forest edge) and the rail trestles (RailNet.water_bridges).
static func _add_foot_and_rail() -> void:
	for def in [[1, 0.7, &"foot_eastwater", "EASTWATER FOOTBRIDGE"], [2, 0.55, &"foot_creek", "CREEK FOOTBRIDGE"]]:
		var rp := river_point(int(def[0]), float(def[1]))
		var c: Vector2 = rp[0]
		var d: Vector2 = rp[1]
		var n := Vector2(-d.y, d.x)
		var half: float = float(rp[2]) + 7.0
		var a := c - n * half
		var bb := c + n * half
		var ya := TerrainHeight.height_at(a.x, a.y)
		var yb := TerrainHeight.height_at(bb.x, bb.y)
		var ym := maxf(float(rp[3]) + 2.4, maxf(ya, yb) + 0.2)
		_add({"id": def[2], "name": def[3], "kind": &"foot", "pts": PackedVector3Array([Vector3(a.x, ya + 0.15, a.y), Vector3(c.x, ym, c.y), Vector3(bb.x, yb + 0.15, bb.y)]),
			"w": 2.8, "road_w": 2.2, "piers": 0.0, "road": ""})
	for rb in RailNet.water_bridges():                               # the railway's viaducts over water (wave 106): the trestle structure and the deck collider come from the bridge kit
		_add(rb)


static func by_id(id: StringName) -> Dictionary:
	ensure()
	for b in list:
		if b["id"] == id:
			return b
	return {}


## All bridges of a kind (&"" = every one).
static func of_kind(kind: StringName) -> Array[Dictionary]:
	ensure()
	var out: Array[Dictionary] = []
	for b in list:
		if kind == &"" or b["kind"] == kind:
			out.append(b)
	return out


## The deck height at (x, z) for a thing at height `y_hint` (a car's own y): NONE when (x, z) is not over a deck, or the thing is more than 3 m under it (it drives below the bridge).
static func deck_y(x: float, z: float, y_hint: float) -> float:
	if not built:
		return NONE
	var arr = _grid.get(_key(int(floor(x / CELL)), int(floor(z / CELL))))
	if arr == null:
		return NONE
	var best := NONE
	for code: int in (arr as PackedInt32Array):
		var b: Dictionary = list[code >> 12]
		if b["kind"] == &"rail":
			continue
		var pts: PackedVector3Array = b["pts"]
		var s := code & 4095
		var a := pts[s]
		var c := pts[s + 1]
		var ab := Vector2(c.x - a.x, c.z - a.z)
		var l2 := ab.length_squared()
		if l2 < 1.0e-6:
			continue
		var t := ((x - a.x) * ab.x + (z - a.z) * ab.y) / l2
		if t < -0.001 or t > 1.001:
			continue
		var px := a.x + ab.x * t
		var pz := a.z + ab.y * t
		var lat := Vector2(x - px, z - pz).length()
		if lat > float(b["w"]) * 0.5:
			continue
		var y := lerpf(a.y, c.y, clampf(t, 0.0, 1.0))
		if y_hint < y - 3.0 or y_hint > y + 40.0:
			continue
		if y > best:
			best = y
	return best


static func on_deck(x: float, z: float, y_hint := 1.0e6) -> bool:
	return deck_y(x, z, y_hint) != NONE


## [bridge Dictionary, distance in metres to its centre line (horizontal)] of the bridge nearest to `p`, [{}, INF] when none.
static func nearest(p: Vector3) -> Array:
	ensure()
	var best: Dictionary = {}
	var bd := INF
	for b in list:
		var pts: PackedVector3Array = b["pts"]
		for s in pts.size() - 1:
			var a := Vector2(pts[s].x, pts[s].z)
			var c := Vector2(pts[s + 1].x, pts[s + 1].z)
			var ab := c - a
			var t := clampf((Vector2(p.x, p.z) - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
			var d := Vector2(p.x, p.z).distance_to(a + ab * t)
			if d < bd:
				bd = d
				best = b
	return [best, bd]


## Height of the centre line of bridge `b` at distance `u` metres from its start.
static func y_at(b: Dictionary, u: float) -> float:
	var pts: PackedVector3Array = b["pts"]
	var run := 0.0
	for s in pts.size() - 1:
		var l := Vector2(pts[s + 1].x - pts[s].x, pts[s + 1].z - pts[s].z).length()
		if u <= run + l or s == pts.size() - 2:
			return lerpf(pts[s].y, pts[s + 1].y, clampf((u - run) / maxf(l, 0.001), 0.0, 1.0))
		run += l
	return pts[pts.size() - 1].y


## Position (x, y = deck, z) and the unit direction at distance `u` along bridge `b`.
static func point_at(b: Dictionary, u: float) -> Array:
	var pts: PackedVector3Array = b["pts"]
	var run := 0.0
	for s in pts.size() - 1:
		var l := Vector2(pts[s + 1].x - pts[s].x, pts[s + 1].z - pts[s].z).length()
		if u <= run + l or s == pts.size() - 2:
			var t := clampf((u - run) / maxf(l, 0.001), 0.0, 1.0)
			var dir := Vector3(pts[s + 1].x - pts[s].x, 0.0, pts[s + 1].z - pts[s].z).normalized()
			return [pts[s].lerp(pts[s + 1], t), dir]
		run += l
	return [pts[pts.size() - 1], Vector3.RIGHT]
