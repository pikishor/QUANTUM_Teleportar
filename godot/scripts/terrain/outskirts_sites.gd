class_name OutskirtsSites
extends RefCounted
## The destinations of the outskirts (wave 105: mountain and outskirt sites). Data and terrain only: the meshes are OutskirtsKit, the live nodes OutskirtsWorld, the forests VegetationWorld.
##
## Eleven sites, each a flat PAD cut into the finished terrain (`carve`, chained into TerrainHeight.height_at after the road benches, so meshes, colliders, vehicles and the hero's feet see it):
##   MOUNTAIN OBSERVATORY (end of SUMMIT ROAD, hairpins up the rim of MIRROR LAKE), RADIO TOWER (end of RIDGE TRACK, hairpins up the east range), OLD MINE (end of QUARRY TRACK), ALIEN CRASH SITE
##   (a crater in the south desert), HIDDEN CAVE (mouth in the east wall of MIRROR LAKE, a small cave system inside, see CaveSystem), LAKESIDE LODGE and HUNTERS CABINS (cabins),
##   PINE HOLLOW and DUST WELLS (villages), SOUTH FARM and NORTH FARM (farms).
## A site stands where the road ends (`road`) or at a fixed position found by the placement search (flat dry land away from the roads). `pos.y` is the pad height; the pad is flat to `r` metres and
## blends into the land over `blend` more. `yaw` points the site's front (-Z) at the way in. Pure functions after `ensure()` (TerrainHeight.warm calls it on the main thread).
##
##   OutskirtsSites.list / by_id(id) / nearest(p) / inside(x, z, margin)      queries (inside: vegetation and props keep out)
##   OutskirtsSites.carve(x, z, h)                                            the terrain with the pads
##   OutskirtsSites.map_markers() / hooks()                                   the map's pins and the mission hooks
##   OutskirtsSites.is_found(id) / mark_found(id)                             discovery (persisted in user://outskirts.cfg; the hidden cave only shows once found)

const CELL := 128.0
const SAVE_PATH := "user://outskirts.cfg"

## id, name, kind (selects the kit and the event), pos (x, z) or road (the road whose end it is), r flat radius, blend, yaw, reward, tag (one line on the map)
const DEFS: Array[Dictionary] = [
	{"id": &"observatory", "name": "MOUNTAIN OBSERVATORY", "kind": &"observatory", "road": "SUMMIT ROAD", "r": 34.0, "blend": 36.0, "reward": 400, "tag": "SCAN THE SKY: REVEALS THE WORLD MAP"},
	{"id": &"radio_tower", "name": "RADIO TOWER", "kind": &"tower", "road": "RIDGE TRACK", "r": 26.0, "blend": 34.0, "reward": 300, "tag": "RESTORE THE SIGNAL"},
	{"id": &"mine", "name": "OLD MINE", "kind": &"mine", "road": "QUARRY TRACK", "r": 30.0, "blend": 26.0, "reward": 350, "tag": "SEARCH THE SHAFT"},
	{"id": &"crash", "name": "ALIEN CRASH SITE", "kind": &"crash", "pos": Vector2(1150, 1550), "r": 54.0, "blend": 56.0, "yaw": 0.6, "reward": 500, "tag": "RECOVER THE CORE FRAGMENT"},
	{"id": &"cave", "name": "HIDDEN CAVE", "kind": &"cave", "pos": Vector2(-98, -2200), "r": 15.0, "blend": 18.0, "yaw": 1.5708, "reward": 450, "tag": "A STASH IN THE ROCK", "hidden": true},
	{"id": &"lodge", "name": "LAKESIDE LODGE", "kind": &"cabins", "pos": Vector2(-385, -1970), "r": 40.0, "blend": 44.0, "yaw": 0.4, "reward": 200, "tag": "A SAFE PLACE BY THE LAKE"},
	{"id": &"hunters", "name": "HUNTERS CABINS", "kind": &"cabins", "pos": Vector2(-1315, -1590), "r": 44.0, "blend": 30.0, "yaw": -0.5, "reward": 200, "tag": "CABINS IN THE PINES"},
	{"id": &"pine_hollow", "name": "PINE HOLLOW", "kind": &"village", "pos": Vector2(-1470, -510), "r": 100.0, "blend": 40.0, "yaw": 0.2, "reward": 250, "tag": "FOREST VILLAGE"},
	{"id": &"dust_wells", "name": "DUST WELLS", "kind": &"village", "pos": Vector2(1520, 320), "r": 100.0, "blend": 40.0, "yaw": 1.2, "reward": 250, "tag": "DESERT VILLAGE"},
	{"id": &"south_farm", "name": "SOUTH FARM", "kind": &"farm", "pos": Vector2(1490, 1650), "r": 80.0, "blend": 34.0, "yaw": 0.1, "reward": 200, "tag": "FARM ON THE PLAINS"},
	{"id": &"north_farm", "name": "NORTH FARM", "kind": &"farm", "pos": Vector2(-640, -1480), "r": 80.0, "blend": 34.0, "yaw": -0.7, "reward": 200, "tag": "FARM BELOW THE HILLS"},
]

static var built := false
static var list: Array[Dictionary] = []                     ## per site: the DEFS entry plus pos (Vector3, y = pad height), yaw, reach (r + blend), pad_y
static var _grid := {}                                      ## cell key -> PackedInt32Array of site indices whose reach touches the cell
static var _found := {}
static var _loaded := false


static func ensure() -> void:
	if built:
		return
	if TerrainRoads.roads_built() < TerrainRoads.DEFS.size():        # TerrainRoads.ensure() calls TerrainHeight.warm() while it builds: wait until every road exists (it calls us again at its end)
		return
	TerrainBase.warm()
	list.clear()
	_grid.clear()
	for d in DEFS + SettlementDefs.DEFS:                           # wave 112: and the seven towns (scripts/settlements/settlement_defs.gd, kind &"town")
		var s: Dictionary = d.duplicate()
		var c := Vector2.ZERO
		var y := 0.0
		var yaw := float(d.get("yaw", 0.0))
		if d.has("road"):
			var rd := _road_end(String(d["road"]))
			c = rd["pos"]
			y = float(rd["y"])
			var dir: Vector2 = rd["dir"]
			yaw = atan2(dir.x, dir.y)
			c += dir * float(d["r"]) * 0.45                    # the centre lies a little beyond the end of the road, the road arrives at the pad
		elif d.has("on_road"):                                 # a town stands ON a road: centred on it, yaw along it, the pad height from the land round it
			var rs := SettlementDefs.resolve(d)
			c = rs["c"]
			y = float(rs["y"])
			yaw = float(rs["yaw"])
		else:
			c = d["pos"]
			y = _ring_mean(c, float(d["r"]))
		s["pos"] = Vector3(c.x, y, c.y)
		s["pad_y"] = y
		s["yaw"] = yaw
		s["sn"] = sin(yaw)
		s["cs"] = cos(yaw)
		s["len"] = float(d.get("len", d["r"]))                 # half length of the pad along local +Z: a town is an ellipse (r across, len along its street), every other site a disc
		s["reach_e"] = float(d["r"]) + float(d["blend"])       # the reach in the across metric of the pad (carve)
		s["reach"] = maxf(float(s["len"]), float(d["r"])) + float(d["blend"]) * maxf(1.0, float(s["len"]) / float(d["r"]))      # the bounding radius in metres (the cell grid)
		s["found"] = false
		list.append(s)
		if d.has("on_road"):                                   # the roads through the pad are levelled to its height (before RoadLanes copies the profiles)
			TerrainRoads.level_profile(c, yaw, float(d["r"]), float(s["len"]), float(d["blend"]), y)
	for i in list.size():
		var p: Vector3 = list[i]["pos"]
		var rr: float = list[i]["reach"] + 2.0
		for cx in range(int(floor((p.x - rr) / CELL)), int(floor((p.x + rr) / CELL)) + 1):
			for cz in range(int(floor((p.z - rr) / CELL)), int(floor((p.z + rr) / CELL)) + 1):
				var k := _key(cx, cz)
				var arr: PackedInt32Array = _grid.get(k, PackedInt32Array())
				arr.append(i)
				_grid[k] = arr
	built = true


static func _key(cx: int, cz: int) -> int:
	return (cx + 100) * 1000 + (cz + 100)


## The land as it is before the pads: rivers, roads and the harbour quay on top of the base height (the pads are cut into this).
static func pre_height(x: float, z: float) -> float:
	return Harbour.carve(x, z, TerrainRoads.carve(x, z, WaterLayout.carve(x, z, TerrainBase.height(x, z))))


static func _ring_mean(c: Vector2, r: float) -> float:
	var sum := pre_height(c.x, c.y) * 2.0
	var n := 2.0
	for k in 8:
		var a := TAU * float(k) / 8.0
		sum += pre_height(c.x + cos(a) * r * 0.6, c.y + sin(a) * r * 0.6)
		n += 1.0
	return sum / n


static func _road_end(road_name: String) -> Dictionary:
	for r in TerrainRoads.roads():
		if String(r["name"]) == road_name:
			var pts: PackedVector2Array = r["pos"]
			var prof: PackedFloat32Array = r["prof"]
			var n := pts.size()
			var dir := (pts[n - 1] - pts[maxi(n - 4, 0)]).normalized()
			return {"pos": pts[n - 1], "y": prof[n - 1], "dir": dir}
	return {"pos": Vector2.ZERO, "y": 0.0, "dir": Vector2.DOWN}


## Terrain height with the pads cut in. A flat pad blends into the land; the crash site is a bowl with a raised rim.
static func carve(x: float, z: float, h: float) -> float:
	if not built:
		return h
	var cand = _grid.get(_key(int(floor(x / CELL)), int(floor(z / CELL))))
	if cand == null:
		return h
	for i: int in (cand as PackedInt32Array):
		var s: Dictionary = list[i]
		var d := _pad_d(s, x, z)
		var reach: float = s["reach_e"]
		if d >= reach:
			continue
		var r: float = s["r"]
		var target: float = s["pad_y"]
		var w := 1.0 - smoothstep(r, reach, d)
		if (s.has("road") or s.has("on_road")) and d > r:      # a site at the end of a road (or a town on one) leaves the road's own bench alone (the pad only shapes the land beside it)
			var rn := TerrainRoads.nearest(x, z)
			if int(rn[1]) >= 0:
				w *= smoothstep(6.0, 14.0, float(rn[0]))
		if s["kind"] == &"crash":
			var t := clampf(d / r, 0.0, 1.0)
			target = float(s["pad_y"]) - 7.0 * (1.0 - t * t) * (1.0 - t * 0.35) + 2.2 * exp(-pow((d - r * 1.02) / 9.0, 2.0))
			w = 1.0 - smoothstep(r * 0.95, reach, d)
		h = lerpf(h, target, w)
	return h


## Index of the site whose pad (plus `margin` metres) covers (x, z), -1 outside every pad. Vegetation, props and roadside things keep out of these.
static func inside(x: float, z: float, margin := 0.0) -> int:
	if not built:
		return -1
	var cand = _grid.get(_key(int(floor(x / CELL)), int(floor(z / CELL))))
	if cand == null:
		return -1
	for i: int in (cand as PackedInt32Array):
		if _pad_d(list[i], x, z) < float(list[i]["r"]) + margin:
			return i
	return -1


## Distance of (x, z) from the centre of a site's pad in the across metric: a plain distance for the discs, for a town (an ellipse, `len` along its street) the length along the street is scaled by r / len.
static func _pad_d(s: Dictionary, x: float, z: float) -> float:
	var p: Vector3 = s["pos"]
	var dx := x - p.x
	var dz := z - p.z
	var r: float = s["r"]
	var ln: float = s["len"]
	if ln <= r + 0.01:
		return sqrt(dx * dx + dz * dz)
	var u := (dx * float(s["sn"]) + dz * float(s["cs"])) * r / ln
	var v := dx * float(s["cs"]) - dz * float(s["sn"])
	return sqrt(u * u + v * v)


## Router penalty (TerrainRoads._route, wave 112): the pad of a free-standing site and its blend are no place for a road (a site at the end of a road and the towns, which stand on their own roads, are excluded).
## Reads the constant data only, so it works while the roads are still being built.
static func keep_clear(x: float, z: float) -> float:
	var pen := 0.0
	for d in DEFS:
		if d.has("road"):
			continue
		var p: Vector2 = d["pos"]
		var reach := float(d["r"]) + float(d["blend"]) + 30.0
		if absf(p.x - x) < reach and absf(p.y - z) < reach and Vector2(p.x - x, p.y - z).length() < reach:
			pen += 500.0
	return pen


## The mean ground height round (c, r): what a pad is set to when the data gives no height.
static func ring_mean(c: Vector2, r: float) -> float:
	return _ring_mean(c, r)


static func by_id(id: StringName) -> Dictionary:
	ensure()
	for s in list:
		if s["id"] == id:
			return s
	return {}


static func index_of(id: StringName) -> int:
	ensure()
	for i in list.size():
		if list[i]["id"] == id:
			return i
	return -1


## [site, distance] of the site nearest to `p` (horizontal), [{}, 1e9] when there is none.
static func nearest(p: Vector3) -> Array:
	ensure()
	var best := {}
	var bd := 1.0e9
	for s in list:
		var sp: Vector3 = s["pos"]
		var d := Vector2(sp.x - p.x, sp.z - p.z).length()
		if d < bd:
			bd = d
			best = s
	return [best, bd]


## World position of a point in a site's local frame (x right, z back, y up from the pad): the kit is built in this frame and rotated by the yaw.
static func to_world(s: Dictionary, local: Vector3) -> Vector3:
	var p: Vector3 = s["pos"]
	return p + Basis(Vector3.UP, float(s["yaw"])) * local


# --- discovery --------------------------------------------------------------------------------------------------------------------------------

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		for k in cf.get_section_keys("found"):
			_found[StringName(k)] = bool(cf.get_value("found", k, false))


static func is_found(id: StringName) -> bool:
	_load()
	return bool(_found.get(id, false))


static func mark_found(id: StringName) -> void:
	_load()
	if bool(_found.get(id, false)):
		return
	_found[id] = true
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("found", String(id), true)
	cf.save(SAVE_PATH)


## Forget what was found (tests, new game).
static func reset_found() -> void:
	_found.clear()
	_loaded = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## Parked rides at the sites (appended to VehicleSpawns.all_points; the manager puts a vehicle on the point when the hero comes within SPAWN_AT metres): local (x, z) in the site frame, kind, heading
## offset from the site's yaw. Off-road kinds at the mountain sites, work vehicles at the villages and farms, a hover car at the crash site.
const RIDES := {
	&"observatory": [["suv", Vector2(10.0, -22.0), 0.0]],
	&"radio_tower": [["quad", Vector2(-8.0, -14.0), 0.0]],
	&"mine": [["truck", Vector2(-10.0, -12.0), 0.3]],
	&"crash": [["hover", Vector2(-14.0, -22.0), 0.0]],
	&"lodge": [["rover", Vector2(14.0, -20.0), 0.0]],
	&"hunters": [["pickup", Vector2(14.0, -20.0), 0.0]],
	&"pine_hollow": [["pickup", Vector2(-9.0, -26.0), 0.0], ["quad", Vector2(10.0, -10.0), 0.4]],
	&"dust_wells": [["rover", Vector2(-9.0, -26.0), 0.0], ["van", Vector2(11.0, 8.0), 1.2]],
	&"south_farm": [["pickup", Vector2(6.0, -22.0), 0.0], ["quad", Vector2(-18.0, 6.0), 0.5]],
	&"north_farm": [["pickup", Vector2(6.0, -22.0), 0.0], ["truck", Vector2(-18.0, 6.0), 0.5]],
}


static func vehicle_points() -> Array[Dictionary]:
	ensure()
	var out: Array[Dictionary] = []
	for s in list:
		var rides: Array = RIDES.get(s["id"], [])
		for i in rides.size():
			var r: Array = rides[i]
			var l2: Vector2 = r[1]
			var w := to_world(s, Vector3(l2.x, 0.0, l2.y))
			w.y = TerrainHeight.height_at(w.x, w.z)
			out.append({"id": StringName("site_%s_%d" % [s["id"], i]), "kind": StringName(r[0]), "pos": w, "h": float(s["yaw"]) + float(r[2]), "label": ""})
	return out


## The map's pins: [{kind, pos, fog, label}]. The hidden cave only shows once it has been found; everything else is on the map from the start (a world to go and see).
static func map_markers() -> Array[Dictionary]:
	ensure()
	var out: Array[Dictionary] = []
	for s in list:
		if bool(s.get("hidden", false)) and not is_found(s["id"]):
			continue
		var mk := {"kind": &"site", "pos": s["pos"], "fog": false, "label": String(s["name"])}
		if s["kind"] == &"town":
			mk["glyph"] = &"town"                                         # three houses (MapIcons)
		out.append(mk)
	return out


## Mission hooks (the mission board and the campaign can aim at a site): {id, kind, name, pos, r, reward, tag}.
static func hooks() -> Array[Dictionary]:
	ensure()
	var out: Array[Dictionary] = []
	for s in list:
		out.append({"id": s["id"], "kind": s["kind"], "name": s["name"], "pos": s["pos"], "r": maxf(float(s["r"]) * 0.6, 14.0), "reward": s["reward"], "tag": s["tag"]})
	return out
