class_name AirMissions
extends RefCounted
## THE AIR MISSIONS of the Mission Board (wave 126, w126-air; plan line 126). Six missions flown from EASTFIELD AIRPORT, each a chapter of campaign steps like every board mission (checkpoint at
## every step, instant retry, objective line, beacon, MissionGuide), built from WorldSteps' `reach` with a vehicle, `gates`, and the new `air_task` of AirSteps:
##   DOGFIGHT          take the jet off the strip, shoot down the bandits circling over the east plain (guns, or missiles: hold the target in the seeker until LOCKED), fly back to the field
##   AIRLINER ESCORT   take the jet, meet the airliner on its climb-out and keep the raiders off it until it is through the danger zone
##   BOMB RUN          take the jet (its BOMB arm is selected), bomb the armoured column parked at a field, fly back
##   CARGO DROP        take the cargo plane, drop the crates (the DROP arm) inside the ring at a farm field
##   HELI RESCUE       take the rescue helicopter, land at the stranded climbers' pad, hold still while they board, fly them to the HOSPITAL pad and land
##   SKY RINGS         take the stunt plane through the rings over the airport
## Offered by location: the hero within NEAR of the airport gets one for sure (in turn), from anywhere now and then (INJECT_CHANCE), like the world missions. Pure data, no nodes.
## W126A_OLD=1 (or AirMissions.on = false): the wave 125 board (no air missions).

const TYPES: Array[StringName] = [&"air_dogfight", &"air_escort", &"air_bomb", &"air_cargo", &"air_rescue", &"air_rings"]
const NEAR := 1400.0
const INJECT_CHANCE := 0.3
const RING_R := 22.0
const DEFS := {
	&"air_dogfight": {"title": "DOGFIGHT", "brief": "Take the jet up and shoot down the bandits.", "base": 480, "weight": 3, "glyph": &"target"},
	&"air_escort": {"title": "AIRLINER ESCORT", "brief": "Keep the raiders off the airliner until it is clear.", "base": 520, "weight": 3, "glyph": &"shield"},
	&"air_bomb": {"title": "BOMB RUN", "brief": "Bomb the armoured column at the field.", "base": 460, "weight": 3, "glyph": &"blast"},
	&"air_cargo": {"title": "CARGO DROP", "brief": "Fly the cargo plane and drop the crates in the ring.", "base": 420, "weight": 3, "glyph": &"dest"},
	&"air_rescue": {"title": "HELI RESCUE", "brief": "Fly the rescue helicopter to the climbers and bring them to the hospital.", "base": 450, "weight": 3, "glyph": &"person"},
	&"air_rings": {"title": "SKY RINGS", "brief": "Fly the stunt plane through the rings over the airport.", "base": 380, "weight": 3, "glyph": &"dest"},
}

static var on := OS.get_environment("W126A_OLD") != "1"
static var _turn := 0


static func _s(kind: String, text: String, extra := {}) -> Dictionary:
	var d := {"kind": kind, "text": text, "quiet": true}
	d.merge(extra, true)
	return d


static func _h(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


## A point of the airport's frame (local x, height above the ground, local z) in the world, at least `clear` metres over the terrain under it.
static func air_point(lx: float, agl: float, lz: float, clear := 60.0) -> Vector3:
	var w := Airport.to_world(Vector3(lx, 0.0, lz))
	var g := TerrainHeight.height_at(w.x, w.z) if (absf(w.x) > TerrainHeight.CITY_HALF or absf(w.z) > TerrainHeight.CITY_HALF) else 0.0
	return Vector3(w.x, g + maxf(agl, clear), w.z)


static func site_of(t: StringName, origin: Vector3) -> Vector3:
	if not DEFS.has(t):
		return Vector3.INF
	var ap := WorldSites.airport()
	if t == &"air_rescue":
		return ap["heli"]
	return ap["strip"]


static func eligible(t: StringName, origin := Vector3.ZERO) -> bool:
	if not on or not DEFS.has(t):
		return false
	if OutskirtsSites.list.is_empty():
		OutskirtsSites.ensure()
	if OutskirtsSites.list.is_empty():
		return false
	return site_of(t, origin).is_finite() and bool(WorldSites.airport()["real"])


## The board's picks with an air mission worked in: one replaces the first pick when the hero is near the airport (the six in turn), or now and then from anywhere.
static func inject(picks: Array[StringName], origin: Vector3, rng: RandomNumberGenerator) -> Array[StringName]:
	if not on or picks.is_empty():
		return picks
	for p in picks:
		if DEFS.has(p):
			return picks
	var ap := WorldSites.airport()
	if not bool(ap["real"]):
		return picks
	var near := _h(origin, ap["strip"]) <= NEAR
	if not near and rng.randf() > INJECT_CHANCE:
		return picks
	var t: StringName = TYPES[_turn % TYPES.size()]
	_turn += 1
	if not eligible(t, origin):
		return picks
	var out: Array[StringName] = picks.duplicate()
	out[0] = t
	return out


static func _provide_strip(kind: String, text: String, ap: Dictionary) -> Dictionary:
	return _s("reach", text, {"pos": ap["strip"], "radius": 18.0, "veh": "plane", "provide": kind, "provide_at": ap["strip"], "provide_h": float(ap["strip_h"])})


## The steps of mission `t` (every goal placed); [] when the world cannot hold it.
static func steps(t: StringName, tier: int, origin: Vector3, r: RandomNumberGenerator) -> Array[Dictionary]:
	var g := clampi(tier, 0, 3)
	var ap := WorldSites.airport()
	var out: Array[Dictionary] = []
	if not bool(ap["real"]):
		return out
	var strip: Vector3 = ap["strip"]
	var home := air_point(Airport.RUNWAY_X, 90.0, -500.0)
	match t:
		&"air_dogfight":
			var zone := air_point(1520.0, 200.0, -1000.0, 140.0)
			out = [
				_provide_strip("jet", "GET IN THE JET", ap),
				_s("air_task", "SHOOT DOWN THE BANDITS", {"pos": zone, "task": "dogfight", "n": 2 + (g / 2), "bandit": "jet", "hp": 150.0, "veh": "air", "time": 420.0}),
				_s("reach", "FLY BACK TO THE AIRPORT", {"pos": home, "radius": 160.0, "veh": "air", "time": 300.0}),
			]
		&"air_escort":
			var pts: Array[Vector3] = [air_point(1262.0, 170.0, -1250.0, 120.0), air_point(1520.0, 210.0, -1650.0, 120.0), air_point(1700.0, 230.0, -1000.0, 120.0),
					air_point(1680.0, 230.0, -100.0, 120.0)]
			out = [
				_provide_strip("jet", "GET IN THE JET", ap),
				_s("reach", "MEET THE AIRLINER", {"pos": pts[0], "radius": 220.0, "veh": "air", "time": 300.0}),
				_s("air_task", "PROTECT THE AIRLINER", {"pos": pts[0], "task": "escort", "pts": pts, "n": 2, "waves": 2, "bandit": "plane", "hp": 130.0, "veh": "air", "time": 480.0}),
			]
		&"air_bomb":
			var field := WorldSites.far_field(strip, 700.0, &"", r)
			if field.is_empty():
				return out
			var fp: Vector3 = field["pos"]
			fp.y = TerrainHeight.height_at(fp.x, fp.z)
			out = [
				_provide_strip("jet", "GET IN THE JET", ap),
				_s("air_task", "BOMB THE COLUMN AT " + String(field["name"]).substr(0, 16), {"pos": fp, "task": "bomb", "n": 3 + (g / 2), "target": "apc", "veh": "air", "time": 480.0}),
				_s("reach", "FLY BACK TO THE AIRPORT", {"pos": home, "radius": 160.0, "veh": "air", "time": 300.0}),
			]
		&"air_cargo":
			var field2 := WorldSites.far_field(strip, 900.0, &"", r)
			if field2.is_empty():
				return out
			var dz: Vector3 = field2["pos"]
			dz.y = TerrainHeight.height_at(dz.x, dz.z)
			out = [
				_provide_strip("cargo", "GET IN THE CARGO PLANE", ap),
				_s("air_task", "DROP THE CRATES AT " + String(field2["name"]).substr(0, 16), {"pos": dz, "task": "drop", "n": 1 + (g / 2), "radius": 60.0, "veh": "plane", "time": 540.0}),
			]
		&"air_rescue":
			var heli_at: Vector3 = ap["heli"]
			var best := {}
			var bd := INF
			for d in WorldSites.heli_pads():
				var dd := _h(heli_at, d["pos"])
				if dd < bd:
					bd = dd
					best = d
			if best.is_empty():
				return out
			var site: Vector3 = best["pos"]
			var hosp := _hospital(heli_at)
			out = [
				_s("reach", "GET IN THE RESCUE HELICOPTER", {"pos": heli_at, "radius": 16.0, "veh": "heli", "provide": "h_medic" if VehicleSpecs.SPECS.has(&"h_medic") else "heli",
						"provide_at": heli_at, "provide_h": WorldMissions.heading_to(heli_at, site)}),
				_s("reach", "FLY TO " + String(best["name"]).substr(0, 18), {"pos": site, "radius": 120.0, "veh": "heli", "time": 360.0}),
				_s("air_task", "LAND AND TAKE THE CLIMBERS ABOARD", {"pos": site, "task": "board", "radius": 30.0, "hold": 4.0, "veh": "heli", "time": 240.0}),
				_s("reach", "FLY THEM TO " + String(hosp["name"]).substr(0, 20), {"pos": hosp["pos"], "radius": 26.0, "veh": "heli", "land": true, "time": 420.0}),
			]
		&"air_rings":
			var rings: Array[Vector3] = []
			var n := 8
			for i in n:
				var a := TAU * float(i) / float(n)
				rings.append(air_point(1400.0 + cos(a) * 260.0, 70.0 + 30.0 * sin(a * 2.0) + 10.0 * float(g), -900.0 + sin(a) * 520.0, 50.0))
			out = [
				_provide_strip("plane", "GET IN THE STUNT PLANE", ap),
				_s("gates", "FLY THROUGH THE RINGS", {"pos": rings[0], "pts": rings, "radius": RING_R, "veh": "air", "time": 420.0}),
			]
	for st: Dictionary in out:
		st["quiet"] = true
	return out


## The hospital pad of the city (w125 Helipads), else the airport's helipad.
static func _hospital(fallback: Vector3) -> Dictionary:
	for p in Helipads.all():
		if p.get("role", &"") == &"hospital":
			return {"name": String(p["name"]), "pos": p["pos"]}
	return {"name": "THE HELIPAD", "pos": fallback}


## One offer record {steps, route_m, pos, title, brief, base, glyph, site}; {} when the world has no place for it.
static func build(t: StringName, tier: int, origin: Vector3, r: RandomNumberGenerator) -> Dictionary:
	if not eligible(t, origin):
		return {}
	var st := steps(t, tier, origin, r)
	if st.is_empty():
		return {}
	var route := 0.0
	var cur := origin
	for s: Dictionary in st:
		if s.has("pts"):
			for q: Variant in s["pts"] as Array:
				route += _h(cur, q as Vector3)
				cur = q as Vector3
		else:
			route += _h(cur, s["pos"])
			cur = s["pos"]
	var d: Dictionary = DEFS[t]
	return {"steps": st, "route_m": route, "pos": (st[0]["pos"] as Vector3), "title": String(d["title"]), "brief": String(d["brief"]), "base": float(d["base"]), "glyph": d["glyph"], "site": site_of(t, origin)}
