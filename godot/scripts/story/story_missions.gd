class_name StoryMissions
extends RefCounted
## Turns a story mission of StoryActs into campaign steps (the same dictionaries the Mission Board runs, scripts/missions/campaign_steps.gd) placed on the real world: the city, the
## harbour quay and bay, SUMMIT ROAD, the observatory, EASTFIELD airport, the canyon, the sound, the alien outpost and the Array tower. Pure data and terrain queries, no nodes.
##
## Every step carries the radio line StoryActs wrote for it (`radio`, said when the step starts) and `quiet` (the HUD line says the objective). Places that the world cannot offer (a stub
## test world without terrain, a missing site) fall back to a city version of the same mission with the same number of steps (`fallback` true): a story mission is NEVER impossible,
## so the story cannot stall. EASY by construction: wide rings, generous times, one boss at most, no instant failures.

const SEA_Y := -2.0                              ## the sea surface (Harbour): boat gates and boat goals sit on it
const LEAD := 70.0
const BOAT_CLEAR := -2.6                         ## a point is water for a boat when the ground is lower than this
const FINAL_ID := "tuning_day"


static func _s(kind: String, text: String, extra := {}) -> Dictionary:
	var d := {"kind": kind, "text": text, "quiet": true}
	d.merge(extra, true)
	return d


static func _h(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


static func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, TerrainHeight.height_at(p.x, p.z), p.z)


static func is_water(p: Vector3) -> bool:
	return TerrainHeight.height_at(p.x, p.z) < BOAT_CLEAR


static func _clip(s: String, n: int) -> String:
	return s.substr(0, n)


## The steps of story mission `id` (without their radio lines); [] when the world has no place for it. Every goal that is not a street point already has its `pos`.
static func world_steps(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match id:
		"landfall":
			out = [
				_s("reach", "FOLLOW THE BEACON", {"range": [90.0, 150.0]}),
				_s("kill_target", "DRIVE OFF THE AUTHORITY PATROL", {"enemy": "operative", "guards": 2, "hp_mult": 1.0, "name": "AUTHORITY PATROL", "range": [60.0, 100.0]}),
			]
		"borrowed_wheels":
			out = [
				_s("reach", "TAKE A CAR TO RIVET'S GARAGE", {"car": true, "radius": 10.0, "range": [170.0, 250.0]}),
				_s("escape", "LOSE THE AUTHORITY CARS", {"patrol": 1, "heat": 2.0}),
			]
		"the_relay":
			out = [
				_s("hack", "HACK THE AUTHORITY RELAY", {"hold": 20.0, "radius": 10.0, "range": [90.0, 140.0]}),
				_s("defend", "HOLD THE RELAY TOWER", {"hold": 30.0, "gap": 12.0, "count": 2, "radius": 32.0}),
				_s("kill_target", "DROP THE RELAY CHIEF", {"target": "specialist", "guards": 1, "hp_mult": 1.5, "name": "RELAY CHIEF", "range": [60.0, 100.0]}),
			]
		"container_17":
			var q: Dictionary = Harbour.dock(&"west_quay")
			if q.is_empty():
				return out
			var dp: Vector3 = q["pos"]                                 # the dock's own point sits on the basin's edge (the terrain there is the dredged water): the goals are on the apron beside it
			var qp := Vector3(dp.x - 24.0, Harbour.QUAY_Y, dp.z - 6.0)
			var yard := Vector3(qp.x - 40.0, Harbour.QUAY_Y, qp.z - 30.0)
			var box := Vector3(qp.x - 30.0, Harbour.QUAY_Y, qp.z - 74.0)
			out = [
				_s("reach", "GET TO THE WEST QUAY", {"pos": qp, "radius": 22.0, "veh": "ground"}),
				_s("kill_target", "CLEAR THE QUAY GUARDS", {"pos": yard, "enemy": "operative", "guards": 3, "hp_mult": 1.2, "name": "QUAY GUARD"}),
				_s("hack", "OPEN CONTAINER 17", {"pos": box, "hold": 18.0, "radius": 9.0}),
			]
		"ferry_run":
			var route := bay_route()
			if route.size() < 4:
				return out
			var berth := berth_pos()
			var pr := PathFollow.new(route)
			var lead := pr.point_at(LEAD)
			out = [
				_s("reach", "GET IN THE SPEEDBOAT", {"pos": berth, "radius": 18.0, "veh": "boat", "provide": "boat", "provide_at": berth, "provide_h": PI}),
				_s("pursuit", "CATCH THE COURIER BOAT", {"pos": lead, "route": route, "target": "boat", "hp": 200.0, "cruise": 15.0, "catch": 17.0, "time": 300.0, "lead": LEAD}),
				_s("reach", "FOLLOW IT PAST THE BREAKWATER", {"pos": route[route.size() - 1], "radius": 36.0, "veh": "boat"}),
			]
		"summit_road":
			var rn := chase_road()
			if rn == "":
				return out
			var rt := WorldSites.road_route(rn)
			var start := rt[0]
			var pf := PathFollow.new(rt)
			var lead2 := pf.point_at(LEAD)
			var top := rt[rt.size() - 1]
			out = [
				_s("reach", "GET TO " + _clip(rn, 20), {"pos": start, "radius": 16.0, "veh": "ground", "provide": "suv", "provide_at": start + pf.dir_at(0.0).rotated(Vector3.UP, -PI * 0.5) * 5.0,
						"provide_h": WorldMissions.heading_to(start, lead2)}),
				_s("pursuit", "CHASE THE FORK'S PICKUP", {"pos": lead2, "route": rt, "target": "pickup", "hp": 220.0, "cruise": 15.0, "catch": 15.0, "time": 300.0, "lead": LEAD}),
				_s("reach", "SECURE THE FORK AT THE TOP", {"pos": top, "radius": 18.0, "veh": "ground"}),
			]
		"observatory":
			var pad := WorldSites.pad(&"observatory")
			if pad.is_empty():
				return out
			var pp: Vector3 = pad["pos"]
			out = [
				_s("reach", "REACH THE OBSERVATORY", {"pos": pp, "radius": 22.0, "veh": "ground"}),
				_s("defend", "HOLD THE DISH", {"pos": pp, "hold": 40.0, "gap": 12.0, "count": 2, "radius": 30.0}),
				_s("hack", "DOWNLOAD THE ARRAY MAP", {"pos": pp + Vector3(7.0, 0.0, 5.0), "hold": 20.0, "radius": 10.0}),
			]
		"eastfield":
			var ap := WorldSites.airport()
			var gate: Vector3 = ap["gate"]
			var strip: Vector3 = ap["strip"]
			var field := WorldSites.far_field(strip, 900.0)
			if not gate.is_finite() or not strip.is_finite() or field.is_empty():
				return out
			var fp: Vector3 = field["pos"]
			out = [
				_s("reach", "GET TO EASTFIELD AIRPORT", {"pos": gate, "radius": 24.0, "veh": "ground"}),
				_s("kill_target", "CLEAR THE HANGAR", {"pos": ap["hangar"], "enemy": "operative", "guards": 2, "hp_mult": 1.2, "name": "HANGAR GUARD"}),
				_s("reach", "TAKE BASALT'S PLANE", {"pos": strip, "radius": 16.0, "veh": "plane", "provide": "plane", "provide_at": strip, "provide_h": float(ap["strip_h"])}),
				_s("reach", "FLY OUT AND LAND AT " + _clip(String(field["name"]), 14), {"pos": fp, "radius": 70.0, "veh": "air", "land": true, "time": 420.0}),
			]
		"canyon_run":
			var c := canyon()
			if c.is_empty():
				return out
			var pad2 := WorldSites.pad(StringName(c["pad"]))
			var pp2: Vector3 = pad2["pos"]
			var gates := WorldSites.canyon_gates(c, 9, 16.0, 34.0)
			if gates.size() < 4:
				return out
			var heli := pp2 + Vector3(9.0, 0.0, 7.0)
			out = [
				_s("reach", "GET IN THE HELICOPTER", {"pos": heli, "radius": 16.0, "veh": "heli", "provide": "heli", "provide_at": heli, "provide_h": WorldMissions.heading_to(pp2, gates[0])}),
				_s("gates", "FLY THE " + _clip(String(c["name"]), 20), {"pos": gates[0], "pts": gates, "radius": WorldMissions.GATE_R, "veh": "air", "time": 300.0}),
				_s("reach", "LAND ON THE PAD", {"pos": pp2, "radius": 34.0, "veh": "heli", "land": true, "time": 240.0}),
			]
		"deep_water":
			var pts := sea_gates()
			if pts.size() < 3:
				return out
			var berth2 := berth_pos()
			var last := pts[pts.size() - 1]
			out = [
				_s("reach", "GET IN THE SPEEDBOAT", {"pos": berth2, "radius": 18.0, "veh": "boat", "provide": "boat", "provide_at": berth2, "provide_h": PI}),
				_s("gates", "FOLLOW THE CABLE BUOYS", {"pos": pts[0], "pts": pts, "radius": 24.0, "veh": "boat", "time": 420.0}),
				_s("reach", "REACH THE RELAY BUOY", {"pos": last + Vector3(0.0, 0.0, 70.0), "radius": 40.0, "veh": "boat"}),
			]
		"the_outpost":
			var camp := outpost()
			var pad3 := nearest_pad(camp["pos"]) if not camp.is_empty() else {}
			if camp.is_empty() or pad3.is_empty():
				return out
			var cp: Vector3 = camp["pos"]
			var pp3: Vector3 = pad3["pos"]
			var heli_at := pp3 + Vector3(9.0, 0.0, 7.0)
			out = [
				_s("reach", "GET TO " + _clip(String(pad3["name"]), 20), {"pos": pp3, "radius": 22.0, "veh": "ground"}),
				_s("reach", "GET IN THE HELICOPTER", {"pos": heli_at, "radius": 14.0, "veh": "heli", "provide": "heli", "provide_at": heli_at, "provide_h": WorldMissions.heading_to(pp3, cp)}),
				_s("reach", "FLY TO " + _clip(String(camp["name"]), 22), {"pos": cp, "radius": 90.0, "veh": "heli", "time": 420.0}),
				_s("kill_target", "BREAK THE OUTPOST WARDEN", {"pos": cp, "enemy": "phasewright", "hp_mult": 0.8, "guards": 2, "name": "OUTPOST WARDEN"}),
				_s("hack", "PLANT THE DAMPER CORE", {"pos": cp + Vector3(8.0, 0.0, 6.0), "hold": 25.0, "radius": 10.0}),
			]
		"tuning_day":
			out = [
				_s("reach", "REACH THE ARRAY TOWER", {"range": [200.0, 300.0]}),
				_s("defend", "HOLD THE LOBBY", {"hold": 40.0, "gap": 12.0, "count": 3, "radius": 32.0}),
				_s("kill_target", "BREAK DIRECTOR VOSS", {"enemy": "bulwark", "hp_mult": 0.9, "guards": 2, "name": "DIRECTOR VOSS", "range": [50.0, 80.0]}),
				_s("escape", "ESCAPE THE COLLAPSING ARRAY", {"patrol": 2, "heat": 3.0}),
			]
	for st: Dictionary in out:
		if st.has("pos"):
			var p: Vector3 = st["pos"]
			if not p.is_finite():
				return []
	return out


## The same mission on city streets only: used when the world has no place for it. Step for step the same count, so the radio lines and beats still fit.
static func city_steps(steps: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for st: Dictionary in steps:
		var d: Dictionary = {"kind": str(st["kind"]), "text": str(st["text"]), "quiet": true, "fallback": true}
		for key: String in ["hold", "gap", "count", "enemy", "target", "guards", "hp_mult", "name", "patrol", "heat", "range"]:
			if st.has(key):
				d[key] = st[key]
		match str(st["kind"]):
			"gates":
				d["kind"] = "reach"
				d["range"] = [120.0, 190.0]
			"pursuit":
				d["kind"] = "chase"
				d["range"] = [60.0, 100.0]
				d["on_foot"] = false
			"reach":
				d["range"] = [110.0, 190.0]
			"kill_target":
				if not d.has("range"):
					d["range"] = [60.0, 100.0]
		if str(st["kind"]) == "hack" or str(st["kind"]) == "defend":
			d["range"] = [80.0, 130.0]
		out.append(d)
	return out


## One finished mission: {id, index, steps (with radio), route_m, pos, title, brief, reward, glyph, story, fallback, chapter}. The offer the Mission Board starts.
static func build(id: String) -> Dictionary:
	var idx := StoryActs.index_of(id)
	if idx < 0:
		return {}
	var m := StoryActs.mission(idx)
	var steps := world_steps(id)
	var fallback := false
	var want := int(m["steps"])
	if steps.size() != want:
		var base := world_steps_for_fallback(id, want)
		steps = city_steps(base)
		fallback = true
	var radio: Array = m["radio"]
	for i in steps.size():
		steps[i]["radio"] = (radio[i] as Dictionary).duplicate() if i < radio.size() else {}
		steps[i]["quiet"] = true
	var route := 0.0
	var cur := Vector3.INF
	var first := Vector3.INF
	for st: Dictionary in steps:
		var p: Vector3 = st.get("pos", Vector3.INF)
		if str(st["kind"]) == "pursuit":
			route += WorldSites.length_of(st["route"] as PackedVector3Array)
		elif str(st["kind"]) == "gates":
			for q: Variant in st["pts"] as Array:
				if cur.is_finite():
					route += _h(cur, q as Vector3)
				cur = q as Vector3
		elif p.is_finite():
			if cur.is_finite():
				route += _h(cur, p)
			cur = p
		if not first.is_finite() and p.is_finite():
			first = p
	var offer := {
		"id": 1000 + idx, "type": &"story", "story": false, "story_act": true, "story_id": id, "story_index": idx, "title": str(m["title"]), "brief": str(m["card"]),
		"glyph": &"star", "steps": steps, "route_m": route, "reward": int(m["reward"]), "pos": first if first.is_finite() else Vector3.INF, "tier": 0, "fallback": fallback,
		"gift": "", "act": int(m["act"]),
		"chapter": {"id": "story_" + id, "title": str(m["title"]), "clears_sector": false, "steps": steps},
	}
	return offer


## A mission whose world version could not be built: the recipe at the right length, as plain street kinds.
static func world_steps_for_fallback(id: String, want: int) -> Array[Dictionary]:
	var kinds := {
		"container_17": ["reach", "kill_target", "hack"], "ferry_run": ["reach", "chase", "reach"], "summit_road": ["reach", "chase", "reach"],
		"observatory": ["reach", "defend", "hack"], "eastfield": ["reach", "kill_target", "reach", "reach"], "canyon_run": ["reach", "reach", "reach"],
		"deep_water": ["reach", "reach", "reach"], "the_outpost": ["reach", "reach", "reach", "kill_target", "hack"],
	}
	var out: Array[Dictionary] = []
	var texts := {"reach": "REACH THE WAYPOINT", "kill_target": "CLEAR THE GUARDS", "hack": "HACK THE NODE", "chase": "RUN DOWN THE TARGET", "defend": "HOLD THE POSITION"}
	var ks: Array = kinds.get(id, [])
	for i in want:
		var k := str(ks[i]) if i < ks.size() else "reach"
		var d := {"kind": k, "text": texts[k], "quiet": true}
		if k == "kill_target":
			d.merge({"enemy": "operative", "guards": 2, "hp_mult": 1.2, "name": "GUARD"})
		elif k == "hack":
			d["hold"] = 18.0
		elif k == "defend":
			d.merge({"hold": 30.0, "count": 2})
		out.append(d)
	return out


# --- places -----------------------------------------------------------------------------------------------------------------------

## The speedboat berth at pier A.
static func berth_pos() -> Vector3:
	for b: Dictionary in Harbour.BERTHS:
		if b["id"] == &"dock_speed_a":
			return b["pos"]
	return Harbour.COURSE[0]


## The courier boat's water route out of the basin: from the berth through the channel, round the buoys to the open water past the breakwater (water points only).
static func bay_route() -> PackedVector3Array:
	var pts := PackedVector3Array()
	var b := berth_pos()
	pts.append(b)
	pts.append(Vector3(b.x + 12.0, SEA_Y, 1532.0))
	for i in 3:
		pts.append(Harbour.COURSE[i])
	var out := PackedVector3Array()
	for p in pts:
		if p == b or is_water(p):
			out.append(Vector3(p.x, SEA_Y, p.z))
	return out


## The buoys of DEEP WATER: out of the basin, past the breakwater and on into the open sound (water points only, at least 3 or none).
static func sea_gates() -> Array[Vector3]:
	var cand: Array[Vector3] = [Vector3(30.0, SEA_Y, 1700.0), Vector3(90.0, SEA_Y, 1880.0), Vector3(-30.0, SEA_Y, 2040.0), Vector3(-110.0, SEA_Y, 2180.0), Vector3(-130.0, SEA_Y, 2300.0)]
	var out: Array[Vector3] = []
	for p in cand:
		if is_water(p):
			out.append(p)
	return out


static func chase_road() -> String:
	var rt := WorldSites.road_route("SUMMIT ROAD")
	if rt.size() >= 8 and WorldSites.length_of(rt) >= 420.0:
		return "SUMMIT ROAD"
	for rn in WorldSites.CHASE_ROADS:
		var r2 := WorldSites.road_route(rn)
		if r2.size() >= 8 and WorldSites.length_of(r2) >= 420.0:
			return rn
	return ""


static func canyon() -> Dictionary:
	for c in WorldSites.CANYONS:
		if c["id"] == &"highline" and not WorldSites.pad(StringName(c["pad"])).is_empty() and WorldSites.canyon_gates(c, 9, 16.0, 34.0).size() >= 4:
			return c
	for c in WorldSites.CANYONS:
		if not WorldSites.pad(StringName(c["pad"])).is_empty() and WorldSites.canyon_gates(c, 9, 16.0, 34.0).size() >= 4:
			return c
	return {}


## The alien camp the outpost mission visits: the one closest to a helicopter pad (so the flight is short), a camp at all or {}.
static func outpost() -> Dictionary:
	var best := {}
	var bd := INF
	for s in AlienSites.of_kind(&"camp"):
		var pad := nearest_pad(s["pos"])
		if pad.is_empty():
			continue
		var d := _h(pad["pos"], s["pos"])
		if d < bd:
			bd = d
			best = s
	return best


static func nearest_pad(p: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for d in WorldSites.heli_pads():
		var dist := _h(d["pos"], p)
		if dist < bd:
			bd = dist
			best = d
	return best
