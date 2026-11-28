class_name TankMissions
extends RefCounted
## THE TANK MISSIONS of the Mission Board (wave 127, w127-arms; plan line 127). Three missions that start at the ARMY YARD (ArmourSites.YARD), each a chapter of campaign steps like every board
## mission (checkpoint at every step, instant retry, objective line, beacon, MissionGuide), built from WorldSteps' `reach` with a provided vehicle and the new `tank_task` of TankSteps:
##   TANK BATTLE       take the battle tank, drive out to a field and destroy the enemy tanks holding it (cannon, AP shells, the ATGM's lock-on)
##   CONVOY ESCORT     take the battle tank, meet the supply trucks and keep the enemy tanks off them until they are through
##   ARTILLERY STRIKE  take the mobile artillery to the firing position and shell the enemy armour hundreds of metres away (the target marker shows where a shell lands)
## Offered by location: standing in the yard (within NEAR of it) gets one for sure, in turn; from anywhere now and then (INJECT_CHANCE). Pure data, no nodes.
## W127A_OLD=1 (or TankMissions.on = false): the wave 126 board (no tank missions).

const TYPES: Array[StringName] = [&"tank_battle", &"tank_convoy", &"tank_artillery"]
const NEAR := 60.0
const INJECT_CHANCE := 0.12
const DEFS := {
	&"tank_battle": {"title": "TANK BATTLE", "brief": "Take the battle tank and destroy the enemy tanks at the field.", "base": 460, "glyph": &"target"},
	&"tank_convoy": {"title": "CONVOY ESCORT", "brief": "Keep the enemy tanks off the supply trucks until they are through.", "base": 500, "glyph": &"shield"},
	&"tank_artillery": {"title": "ARTILLERY STRIKE", "brief": "Take the mobile artillery to the firing position and shell the enemy armour.", "base": 440, "glyph": &"blast"},
}

const BRIEF_NEAR := {
	&"tank_battle": "Take the battle tank in the ARMY YARD and stop the enemy tanks coming down the street.",
	&"tank_convoy": "Take the battle tank in the ARMY YARD and keep the enemy tanks off the supply trucks.",
	&"tank_artillery": "Take the mobile artillery out of the ARMY YARD and shell the enemy armour down the street.",
}

static var on := OS.get_environment("W127A_OLD") != "1"
static var near_on := OS.get_environment("W129TM_OLD") != "1"     ## w129-tankmis: the missions play out on the street in front of the ARMY YARD (near_steps); W129TM_OLD=1 = the wave 127 far fields

## w129-tankmis: THE FIELD IN FRONT OF THE YARD. The yard (120 m from the start) opens onto the long east-west street z = -80 (CityLayout: roads every 80 m, 20 m wide); every tank
## mission is staged in the yard and fought along that street to the west, so a finger player finishes it in a few minutes (the wave 127 fields lay 1.5 - 3.5 km away over the city and
## the steps only ended through the guide's stuck recovery). The enemy comes down the street (TankCrews.road_goal leads a crew round the blocks when it has no line of fire).
const STREET_Z := -80.0
const LANE_W := -85.0                ## the westbound lane (right-hand side)
const BATTLE_FIELD := Vector3(-290.0, 0.0, -80.0)
const BATTLE_SPAWNS: Array[Vector3] = [Vector3(-405.0, 0.0, -76.0), Vector3(-428.0, 0.0, -84.0), Vector3(-451.0, 0.0, -76.0), Vector3(-474.0, 0.0, -84.0)]
const EAST := -PI * 0.5              ## heading of a vehicle that faces +x (forward is (-sin h, 0, -cos h))
const CONVOY_ROAD: Array[Vector3] = [Vector3(-215.0, 0.0, -85.0), Vector3(-315.0, 0.0, -85.0), Vector3(-315.0, 0.0, -345.0)]
const ART_FIRE := Vector3(-128.0, 0.0, -80.0)
const ART_TARGETS: Array[Vector3] = [Vector3(-388.0, 0.0, -76.0), Vector3(-408.0, 0.0, -84.0), Vector3(-428.0, 0.0, -76.0), Vector3(-448.0, 0.0, -84.0)]
static var _turn := 0


static func _s(kind: String, text: String, extra := {}) -> Dictionary:
	var d := {"kind": kind, "text": text, "quiet": true}
	d.merge(extra, true)
	return d


static func _h(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


static func _ground(p: Vector3) -> Vector3:
	var g := TerrainHeight.height_at(p.x, p.z) if (absf(p.x) > TerrainHeight.CITY_HALF or absf(p.z) > TerrainHeight.CITY_HALF) else 0.0
	return Vector3(p.x, g, p.z)


static func eligible(t: StringName) -> bool:
	if not on or not DEFS.has(t) or not TankCrews.on:
		return false
	return not WorldSites.landing_fields().is_empty()


## The board's picks with a tank mission worked in: in the yard one replaces the first pick for sure (the three in turn), now and then from anywhere.
static func inject(picks: Array[StringName], origin: Vector3, rng: RandomNumberGenerator) -> Array[StringName]:
	if not on or picks.is_empty():
		return picks
	for p in picks:
		if DEFS.has(p):
			return picks
	var near := _h(origin, ArmourSites.YARD) <= NEAR
	if not near and rng.randf() > INJECT_CHANCE:
		return picks
	var t: StringName = TYPES[_turn % TYPES.size()]
	_turn += 1
	if not eligible(t):
		return picks
	var out: Array[StringName] = picks.duplicate()
	if near:
		out[0] = t
		return out
	# away from the yard the last ordinary card goes (w127-integrator: never a world, air or snake mission placed before: at the lodge the world mission card was the last one and was
	# replaced, tests/test_world_missions.gd "the board offers a world mission every time" 3-5 of 6)
	for i in range(out.size() - 1, -1, -1):
		var p: StringName = out[i]
		if WorldMissions.DEFS.has(p) or AirMissions.DEFS.has(p) or SnakeMissions.DEFS.has(p) or SnakeWarMissions.DEFS.has(p):
			continue
		out[i] = t
		return out
	return picks


static func _provide(kind: String, text: String, at: Vector3, h: float) -> Dictionary:
	return _s("reach", text, {"pos": at, "radius": 14.0, "veh": "tank", "provide": kind, "provide_at": at, "provide_h": h})


## w129-tankmis: the steps of mission `t` on the street in front of the yard: board the vehicle in the yard, then the fight right outside (no long drive).
static func near_steps(t: StringName, tier: int) -> Array[Dictionary]:
	var g := clampi(tier, 0, 3)
	var out: Array[Dictionary] = []
	match t:
		&"tank_battle":
			var n := 2 + g / 2
			out = [
				_provide("tank", "GET IN THE BATTLE TANK", ArmourSites.YARD_BAYS[&"depot"], 0.0),
				_s("tank_task", "DESTROY THE ENEMY TANKS", {"pos": BATTLE_FIELD, "task": "battle", "n": n, "spawns": BATTLE_SPAWNS.slice(0, n), "head": EAST, "kinds": ["ltank", "tank", "apc"],
						"hp": 650.0, "veh": "tank", "time": 600.0, "say": "ENEMY TANKS COMING DOWN THE STREET FROM THE WEST"}),
			]
		&"tank_convoy":
			out = [
				_provide("tank", "GET IN THE BATTLE TANK", ArmourSites.YARD_BAYS[&"depot"], 0.0),
				_s("tank_task", "PROTECT THE CONVOY", {"pos": CONVOY_ROAD[0], "task": "convoy", "pts": CONVOY_ROAD.duplicate(), "road": true, "truck": "t_truck" if TankRoster.on else "truck",
						"trucks": 2 + g / 3, "waves": 2, "n": 1 + g / 2, "hp": 550.0, "veh": "tank", "time": 600.0, "join": 45.0}),
			]
		&"tank_artillery":
			var n2 := 3 + g / 3
			out = [
				_provide("artillery", "GET IN THE MOBILE ARTILLERY", ArmourSites.YARD + Vector3(16.0, 0.0, 4.0), 0.0),
				_s("reach", "DRIVE OUT TO THE FIRING POSITION", {"pos": ART_FIRE, "radius": 14.0, "veh": "tank", "time": 240.0}),
				_s("tank_task", "SHELL THE ENEMY ARMOUR DOWN THE STREET", {"pos": ART_TARGETS[1], "task": "artillery", "n": n2, "spots": ART_TARGETS.slice(0, n2), "kinds": ["apc", "ltank"],
						"hp": 240.0, "veh": "tank", "time": 420.0}),
			]
	for st: Dictionary in out:
		st["quiet"] = true
	return out


## The steps of mission `t` (every goal placed); [] when the world cannot hold it.
static func steps(t: StringName, tier: int, r: RandomNumberGenerator) -> Array[Dictionary]:
	if near_on:
		return near_steps(t, tier)
	var g := clampi(tier, 0, 3)
	var yard := ArmourSites.YARD
	var out: Array[Dictionary] = []
	var field := WorldSites.far_field(yard, 350.0, &"", r)
	if field.is_empty():
		return out
	var fp := _ground(field["pos"])
	var fname := String(field["name"]).substr(0, 16)
	var dir := Vector3(fp.x - yard.x, 0.0, fp.z - yard.z).normalized()
	var side := Vector3(-dir.z, 0.0, dir.x)
	match t:
		&"tank_battle":
			out = [
				_provide("tank", "GET IN THE BATTLE TANK", ArmourSites.YARD_BAYS[&"depot"], 0.0),
				_s("reach", "DRIVE TO " + fname, {"pos": fp - dir * 120.0, "radius": 40.0, "veh": "tank", "time": 420.0}),
				_s("tank_task", "DESTROY THE ENEMY TANKS", {"pos": fp, "task": "battle", "n": 2 + g / 2, "kinds": ["ltank", "tank", "apc"], "hp": 650.0, "veh": "tank", "time": 600.0}),
			]
		&"tank_convoy":
			var a := fp
			var pts: Array[Vector3] = [a, _ground(a + dir * 220.0), _ground(a + dir * 400.0 + side * 60.0)]
			out = [
				_provide("tank", "GET IN THE BATTLE TANK", ArmourSites.YARD_BAYS[&"depot"], 0.0),
				_s("reach", "MEET THE CONVOY AT " + fname, {"pos": a - dir * 30.0, "radius": 45.0, "veh": "tank", "time": 420.0}),
				_s("tank_task", "PROTECT THE CONVOY", {"pos": a, "task": "convoy", "pts": pts, "trucks": 2, "waves": 2, "n": 1 + g / 2, "hp": 550.0, "veh": "tank", "time": 600.0}),
			]
		&"tank_artillery":
			var fire_at := _ground(fp)
			var tp := _ground(fp + dir * 300.0 + side * 40.0)
			out = [
				_provide("artillery", "GET IN THE MOBILE ARTILLERY", yard + Vector3(16.0, 0.0, 4.0), 0.0),
				_s("reach", "DRIVE TO THE FIRING POSITION", {"pos": fire_at, "radius": 40.0, "veh": "tank", "time": 420.0}),
				_s("tank_task", "SHELL THE ENEMY ARMOUR", {"pos": tp, "task": "artillery", "n": 3 + g / 2, "kinds": ["apc", "ltank"], "hp": 240.0, "veh": "tank", "time": 420.0}),
			]
	for st: Dictionary in out:
		st["quiet"] = true
	return out


## One offer record {steps, route_m, pos, title, brief, base, glyph, site}; {} when the world has no place for it.
static func build(t: StringName, tier: int, origin: Vector3, r: RandomNumberGenerator) -> Dictionary:
	if not eligible(t):
		return {}
	var st := steps(t, tier, r)
	if st.is_empty():
		return {}
	var route := 0.0
	var cur := origin
	for s: Dictionary in st:
		route += _h(cur, s["pos"])
		cur = s["pos"]
	var d: Dictionary = DEFS[t]
	return {"steps": st, "route_m": route, "pos": (st[0]["pos"] as Vector3), "title": String(d["title"]), "brief": String(BRIEF_NEAR[t] if near_on else d["brief"]), "base": float(d["base"]), "glyph": d["glyph"], "site": ArmourSites.YARD}
