class_name WorldHud
extends RefCounted
## The in-game readouts of the big world (wave 109b): WHERE the hero is, WHAT lies around him and HOW FAR the goal is. All of it lives inside controls the default frame already has, so the 12-control
## limit holds (the place name and the landmark compass sit in the objective stack, the route chip is part of the objective, the feeds share the toast slot).
##   place(p)            {name, kind, alt}: the name the HUD and the map print for a point: EASTFIELD AIRPORT, HARBOUR, a site, a river / lake / road, a biome (HIGH RANGE, FOREST HILLS, DRY PLAINS, COAST, OPEN SEA), CITY
##   update_place(...)   the tracker: the name changes are timed so the HUD can say ENTERING for a few seconds
##   landmarks()         the places the compass shows: the city, the airport, the harbour and the outskirt sites
##   compass(...)        the strip's data: the heading, the cardinal letters, the landmarks in the +-90 degree window and the goal (pinned to an end when it is behind)
##   compass_wanted()    outside the city, in the air or on the water: the strip shows; in the city the minimap and the beacon are enough
##   tracker(...)        the goal's route length and ETA in the hero's mode (foot, car, air, boat): "1.2 KM  ETA 0:55  CAR"
##   wanted_info()       the stars' pursuit line: SPOTTED / SEARCHING / HIDDEN and what the police send at this level
##   region_labels()     the names printed on the world map at each zoom
##   draw_compass(hud, ...) paints the strip with the Hud's batched primitives (so it costs no extra draw calls)

const PLACE_HOLD := 3.5                  ## seconds the ENTERING word stays after the name changed
const WINDOW := PI * 0.5                 ## the compass shows +-90 degrees
const MARK_MAX := 3                      ## landmarks drawn at once
const FAR_MARK_M := 3200.0
const SHORT := {"MOUNTAIN OBSERVATORY": "OBSERVATORY", "RADIO TOWER": "RADIO", "OLD MINE": "MINE", "ALIEN CRASH SITE": "CRASH", "HIDDEN CAVE": "CAVE", "LAKESIDE LODGE": "LODGE",
	"HUNTERS CABINS": "CABINS", "PINE HOLLOW": "HOLLOW", "DUST WELLS": "WELLS", "SOUTH FARM": "FARM S", "NORTH FARM": "FARM N", "EASTFIELD AIRPORT": "AIRPORT", "HARBOUR": "HARBOUR", "CITY": "CITY"}
const KIND_COL := {&"airport": Color(0.55, 0.85, 1.0), &"harbour": Color(0.4, 0.8, 1.0), &"city": Color(1.0, 0.9, 0.5), &"site": Color(0.95, 0.75, 0.45)}

static var _place_name := ""
static var _place_since := -100.0
static var _marks: Array[Dictionary] = []
static var _marks_sites := -1
static var _labels: Array = []
static var _labels_water := false


# --- where ------------------------------------------------------------------------------------------------------------

## The place at (x, z). `kind`: city, airport, harbour, site, water, road, sea, mountain, forest, desert, coast, plains.
static func place(p: Vector3) -> Dictionary:
	var x := p.x
	var z := p.z
	var out := {"name": "CITY", "kind": &"city", "alt": 0}
	if absf(x) <= CityLayout.HALF + 10.0 and absf(z) <= CityLayout.HALF + 10.0:
		return out
	var h := TerrainHeight.height_at(x, z)
	out["alt"] = maxi(roundi(h - TerrainHeight.SEA_LEVEL), 0)
	var loc := Airport.to_local(Vector3(x, 0.0, z))
	if Airport.PAD.grow(60.0).has_point(Vector2(loc.x, loc.z)):
		out["name"] = Airport.NAME
		out["kind"] = &"airport"
		return out
	var hc := Harbour.center()
	if Harbour.BASIN.grow(150.0).has_point(Vector2(x, z)) or Vector2(x - hc.x, z - hc.z).length() < 260.0:
		out["name"] = "HARBOUR"
		out["kind"] = &"harbour"
		return out
	var si := OutskirtsSites.inside(x, z, 60.0)
	if si >= 0:
		out["name"] = String(OutskirtsSites.list[si]["name"])
		out["kind"] = &"site"
		return out
	var wb := WaterLayout.body_at(x, z) if WaterLayout.built else -1
	if wb >= 0:
		out["name"] = String(WaterLayout.RIVERS[wb]["name"]) if wb < 100 else String(WaterLayout.LAKES[wb - 100]["name"])
		out["kind"] = &"water"
		return out
	var nm := TerrainMap.region_name(x, z)
	out["name"] = nm
	match nm:
		"OPEN SEA":
			out["kind"] = &"sea"
		"HIGH RANGE":
			out["kind"] = &"mountain"
		"FOREST HILLS":
			out["kind"] = &"forest"
		"DRY PLAINS":
			out["kind"] = &"desert"
		"COAST":
			out["kind"] = &"coast"
		"OUTSKIRTS":
			out["kind"] = &"plains"
		_:
			out["kind"] = &"road"
	return out


## Feeds the hero's position; returns the name. `since()` is how long the current name has stood.
static func update_place(p: Vector3, now: float) -> String:
	var nm := String(place(p)["name"])
	if nm != _place_name:
		_place_name = nm
		_place_since = now
	return nm


static func place_age(now: float) -> float:
	return now - _place_since


static func current_place() -> String:
	return _place_name


static func reset_place() -> void:
	_place_name = ""
	_place_since = -100.0


# --- landmarks and the compass ---------------------------------------------------------------------------------------

static func landmarks() -> Array[Dictionary]:
	var ns := OutskirtsSites.list.size() if OutskirtsSites.built else 0
	if not _marks.is_empty() and ns == _marks_sites:
		return _marks
	_marks_sites = ns
	_marks = []
	_marks.append({"name": "CITY", "pos": Vector3.ZERO, "glyph": &"city", "kind": &"city"})
	_marks.append({"name": Airport.NAME, "pos": Airport.to_world(Vector3(1170.0, 0.0, -560.0)), "glyph": &"airport", "kind": &"airport"})
	_marks.append({"name": "HARBOUR", "pos": Harbour.center(), "glyph": &"harbour", "kind": &"harbour"})
	if OutskirtsSites.built:
		for s: Dictionary in OutskirtsSites.list:
			if bool(s.get("hidden", false)) and not OutskirtsSites.is_found(s["id"]):
				continue
			_marks.append({"name": String(s["name"]), "pos": s["pos"], "glyph": &"site", "kind": &"site"})
	return _marks


static func short_name(n: String) -> String:
	return String(SHORT.get(n, n))


static func compass_wanted(p: Vector3, veh: Object) -> bool:
	if InteriorGameplay.active:
		return false
	var m := WorldRoute.mode_for(veh)
	if m != &"car":
		return true
	return not WorldRoute.in_city(p)


## The compass strip's data from `from` looking along camera yaw `yaw` (Node3D convention): {heading, cardinals [{l, b}], marks [{name, short, b, dist, glyph, kind}], goal {b, dist, pinned, pos}}.
static func compass(from: Vector3, yaw: float, goal: Vector3 = Vector3.INF) -> Dictionary:
	var out := {"heading": int(fposmod(roundf(-rad_to_deg(yaw)), 360.0)), "cardinals": [], "marks": [], "goal": {}}
	for l: Array in [["N", Vector3(0, 0, -1)], ["E", Vector3(1, 0, 0)], ["S", Vector3(0, 0, 1)], ["W", Vector3(-1, 0, 0)]]:
		var b := MissionGuide.compass_bearing(Vector3.ZERO, l[1], yaw)
		if absf(b) <= WINDOW:
			(out["cardinals"] as Array).append({"l": l[0], "b": b})
	var seen: Array[Dictionary] = []
	for m: Dictionary in landmarks():
		var pos: Vector3 = m["pos"]
		var d := Vector2(pos.x - from.x, pos.z - from.z).length()
		if d < 60.0 or d > FAR_MARK_M:
			continue
		var b2 := MissionGuide.compass_bearing(from, pos, yaw)
		if absf(b2) > WINDOW * 0.8:                          # (a label near the strip's end would have to be pushed over its neighbour)
			continue
		seen.append({"name": m["name"], "short": short_name(String(m["name"])), "b": b2, "dist": d, "glyph": m["glyph"], "kind": m["kind"]})
	seen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	var taken: Array[Dictionary] = []                          # nearest first; a mark whose label would touch a taken one's (about 0.105 rad per letter) is skipped
	for m: Dictionary in seen:
		if (out["marks"] as Array).size() >= MARK_MAX:
			break
		var clash := false
		for t: Dictionary in taken:
			var need := 0.105 * 0.5 * float(String(t["short"]).length() + String(m["short"]).length()) + 0.08
			if absf(float(t["b"]) - float(m["b"])) < need:
				clash = true
		if not clash:
			taken.append(m)
			(out["marks"] as Array).append(m)
	var cards: Array = out["cardinals"]
	for i in range(cards.size() - 1, -1, -1):                  # a cardinal letter under a landmark's diamond would hide it: the landmark wins
		for m: Dictionary in out["marks"]:
			if absf(float(cards[i]["b"]) - float(m["b"])) < 0.13:
				cards.remove_at(i)
				break
	if goal.is_finite():
		var gb := MissionGuide.compass_bearing(from, goal, yaw)
		out["goal"] = {"b": gb, "dist": Vector2(goal.x - from.x, goal.z - from.z).length(), "pinned": absf(gb) > WINDOW, "pos": goal}
	return out


static var _ms: MapScreen = null

## The one goal to guide to (MapRoute.goal: the map waypoint the player placed, else the campaign step, else the side contract); Vector3.INF when none.
static func goal() -> Vector3:
	if not is_instance_valid(_ms) and Game.get_tree() != null:
		_ms = Game.get_tree().root.find_child("MapScreen", true, false) as MapScreen
	return MapRoute.goal(_ms.waypoint if is_instance_valid(_ms) else Vector3.INF)


# --- the goal's route -----------------------------------------------------------------------------------------------

## {dist, eta, mode, word, text} of the way to `goal`, "" / empty when it is nearer than 150 m. `speed_mode` is foot / car / air / boat (the route follows WorldRoute's three modes; foot walks the car route).
static func tracker(from: Vector3, goal: Vector3, speed_mode: StringName) -> Dictionary:
	if not goal.is_finite() or Vector2(goal.x - from.x, goal.z - from.z).length() < 150.0:
		return {}
	var rmode: StringName = speed_mode if speed_mode in WorldRoute.MODES else &"car"
	var poly := WorldRoute.route(from, goal, rmode)
	var len := WorldRoute.length(poly)
	var eta := WorldRoute.eta(len, speed_mode)
	var word := "ON FOOT" if speed_mode == &"foot" else String(WorldRoute.MODE_WORD.get(speed_mode, "CAR"))
	return {"dist": len, "eta": eta, "mode": speed_mode, "word": word, "text": "%s  ETA %s  %s" % [WorldRoute.dist_text(len), WorldRoute.clock(eta), word]}


## The movement mode of the hero for the tracker: foot, or the vehicle's route mode (tanks and cars drive).
static func speed_mode(veh: Object) -> StringName:
	return &"foot" if veh == null else WorldRoute.mode_for(veh)


# --- wanted ---------------------------------------------------------------------------------------------------------------

## {level, state, response, hidden} of the pursuit, {} without heat.
static func wanted_info() -> Dictionary:
	var w := Wanted.current
	if w == null or Game.heat <= 0.01:
		return {}
	var lvl := w.level()
	return {"level": lvl, "state": w.state_label(), "response": String(Wanted.RESPONSE_LABEL[clampi(lvl, 0, Wanted.LEVELS)]), "hidden": w.hide_mode != &"", "heat": Game.heat}


# --- map labels ----------------------------------------------------------------------------------------------------------

## The names the world map prints: [{name, pos Vector2, tier}]; tier 0 = the big regions (always in the WORLD view), tier 1 = rivers and lakes (from zoom 0.5), tier 2 = the sites (from zoom 1).
static func region_labels() -> Array:
	var water := WaterLayout.built
	if not _labels.is_empty() and water == _labels_water:
		return _labels
	_labels_water = water
	_labels = []
	for e in TerrainMap.LABELS:
		_labels.append({"name": e[0], "pos": e[1], "tier": 0})
	if water:
		for pth: Dictionary in WaterLayout.paths:
			var pts: PackedVector2Array = pth["pos"]
			if pts.size() > 2:
				_labels.append({"name": String(pth["name"]), "pos": pts[pts.size() / 2], "tier": 1})
		for l: Dictionary in WaterLayout.LAKES:
			if String(l["name"]) != "MIRROR LAKE":                  # (TerrainMap.LABELS has it)
				_labels.append({"name": String(l["name"]), "pos": l["c"], "tier": 1})
	var ap := Airport.to_world(Vector3(1170.0, 0.0, -560.0))
	_labels.append({"name": Airport.NAME, "pos": Vector2(ap.x, ap.z), "tier": 2})
	_labels.append({"name": "HARBOUR", "pos": Vector2(Harbour.center().x, Harbour.center().z), "tier": 2})
	return _labels


# --- drawing --------------------------------------------------------------------------------------------------------

## A dashed polyline on any CanvasItem (at most 120 dashes): used for flight lines and sea lanes.
static func dashed(ci: CanvasItem, pl: PackedVector2Array, col: Color, w: float, dash: float, gap: float) -> void:
	var left := 120
	var phase := 0.0
	var on := true
	for i in range(1, pl.size()):
		var a := pl[i - 1]
		var seg := pl[i] - a
		var l := seg.length()
		if l < 0.5 or not is_finite(l):
			continue
		var dir := seg / l
		var t := 0.0
		while t < l and left > 0:
			var e := minf(t + (dash if on else gap) - phase, l)
			if on:
				ci.draw_line(a + dir * t, a + dir * e, col, w)
				left -= 1
			phase += e - t
			if phase >= (dash if on else gap) - 0.01:
				on = not on
				phase = 0.0
			t = e


const PLATE_H := 80.0                    ## base px of the compass plate

## The landmark compass strip at `y` (px) centred on the screen; returns the new bottom of the stack. Uses the Hud's queued primitives (`_rect`, `_text`, `_sprite`).
static func draw_compass(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, y: float, goal: Vector3, now: float) -> float:
	if not is_instance_valid(Game.camera) or not is_instance_valid(Game.player):
		return y
	var from: Vector3 = Game.player.global_position
	var d := compass(from, Game.camera.global_rotation.y, goal)
	var width := minf(420.0 * s, vp.x * 0.36)
	var x0 := vp.x * 0.5 - width * 0.5
	var plate := Rect2(x0 - 14.0 * s, y, width + 28.0 * s, PLATE_H * s)
	hud._rect(c, plate, Color(UiUtil.PLATE, 0.82))
	hud._rect(c, Rect2(plate.position.x, plate.end.y - 2.0 * s, plate.size.x, 2.0 * s), Color(UiUtil.CYAN, 0.45))
	var base := y + 52.0 * s                                      # the tick line
	hud._rect(c, Rect2(x0, base, width, 1.5 * s), Color(1, 1, 1, 0.45))
	for i in range(-6, 7):
		var a := float(i) * PI / 12.0
		var tx := x0 + width * (0.5 + a / (2.0 * WINDOW))
		var tall := i % 3 == 0
		hud._rect(c, Rect2(tx - 1.0 * s, base - (8.0 if tall else 5.0) * s, 2.0 * s, (8.0 if tall else 5.0) * s), Color(1, 1, 1, 0.75))
	var lsize := int(UiUtil.BAR_LABEL * s)
	for cd: Dictionary in d["cardinals"]:
		var cx := x0 + width * (0.5 + float(cd["b"]) / (2.0 * WINDOW))
		hud._text(c, font, Vector2(cx - 12.0 * s, base - 10.0 * s), String(cd["l"]), HORIZONTAL_ALIGNMENT_CENTER, 24.0 * s, lsize, Color(1, 1, 1, 0.96 if cd["l"] == "N" else 0.72))
	var small := int(UiUtil.BAR_LABEL * s * 0.78)
	for m: Dictionary in d["marks"]:
		var mx := x0 + width * (0.5 + float(m["b"]) / (2.0 * WINDOW))
		var col: Color = KIND_COL.get(m["kind"], Color(1, 1, 1))
		hud._sprite(c, &"diamond", Rect2(Vector2(mx - 6.0 * s, base - 22.0 * s), Vector2(12.0, 12.0) * s), col)
		hud._text(c, font, Vector2(mx - 60.0 * s, y + 19.0 * s), String(m["short"]), HORIZONTAL_ALIGNMENT_CENTER, 120.0 * s, small, Color(col.lerp(Color.WHITE, 0.35), 0.98), 1.0 * s)
	var g: Dictionary = d["goal"]
	if not g.is_empty():
		var gb: float = g["b"]
		var gx := x0 + width * (0.5 + clampf(gb, -WINDOW, WINDOW) / (2.0 * WINDOW))
		var pulse := 0.8 + 0.2 * sin(now * 5.0)
		var hs := 8.0 * s
		hud._sprite(c, &"diamond", Rect2(Vector2(gx - hs, base - hs * 2.4), Vector2(hs, hs) * 2.0), Color(UiUtil.AMBER, pulse))
		if bool(g["pinned"]):
			hud._text(c, font, Vector2(gx + (-34.0 if gb < 0.0 else 8.0) * s, base - 4.0 * s), "<" if gb < 0.0 else ">", HORIZONTAL_ALIGNMENT_CENTER, 26.0 * s, lsize, Color(UiUtil.AMBER, pulse))
	# row 3: heading, the place (ENTERING in amber for a few seconds after a change)
	var row := y + 74.0 * s
	hud._text(c, font, Vector2(x0 - 6.0 * s, row), "%03d" % int(d["heading"]), HORIZONTAL_ALIGNMENT_LEFT, 70.0 * s, small, Color(UiUtil.CYAN, 0.95), 1.0 * s)
	var nm := update_place(from, now)
	var fresh := place_age(now) < PLACE_HOLD
	var label := ("ENTERING  " + nm) if fresh else nm
	var pcol := Color(UiUtil.AMBER.lerp(Color.WHITE, 0.3), 1.0) if fresh else Color(1, 1, 1, 0.9)
	var psz := UiUtil.fit_size(font, label, width - 150.0 * s, small)
	hud._text(c, font, Vector2(x0 + 70.0 * s, row), label, HORIZONTAL_ALIGNMENT_CENTER, width - 140.0 * s, psz, pcol, 1.0 * s)
	return plate.end.y + 2.0 * s
