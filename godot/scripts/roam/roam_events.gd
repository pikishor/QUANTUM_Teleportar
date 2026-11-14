class_name RoamEvents
extends Node
## RANDOM WORLD EVENTS OF THE OUTSKIRTS (wave 111; the city has its own, `CityEvents`). While the hero roams outside the city, on foot or in a ground vehicle, something turns up every
## 45-75 s (the first after 25 s) 170-340 m away, in ANY biome (mountain, forest, desert, plains, beach). One at a time, on a ring and a column, on the minimap and the big map, told by a line:
##   CONVOY      SMUGGLER CONVOY: a cargo truck with two rover escorts runs along the nearest road (scripted vehicles, `PathFollow`); it waits until the hero is within about 190 m and eases off when
##               he is behind, so it is always catchable. Wreck the truck (or take it over) before it reaches the end of the road.
##   CRASH       SUPPLY CRASH: a burning wreck with smoke; scavengers (a roster encounter) turn up when the hero comes within 140 m; reach the wreck to recover the supplies.
##   RAID        ALIEN RAID: a hive encounter that comes at the hero (aggro); kill every one of them. More and nastier at night (`RosterSpecies.encounter_weight` weighs the night).
##   SMUGGLERS   SMUGGLER STASH: mercenary guards by a parked van with crates; clear the guards, then step up to the crates.
## What turns up depends on the biome and the hour (`weights()`: smugglers on beaches, crashes on the mountains, raids in the forests and at night, convoys on the plains by day), and a kind the hero
## has never finished is twice as likely. The first finish of each kind is a discovery; every one pays credits and every third counts as a mission for MissionRewards (the weapon ladder).
## EASY: nothing here can kill by surprise; the hero is strong, the groups are small and the ring tells where. `poll(dt, hero)` is driven by RoamWorld; tests call `spawn(kind, pos)`.

signal spawned(e: Dictionary)
signal ended(e: Dictionary, ok: bool)

const DEF := {
	&"convoy": {"label": "SMUGGLER CONVOY", "ttl": 480.0, "pay": 340, "color": Color(1.0, 0.72, 0.25), "radius": 9.0},
	&"crash": {"label": "SUPPLY CRASH", "ttl": 300.0, "pay": 240, "color": Color(1.0, 0.5, 0.2), "radius": 7.0},
	&"raid": {"label": "ALIEN RAID", "ttl": 200.0, "pay": 300, "color": Color(1.0, 0.3, 0.28), "radius": 16.0},
	&"smugglers": {"label": "SMUGGLER STASH", "ttl": 300.0, "pay": 280, "color": Color(0.7, 0.55, 1.0), "radius": 7.0},
}
const FIRST_AT := 25.0
const GAP_MIN := 45.0
const GAP_MAX := 75.0
const KIND_COOLDOWN := 150.0
const MIN_D := 170.0
const MAX_D := 340.0
const FORGET_D := 900.0
const CONVOY_CRUISE := 14.0
const CONVOY_WAIT := 190.0
const GUARD_TRIGGER := 140.0
const REACH_R := 6.0
const WORLD_LIM := 2850.0
const ROADS: Array[String] = ["PASS ROAD", "DESERT ROAD", "COAST ROAD", "FOREST ROAD", "MOUNTAIN TRACK", "QUARRY TRACK", "HARBOUR ROAD", "SUMMIT ROAD", "RIDGE TRACK"]

var world: RoamWorld
var active: Array[Dictionary] = []
var prompt := ""
var clock := 0.0
var next_spawn := FIRST_AT
var completed := 0
var failed := 0
var enabled := true
var rng := RandomNumberGenerator.new()

var _cool := {}
var _next_id := 1
var _marks: RoamMarks
var _smoke_t := 0.0


func _init(w: RoamWorld = null) -> void:
	world = w
	name = "RoamEvents"
	rng.seed = 77077


func _ready() -> void:
	_marks = RoamMarks.new(2)
	_marks.host = self                                       # joins the tree on the first event ring (an idle pool still costs the phone draw calls)


func reset() -> void:
	for e in active.duplicate():
		_cleanup(e, false)
	active.clear()
	_cool.clear()
	clock = 0.0
	next_spawn = FIRST_AT
	completed = 0
	failed = 0
	prompt = ""
	if _marks != null:
		_marks.hide_all()


# --- what turns up where --------------------------------------------------------------------------------------------------------------

## [[kind, weight], ...] for a biome and night 0..1 (pure rule, no scene).
static func weights(biome: StringName, night: float) -> Array:
	var b := {&"convoy": {&"plains": 3.0, &"desert": 3.0, &"forest": 2.0, &"mountain": 1.0, &"beach": 1.0},
			&"crash": {&"plains": 2.0, &"desert": 2.0, &"forest": 2.0, &"mountain": 3.0, &"beach": 2.0},
			&"raid": {&"plains": 1.5, &"desert": 2.0, &"forest": 3.0, &"mountain": 3.0, &"beach": 1.0},
			&"smugglers": {&"plains": 2.0, &"desert": 2.0, &"forest": 1.5, &"mountain": 0.5, &"beach": 4.0}}
	var out: Array = []
	for k: StringName in RoamData.EVENT_KINDS:
		var w := float((b[k] as Dictionary).get(biome, 0.0))
		if w <= 0.0:
			continue
		match k:
			&"convoy":
				w *= 1.0 - 0.6 * night
			&"raid":
				w *= 1.0 + 2.5 * night
			&"smugglers":
				w *= 1.0 + 0.8 * night
		out.append([k, w])
	return out


func _biome(p: Vector3) -> StringName:
	return TerrainBase.biome_at(p.x, p.z, TerrainHeight.height_at(p.x, p.z))


func _kind_active(k: StringName) -> bool:
	for e in active:
		if e["kind"] == k:
			return true
	return false


func _alien() -> AlienWorld:
	return AlienWorld.instance


# --- the poll -------------------------------------------------------------------------------------------------------------------------

func poll(dt: float, hero: Vector3) -> void:
	prompt = ""
	var busy := world != null and (world.busy() or world.runs.active != &"")
	for i in range(active.size() - 1, -1, -1):
		var e := active[i]
		e["ttl"] = float(e["ttl"]) - dt
		if RoamWorld.flat(e["pos"], hero) > FORGET_D:
			_end(e, false, true)
			continue
		var st := _step(e, dt, hero)
		if st >= 0:
			_end(e, st == 1, false)
		elif float(e["ttl"]) <= 0.0:
			_end(e, false, false)
	_show(hero)
	if not enabled or busy or not Game.is_playing():
		return
	clock += dt
	if active.is_empty() and clock >= next_spawn:
		next_spawn = clock + rng.randf_range(GAP_MIN, GAP_MAX)
		spawn_near(hero)


## Where the hero stands decides whether anything turns up (outside the city, on land, on foot or in a ground vehicle).
func can_spawn_at(hero: Vector3) -> bool:
	var v := WorldSteps.hero_vehicle()
	if v != null and not WorldSteps.class_ok(v, &"ground"):
		return false
	var b := _biome(hero)
	return b != TerrainBase.CITY and b != TerrainBase.OCEAN


## A scheduler step: pick a kind (by biome, hour and what is still undiscovered), a place 170-340 m away and build it. Returns the event or {}.
func spawn_near(hero: Vector3, kind: StringName = &"") -> Dictionary:
	if active.size() >= 1 or not can_spawn_at(hero):
		return {}
	var night := DayNight.night_now
	var b := _biome(hero)
	var list := weights(b, night)
	var pool: Array = []
	for w in list:
		var k: StringName = w[0]
		if (kind != &"" and k != kind) or clock < float(_cool.get(k, -1.0)):
			continue
		var wt := float(w[1])
		if world != null and int(world.events_done.get(k, 0)) == 0:
			wt *= 2.0
		pool.append([k, wt])
	if kind != &"" and pool.is_empty():
		pool.append([kind, 1.0])
	var order := pool.duplicate()
	while not order.is_empty():
		var k: StringName = AlienSpecies.pick(order, rng.randf())
		var pos := _place(k, hero)
		if pos.is_finite():
			var e := spawn(k, pos)
			if not e.is_empty():
				return e
		for i in order.size():
			if order[i][0] == k:
				order.remove_at(i)
				break
	return {}


func _place(kind: StringName, hero: Vector3) -> Vector3:
	if kind == &"convoy":
		return _convoy_place(hero)
	for i in 30:
		var a := rng.randf() * TAU
		var d := rng.randf_range(MIN_D, MAX_D)
		var x := clampf(hero.x + cos(a) * d, -WORLD_LIM, WORLD_LIM)
		var z := clampf(hero.z + sin(a) * d, -WORLD_LIM, WORLD_LIM)
		var h := TerrainHeight.height_at(x, z)
		if TerrainHeight.depth_at(x, z) > 0.0 or TerrainHeight.slope_at(x, z) > 0.4:
			continue
		var bi := TerrainBase.biome_at(x, z, h)
		if bi == TerrainBase.CITY or bi == TerrainBase.OCEAN:
			continue
		if kind == &"smugglers" and (bi == TerrainBase.MOUNTAIN):
			continue
		return Vector3(x, h, z)
	return Vector3.INF


## The road sample nearest to the hero within 120-650 m outside the city: {road, s} for `_convoy_place`.
func _road_near(hero: Vector3) -> Dictionary:
	var best := {}
	var bd := 650.0
	for name_s: String in ROADS:
		var route := _route(name_s)
		if route.size() < 8:
			continue
		var pf := _sampler(name_s)
		var k := 0.0
		while k < pf.total:
			var q := pf.point_at(k)
			var d := RoamWorld.flat(q, hero)
			if d >= 120.0 and d < bd and TerrainBase.biome_at(q.x, q.z, q.y) != TerrainBase.CITY and TerrainHeight.depth_at(q.x, q.z) <= 0.0:
				bd = d
				best = {"road": name_s, "s": k, "route": route}
			k += 40.0
	return best


static var _routes := {}
static var _samplers := {}


## The road polylines are built once (they only change with the terrain).
static func _route(road: String) -> PackedVector3Array:
	if not _routes.has(road):
		_routes[road] = WorldSites.road_route(road)
	return _routes[road]


static func _sampler(road: String) -> PathFollow:
	if not _samplers.has(road):
		_samplers[road] = PathFollow.new(_route(road))
	return _samplers[road]


func _convoy_place(hero: Vector3) -> Vector3:
	var r := _road_near(hero)
	if r.is_empty():
		return Vector3.INF
	_pending_road = r
	return _sampler(String(r["road"])).point_at(float(r["s"]))


var _pending_road: Dictionary = {}


# --- building the events --------------------------------------------------------------------------------------------------------------

## Builds event `kind` at `pos` (the scheduler and the tests call this). {} when it cannot be built (no creature room, no road).
func spawn(kind: StringName, pos: Vector3) -> Dictionary:
	if not DEF.has(kind):
		return {}
	var e := {"id": _next_id, "kind": kind, "pos": pos, "ttl": float(DEF[kind]["ttl"]), "biome": _biome(pos), "night": DayNight.night_now,
			"creatures": [], "vehicles": [], "state": &"live", "guards_out": false, "t": 0.0}
	var ok := false
	match kind:
		&"crash":
			ok = _build_crash(e)
		&"raid":
			ok = _build_raid(e)
		&"smugglers":
			ok = _build_smugglers(e)
		&"convoy":
			ok = _build_convoy(e)
	if not ok:
		_cleanup(e, false)
		return {}
	_next_id += 1
	_cool[kind] = clock + KIND_COOLDOWN
	active.append(e)
	var hero := world._hero() if world != null else Vector3.INF
	Game.say("%s  %s" % [String(DEF[kind]["label"]), _where(e, hero)], 3.5)
	Sfx.play(&"mission_start", -6.0)
	spawned.emit(e)
	return e


func _where(e: Dictionary, hero: Vector3) -> String:
	if not hero.is_finite():
		return ""
	var p: Vector3 = e["pos"]
	return "%d M %s" % [roundi(RoamWorld.flat(p, hero) / 10.0) * 10, WorldRoam._compass(Vector2(p.x - hero.x, p.z - hero.z))]


func _park(kind: StringName, at: Vector3, heading: float) -> Vehicle:
	var vm := Game.vehicles as VehicleManager
	if vm == null:
		return null
	var v := vm.spawn_parked(kind, at, heading)
	if v == null:
		return null
	v.set_meta(&"hold", true)
	return v


## A burning wreck of an aircraft with the supplies by it.
func _build_crash(e: Dictionary) -> bool:
	var p: Vector3 = e["pos"]
	var kind := &"heli" if (e["biome"] == TerrainBase.MOUNTAIN or e["biome"] == TerrainBase.FOREST) else &"plane"
	var v := _park(kind, p, rng.randf() * TAU)
	if v != null:
		v.become_wreck()
		(e["vehicles"] as Array).append(v)
	e["wreck"] = v != null
	return true


func _faction_pick(faction: StringName, e: Dictionary) -> StringName:
	var a := _alien()
	if a == null or a.roster == null:
		return &""
	var tier := a.roster.tier()
	var list: Array = []
	for eid: StringName in RosterSpecies.ENCOUNTERS:
		if faction != &"" and RosterSpecies.ENCOUNTERS[eid]["faction"] != faction:
			continue
		var w := RosterSpecies.encounter_weight(eid, e["biome"], float(e["night"]), &"", tier)
		if w > 0.0:
			list.append([eid, w])
	if list.is_empty() and faction != &"":
		return _faction_pick(&"", e)
	return RosterSpecies.pick(list, rng.randf()) if not list.is_empty() else &""


func _build_raid(e: Dictionary) -> bool:
	var a := _alien()
	if a == null or a.roster == null:
		return false
	var groups := 2 if float(e["night"]) > 0.6 else 1
	var p: Vector3 = e["pos"]
	for g in groups:
		var eid := _faction_pick(RosterSpecies.HIVE, e)
		if eid == &"":
			continue
		var off := Vector3(rng.randf_range(-12.0, 12.0), 0.0, rng.randf_range(-12.0, 12.0)) if g > 0 else Vector3.ZERO
		var made := a.roster.spawn_encounter(eid, p + off, true)
		for c in made:
			_adopt(e, c)
	return not (e["creatures"] as Array).is_empty()


## A creature of event `e`: listed with it and held, because the ambient despawn rule of the AlienWorld (about 140 to 180 m from the hero, by tier) would remove it the moment it stands in
## the ring 170-340 m away where the events are built (the raid then counted as won after one second, the guards of a stash were gone before the hero came; wave 113 CI: test_free_roam_world).
## `_cleanup` lets it go again.
func _adopt(e: Dictionary, c: AlienCreature) -> void:
	c.set_meta(&"hold", true)
	(e["creatures"] as Array).append(c)


func _build_smugglers(e: Dictionary) -> bool:
	var a := _alien()
	if a == null or a.roster == null:
		return false
	var p: Vector3 = e["pos"]
	var eid := _faction_pick(RosterSpecies.CONTRACT, e)
	if eid == &"":
		return false
	var made := a.roster.spawn_encounter(eid, p + Vector3(6.0, 0.0, 5.0), false)
	if made.is_empty():
		return false
	for c in made:
		_adopt(e, c)
	var v := _park(&"van", p, rng.randf() * TAU)
	if v != null:
		(e["vehicles"] as Array).append(v)
	return true


func _build_convoy(e: Dictionary) -> bool:
	var r := _pending_road
	_pending_road = {}
	if r.is_empty():
		return false
	var route: PackedVector3Array = r["route"]
	var s0 := float(r["s"])
	var pf0 := PathFollow.new(route)
	# run away from the nearer end: along the road toward whichever end is farther
	var forward := (pf0.total - s0) >= s0
	var pts := route
	var start_s := s0
	if not forward:
		var rev := PackedVector3Array()
		for i in range(route.size() - 1, -1, -1):
			rev.append(route[i])
		pts = rev
		start_s = pf0.total - s0
	var kinds: Array[StringName] = [&"truck", &"rover", &"rover"]
	var gaps := [0.0, 22.0, 44.0]
	var paths: Array = []
	for k in kinds.size():
		var pf := PathFollow.new(pts)
		var ss := maxf(start_s - float(gaps[k]), 4.0)
		var at := pf.point_at(ss)
		var d := pf.dir_at(ss)
		var v := _park(kinds[k], at, atan2(-d.x, -d.z))
		if v == null:
			if k == 0:
				return false
			continue
		v.scripted = true
		v.script_thr = 0.0
		v.script_steer = 0.0
		if k == 0:
			v.max_hp *= 2.5
			v.hp = v.max_hp
			v.exploded.connect(func(_x: Vehicle) -> void: e["lead_down"] = true)
		pf.s = ss
		pf._i = 0
		pf.advance(at)
		paths.append(pf)
		(e["vehicles"] as Array).append(v)
	e["paths"] = paths
	e["road"] = String(r["road"])
	return true


# --- stepping an event ----------------------------------------------------------------------------------------------------------------

## 1 = done (success), 0 = over (failed), -1 = running.
func _step(e: Dictionary, dt: float, hero: Vector3) -> int:
	e["t"] = float(e["t"]) + dt
	var p: Vector3 = e["pos"]
	match e["kind"]:
		&"crash":
			_smoke(e, hero, dt)
			if not bool(e["guards_out"]) and RoamWorld.flat(p, hero) < GUARD_TRIGGER:
				e["guards_out"] = true
				_scavengers(e)
			if RoamWorld.flat(p, hero) < REACH_R and absf(hero.y - p.y) < 90.0:
				return 1
		&"raid":
			if _alive(e) == 0 and float(e["t"]) > 1.0:
				return 1
		&"smugglers":
			if RoamWorld.flat(p, hero) < REACH_R * 2.0 and absf(hero.y - p.y) < 90.0:
				if _alive(e) == 0:
					return 1
				prompt = "SMUGGLER STASH  CLEAR THE GUARDS FIRST"
		&"convoy":
			return _step_convoy(e, dt, hero)
	return -1


func _alive(e: Dictionary) -> int:
	var n := 0
	for c in e["creatures"]:
		if is_instance_valid(c) and not (c as AlienCreature).dead:
			n += 1
	return n


func _scavengers(e: Dictionary) -> void:
	var a := _alien()
	if a == null or a.roster == null:
		return
	var eid := _faction_pick(RosterSpecies.CONTRACT, e)
	if eid == &"":
		return
	var p: Vector3 = e["pos"]
	for c in a.roster.spawn_encounter(eid, p + Vector3(14.0, 0.0, -9.0), true):
		_adopt(e, c)
	Game.say("SCAVENGERS AT THE WRECK", 2.5)


func _smoke(e: Dictionary, hero: Vector3, dt: float) -> void:
	_smoke_t -= dt
	if _smoke_t > 0.0 or RoamWorld.flat(e["pos"], hero) > 260.0:
		return
	_smoke_t = 1.3
	var p: Vector3 = e["pos"]
	FX.burst(p + Vector3(0.0, 2.0, 0.0), Color(0.16, 0.16, 0.17, 0.75), 4, 1.5, 1.8, -1.6, 3.0)
	FX.burst(p + Vector3(0.0, 1.2, 0.0), Color(1.0, 0.55, 0.15), 3, 2.0, 0.5, 1.0, 1.4)


func _step_convoy(e: Dictionary, dt: float, hero: Vector3) -> int:
	var vs: Array = e["vehicles"]
	var paths: Array = e["paths"]
	if vs.is_empty():
		return 0
	var lead: Vehicle = vs[0] if is_instance_valid(vs[0]) else null
	if lead == null:
		return 1 if bool(e.get("lead_down", false)) else 0
	if lead.dead or lead.wreck or bool(e.get("lead_down", false)):
		return 1
	if lead.driver_is_player:
		return 1
	var d := RoamWorld.flat(lead.global_position, hero)
	var f := clampf(1.6 - d / 120.0, 0.0, 1.0)
	if d > CONVOY_WAIT:
		f = 0.0
	var want := CONVOY_CRUISE * f
	for i in mini(vs.size(), paths.size()):
		var v: Vehicle = vs[i] if is_instance_valid(vs[i]) else null
		if v == null or v.dead or v.wreck or v.driver_is_player:
			continue
		(paths[i] as PathFollow).drive(v, want, dt)
	var pf0 := paths[0] as PathFollow
	e["pos"] = lead.global_position
	if pf0.remaining() < 10.0:
		Game.say("THE CONVOY GOT AWAY", 2.5)
		return 0
	# stuck on something: put it back on the line a few metres ahead
	if want > 3.0 and absf(lead.speed) < 0.8:
		e["stuck"] = float(e.get("stuck", 0.0)) + dt
		if float(e["stuck"]) > 3.0:
			e["stuck"] = 0.0
			for i in mini(vs.size(), paths.size()):
				_put_back(vs[i], paths[i])
	else:
		e["stuck"] = maxf(float(e.get("stuck", 0.0)) - dt, 0.0)
	return -1


func _put_back(v: Vehicle, pf: PathFollow) -> void:
	if not is_instance_valid(v) or v.dead or v.wreck:
		return
	var s2 := pf.s + 7.0
	var q := pf.point_at(s2)
	var dir := pf.dir_at(s2)
	v.global_position = Vector3(q.x, TerrainHeight.height_at(q.x, q.z) + v.base_y, q.z)
	v.heading = atan2(-dir.x, -dir.z)
	v.rotation.y = v.heading
	v.speed = 0.0
	v.vel = Vector3.ZERO
	pf.s = s2


# --- ending an event ------------------------------------------------------------------------------------------------------------------

func _end(e: Dictionary, ok: bool, silent: bool) -> void:
	active.erase(e)
	_cleanup(e, ok)
	if silent:
		return
	var kind: StringName = e["kind"]
	if ok:
		completed += 1
		var pay := int(DEF[kind]["pay"]) + (60 if float(e["night"]) > 0.6 else 0)
		var first := world != null and int(world.events_done.get(kind, 0)) == 0
		if world != null:
			world.events_done[kind] = int(world.events_done.get(kind, 0)) + 1
		var label := String(DEF[kind]["label"])
		if first and world != null:
			world.note(&"event", kind, "%s  DONE" % label, pay)
		else:
			var prog := Game.progress as Progress
			if prog != null:
				prog.add_credits(pay)
				prog.bonus_score(pay)
			Game.say("%s  DONE  +%d" % [label, pay], 3.0)
			if world != null:
				world.save_now()
		if completed % 3 == 0 and not DemoMode.active and Game.progress != null:
			MissionRewards.complete(&"activity", label)
	else:
		failed += 1
		Game.say("%s  OVER" % String(DEF[kind]["label"]), 2.0)
	ended.emit(e, ok)


## The vehicles go back to the streaming rules (a destroyed or abandoned one is recycled), the survivors of a failed event are let go.
func _cleanup(e: Dictionary, ok: bool) -> void:
	var vm := Game.vehicles as VehicleManager
	for v: Vehicle in e["vehicles"]:
		if not is_instance_valid(v):
			continue
		v.remove_meta(&"hold")
		v.scripted = false
		if vm != null and not v.driver_is_player and (v.wreck or not ok or e["kind"] == &"crash") and vm.list.has(v):
			vm._release(v)
	(e["vehicles"] as Array).clear()
	for c: Variant in e["creatures"]:                                          # the survivors of a failed event are let go: the ambient rules take them again
		if is_instance_valid(c):
			(c as AlienCreature).remove_meta(&"hold")
	if _marks != null:
		_marks.hide_all()


# --- the ring and the line ------------------------------------------------------------------------------------------------------------

func _show(hero: Vector3) -> void:
	if _marks == null:
		return
	_marks.hide_all()
	if active.is_empty():
		return
	_marks.hide_all()
	var e := active[0]
	var d: Dictionary = DEF[e["kind"]]
	var p: Vector3 = e["pos"]
	_marks.show_at(0, Vector3(p.x, p.y, p.z), float(d["radius"]), d["color"], true, false)
	if prompt == "" and hero.is_finite() and float(e["t"]) > 5.0:                # the toast at the start says it already (render loop 1: the same line twice)
		prompt = "%s  %s" % [String(d["label"]), _where(e, hero)]


func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in active:
		var d: Dictionary = DEF[e["kind"]]
		out.append({"pos": e["pos"], "color": d["color"], "radius": float(d["radius"]) + 4.0, "goal": true, "label": String(d["label"]), "kind": &"job"})
	return out
