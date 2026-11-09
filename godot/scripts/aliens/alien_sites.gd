class_name AlienSites
extends RefCounted
## WHERE the alien world is (wave 107b): the alien camps of the mountains and canyons, the hive nests, the crash sites and the boss lairs. Data and terrain queries only, no nodes (AlienWorld
## builds and populates them). Every site is FOUND, not hand-placed: a deterministic search over a region for flat dry ground of the right biome that no road, river or outskirt pad has touched,
## so the sites follow the terrain wherever it is tuned. Pure functions after `ensure()` (call it after TerrainHeight.warm()); tests check the rules, not the numbers.
##
##   camp    guards (hive grunts, acid spitters, a crag brute, a shade stalker) and spore sentries around tents and a spire; clear it, then take the cache
##   nest    a HIVE HEART among eggs that keeps hatching skitters: destroy it
##   crash   a wrecked alien craft: survivors, three shield relays and (at the big one) the HIVE WARDEN
##   lair    a boss and its bones: the BROODMOTHER in the forest, the STORM DRAKE on a peak, the SAND LEVIATHAN in the dunes, the DEEP KRAKEN out at sea
## State (cleared sites, defeated bosses) is saved in user://alien_world.cfg; `reset_all()` clears it (new game, tests).

const SAVE_PATH := "user://alien_world.cfg"
const CITY_SKIRT := 780.0

## id | name | kind | biomes | region (x, z, radius of the search) | h (min, max ground height) | flat (metres of terrain around the centre that must be level) | r (activity radius) |
## guards [[species, n]] | sentries | boss | reward | tag
const DEFS: Array[Dictionary] = [
	{"id": &"ridge_camp", "name": "RIDGE CLAW CAMP", "kind": &"camp", "biomes": [&"mountain"], "region": Vector3(250, -2350, 420), "h": Vector2(80.0, 280.0), "flat": 14.0, "r": 40.0,
		"guards": [[&"hive_grunt", 3], [&"acid_spitter", 2], [&"crag_brute", 1], [&"shade_stalker", 1]], "sentries": 2, "reward": 650, "tag": "CLEAR THE CAMP"},
	{"id": &"peak_camp", "name": "FROSTFANG OUTPOST", "kind": &"camp", "biomes": [&"mountain", &"forest"], "region": Vector3(-1000, -2350, 420), "h": Vector2(60.0, 280.0), "flat": 14.0, "r": 40.0,
		"guards": [[&"hive_grunt", 3], [&"acid_spitter", 3], [&"crag_brute", 1]], "sentries": 2, "reward": 600, "tag": "CLEAR THE CAMP"},
	{"id": &"east_camp", "name": "EAST RANGE BASE", "kind": &"camp", "biomes": [&"mountain", &"desert"], "region": Vector3(2250, -900, 450), "h": Vector2(40.0, 280.0), "flat": 14.0, "r": 40.0,
		"guards": [[&"hive_grunt", 4], [&"acid_spitter", 2], [&"shade_stalker", 2]], "sentries": 3, "reward": 700, "tag": "CLEAR THE CAMP"},
	{"id": &"canyon_camp", "name": "EASTWATER ROOST", "kind": &"camp", "biomes": [&"mountain", &"desert"], "region": Vector3(2147, -99, 300), "h": Vector2(80.0, 280.0), "flat": 12.0, "r": 36.0,
		"guards": [[&"hive_grunt", 2], [&"acid_spitter", 3], [&"shade_stalker", 1], [&"crag_brute", 1]], "sentries": 2, "reward": 600, "tag": "CANYON CAMP"},
	{"id": &"gorge_camp", "name": "HIGHLINE HOLD", "kind": &"camp", "biomes": [&"forest", &"mountain"], "region": Vector3(160, -1810, 320), "h": Vector2(30.0, 280.0), "flat": 12.0, "r": 36.0,
		"guards": [[&"hive_grunt", 3], [&"acid_spitter", 2], [&"shade_stalker", 2]], "sentries": 2, "reward": 550, "tag": "GORGE CAMP"},
	{"id": &"forest_nest", "name": "FOREST HIVE", "kind": &"nest", "biomes": [&"forest"], "region": Vector3(-1150, -1650, 380), "h": Vector2(2.0, 200.0), "flat": 16.0, "r": 36.0,
		"guards": [[&"skitter", 3], [&"hive_grunt", 2]], "sentries": 0, "reward": 500, "tag": "DESTROY THE HIVE HEART"},
	{"id": &"dune_nest", "name": "DUNE HIVE", "kind": &"nest", "biomes": [&"desert"], "region": Vector3(1750, -350, 380), "h": Vector2(2.0, 200.0), "flat": 16.0, "r": 36.0,
		"guards": [[&"skitter", 3], [&"popper", 2]], "sentries": 0, "reward": 500, "tag": "DESTROY THE HIVE HEART"},
	{"id": &"plains_nest", "name": "HOLLOW HIVE", "kind": &"nest", "biomes": [&"plains", &"forest"], "region": Vector3(500, -1250, 380), "h": Vector2(2.0, 200.0), "flat": 16.0, "r": 36.0,
		"guards": [[&"skitter", 4], [&"popper", 1]], "sentries": 0, "reward": 450, "tag": "DESTROY THE HIVE HEART"},
	{"id": &"crash", "name": "ALIEN CRASH SITE", "kind": &"crash", "reuse": &"crash", "r": 46.0, "guards": [[&"hive_grunt", 2], [&"acid_spitter", 1]], "sentries": 2, "boss": &"hive_warden", "relays": 3,
		"reward": 800, "tag": "BREAK THE SHIELD  FACE THE WARDEN"},
	{"id": &"crash_peak", "name": "PEAK WRECK", "kind": &"crash", "biomes": [&"mountain"], "region": Vector3(900, -2200, 420), "h": Vector2(80.0, 300.0), "flat": 12.0, "r": 38.0,
		"guards": [[&"hive_grunt", 2], [&"shade_stalker", 2], [&"acid_spitter", 1]], "sentries": 2, "reward": 550, "tag": "SALVAGE THE WRECK"},
	{"id": &"crash_shore", "name": "SHORE WRECK", "kind": &"crash", "biomes": [&"beach", &"plains"], "region": Vector3(-1500, 1350, 320), "h": Vector2(0.5, 60.0), "flat": 12.0, "r": 38.0,
		"guards": [[&"popper", 2], [&"skitter", 3]], "sentries": 1, "reward": 500, "tag": "SALVAGE THE WRECK"},
	{"id": &"lair_forest", "name": "BROODMOTHER LAIR", "kind": &"lair", "biomes": [&"forest"], "region": Vector3(-1000, -1450, 360), "h": Vector2(2.0, 200.0), "flat": 18.0, "r": 60.0,
		"guards": [[&"skitter", 3]], "sentries": 0, "boss": &"broodmother", "reward": 900, "tag": "THE FOREST BROODMOTHER"},
	{"id": &"lair_peak", "name": "STORM DRAKE ROOST", "kind": &"lair", "biomes": [&"mountain"], "region": Vector3(-250, -2500, 420), "h": Vector2(100.0, 320.0), "flat": 12.0, "r": 60.0,
		"guards": [], "sentries": 0, "boss": &"storm_drake", "reward": 900, "tag": "THE STORM DRAKE"},
	{"id": &"lair_dunes", "name": "LEVIATHAN DUNES", "kind": &"lair", "biomes": [&"desert"], "region": Vector3(1850, 250, 360), "h": Vector2(2.0, 200.0), "flat": 18.0, "r": 60.0,
		"guards": [], "sentries": 0, "boss": &"sand_leviathan", "reward": 950, "tag": "THE SAND LEVIATHAN"},
	{"id": &"lair_deep", "name": "KRAKEN DEEPS", "kind": &"lair", "biomes": [&"ocean"], "region": Vector3(-100, 2250, 340), "h": Vector2(-60.0, -8.0), "flat": 0.0, "r": 70.0,
		"guards": [], "sentries": 0, "boss": &"deep_kraken", "reward": 950, "tag": "THE DEEP KRAKEN"},
]

static var built := false
static var list: Array[Dictionary] = []                  ## per site: the DEF plus pos (Vector3, ground height), yaw, found (placement quality)
static var cleared := {}                                 ## site id -> true
static var bosses_down := {}                             ## boss id -> true
static var _loaded := false
static var _task := -1


## Starts the placement search on a worker thread (about 0.6 s of terrain sampling: never on the frame that opens the map or loads the city). `ready_now()` says when it is done.
static func start() -> void:
	if built or _task != -1:
		return
	TerrainHeight.warm()                                      # main thread, once (the terrain needs it anyway)
	OutskirtsSites.ensure()
	_task = WorkerThreadPool.add_task(_build)


## True when the sites exist (finishes the worker task if it is done).
static func ready_now() -> bool:
	if built:
		return true
	if _task != -1 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	return built


## Blocking version (tests, mission hooks): waits for the worker or builds on the spot.
static func ensure() -> void:
	if built:
		return
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if built:
			return
	TerrainHeight.warm()
	OutskirtsSites.ensure()
	_build()


static func _build() -> void:
	if built:
		return
	var tmp: Array[Dictionary] = []
	var placed: Array[Vector2] = []
	for d in DEFS:
		var s: Dictionary = d.duplicate()
		var c := Vector2.ZERO
		var found := true
		if d.has("reuse"):
			s["no_mesh"] = true                                      # the existing crash site (OutskirtsKit) already has its wreck
			var os := OutskirtsSites.by_id(StringName(d["reuse"]))
			if os.is_empty():
				continue
			c = Vector2((os["pos"] as Vector3).x, (os["pos"] as Vector3).z)
		else:
			var res := _find(d, placed)
			c = res["pos"]
			found = bool(res["ok"])
		placed.append(c)
		var y := TerrainHeight.height_at(c.x, c.y)
		if StringName(d["kind"]) == &"lair" and (d["biomes"] as Array).has(&"ocean"):
			y = TerrainHeight.SEA_LEVEL
		s["pos"] = Vector3(c.x, y, c.y)
		s["yaw"] = _hash01(String(d["id"])) * TAU
		s["found"] = found
		tmp.append(s)
	list = tmp
	built = true


static func _hash01(s: String) -> float:
	return float(absi(s.hash()) % 100000) / 100000.0


## The search: rings around the region centre, nearest first, 16 angles per ring; the first candidate that passes every rule wins, else the best-scoring one.
static func _find(d: Dictionary, placed: Array[Vector2]) -> Dictionary:
	var reg: Vector3 = d["region"]
	var biomes: Array = d["biomes"]
	var hr: Vector2 = d["h"]
	var flat := float(d["flat"])
	var ocean: bool = biomes.has(&"ocean")
	var best := Vector2(reg.x, reg.y)
	var best_score := 1.0e9
	var r := 0.0
	while r <= reg.z:
		var n := 1 if r < 1.0 else 16
		for k in n:
			var a := TAU * float(k) / float(n) + r * 0.013
			var p := Vector2(reg.x + cos(a) * r, reg.y + sin(a) * r)
			var score := _score(p, biomes, hr, flat, placed, ocean)
			if score < 0.0:
				continue
			if score < best_score:
				best_score = score
				best = p
			if score < 0.35:
				return {"pos": p, "ok": true}
		r += 36.0
	return {"pos": best, "ok": best_score < 1.0e8}


## < 0 = rejected, else a badness (0 perfect flat ground, grows with the relief and the distance to other sites).
static func _score(p: Vector2, biomes: Array, hr: Vector2, flat: float, placed: Array[Vector2], ocean: bool) -> float:
	if maxf(absf(p.x), absf(p.y)) < CITY_SKIRT or maxf(absf(p.x), absf(p.y)) > TerrainHeight.WORLD_HALF - 120.0:
		return -1.0
	var h := TerrainHeight.height_at(p.x, p.y)
	if h < hr.x or h > hr.y:
		return -1.0
	var biome := TerrainBase.biome_at(p.x, p.y, h)
	if not biomes.has(biome):
		return -1.0
	for q in placed:
		if q.distance_to(p) < 260.0:
			return -1.0
	if ocean:
		var depth := TerrainHeight.depth_at(p.x, p.y)
		return 0.1 if depth > 12.0 else -1.0
	if OutskirtsSites.inside(p.x, p.y, 70.0) >= 0:
		return -1.0
	var w := TerrainHeight.water_level_for(p.x, p.y, h)
	if w != TerrainHeight.NO_WATER:
		return -1.0
	if absf(h - TerrainBase.height(p.x, p.y)) > 0.8:                  # a road bench, a river bed, a pad: not here
		return -1.0
	var lo := h
	var hi := h
	for k in 8:
		var a := TAU * float(k) / 8.0
		var qx := p.x + cos(a) * flat
		var qy := p.y + sin(a) * flat
		var hh := TerrainHeight.height_at(qx, qy)
		if TerrainHeight.water_level_for(qx, qy, hh) != TerrainHeight.NO_WATER or absf(hh - TerrainBase.height(qx, qy)) > 1.5:
			return -1.0
		lo = minf(lo, hh)
		hi = maxf(hi, hh)
	var relief := hi - lo
	return relief / maxf(flat * 0.5, 1.0)


# --- queries ---------------------------------------------------------------------------------------------------------------------------------------

static func by_id(id: StringName) -> Dictionary:
	ensure()
	for s in list:
		if s["id"] == id:
			return s
	return {}


static func of_kind(kind: StringName) -> Array[Dictionary]:
	ensure()
	var out: Array[Dictionary] = []
	for s in list:
		if s["kind"] == kind:
			out.append(s)
	return out


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


## World position of a point in a site's local frame (x right, z back, y up from the ground at that point): the kit is built in this frame and turned by the yaw.
static func to_world(s: Dictionary, local: Vector3) -> Vector3:
	var p: Vector3 = s["pos"]
	var w := Basis(Vector3.UP, float(s["yaw"])) * local
	var x := p.x + w.x
	var z := p.z + w.z
	return Vector3(x, TerrainHeight.height_at(x, z) + local.y, z)


static func is_cleared(id: StringName) -> bool:
	_load()
	return bool(cleared.get(id, false))


static func mark_cleared(id: StringName) -> void:
	_load()
	cleared[id] = true
	save()


static func boss_down(boss: StringName) -> bool:
	_load()
	return bool(bosses_down.get(boss, false))


static func mark_boss(boss: StringName) -> void:
	_load()
	bosses_down[boss] = true
	save()


static func cleared_count() -> int:
	_load()
	return cleared.size()


static func reset_all() -> void:
	cleared.clear()                                          
	bosses_down.clear()
	_loaded = true
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	if cf.has_section("cleared"):
		cf.erase_section("cleared")
	if cf.has_section("bosses"):
		cf.erase_section("bosses")
	cf.save(SAVE_PATH)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	if cf.has_section("cleared"):
		for k in cf.get_section_keys("cleared"):
			cleared[StringName(k)] = bool(cf.get_value("cleared", k, false))
	if cf.has_section("bosses"):
		for k in cf.get_section_keys("bosses"):
			bosses_down[StringName(k)] = bool(cf.get_value("bosses", k, false))


static func save() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	for k: StringName in cleared:
		cf.set_value("cleared", String(k), true)
	for k: StringName in bosses_down:
		cf.set_value("bosses", String(k), true)
	cf.save(SAVE_PATH)


## The pins of the big map (kind `danger`: a red alien glyph) and the mission hooks: {id, kind, name, pos, r, reward, tag, boss}.
static func map_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not ready_now():                                       # never block the map: the pins come when the worker is done
		start()
		return out
	for s in list:
		if is_cleared(s["id"]):
			continue
		out.append({"kind": &"site", "pos": s["pos"], "fog": false, "label": String(s["name"]), "alien": true})
	return out


static func hooks() -> Array[Dictionary]:
	ensure()
	var out: Array[Dictionary] = []
	for s in list:
		out.append({"id": s["id"], "kind": s["kind"], "name": s["name"], "pos": s["pos"], "r": float(s["r"]), "reward": s["reward"], "tag": s["tag"], "boss": s.get("boss", &""), "cleared": is_cleared(s["id"])})
	return out
