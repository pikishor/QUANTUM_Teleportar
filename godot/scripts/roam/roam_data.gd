class_name RoamData
extends RefCounted
## WHERE THE FREE-ROAM WORLD HIDES THINGS (wave 111; docs/DESIGN.md "side activities, races, events -> optional open-world fun with markers; rewards feed weapons"). Pure data and terrain
## queries, no nodes, deterministic (same world, same places), so tests and the map can ask without the game running. Everything is derived from the finished terrain, the roads, the
## outskirt sites, the harbour, the airport and the rivers, so it follows them wherever they are built.
##   pads()         QUANTUM PADS (fast travel): the city hub, the airport, the harbour quay and the camps; found by driving or walking up to one, then every found pad is a destination
##   relics()       24 hidden SIGNAL RELICS in all five outskirt biomes (the scanner pulse shows them; walking up to one picks it up)
##   photo_spots()  eight views with a time of day (NIGHT SKY at the observatory, SUNSET at the lighthouse ...); a photo taken from the ring counts
##   fish_spots()   six places to fish (lake, river, sea, pier) and `FISH`: eight species that bite by water and time of day
##   stunts()       five stunt ramps on the outskirt roads (a ramp, a landing ring 40 m on)
##   races()        five landmark races along the real roads (start ring, checkpoints, finish ring, par time)
##   HUNTS          the eight animals of the hunt log
##   RIDES          vehicles that wait on a pad once enough has been discovered (the reward ladder)
## `total()` is the discovery counter's denominator.

const HUNTS: Array[StringName] = [&"deer", &"goat", &"boar", &"wolf", &"coyote", &"fox", &"zebra", &"eagle"]
const EVENT_KINDS: Array[StringName] = [&"convoy", &"crash", &"raid", &"smugglers"]

const RELIC_QUOTA := {&"mountain": 6, &"forest": 5, &"desert": 5, &"plains": 4, &"beach": 4}
const RELIC_NAMES := {&"mountain": "SUMMIT RELIC", &"forest": "FOREST RELIC", &"desert": "DUNE RELIC", &"plains": "FIELD RELIC", &"beach": "SHORE RELIC"}
const RELIC_SEP := 240.0                    ## no two relics closer than this
const RELIC_SEED := 31337

## Fast-travel pads: id, name, kind (where the position comes from), site id for the camps, local offset from the site
const PAD_DEFS: Array[Dictionary] = [
	{"id": &"hub", "name": "CITY HUB", "kind": &"hub"},
	{"id": &"airport", "name": "EASTFIELD AIRPORT", "kind": &"airport"},
	{"id": &"harbour", "name": "HARBOUR QUAY", "kind": &"harbour"},
	{"id": &"observatory", "name": "OBSERVATORY CAMP", "kind": &"site", "site": &"observatory", "off": Vector3(18.0, 0.0, 14.0)},
	{"id": &"lodge", "name": "LAKESIDE CAMP", "kind": &"site", "site": &"lodge", "off": Vector3(-16.0, 0.0, 12.0)},
	{"id": &"radio_tower", "name": "RADIO TOWER CAMP", "kind": &"site", "site": &"radio_tower", "off": Vector3(14.0, 0.0, 12.0)},
	{"id": &"hunters", "name": "HUNTERS CAMP", "kind": &"site", "site": &"hunters", "off": Vector3(16.0, 0.0, 14.0)},
	{"id": &"dust_wells", "name": "DUST WELLS CAMP", "kind": &"site", "site": &"dust_wells", "off": Vector3(26.0, 0.0, 20.0)},
	{"id": &"pine_hollow", "name": "PINE HOLLOW CAMP", "kind": &"site", "site": &"pine_hollow", "off": Vector3(-24.0, 0.0, 22.0)},
]

## Photo spots: id, name, site (or special), local offset, when (any / day / dusk / night), radius
const PHOTO_DEFS: Array[Dictionary] = [
	{"id": &"ph_observatory", "name": "NIGHT SKY", "site": &"observatory", "off": Vector3(-26.0, 0.0, 20.0), "when": &"night", "r": 60.0},
	{"id": &"ph_lighthouse", "name": "SUNSET LIGHT", "site": &"", "at": Vector2(372.0, 1612.0), "when": &"dusk", "r": 60.0},
	{"id": &"ph_bridge", "name": "HARBOUR GATE", "site": &"", "at": Vector2(60.0, 1604.0), "when": &"any", "r": 70.0},
	{"id": &"ph_airport", "name": "THE APRON", "site": &"", "kind": &"airport", "when": &"any", "r": 70.0},
	{"id": &"ph_lodge", "name": "MIRROR LAKE", "site": &"lodge", "off": Vector3(46.0, 0.0, 36.0), "when": &"day", "r": 60.0},
	{"id": &"ph_crash", "name": "ALIEN WRECK", "site": &"crash", "off": Vector3(60.0, 0.0, 10.0), "when": &"any", "r": 70.0},
	{"id": &"ph_dust", "name": "DUNE SUNSET", "site": &"dust_wells", "off": Vector3(-60.0, 0.0, 30.0), "when": &"dusk", "r": 70.0},
	{"id": &"ph_tower", "name": "ABOVE THE CLOUDS", "site": &"radio_tower", "off": Vector3(-24.0, 0.0, -18.0), "when": &"day", "r": 60.0},
]

## Fish: id, name, the water it lives in (lake / river / sea), when it bites (any / day / dusk / night), pay, rare (a lucky catch)
const FISH: Dictionary = {
	&"trout": {"name": "RIVER TROUT", "water": [&"river"], "when": &"any", "pay": 35, "w": 3.0},
	&"eel": {"name": "SILVER EEL", "water": [&"river"], "when": &"night", "pay": 80, "w": 2.0},
	&"carp": {"name": "LAKE CARP", "water": [&"lake"], "when": &"day", "pay": 40, "w": 3.0},
	&"glowfin": {"name": "GLOWFIN", "water": [&"lake"], "when": &"night", "pay": 130, "w": 2.0},
	&"koi": {"name": "GOLD KOI", "water": [&"lake", &"river"], "when": &"dusk", "pay": 110, "w": 2.0},
	&"mackerel": {"name": "MACKEREL", "water": [&"sea"], "when": &"any", "pay": 30, "w": 3.0},
	&"tuna": {"name": "BLUEFIN TUNA", "water": [&"sea"], "when": &"day", "pay": 90, "w": 1.5},
	&"moonfish": {"name": "MOONFISH", "water": [&"sea"], "when": &"night", "pay": 140, "w": 2.0},
}

## The reward ladder: discoveries needed, the vehicle that then waits on the pad (VehicleSpawns.all_points), and what it is called on the toast
const RIDES: Array[Dictionary] = [
	{"need": 6, "kind": &"hoverbike", "pad": &"hub", "label": "HOVER BIKE"},
	{"need": 12, "kind": &"rover", "pad": &"observatory", "label": "MOUNTAIN ROVER"},
	{"need": 20, "kind": &"apc", "pad": &"harbour", "label": "ARMOURED CARRIER"},
	{"need": 28, "kind": &"gunship", "pad": &"airport", "label": "GUNSHIP"},
	{"need": 38, "kind": &"ltank", "pad": &"dust_wells", "label": "LIGHT TANK"},
	{"need": 50, "kind": &"jet", "pad": &"airport", "label": "JET FIGHTER"},
]
## Every N discoveries the next finished mission reward (weapon ladder) is handed out
const LADDER_EVERY := 5

## Stunt ramps on the outskirt roads: road, fraction of the way along it to start looking
const STUNT_DEFS: Array[Dictionary] = [
	{"id": &"st_forest", "name": "FOREST JUMP", "road": "FOREST ROAD", "f": 0.35},
	{"id": &"st_desert", "name": "DUNE JUMP", "road": "DESERT ROAD", "f": 0.45},
	{"id": &"st_coast", "name": "COAST JUMP", "road": "COAST ROAD", "f": 0.40},
	{"id": &"st_pass", "name": "PASS JUMP", "road": "PASS ROAD", "f": 0.25},
	{"id": &"st_quarry", "name": "QUARRY JUMP", "road": "QUARRY TRACK", "f": 0.50},
]
const STUNT_LAND := 32.0                    ## from the ramp's high end to the centre of the landing ring (FreedomData.JUMP_DIST)
const STUNT_RING := 18.0

## Landmark races: the road they run along, and the two places that are named in the title
const RACE_DEFS: Array[Dictionary] = [
	{"id": &"rc_desert", "name": "CITY TO DUST WELLS", "road": "DESERT ROAD", "pay": 360},
	{"id": &"rc_coast", "name": "CITY TO THE COAST", "road": "COAST ROAD", "pay": 360},
	{"id": &"rc_forest", "name": "CITY TO PINE HOLLOW", "road": "FOREST ROAD", "pay": 360},
	{"id": &"rc_pass", "name": "THE MOUNTAIN PASS", "road": "PASS ROAD", "pay": 380},
	{"id": &"rc_summit", "name": "SUMMIT CLIMB", "road": "SUMMIT ROAD", "pay": 420},
]
const RACE_SPEED := 22.0                    ## m/s the par time assumes
const RACE_LIMIT_X := 2.4
const RACE_GATE_EVERY := 300.0

static var _built := false
static var _pads: Array[Dictionary] = []
static var _relics: Array[Dictionary] = []
static var _photos: Array[Dictionary] = []
static var _fish: Array[Dictionary] = []
static var _stunts: Array[Dictionary] = []
static var _races: Array[Dictionary] = []


## Builds every list once (the terrain, the water layout and the sites have to be there).
static func ensure() -> void:
	if _built:
		return
	TerrainHeight.warm()
	TerrainBase.warm()
	WaterLayout.ensure()
	OutskirtsSites.ensure()
	_pads = _build_pads()
	_relics = _build_relics()
	_photos = _build_photos()
	_fish = _build_fish()
	_stunts = _build_stunts()
	_races = _build_races()
	_built = true


static func forget() -> void:
	_built = false


static func pads() -> Array[Dictionary]:
	ensure()
	return _pads


static func relics() -> Array[Dictionary]:
	ensure()
	return _relics


static func photo_spots() -> Array[Dictionary]:
	ensure()
	return _photos


static func fish_spots() -> Array[Dictionary]:
	ensure()
	return _fish


static func stunts() -> Array[Dictionary]:
	ensure()
	return _stunts


static func races() -> Array[Dictionary]:
	ensure()
	return _races


static func pad(id: StringName) -> Dictionary:
	for p in pads():
		if p["id"] == id:
			return p
	return {}


## The discovery counter's denominator: pads + relics + photos + fish species + hunted animals + stunts + races + event kinds.
static func total() -> int:
	return pads().size() + relics().size() + photo_spots().size() + FISH.size() + HUNTS.size() + stunts().size() + races().size() + EVENT_KINDS.size()


static func ground(x: float, z: float) -> Vector3:
	return Vector3(x, TerrainHeight.height_at(x, z), z)


## The hour of day the roam rules see: the test override, else the city's clock (12 when the world has none).
static var hour_override := -1.0


static func hour_now() -> float:
	if hour_override >= 0.0:
		return hour_override
	var h := Sfx.hour_now()
	return h if h >= 0.0 else 12.0


## Time-of-day word of an hour: "day" 7..17.5, "dusk" 17.5..20 and 5..7, "night" otherwise.
static func phase_of(h: float) -> StringName:
	h = fposmod(h, 24.0)
	if h >= 7.0 and h < 17.5:
		return &"day"
	if (h >= 17.5 and h < 20.0) or (h >= 5.0 and h < 7.0):
		return &"dusk"
	return &"night"


## Whether a `when` rule (any / day / dusk / night) holds at hour `h`.
static func when_ok(when: StringName, h: float) -> bool:
	return when == &"any" or when == phase_of(h)


# --- pads -----------------------------------------------------------------------------------------------------------------------------

static func _build_pads() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in PAD_DEFS:
		var p := Vector3.INF
		match StringName(d["kind"]):
			&"hub":
				var j := FreedomData.junction(Vector2i(8, 8))
				p = Vector3(j.x + 7.0, 0.0, j.z - 7.0)
			&"airport":
				p = Airport.to_world(Vector3(1188.0, 0.0, -560.0))            # the open apron south of the last gate, clear of the parked airliners and the terminal's canopy
			&"harbour":
				p = Vector3(-282.0, 0.0, 1360.0)
			&"site":
				var s := OutskirtsSites.by_id(StringName(d["site"]))
				if not s.is_empty():
					p = OutskirtsSites.to_world(s, d["off"] as Vector3)
		if not p.is_finite():
			continue
		var e: Dictionary = d.duplicate()
		e["pos"] = ground(p.x, p.z)
		out.append(e)
	return out


# --- relics ---------------------------------------------------------------------------------------------------------------------------

static func _build_relics() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var need: Dictionary = RELIC_QUOTA.duplicate()
	var left := 0
	for k in need:
		left += int(need[k])
	var rng := RandomNumberGenerator.new()
	rng.seed = RELIC_SEED
	var keep_away: Array[Vector3] = []
	for s in OutskirtsSites.list:
		keep_away.append(s["pos"])
	var ap := WorldSites.airport()
	keep_away.append(ap["gate"])
	keep_away.append(Harbour.center())
	var tries := 0
	while left > 0 and tries < 9000:
		tries += 1
		var x := rng.randf_range(-2750.0, 2750.0)
		var z := rng.randf_range(-2750.0, 2750.0)
		var h := TerrainHeight.height_at(x, z)
		var biome := TerrainBase.biome_at(x, z, h)
		if int(need.get(biome, 0)) <= 0:
			continue
		if TerrainHeight.depth_at(x, z) > 0.0 or TerrainHeight.slope_at(x, z) > 0.4:
			continue
		var p := Vector3(x, h, z)
		var ok := true
		for q in keep_away:
			if Vector2(q.x - x, q.z - z).length() < 260.0:
				ok = false
				break
		if not ok:
			continue
		for e in out:
			var ep: Vector3 = e["pos"]
			if Vector2(ep.x - x, ep.z - z).length() < RELIC_SEP:
				ok = false
				break
		if not ok:
			continue
		need[biome] = int(need[biome]) - 1
		left -= 1
		out.append({"id": StringName("relic_%d" % out.size()), "name": String(RELIC_NAMES[biome]), "biome": biome, "pos": p})
	return out


# --- photo spots ----------------------------------------------------------------------------------------------------------------------

static func _build_photos() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	Bridges.ensure()
	for d in PHOTO_DEFS:
		var p := Vector3.INF
		if StringName(d.get("kind", &"")) == &"airport":
			p = Airport.to_world(Vector3(1172.0, 0.0, -540.0))
		elif d.has("at"):
			var a: Vector2 = d["at"]
			p = Vector3(a.x, 0.0, a.y)
		else:
			var s := OutskirtsSites.by_id(StringName(d["site"]))
			if not s.is_empty():
				p = OutskirtsSites.to_world(s, d["off"] as Vector3)
		if not p.is_finite():
			continue
		var e: Dictionary = d.duplicate()
		var y := TerrainHeight.height_at(p.x, p.z)
		if d["id"] == &"ph_bridge":
			var dy := Bridges.deck_y(p.x, p.z, 12.0)
			if dy > -1.0e8 and dy < 1.0e8:
				y = dy
		e["pos"] = Vector3(p.x, y, p.z)
		out.append(e)
	return out


# --- fishing --------------------------------------------------------------------------------------------------------------------------

## A dry point near (cx, cz) with water 7 and 11 m away: {pos, cast (the direction to the water, unit xz)}; {} when there is none within `rmax`.
static func shore_near(cx: float, cz: float, rmax: float) -> Dictionary:
	var r := 0.0
	while r <= rmax:
		var n := maxi(int(TAU * r / 14.0), 1) if r > 0.0 else 1
		for k in n:
			var a := TAU * float(k) / float(n) + r * 0.37
			var x := cx + cos(a) * r
			var z := cz + sin(a) * r
			if TerrainHeight.depth_at(x, z) > 0.0 or TerrainHeight.slope_at(x, z) > 0.6:
				continue
			for dk in 12:
				var da := TAU * float(dk) / 12.0
				var dv := Vector2(cos(da), sin(da))
				if TerrainHeight.depth_at(x + dv.x * 7.0, z + dv.y * 7.0) > 0.12 and TerrainHeight.depth_at(x + dv.x * 11.0, z + dv.y * 11.0) > 0.12:
					return {"pos": ground(x, z), "cast": Vector3(dv.x, 0.0, dv.y)}
		r += 14.0
	return {}


static func _build_fish() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var centres: Array[Dictionary] = []
	var lodge := OutskirtsSites.by_id(&"lodge")
	if not lodge.is_empty():
		centres.append({"id": &"fs_mirror", "name": "MIRROR LAKE", "water": &"lake", "c": Vector2((lodge["pos"] as Vector3).x, (lodge["pos"] as Vector3).z), "rmax": 320.0})
	centres.append({"id": &"fs_quarry", "name": "QUARRY LAKE", "water": &"lake", "c": (WaterLayout.LAKES[1] as Dictionary)["c"], "rmax": 220.0})
	var east := WorldSites.river_route(1, 0, 40, 60.0)
	if east.size() > 4:
		var m := east[east.size() / 2]
		centres.append({"id": &"fs_eastwater", "name": "EASTWATER BANK", "water": &"river", "c": Vector2(m.x, m.z), "rmax": 160.0})
	var high := WorldSites.river_route(0, 0, 60, 60.0)
	if high.size() > 4:
		var m2 := high[high.size() / 2]
		centres.append({"id": &"fs_highline", "name": "HIGHLINE BANK", "water": &"river", "c": Vector2(m2.x, m2.z), "rmax": 160.0})
	centres.append({"id": &"fs_beach", "name": "SOUTH-WEST SHORE", "water": &"sea", "c": Vector2(-1500.0, 650.0), "rmax": 700.0})
	for c in centres:
		var cc: Vector2 = c["c"]
		var s := shore_near(cc.x, cc.y, float(c["rmax"]))
		if s.is_empty():
			continue
		var e: Dictionary = c.duplicate()
		e["pos"] = s["pos"]
		e["cast"] = s["cast"]
		out.append(e)
	# the harbour pier (always there): the end of the middle pier looks east over the basin
	out.append({"id": &"fs_pier", "name": "HARBOUR PIER", "water": &"sea", "pos": Vector3(Harbour.PIER_X[1] + 3.2, Harbour.QUAY_Y, Harbour.PIER_Z1 - 5.0), "cast": Vector3(0.0, 0.0, 1.0)})
	return out


## The species that bite in `water` at hour `h`: [[id, weight], ...] (a species of another time of day is left out).
static func fish_weights(water: StringName, h: float) -> Array:
	var out: Array = []
	for id: StringName in FISH:
		var f: Dictionary = FISH[id]
		if (f["water"] as Array).has(water) and when_ok(StringName(f["when"]), h):
			out.append([id, float(f["w"])])
	return out


# --- stunts and races -----------------------------------------------------------------------------------------------------------------

static func _build_stunts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in STUNT_DEFS:
		var route := WorldSites.road_route(String(d["road"]))
		if route.size() < 8:
			continue
		var pf := PathFollow.new(route)
		var s := pf.total * float(d["f"])
		var found := false
		var steps := 0
		while steps < 80 and s < pf.total - 120.0:
			steps += 1
			if _stunt_ok(pf, s):
				found = true
				break
			s += 25.0
		if not found:
			s = pf.total * float(d["f"])
		var pos := pf.point_at(s)
		var dir := pf.dir_at(s)
		dir = Vector3(dir.x, 0.0, dir.z).normalized()
		var land := pos + dir * (FreedomData.RAMP_LEN + STUNT_LAND)
		out.append({"id": d["id"], "name": String(d["name"]), "pos": Vector3(pos.x, TerrainHeight.height_at(pos.x, pos.z), pos.z), "dir": dir, "yaw": atan2(-dir.x, -dir.z),
				"land": Vector3(land.x, TerrainHeight.height_at(land.x, land.z), land.z), "road": String(d["road"]), "ok": found})
	return out


## A straight, dry, level stretch of road from 14 m before the ramp to 14 m beyond the landing ring.
static func _stunt_ok(pf: PathFollow, s: float) -> bool:
	var a := s - 14.0
	var b := s + FreedomData.RAMP_LEN + STUNT_LAND + 14.0
	if a < 0.0 or pf.bend_ahead(a, b - a) > 0.12:
		return false
	var h0 := pf.point_at(a).y
	var k := a
	while k <= b:
		var q := pf.point_at(k)
		if TerrainHeight.depth_at(q.x, q.z) > 0.0 or absf(q.y - h0) > 2.6:
			return false
		k += 10.0
	return true


static func _build_races() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in RACE_DEFS:
		var route := WorldSites.road_route(String(d["road"]))
		if route.size() < 8:
			continue
		var pf := PathFollow.new(route)
		var len := pf.total
		var n := clampi(int(len / RACE_GATE_EVERY), 3, 14)
		var gates: Array[Vector3] = []
		for k in n:
			var q := pf.point_at(len * float(k + 1) / float(n))
			gates.append(Vector3(q.x, q.y + 1.0, q.z))
		var st := pf.point_at(18.0)
		var par := len / RACE_SPEED
		out.append({"id": d["id"], "name": String(d["name"]), "road": String(d["road"]), "start": Vector3(st.x, st.y, st.z), "gates": gates, "length": len,
				"par": par, "limit": par * RACE_LIMIT_X, "pay": int(d["pay"]), "heading": atan2(-pf.dir_at(18.0).x, -pf.dir_at(18.0).z)})
	return out


## Pay of a race by time: base + 5 per second under par.
static func race_pay(base: int, par: float, secs: float) -> int:
	return base + int(maxf(par - secs, 0.0)) * 5


# --- the reward ladder ----------------------------------------------------------------------------------------------------------------

## Vehicle spawn points of the rides that were handed out so far (`unlocked` = how many of RIDES), at their pads: VehicleSpawns appends these.
static func ride_points(unlocked: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if unlocked <= 0:
		return out
	for i in mini(unlocked, RIDES.size()):
		var r: Dictionary = RIDES[i]
		var p := pad(StringName(r["pad"]))
		if p.is_empty():
			continue
		var pp: Vector3 = p["pos"]
		var side := 1.0 if i % 2 == 0 else -1.0
		var kind := StringName(r["kind"])
		var off := Vector3(side * 12.0, 0.0, 6.0)
		if VehicleSpecs.AIRCRAFT_KINDS.has(kind) or kind == &"ltank":
			off = Vector3(side * 26.0, 0.0, 14.0)
		var q := pp + off
		out.append({"id": StringName("roam_ride_%d" % i), "kind": kind, "pos": Vector3(q.x, TerrainHeight.height_at(q.x, q.z), q.z), "h": 0.0, "label": String(r["label"])})
	return out
