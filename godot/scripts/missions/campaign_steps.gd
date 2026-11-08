class_name CampaignSteps
extends RefCounted
## Pure data rules of the scripted campaign steps (scripts/missions/campaign_runner.gd): aliases, per-kind defaults, normalising a chapter's step dictionaries, validation and
## position parsing. Nothing here touches the scene tree, so tests and the story data tests can call it freely.
##
## STEP DICTIONARY (every key but `kind` is optional)
##   kind        one of CampaignRunner.StepKinds (aliases accepted: "infiltrate" = enter_interior, "assassinate" = kill_target); String or StringName
##   id          step id, default "<kind>_<index>"
##   text        objective line on the HUD (alias `obj`), at most StoryData.OBJ_MAX characters; default is the kind's title
##   pos         the goal as Vector3, Vector2 (x, z) or [x, z] / [x, y, z]. Missing: a street point `dist` metres [min, max] from where the step starts (seeded, saved in the checkpoint)
##   radius      ring size in metres (reach, enter_interior, hack, defend, escort destination)
##   time        time limit in seconds, 0 = none (the step fails with TIME OUT and is retried)
##   hold        seconds to hold (hack, defend, survive)
##   checkpoint  false: finishing this step does NOT save a checkpoint (default true)
##   heat        heat added when the step starts (escape: the heat level the player starts the escape at)
##   reward      {credits: int, rep: int} paid when the step is done
##   radio       one line {s, t} said when the step starts, or {start, done, fail}: each a line {s, t}
## KIND KEYS
##   enter_interior  door (door id) | interior (InteriorData type, the nearest door of that type), leave (true: done when the player is back on the street)
##   escort          to (alias of pos), from, hp (120), speed (2.6 m/s), leash (26), abandon (60), ambush: [{at: 0..1 along the route, n: enemies, types: [type]}]
##   defend          waves gap (12 s), count (enemies per wave), types
##   hack            count (drones per pulse)
##   kill_target     enemy (type, default operative) | target ("specialist" / "boss", scope A's keys), guards (count), hp_mult (2.5), name (boss bar)
##   chase           hp (140), cruise (m/s)
##   escape          clear (heat level that counts as lost, 0.5), dist (metres from the start that counts as away, 110), patrol (0..3 Vael patrol vehicles sent after the player the moment
##                   the step starts, topped up while the heat stays up, at most VehicleManager.patrol_cap(); 0 = only the heat; the step is done when the player is far, the heat is
##                   below `clear` AND no chasing patrol is within CampaignRunner.PATROL_LOSE metres)
##   survive         gap (10 s), count, types
##   rift_hold       a COLLAPSE anomaly at pos: stay within `radius` (12 m) and keep it fed with verbs (ENTANGLE, SUPERPOSITION, COLLAPSE, link or any quantum verb used inside 1.6 radii, each feeds `feed` 5 s,
##                   at most 9 s banked); the hold bar fills only while it is fed, drains slowly otherwise; waves (gap 12, count, types) hit the rift, aware enemies near it drain its `integrity` (100)
##                   and the step fails with RIFT LOST at 0 (retry), with ZONE LOST after 10 s outside. hold 40 s
##   heist           quantum heist: door / interior as enter_interior (default interior lobby): phase 1 go inside, phase 2 steal (the interior's mission completes, or after `grace` 3 s in a room without
##                   one), phase 3 getaway: heat jumps to `heat` (3), `patrol` (2) Vael patrol vehicles chase, done when `dist` (110) m from the door, heat below `clear` (0.5) and no patrol within
##                   60 m; `escape_time` (100 s) of getaway fails with NOT LOST. Leaving without the loot sends you back in
##   convoy_intercept `cars` (3, 1..3) traffic cars (hp 90, cruise 13) driving in a line from pos along a road: ENTANGLE (within 8 m of the swap), COLLAPSE (within 16 m, also 30 % damage) or damage
##                   below 35 % hp STOP a car (ai_stun held), a wreck counts too; done when every car is stopped; one car 150 m away for 6 s: CONVOY GOT AWAY. time 120
## CHAPTER DICTIONARY: {id, title?, steps: [step...], clears_sector: bool (default true: the last step calls Game.win())}. Scope A's CampaignData chapters work as they are.

const ALIASES := {&"infiltrate": &"enter_interior", &"assassinate": &"kill_target"}

## title: the default objective text and HUD title · color: marker colour · dist: [min, max] metres of a generated goal from the step's origin · time: default limit (0 none)
const KIND_DATA := {
	&"reach": {"title": "REACH THE WAYPOINT", "color": &"cyan", "dist": [110.0, 190.0], "time": 0.0},
	&"enter_interior": {"title": "GO INSIDE", "color": &"cyan", "dist": [90.0, 170.0], "time": 0.0},
	&"escort": {"title": "ESCORT THE ASSET", "color": &"cyan", "dist": [150.0, 240.0], "time": 0.0},
	&"defend": {"title": "DEFEND THE POSITION", "color": &"cyan", "dist": [70.0, 130.0], "time": 0.0},
	&"hack": {"title": "HACK THE NODE", "color": &"cyan", "dist": [70.0, 130.0], "time": 0.0},
	&"kill_target": {"title": "ELIMINATE THE TARGET", "color": &"red", "dist": [75.0, 135.0], "time": 0.0},
	&"chase": {"title": "RUN DOWN THE TARGET", "color": &"amber", "dist": [55.0, 100.0], "time": 150.0},
	&"escape": {"title": "LOSE THE PURSUIT", "color": &"red", "dist": [0.0, 0.0], "time": 120.0},
	&"survive": {"title": "SURVIVE", "color": &"cyan", "dist": [0.0, 0.0], "time": 0.0},
	&"rift_hold": {"title": "HOLD THE RIFT", "color": &"cyan", "dist": [70.0, 130.0], "time": 0.0},
	&"heist": {"title": "STEAL THE DATA", "color": &"amber", "dist": [90.0, 170.0], "time": 0.0},
	&"convoy_intercept": {"title": "STOP THE CONVOY", "color": &"red", "dist": [90.0, 150.0], "time": 120.0},
}

const MAX_TEXT := 56

## One-step sandbox chapters of the sequel mechanics (the DEMO menu's SEQUEL tab, CampaignRunner.start_demo).
const DEMO_IDS: Array[StringName] = [&"rift_hold", &"heist", &"convoy_intercept"]
const DEMO_TITLES := {&"rift_hold": "RIFT HOLD", &"heist": "QUANTUM HEIST", &"convoy_intercept": "CONVOY INTERCEPT"}


static func demo_chapter(id: StringName) -> Dictionary:
	match id:
		&"rift_hold":
			return {"id": "demo_rift_hold", "clears_sector": false, "steps": [{"kind": "rift_hold", "text": "Hold the rift", "hold": 30.0, "count": 2}]}
		&"heist":
			return {"id": "demo_heist", "clears_sector": false, "steps": [{"kind": "heist", "interior": "lobby", "text": "Steal the Exchange data", "patrol": 2}]}
		&"convoy_intercept":
			return {"id": "demo_convoy", "clears_sector": false, "steps": [{"kind": "convoy_intercept", "text": "Stop the convoy", "cars": 3}]}
	return {}


## Canonical kind (aliases resolved), &"" for an unknown one.
static func kind_of(step: Dictionary) -> StringName:
	var k := StringName(str(step.get("kind", "")))
	k = ALIASES.get(k, k)
	return k if KIND_DATA.has(k) else &""


## A position from a Vector3, a Vector2 (x, z) or an array of 2 / 3 numbers; Vector3.INF for anything else. y is kept only for a Vector3 / 3-array.
static func vec3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Vector2:
		return Vector3((v as Vector2).x, 0.0, (v as Vector2).y)
	if v is Array or v is PackedFloat32Array or v is PackedFloat64Array:
		var a: Array = Array(v)
		for n: Variant in a:
			if not (n is float or n is int):
				return Vector3.INF
		if a.size() == 2:
			return Vector3(float(a[0]), 0.0, float(a[1]))
		if a.size() == 3:
			return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.INF


## The steps of a chapter dictionary, copied and completed: canonical `kind`, `id`, `text`, `pos` (Vector3 or Vector3.INF = generate), defaults of the kind. Unknown steps are
## dropped (validate_chapter reports them). The input is never changed.
static func normalize_chapter(chapter: Dictionary, chapter_index := 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = chapter.get("steps", [])
	if not (raw is Array):
		return out
	for s: Variant in raw as Array:
		if not (s is Dictionary) or kind_of(s as Dictionary) == &"":
			continue
		out.append(normalize_step(s as Dictionary, out.size(), chapter_index))
	return out


static func normalize_step(step: Dictionary, index: int, _chapter_index := 0) -> Dictionary:
	var k := kind_of(step)
	var d: Dictionary = KIND_DATA[k]
	var out := step.duplicate(true)
	out["kind"] = k
	out["id"] = str(step.get("id", "%s_%d" % [k, index]))
	var text := str(step.get("text", step.get("obj", d["title"])))
	out["text"] = text
	var p := vec3(step.get("pos", step.get("to", null)))
	out["pos"] = p
	out["from"] = vec3(step.get("from", null))
	out["time"] = float(step.get("time", d["time"]))
	out["checkpoint"] = bool(step.get("checkpoint", true))
	out["heat"] = float(step.get("heat", 0.0))
	out["radius"] = float(step.get("radius", _default_radius(k)))
	match k:
		&"hack": out["hold"] = float(step.get("hold", 24.0))
		&"defend": out["hold"] = float(step.get("hold", 60.0))
		&"survive": out["hold"] = float(step.get("hold", 45.0))
		&"rift_hold": out["hold"] = float(step.get("hold", 40.0))
	out["gap"] = float(step.get("gap", 12.0 if k == &"defend" else 10.0))
	if k == &"kill_target":
		var enemy := StringName(str(step.get("enemy", "")))
		var tgt := str(step.get("target", ""))
		if enemy == &"":
			enemy = &"overseer" if tgt == "boss" else (&"" if tgt == "specialist" else &"operative")
		out["enemy"] = enemy                                       # &"" = pick a specialist for the chapter when the step begins
		out["hp_mult"] = float(step.get("hp_mult", 1.0 if enemy == &"overseer" else 2.5))
		out["guards"] = int(step.get("guards", -1))                # -1: the sector's count (ContractTypes.count)
		out["name"] = str(step.get("name", "VAEL OVERSEER" if enemy == &"overseer" else "VAEL TARGET"))
	if k == &"escort":
		out["hp"] = float(step.get("hp", 120.0))
		out["speed"] = float(step.get("speed", 2.6))
		out["leash"] = float(step.get("leash", 26.0))
		out["abandon"] = float(step.get("abandon", 60.0))
		if not step.has("ambush"):
			out["ambush"] = [{"at": 0.5, "n": -1, "types": []}]
	if k == &"chase":
		out["hp"] = float(step.get("hp", 140.0))
		out["cruise"] = float(step.get("cruise", 0.0))             # 0: from the sector
	if k == &"escape":
		out["heat"] = float(step.get("heat", 3.0))
		out["clear"] = float(step.get("clear", 0.5))
		out["dist"] = float(step.get("dist", 110.0))
		out["patrol"] = clampi(int(step.get("patrol", 0)), 0, 3)
	if k == &"rift_hold":
		out["feed"] = float(step.get("feed", 5.0))
		out["integrity"] = float(step.get("integrity", 100.0))
	if k == &"convoy_intercept":
		out["cars"] = clampi(int(step.get("cars", 3)), 1, 3)
		out["hp"] = float(step.get("hp", 90.0))
		out["cruise"] = float(step.get("cruise", 13.0))
	if k == &"heist":
		out["heat"] = float(step.get("heat", 3.0))
		out["clear"] = float(step.get("clear", 0.5))
		out["dist"] = float(step.get("dist", 110.0))
		out["patrol"] = clampi(int(step.get("patrol", 2)), 0, 3)
		out["escape_time"] = float(step.get("escape_time", 100.0))
		out["grace"] = float(step.get("grace", 45.0))             # a room without a job of its own: TAKE THE DATA (USE at the loot point) is the way; the data is simply there after this long
		out["leave"] = false
		out["door"] = int(step.get("door", -1))
		out["interior"] = StringName(str(step.get("interior", "lobby" if int(step.get("door", -1)) < 0 else "")))
	if k == &"enter_interior":
		out["leave"] = bool(step.get("leave", false))
		out["door"] = int(step.get("door", -1))
		out["interior"] = StringName(str(step.get("interior", "")))
	return out


static func _default_radius(k: StringName) -> float:
	match k:
		&"reach": return 6.0
		&"enter_interior", &"heist": return 2.6
		&"escort": return 4.0
		&"defend": return 30.0
		&"rift_hold": return 12.0
		&"hack": return 9.0
	return 4.0


## "" when the step is usable, otherwise what is wrong with it.
static func validate_step(step: Variant) -> String:
	if not (step is Dictionary):
		return "step is not a dictionary"
	var s := step as Dictionary
	if kind_of(s) == &"":
		return "unknown kind '%s'" % str(s.get("kind", ""))
	var text := str(s.get("text", s.get("obj", "")))
	if text.length() > MAX_TEXT:
		return "objective text longer than %d characters" % MAX_TEXT
	if s.has("pos") and not vec3(s["pos"]).is_finite():
		return "pos is not a Vector3 / Vector2 / [x, z]"
	if kind_of(s) == &"convoy_intercept" and s.has("cars") and not (s["cars"] is int and int(s["cars"]) >= 1 and int(s["cars"]) <= 3):
		return "cars must be 1 to 3"
	if s.has("radio"):
		var r: Variant = s["radio"]
		if not (r is Dictionary):
			return "radio is not a dictionary"
		var rd := r as Dictionary
		var lines: Array = [rd] if rd.has("t") else [rd.get("start", {}), rd.get("done", {}), rd.get("fail", {})]
		for l: Variant in lines:
			if l is Dictionary and not (l as Dictionary).is_empty():
				if not (l as Dictionary).has("s") or not (l as Dictionary).has("t"):
					return "radio line needs s and t"
				if str((l as Dictionary)["t"]).length() > StoryData.LINE_MAX:
					return "radio line longer than %d characters" % StoryData.LINE_MAX
	for key: String in ["time", "hold", "radius", "hp", "speed", "feed", "integrity", "cruise", "escape_time"]:
		if s.has(key) and not (s[key] is float or s[key] is int):
			return "%s is not a number" % key
	return ""


## Problems of a chapter dictionary (empty array = fine): at least one step, every step valid.
static func validate_chapter(chapter: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (chapter is Dictionary):
		out.append("chapter is not a dictionary")
		return out
	var steps: Variant = (chapter as Dictionary).get("steps", null)
	if not (steps is Array) or (steps as Array).is_empty():
		out.append("no steps")
		return out
	for i in (steps as Array).size():
		var why := validate_step((steps as Array)[i])
		if why != "":
			out.append("step %d: %s" % [i, why])
	return out


## Point at distance `s` metres along a polyline (clamped to its ends) and the unit heading there (x, z).
static func point_along(route: PackedVector3Array, s: float) -> Dictionary:
	if route.is_empty():
		return {"pos": Vector3.ZERO, "dir": Vector3(0, 0, -1)}
	var rest := maxf(s, 0.0)
	var dir := Vector3(0, 0, -1)
	for i in route.size() - 1:
		var a := route[i]
		var b := route[i + 1]
		var seg := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var l := seg.length()
		if l < 0.001:
			continue
		dir = seg / l
		if rest <= l:
			return {"pos": a + dir * rest, "dir": dir}
		rest -= l
	return {"pos": route[route.size() - 1], "dir": dir}


static func route_length(route: PackedVector3Array) -> float:
	var n := 0.0
	for i in route.size() - 1:
		n += Vector2(route[i + 1].x - route[i].x, route[i + 1].z - route[i].z).length()
	return n


## A street route from a to b over the road grid: onto the nearest road, along it, across at a junction, off at b. Escorts and the reach line follow it (an L over the blocks ran through buildings:
## found by the mission audit, the escortee walked through a tower and the player could not follow).
static func street_route(a: Vector3, b: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var ax := CityLayout.road_offset(a.x)
	var az := CityLayout.road_offset(a.z)
	var bx := CityLayout.road_offset(b.x)
	var bz := CityLayout.road_offset(b.z)
	var a_on_z := absf(ax) <= absf(az)                 # a stands on / next to a road that runs along z (constant x)
	var b_on_z := absf(bx) <= absf(bz)
	var sa := Vector3(a.x - ax, 0.0, a.z) if a_on_z else Vector3(a.x, 0.0, a.z - az)
	var sb := Vector3(b.x - bx, 0.0, b.z) if b_on_z else Vector3(b.x, 0.0, b.z - bz)
	pts.append(Vector3(a.x, 0.0, a.z))
	pts.append(sa)
	if a_on_z and b_on_z:
		if is_equal_approx(sa.x, sb.x):
			pass
		else:
			var z0 := sa.z - CityLayout.road_offset(sa.z)
			pts.append(Vector3(sa.x, 0.0, z0))
			pts.append(Vector3(sb.x, 0.0, z0))
	elif a_on_z and not b_on_z:
		pts.append(Vector3(sa.x, 0.0, sb.z))
	elif not a_on_z and b_on_z:
		pts.append(Vector3(sb.x, 0.0, sa.z))
	else:
		if is_equal_approx(sa.z, sb.z):
			pass
		else:
			var x0 := sa.x - CityLayout.road_offset(sa.x)
			pts.append(Vector3(x0, 0.0, sa.z))
			pts.append(Vector3(x0, 0.0, sb.z))
	pts.append(sb)
	pts.append(Vector3(b.x, 0.0, b.z))
	return pts
