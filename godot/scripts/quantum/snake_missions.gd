class_name SnakeMissions
extends RefCounted
## The two QUANTUM SNAKE missions of the Mission Board (wave 115), built like the other board missions: a chapter of campaign steps run by CampaignRunner (checkpoint at every step, instant retry,
## objective line, beacon, MissionGuide), here ON THE ROOFTOPS of the real city:
##   SWING ACROSS THE CITY  (the tutorial: offered first until it has been finished once)
##        1 ZIP UP        a roof 60 to 110 m away: aim at it and tap SNAKE
##        2 SWING         the next roof, 100 to 150 m on: jump and hold SNAKE in the air
##        3 KEEP HOLDING  a third roof: building to building without touching the street
##        4 CLIMB         the top of a tall tower: tap SNAKE at its wall, stick up
##        5 FLY           a ring in the air over the city: hold SNAKE or tap FLY, stick forward
##        6 LAND          back on the street (a ground ring): press LAND
##   ROOFTOP CHASE
##        a courier drone (a real sentinel, put through SnakeMissionDirector) hops from roof to roof; reach each roof, then shoot it down on the last one
## Pure data and rules, no scene tree (the director is the node). Everything EASY: wide rings, no instant failure, no time limit.
## Hooks: MissionBoard.generate calls `inject` after WorldMissions.inject (live game only: `world_offers`), MissionBoard.build calls `build` for these types.

const TYPES: Array[StringName] = [&"swing_city", &"roof_chase"]
const DEFS := {
	&"swing_city": {"title": "SWING ACROSS THE CITY", "brief": "Learn the QUANTUM SNAKE: zip up, swing, climb and fly over the roofs.", "base": 360, "weight": 3, "glyph": &"dest"},
	&"roof_chase": {"title": "ROOFTOP CHASE", "brief": "Chase the courier drone over the roofs and shoot it down.", "base": 420, "weight": 3, "glyph": &"dest"},
}
const INJECT_CHANCE := 0.3
const ROOF_R := 9.0
const AIR_R := 16.0
const SAVE := "user://snake_traversal.cfg"

static var tutorial_done := false          ## SWING ACROSS THE CITY was finished once (saved)
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SAVE) == OK:
		tutorial_done = bool(cf.get_value("missions", "tutorial_done", false))


static func save_flags(extra := {}) -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE)
	cf.set_value("missions", "tutorial_done", tutorial_done)
	for k: Variant in extra:
		cf.set_value("hints", str(k), extra[k])
	cf.save(SAVE)


static func reset_flags() -> void:
	tutorial_done = false
	_loaded = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


static func mark_tutorial_done() -> void:
	_load()
	if not tutorial_done:
		tutorial_done = true
		save_flags()


static func is_tutorial_done() -> bool:
	_load()
	return tutorial_done


static func _s(kind: String, text: String, extra := {}) -> Dictionary:
	var d := {"kind": kind, "text": text.substr(0, CampaignSteps.MAX_TEXT), "quiet": true}
	d.merge(extra, true)
	return d


static func _h(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


## One pick of the board's offers with a snake mission worked in (live game: `MissionBoard.world_offers`): the tutorial replaces the last pick until it has been finished, afterwards a
## snake mission now and then. Picks that already hold one stay.
static func inject(picks: Array[StringName], rng: RandomNumberGenerator, banned: Array = []) -> Array[StringName]:
	_load()
	for p in picks:
		if DEFS.has(p):
			return picks
	if picks.is_empty() or not (Game.world is City) or (Game.world as City).layout == null:
		return picks
	var chosen: StringName = &""
	if not tutorial_done and not banned.has(&"swing_city"):
		chosen = &"swing_city"
	elif rng.randf() < INJECT_CHANCE:
		chosen = &"roof_chase" if not banned.has(&"roof_chase") else &"swing_city"
	if chosen == &"":
		return picks
	var out: Array[StringName] = picks.duplicate()
	out[out.size() - 1] = chosen
	return out


# --- roofs -----------------------------------------------------------------------------------------------------------------------------

## Buildings of the city around `from`: {pos (a point on the roof, toward `from`), h, lot}, nearest first within [rmin, rmax], taller than hmin.
static func roofs(from: Vector3, rmin: float, rmax: float, hmin: float, hmax := 1000.0, avoid: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var city := Game.world as City
	if city == null or city.layout == null:
		return out
	for lot: CityLayout.Lot in city.layout.lots:
		if lot.h < hmin or lot.h > hmax:
			continue
		var c := Vector3(lot.cx, lot.h, lot.cz)
		var d := _h(from, c)
		if d < rmin or d > rmax:
			continue
		var skip := false
		for a: Variant in avoid:
			if _h(a as Vector3, c) < 40.0:
				skip = true
		if skip:
			continue
		var toward := Vector3(from.x - c.x, 0.0, from.z - c.z)
		toward = toward.normalized() if toward.length() > 0.1 else Vector3.RIGHT
		var inset := minf(lot.w, lot.d) * 0.22
		out.append({"pos": c + toward * inset + Vector3(0.0, 0.6, 0.0), "h": lot.h, "d": d, "lot": lot})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	return out


static func _pick(list: Array[Dictionary], r: RandomNumberGenerator) -> Dictionary:
	if list.is_empty():
		return {}
	var n := mini(list.size(), 6)
	return list[int(r.randf() * float(n)) % n]


## The record the board turns into an offer: {title, brief, base, glyph, steps, route_m, pos}; {} when the city has no suitable roofs near `origin`.
static func build(t: StringName, tier: int, origin: Vector3, r: RandomNumberGenerator) -> Dictionary:
	if not DEFS.has(t):
		return {}
	var o := Vector3(origin.x, 0.0, origin.z)
	var out: Array[Dictionary] = []
	var used: Array = []
	match t:
		&"swing_city":
			var a := _pick(roofs(o, 55.0, 120.0, 26.0, 70.0), r)
			if a.is_empty():
				return {}
			used.append(a["pos"])
			var b := _pick(roofs(a["pos"], 95.0, 160.0, 26.0, 90.0, used), r)
			if b.is_empty():
				return {}
			used.append(b["pos"])
			var c := _pick(roofs(b["pos"], 100.0, 170.0, 28.0, 100.0, used), r)
			if c.is_empty():
				return {}
			used.append(c["pos"])
			var d := _pick(roofs(c["pos"], 70.0, 150.0, 62.0, 200.0, used), r)
			if d.is_empty():
				d = _pick(roofs(c["pos"], 60.0, 200.0, 44.0, 200.0, used), r)
			if d.is_empty():
				return {}
			used.append(d["pos"])
			var dp: Vector3 = d["pos"]
			var air := Vector3(dp.x + 70.0 * cos(r.randf() * TAU), dp.y + 26.0, dp.z + 70.0 * sin(r.randf() * TAU))
			var land := Vector3(air.x + 90.0, 0.0, air.z)
			out = [
				_s("reach", "ZIP UP  AIM AT THE ROOF, TAP SNAKE", {"pos": a["pos"], "radius": ROOF_R, "snake_mission": "swing_city"}),
				_s("reach", "SWING  JUMP, THEN HOLD SNAKE", {"pos": b["pos"], "radius": ROOF_R, "snake_mission": "swing_city"}),
				_s("reach", "KEEP HOLDING  BUILDING TO BUILDING", {"pos": c["pos"], "radius": ROOF_R, "snake_mission": "swing_city"}),
				_s("reach", "CLIMB  TAP SNAKE AT THE WALL", {"pos": dp, "radius": ROOF_R + 3.0, "snake_mission": "swing_city"}),
				_s("reach", "FLY  HOLD SNAKE, STICK FORWARD", {"pos": air, "radius": AIR_R + 6.0, "snake_mission": "swing_city"}),
				_s("reach", "LAND  PRESS LAND", {"pos": land, "radius": 14.0, "snake_mission": "swing_city"}),
			]
		&"roof_chase":
			var r1 := _pick(roofs(o, 60.0, 130.0, 28.0, 80.0), r)
			if r1.is_empty():
				return {}
			used.append(r1["pos"])
			var r2 := _pick(roofs(r1["pos"], 90.0, 150.0, 28.0, 90.0, used), r)
			if r2.is_empty():
				return {}
			used.append(r2["pos"])
			var r3 := _pick(roofs(r2["pos"], 90.0, 160.0, 28.0, 100.0, used), r)
			if r3.is_empty():
				return {}
			used.append(r3["pos"])
			var r4 := _pick(roofs(r3["pos"], 80.0, 160.0, 28.0, 100.0, used), r)
			if r4.is_empty():
				return {}
			var hops: Array = [r1["pos"], r2["pos"], r3["pos"], r4["pos"]]
			out = [
				_s("reach", "CHASE THE COURIER  ONTO THE FIRST ROOF", {"pos": r1["pos"], "radius": ROOF_R + 4.0, "snake_mission": "roof_chase", "hops": hops}),
				_s("reach", "KEEP UP  HE JUMPS TO THE NEXT ROOF", {"pos": r2["pos"], "radius": ROOF_R + 4.0, "snake_mission": "roof_chase", "hops": hops}),
				_s("reach", "DON'T LOSE HIM  ONE ROOF MORE", {"pos": r3["pos"], "radius": ROOF_R + 4.0, "snake_mission": "roof_chase", "hops": hops}),
				_s("kill_target", "SHOOT DOWN THE COURIER DRONE", {"pos": r4["pos"] + Vector3(0.0, 3.0, 0.0), "enemy": "sentinel", "guards": 0, "hp_mult": 0.7, "name": "COURIER", "snake_mission": "roof_chase", "hops": hops}),
			]
	if out.is_empty():
		return {}
	var route := 0.0
	var prev := o
	for st: Dictionary in out:
		var q: Vector3 = st["pos"]
		route += _h(prev, q)
		prev = q
	var def: Dictionary = DEFS[t]
	return {"title": def["title"], "brief": def["brief"], "base": def["base"], "glyph": def["glyph"], "steps": out, "route_m": route, "pos": out[0]["pos"]}
