class_name WorldRoam
extends Node
## FREE-ROAM ACTIVITIES of the big world (wave 107; docs/DESIGN.md: "side activities, races, events -> optional open-world fun with markers; rewards feed weapons"). Child of Freedom
## (`WorldRoam.instance`). Four things to do any time, none of them needs a menu or a mission:
##   FLIGHT SCHOOL   fly any aircraft through the rings: down the avenue from the airstrip, out over the desert and back to the strip       (start ring on the strip)
##   OFF-ROAD TRIAL  drive any ground vehicle through the gates of QUARRY TRACK, up the hill to the old mine                                 (start ring where the track begins, a rover and a quad wait there)
##   JET-SKI LAPS    two laps of the harbour buoys on a jet ski (or any boat)                                                                (start ring in the harbour basin)
##   TREASURE HUNT   six caches lie hidden around the crash site, the old mine, the observatory, the cabins and the lodge: the SCANNER PULSE gadget reveals those within reach (a beam and a
##                   map pin for a while) and a ping in the direction of the near ones; walk up to a cache to dig it out. The scanner is given for free at the first hunt.
## A course starts by itself when the hero drives into its start ring in a vehicle of the right kind (a gold ring and beam show where while he is near), counts the gates with GateMarks, pays
## credits by time (base plus a bonus per 10 s under par) and keeps the best time. EASY: wide gates, a generous limit, no failure other than time or leaving the vehicle for good. The FIRST
## finish of each activity (and every third cache) also counts as a mission for MissionRewards: the weapon ladder moves (docs/DESIGN.md). Nothing runs while a board mission is running.
## `markers()` feed the minimap (Freedom.markers), `map_markers()` the big map. Logic is driven by `poll(dt)` from _physics_process in play; tests call it with their own dt.

signal started(id: StringName)
signal gate_passed(id: StringName, index: int)
signal finished(id: StringName, ok: bool, reward: int)
signal cache_found(index: int, total: int)

static var instance: WorldRoam

const IDS: Array[StringName] = [&"flight_school", &"offroad", &"jetski", &"treasure"]
const COURSE_IDS: Array[StringName] = [&"flight_school", &"offroad", &"jetski"]
const TITLES := {&"flight_school": "FLIGHT SCHOOL", &"offroad": "OFF-ROAD TRIAL", &"jetski": "JET-SKI LAPS", &"treasure": "TREASURE HUNT"}
const NEEDS := {&"flight_school": &"air", &"offroad": &"ground", &"jetski": &"boat"}
const PAY := {&"flight_school": 300, &"offroad": 260, &"jetski": 340}
const PAR := {&"flight_school": 150.0, &"offroad": 150.0, &"jetski": 110.0}
const LIMIT_X := 2.6                       ## the time limit is this many times the par
const BONUS_PER_10S := 40
const START_R := 24.0
const SEE_START := 520.0                   ## the start ring shows from this far
const LEAVE_GRACE := 8.0
const COOLDOWN := 5.0
const SAVE_PATH := "user://world_roam.cfg"
# treasure
const SCAN_REVEAL_R := 95.0                ## a pulse reveals the caches this close (beam + pin)
const SCAN_PING_R := 220.0                 ## and tells the direction of those this close
const SHOW_TIME := 30.0
const COLLECT_R := 3.8
const CACHE_PAY := 140
const ALL_BONUS := 300
const HINT_R := 200.0

var active: StringName = &""
var gate_i := 0
var elapsed := 0.0
var best: Dictionary = {}                  ## id -> best seconds
var runs: Dictionary = {}                  ## id -> finished runs this session
var rewarded: Dictionary = {}              ## id -> true once the mission reward was handed out (session)
var last_reward := 0
var found: Dictionary = {}                 ## cache index -> true
var revealed: Dictionary = {}              ## cache index -> seconds the beam still shows
var scans := 0
var pings := 0
var treasure_paid := 0                     ## mission rewards of the hunt handed out (every third cache)
var marks: GateMarks
var start_marks: GateMarks

var _courses := {}
var _caches: Array[Dictionary] = []
var _beams: Array[MeshInstance3D] = []
var _rings: Array[MeshInstance3D] = []
var _gates: Array[Vector3] = []
var _off_t := 0.0
var _last_pos := Vector3.INF
var _cool := 0.0
var _hooked: Gadgets
var _hint_t := 0.0
var _start_for: StringName = &""


func _ready() -> void:
	instance = self
	name = "WorldRoam"
	_load()
	Game.new_game.connect(_on_new_game)
	set_physics_process(true)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not Game.is_playing():
		return
	poll(delta)


# --- courses ------------------------------------------------------------------------------------------------------------------------

## {start, gates, radius, need, flat, par, limit, pay, title}; {} when the world cannot build it.
func course(id: StringName) -> Dictionary:
	if _courses.has(id):
		return _courses[id]
	var c := _build(id)
	_courses[id] = c
	return c


func _build(id: StringName) -> Dictionary:
	var gates: Array[Vector3] = []
	var start := Vector3.INF
	var radius := 18.0
	match id:
		&"flight_school":
			var ap := WorldSites.airport()
			var s: Vector3 = ap["strip"]
			var h := float(ap["strip_h"])
			var f := Vector3(-sin(h), 0.0, -cos(h))
			var rt := Vector3(cos(h), 0.0, -sin(h))
			start = Vector3(s.x, TerrainHeight.height_at(s.x, s.z), s.z)
			# down the avenue low (the strip's axis), then out over the open land and back
			var rel := [Vector3(150.0, 20.0, 0.0), Vector3(300.0, 24.0, 0.0), Vector3(450.0, 28.0, 0.0), Vector3(600.0, 32.0, 0.0), Vector3(760.0, 40.0, 0.0),
					Vector3(900.0, 52.0, 70.0), Vector3(1030.0, 64.0, 190.0), Vector3(1000.0, 70.0, 340.0), Vector3(860.0, 64.0, 410.0), Vector3(700.0, 56.0, 300.0),
					Vector3(520.0, 44.0, 150.0), Vector3(330.0, 30.0, 40.0), Vector3(120.0, 14.0, 0.0)]
			for q: Vector3 in rel:
				var p := s + f * q.x + rt * q.z
				var g := TerrainHeight.height_at(p.x, p.z)
				if q.z != 0.0 or q.x > 780.0:
					g = maxf(g, WorldSites.peak_around(p.x, p.z, 30.0))
				gates.append(Vector3(p.x, g + q.y, p.z))
			radius = 22.0
		&"offroad":
			var route := WorldSites.road_route("QUARRY TRACK")
			if route.size() < 8:
				return {}
			var pr := PathFollow.new(route)
			start = route[0]
			var n := clampi(int(pr.total / 150.0), 5, 9)
			for k in n:
				var d := pr.total * float(k + 1) / float(n)
				gates.append(pr.point_at(d) + Vector3(0.0, 1.0, 0.0))
			radius = 15.0
		&"jetski":
			var cs := Harbour.COURSE
			if cs.size() < 6:
				return {}
			start = Vector3(cs[2].x, cs[2].y, cs[2].z)
			for lap in 2:
				for k in [3, 4, 5, 1, 2]:
					gates.append(cs[k])
			radius = 17.0
		_:
			return {}
	var par := float(PAR[id])
	return {"id": id, "start": start, "gates": gates, "radius": radius, "need": NEEDS[id], "flat": id != &"flight_school", "par": par, "limit": par * LIMIT_X, "pay": int(PAY[id]), "title": String(TITLES[id])}


## Vehicle spawn points the activities add (appended to VehicleSpawns.all_points): a rover and a quad at the foot of QUARRY TRACK.
static func vehicle_points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var route := WorldSites.road_route("QUARRY TRACK")
	if route.size() < 4:
		return out
	var pr := PathFollow.new(route)
	var d := pr.dir_at(0.0)
	var side := d.rotated(Vector3.UP, -PI * 0.5)
	var h := atan2(-d.x, -d.z)
	out.append({"id": &"roam_offroad_rover", "kind": &"rover", "pos": route[0] + side * 7.0 + d * 6.0, "h": h, "label": "OFF-ROAD TRIAL"})
	out.append({"id": &"roam_offroad_quad", "kind": &"quad", "pos": route[0] - side * 7.0 + d * 8.0, "h": h, "label": ""})
	return out


static func pay_for(id: StringName, seconds: float) -> int:
	var par := float(PAR.get(id, 120.0))
	return int(PAY.get(id, 200)) + maxi(0, int((par - seconds) / 10.0)) * BONUS_PER_10S


# --- the poll ------------------------------------------------------------------------------------------------------------------------

func _hero() -> Vector3:
	var p := Game.player
	if not is_instance_valid(p):
		return Vector3.INF
	var v := WorldSteps.hero_vehicle()
	return v.global_position if v != null else (p as Node3D).global_position


func _busy() -> bool:
	var m := Game.missions as Missions
	if m == null:
		return false
	if m.board != null and m.board.state != &"idle":
		return true
	return InteriorGameplay.active


func poll(dt: float) -> void:
	_cool = maxf(0.0, _cool - dt)
	var hero := _hero()
	if not hero.is_finite():
		return
	_tick_treasure(dt, hero)
	if active != &"":
		_tick_run(dt, hero)
	else:
		_idle(dt, hero)
	_last_pos = hero


func _idle(_dt: float, hero: Vector3) -> void:
	if _busy():
		_hide_start()
		return
	var v := WorldSteps.hero_vehicle()
	var near_id: StringName = &""
	var near_d := SEE_START
	for id in COURSE_IDS:
		var c := course(id)
		if c.is_empty():
			continue
		var s: Vector3 = c["start"]
		var d := Vector2(s.x - hero.x, s.z - hero.z).length()
		if d < near_d:
			near_d = d
			near_id = id
		if _cool <= 0.0 and v != null and WorldSteps.class_ok(v, c["need"]) and _moving(v) and d < START_R and absf(hero.y - s.y) < 40.0:
			start(id)
			return
	if near_id != &"":
		if _start_for != near_id:
			_start_for = near_id
			if start_marks == null:
				start_marks = GateMarks.new()
				add_child(start_marks)
			var s2: Vector3 = course(near_id)["start"]
			var arr: Array[Vector3] = [s2]
			start_marks.show_gate(arr, 0, START_R, true)
	else:
		_hide_start()


## A vehicle that is under way (or flying): a course never starts under a hero who only sits in a parked vehicle on the ring.
static func _moving(v: Vehicle) -> bool:
	return absf(v.speed) > 3.0 or (v.craft != null and v.craft.airborne)


func _hide_start() -> void:
	_start_for = &""
	if start_marks != null:
		start_marks.hide_all()


## Begin a course (the hero drove into its ring; tests call it directly). False when the course does not exist or another one runs.
func start(id: StringName) -> bool:
	if active != &"" or not COURSE_IDS.has(id):
		return false
	var c := course(id)
	if c.is_empty():
		return false
	active = id
	_gates = c["gates"] as Array[Vector3]
	gate_i = 0
	elapsed = 0.0
	_off_t = 0.0
	_last_pos = Vector3.INF
	_hide_start()
	if marks == null:
		marks = GateMarks.new()
		add_child(marks)
	marks.show_gate(_gates, 0, float(c["radius"]), bool(c["flat"]))
	Game.say("%s  GO  %d GATES" % [String(c["title"]), _gates.size()], 2.5)
	Sfx.play(&"mission_start")
	started.emit(id)
	return true


func cancel(why: String) -> void:
	if active == &"":
		return
	var id := active
	active = &""
	marks.hide_all()
	_cool = COOLDOWN
	Game.say("%s ENDED  %s" % [String(TITLES[id]), why], 2.5)
	finished.emit(id, false, 0)


func _tick_run(dt: float, hero: Vector3) -> void:
	if _busy():
		cancel("MISSION STARTED")
		return
	var c := course(active)
	elapsed += dt
	var v := WorldSteps.hero_vehicle()
	if not WorldSteps.class_ok(v, c["need"]):
		_off_t += dt
		_last_pos = Vector3.INF
		if _off_t > LEAVE_GRACE:
			cancel("LEFT THE VEHICLE")
		return
	_off_t = 0.0
	if elapsed > float(c["limit"]):
		_finish(false)
		return
	var g := _gates[gate_i]
	var rad := float(c["radius"])
	var hit := false
	if WorldSteps.is_air(c["need"]):
		hit = (WorldSteps.seg_dist(_last_pos, hero, g) if _last_pos.is_finite() else hero.distance_to(g)) < rad
	else:
		var a2 := Vector3(_last_pos.x, 0.0, _last_pos.z) if _last_pos.is_finite() else Vector3(hero.x, 0.0, hero.z)
		hit = WorldSteps.seg_dist(a2, Vector3(hero.x, 0.0, hero.z), Vector3(g.x, 0.0, g.z)) < rad
	if not hit:
		return
	gate_i += 1
	gate_passed.emit(active, gate_i - 1)
	Sfx.play(&"ui_contract_accept")
	if gate_i >= _gates.size():
		_finish(true)
		return
	Game.say("GATE %d OF %d" % [gate_i + 1, _gates.size()], 1.0)
	marks.show_gate(_gates, gate_i, rad, bool(c["flat"]))


func _finish(ok: bool) -> void:
	var id := active
	active = &""
	marks.hide_all()
	_cool = COOLDOWN
	runs[id] = int(runs.get(id, 0)) + 1
	var reward := pay_for(id, elapsed) if ok else 0
	if ok and int(runs[id]) > 1:
		reward = int(reward * 0.5)                           # a repeat pays half: the first run is the prize, the best time the game
	last_reward = reward
	if ok:
		if float(best.get(id, 0.0)) <= 0.0 or elapsed < float(best[id]):
			best[id] = elapsed
		var prog := Game.progress as Progress
		if prog != null:
			prog.add_credits(reward)
			prog.bonus_score(reward)
		_reward_mission(id)
		_save()
		Game.say("%s  %.1f S  +%d" % [String(TITLES[id]), elapsed, reward], 3.5)
	else:
		Game.say("%s  TIME UP" % String(TITLES[id]), 3.0)
	finished.emit(id, ok, reward)


## The first finish of an activity counts as a mission for the weapon ladder (MissionRewards), unless the DEMO profile owns everything anyway.
func _reward_mission(id: StringName) -> void:
	if bool(rewarded.get(id, false)) or DemoMode.active or Game.progress == null:
		return
	rewarded[id] = true
	MissionRewards.complete(&"activity", String(TITLES[id]))


# --- the treasure hunt --------------------------------------------------------------------------------------------------------------

func caches() -> Array[Dictionary]:
	if _caches.is_empty():
		_caches = WorldSites.treasure_spots()
	return _caches


func found_count() -> int:
	return found.size()


func _hook_gadgets() -> void:
	var pl := Game.player as Player
	if pl == null or pl.gadgets == null or pl.gadgets == _hooked:
		return
	_hooked = pl.gadgets
	if not _hooked.used.is_connected(_on_gadget):
		_hooked.used.connect(_on_gadget)


func _on_gadget(id: StringName) -> void:
	if id != &"scanner":
		return
	scan(_hero())


## A scanner pulse at `at`: the caches within SCAN_REVEAL_R show their beam for SHOW_TIME seconds, the ones within SCAN_PING_R say which way they lie. Returns the number revealed.
func scan(at: Vector3) -> int:
	scans += 1
	var n := 0
	var near_d := INF
	var near_dir := ""
	for i in caches().size():
		if found.has(i):
			continue
		var p: Vector3 = _caches[i]["pos"]
		var d := Vector2(p.x - at.x, p.z - at.z).length()
		if d <= SCAN_REVEAL_R:
			revealed[i] = SHOW_TIME
			n += 1
		elif d <= SCAN_PING_R and d < near_d:
			near_d = d
			near_dir = _compass(Vector2(p.x - at.x, p.z - at.z))
	if n > 0:
		Game.say("SIGNAL FOUND  %d CACHE%s NEAR" % [n, "" if n == 1 else "S"], 2.5)
	elif near_dir != "":
		pings += 1
		Game.say("FAINT SIGNAL  %s  %d M" % [near_dir, roundi(near_d)], 2.5)
	return n


static func _compass(v: Vector2) -> String:
	var a := fposmod(rad_to_deg(atan2(v.x, -v.y)), 360.0)
	return ["NORTH", "NORTH-EAST", "EAST", "SOUTH-EAST", "SOUTH", "SOUTH-WEST", "WEST", "NORTH-WEST"][int(round(a / 45.0)) % 8]


func _tick_treasure(dt: float, hero: Vector3) -> void:
	_hook_gadgets()
	var cs := caches()
	if cs.is_empty():
		return
	for i in cs.size():
		if found.has(i):
			continue
		var p: Vector3 = cs[i]["pos"]
		var d := Vector2(p.x - hero.x, p.z - hero.z).length()
		if revealed.has(i):
			revealed[i] = float(revealed[i]) - dt
			if float(revealed[i]) <= 0.0:
				revealed.erase(i)
		if d < COLLECT_R and absf(hero.y - p.y) < 6.0 and not _busy():
			_collect(i)
			continue
		if d < HINT_R and not Gear.is_owned(&"scanner"):
			_grant_scanner()
		if d < HINT_R and Gear.gadget == &"" and Gear.is_owned(&"scanner"):
			Gear.equip(&"scanner")
		if d < HINT_R:
			_hint_t -= dt
			if _hint_t <= 0.0 and not revealed.has(i) and Game.is_playing() and not _busy():
				_hint_t = 24.0
				Game.say("TREASURE HUNT  USE THE SCANNER NEAR %s" % String(WorldSites.CACHE_DEFS[i]["site"]).to_upper().replace("_", " "), 3.0)
		if revealed.has(i):
			_show_beam(i, p)
	for i in _beams.size():
		if not revealed.has(i) or found.has(i):
			_beams[i].visible = false
			if i < _rings.size():
				_rings[i].visible = false


func _show_beam(i: int, p: Vector3) -> void:
	while _beams.size() <= i:
		var b := MissionVisuals.make_beam(Color(0.3, 1.0, 0.8), 0.7, 90.0, 1.3, 0.35)
		b.visible = false
		b.top_level = true
		add_child(b)
		_beams.append(b)
	_beams[i].global_position = Vector3(p.x, p.y + 45.0, p.z)
	_beams[i].visible = true
	while _rings.size() <= i:
		var rg := MissionVisuals.make_ring(2.2)
		rg.visible = false
		rg.top_level = true
		add_child(rg)
		_rings.append(rg)
	_rings[i].global_position = Vector3(p.x, p.y + 0.2, p.z)
	_rings[i].visible = true


func _grant_scanner() -> void:
	Gear.give(&"scanner")
	if Gear.gadget == &"":
		Gear.equip(&"scanner")
	Game.say("TREASURE HUNT  SCANNER PULSE ADDED  USE GADGET", 3.5)


func _collect(i: int) -> void:
	found[i] = true
	revealed.erase(i)
	var prog := Game.progress as Progress
	var pay := CACHE_PAY + 20 * (found.size() - 1)
	var total := caches().size()
	var all := found.size() >= total
	if all:
		pay += ALL_BONUS
	if prog != null:
		prog.add_credits(pay)
		prog.bonus_score(pay)
	var p: Vector3 = _caches[i]["pos"]
	FX.burst(p + Vector3(0.0, 0.6, 0.0), Color(0.3, 1.0, 0.8), 14, 7.0, 0.5, 0.0)
	Game.say("%s FOUND  %d OF %d  +%d" % [String(_caches[i]["name"]), found.size(), total, pay], 3.0)
	Sfx.play(&"ui_contract_accept")
	if found.size() % 3 == 0 and not DemoMode.active and Game.progress != null:
		treasure_paid += 1
		MissionRewards.complete(&"activity", "TREASURE HUNT")
	_save()
	cache_found.emit(i, total)


# --- markers ---------------------------------------------------------------------------------------------------------------------------

## Minimap markers {pos, color, radius, goal, label, kind} (Freedom.markers): the start ring of each course near the hero, the next gate of the running one, the revealed caches.
func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hero := _hero()
	if active != &"":
		if gate_i < _gates.size():
			out.append({"pos": _gates[gate_i], "color": Color(1.0, 0.8, 0.3), "radius": 14.0, "goal": true, "label": String(TITLES[active]), "kind": &"job"})
	elif hero.is_finite():
		for id in COURSE_IDS:
			var c := course(id)
			if c.is_empty():
				continue
			var s: Vector3 = c["start"]
			if Vector2(s.x - hero.x, s.z - hero.z).length() < 900.0:
				out.append({"pos": s, "color": Color(1.0, 0.72, 0.2), "radius": START_R, "goal": false, "label": String(TITLES[id]), "kind": &"job"})
	for i in revealed.keys():
		if not found.has(i) and int(i) < caches().size():
			out.append({"pos": _caches[int(i)]["pos"], "color": Color(0.3, 1.0, 0.8), "radius": 6.0, "goal": false, "label": "CACHE", "kind": &"job"})
	return out


## Pins of the big map: {kind, pos, fog, label}: the three course starts and the sites of the hunt that still hide a cache.
static func map_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var wr := instance
	if wr == null:
		return out
	for id in COURSE_IDS:
		var c := wr.course(id)
		if not c.is_empty():
			out.append({"kind": &"job", "pos": c["start"], "fog": false, "label": String(TITLES[id])})
	for i in wr.caches().size():
		if not wr.found.has(i):
			var site := OutskirtsSites.by_id(StringName(WorldSites.CACHE_DEFS[i]["site"]))
			if not site.is_empty():
				out.append({"kind": &"items", "pos": site["pos"], "fog": false, "label": "TREASURE HUNT"})
				break
	return out


# --- saving --------------------------------------------------------------------------------------------------------------------------

func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	for id in IDS:
		var v := float(cf.get_value("best", String(id), 0.0))
		if v > 0.0:
			best[id] = v
		if bool(cf.get_value("rewarded", String(id), false)):
			rewarded[id] = true
	for k in cf.get_section_keys("found"):
		if bool(cf.get_value("found", k, false)):
			found[int(k)] = true
	treasure_paid = int(cf.get_value("meta", "treasure_paid", 0))


func _save() -> void:
	var cf := ConfigFile.new()
	for id: StringName in best:
		cf.set_value("best", String(id), float(best[id]))
	for id: StringName in rewarded:
		cf.set_value("rewarded", String(id), true)
	for i: int in found:
		cf.set_value("found", str(i), true)
	cf.set_value("meta", "treasure_paid", treasure_paid)
	cf.save(SAVE_PATH)


## Forget everything (tests, a fresh game).
func reset() -> void:
	best.clear()
	runs.clear()
	rewarded.clear()
	found.clear()
	revealed.clear()
	treasure_paid = 0
	active = &""
	if marks != null:
		marks.hide_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _on_new_game() -> void:
	var prog := Game.progress as Progress
	if prog != null and bool(prog.get(&"fresh_game")):
		reset()
