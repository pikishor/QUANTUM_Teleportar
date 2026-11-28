class_name TankSteps
extends RefCounted
## The campaign step kind `tank_task` of the TANK MISSIONS (wave 127, w127-arms; recipes in scripts/missions/tank_missions.gd, runner scripts/missions/campaign_runner.gd, `runner.tank`).
## The hero must sit in a military vehicle (`veh` "tank"). `task`:
##   battle     `n` ENEMY TANKS (TankCrews, mode mission) hold the ground at `pos`; done when every one is destroyed
##   convoy     `trucks` CONVOY TRUCKS drive the road `pts` (puppets, meta tank_puppet, CONVOY_SPEED m/s); enemy tanks come at them in `waves` (each wave appears ahead of the lead truck
##              and goes for the nearest truck or the hero); the convoy HALTS while an enemy tank is within HALT_R of the lead; done when the lead reaches the last point, failed when every truck burns
##   artillery  `n` TARGETS (parked armour, meta tank_target) stand around `pos`; done when all are wrecked (the howitzer's marker snaps onto a target close to the crosshair, TankArms.SNAP_R)
## w129-tankmis (TankMissions.near_on): the steps keep the hero's own tank (`ride`, held) and WAIT while he is out of it (the crews hold still and hold fire, the beacon goes to the
## tank, "GET BACK IN THE TANK"); battle crews start at `spawns` down the street and come for him; a `road` convoy is DRIVEN: real trucks (Vehicle.scripted, their own physics)
## steer along the lane line `pts` with rounded corners, in order, keeping their gap, slowing for the corners, waiting for the escort to join (`join` m) and to keep up (KEEP_UP m);
## artillery targets stand on `spots`.
## EASY like the other board missions: weak crews (their hp), slow reloads, generous clocks, every failed run makes the enemies weaker. One instance per runner; reset at every step.

const CONVOY_SPEED := 7.0
const HALT_R := 130.0
const TRUCK_HP := 1600.0
const GAP := 16.0                          ## w129-tankmis: metres between two driven convoy trucks
const CORNER_R := 11.0                     ## radius of the rounded corners of the convoy road
const CORNER_SPEED := 4.0
const KEEP_UP := 110.0                     ## the driven convoy waits while the escort is farther than this from the lead
const LOOK := 9.0                          ## metres ahead on the road a driven truck steers at
## w129-critic: an army operation on a city street is not a crime spree. The fight of a tank mission (enemy hulls blowing up, shells and husks killing the people on the pavement,
## witnesses calling it in) lifted the heat to 3.7 stars and sent 3 police cars after the hero DURING the TANK BATTLE. While a tank step runs, the heat is held under
## TASK_HEAT_CAP, below the level where the police stand down (VehicleSpecs.COP_STAND_DOWN; the hack / defend cap 1.5 still let an interceptor tail him). W129C_OLD=1 = old.
static var heat_hold := OS.get_environment("W129C_OLD") != "1"
const TASK_HEAT_CAP := VehicleSpecs.COP_STAND_DOWN * 0.8

var r: CampaignRunner
var task: StringName = &""
var enemies: Array[Vehicle] = []
var targets: Array[Vehicle] = []
var trucks: Array[Vehicle] = []
var kills := 0
var need := 0
var wave := 0
var waves := 0
var halted := false
var _pts: Array[Vector3] = []
var _pi := 1
var _lead_d := 0.0                         ## metres the lead truck has driven along the road
var ride: Vehicle = null                   ## w129-tankmis: the hero's tank for this step (held while the step runs)
var waiting := false                       ## the hero is out of his tank: the step waits
var joined := false                        ## a driven convoy: the escort came up to it
var behind := false                        ## a driven convoy waits: the escort fell back past KEEP_UP
var road := PackedVector3Array()           ## a driven convoy: its lane line, sampled every ~2 m with rounded corners
var _cum := PackedFloat32Array()           ## arc length at each sample of `road`
var _ts: Array[float] = []                 ## arc length of every truck along `road`
var _stuck: Array[float] = []
var _back: Array[float] = []


func _init(runner: CampaignRunner) -> void:
	r = runner


func _vm() -> VehicleManager:
	return Game.vehicles as VehicleManager


func in_tank() -> bool:
	return WorldSteps.class_ok(WorldSteps.hero_vehicle(), WorldSteps.need_of(r.step))


func _ground(p: Vector3) -> float:
	if absf(p.x) > TerrainHeight.CITY_HALF or absf(p.z) > TerrainHeight.CITY_HALF:
		return TerrainHeight.height_at(p.x, p.z)
	return 0.0


func _easier() -> float:
	return maxf(1.0 - 0.15 * float(mini(maxi(r.fails, 0), 3)), 0.5)


# --- begin -----------------------------------------------------------------------------------------------------------------------------

func begin() -> bool:
	clean()
	task = StringName(str(r.step.get("task", "")))
	kills = 0
	wave = 0
	halted = false
	var tc := TankCrews.current
	waiting = false
	joined = false
	if TankMissions.near_on:
		var hv := WorldSteps.hero_vehicle()
		if WorldSteps.class_ok(hv, WorldSteps.need_of(r.step)):
			ride = hv
			ride.set_meta(&"hold", true)
	match task:
		&"battle":
			if tc == null:
				return false
			need = int(r.step.get("n", 2))
			var kinds: Array = r.step.get("kinds", ["ltank", "tank"])
			var spawns: Array = r.step.get("spawns", [])
			for i in need:
				var a := float(i) * TAU / float(need) + 0.4
				var at := r.pos + Vector3(cos(a), 0.0, sin(a)) * 26.0
				if i < spawns.size():                                       # w129-tankmis: down the street, nose to the hero
					at = spawns[i] as Vector3
					a = float(r.step.get("head", a))
				at.y = _ground(at)
				var v := tc.spawn(StringName(str(kinds[i % kinds.size()])), at, a, &"mission", {"hp": float(r.step.get("hp", 700.0)) * _easier()})
				if v == null:
					clean()
					return false
				_watch(v)
				enemies.append(v)
		&"convoy":
			if tc == null:
				return false
			_pts.clear()
			for q: Variant in r.step.get("pts", []) as Array:
				var p := q as Vector3
				p.y = _ground(p)
				_pts.append(p)
			if _pts.size() < 2:
				return false
			var vm := _vm()
			if vm == null:
				return false
			if bool(r.step.get("road", false)) and TankMissions.near_on:
				if not _begin_road_convoy(vm):
					clean()
					return false
				waves = int(r.step.get("waves", 2))
				need = _pts.size()
				r.progress = 0.0
				return true
			var h := WorldMissions.heading_to(_pts[0], _pts[1])
			for i in int(r.step.get("trucks", 2)):
				var at := _pts[0] - Vector3(-sin(h), 0.0, -cos(h)) * (14.0 * float(i))
				at.y = _ground(at)
				vm._fixed_n += 1
				var t: Vehicle = vm.spawn_parked(StringName(str(r.step.get("truck", "truck"))), at, h)
				if t == null:
					vm._count_fixed()
					clean()
					return false
				t.set_meta(&"hold", true)
				t.set_meta(&"tank_puppet", true)
				vm._count_fixed()
				t.global_position = at
				t.max_hp = TRUCK_HP
				t.hp = TRUCK_HP
				_watch(t)
				trucks.append(t)
			_pi = 1
			_lead_d = 14.0 * float(trucks.size() - 1)                       # the whole convoy stands on the road, nose to tail
			waves = int(r.step.get("waves", 2))
			need = _pts.size()
		&"artillery":
			need = int(r.step.get("n", 3))
			var vm2 := _vm()
			if vm2 == null:
				return false
			var kinds2: Array = r.step.get("kinds", ["apc", "ltank"])
			for i in need:
				var a2 := float(i) * TAU / float(need)
				var at2 := r.pos + Vector3(cos(a2), 0.0, sin(a2)) * 18.0
				var spots: Array = r.step.get("spots", [])
				if i < spots.size():                                            # w129-tankmis: parked down the street, in the gun's line
					at2 = spots[i] as Vector3
				at2.y = _ground(at2)
				vm2._fixed_n += 1
				var t2: Vehicle = vm2.spawn_parked(StringName(str(kinds2[i % kinds2.size()])), at2, a2)
				if t2 == null:
					vm2._count_fixed()
					clean()
					return false
				t2.set_meta(&"hold", true)
				t2.set_meta(&"tank_target", true)
				vm2._count_fixed()
				t2.max_hp = float(r.step.get("hp", 240.0)) * _easier()           # one good howitzer shell wrecks one
				t2.hp = t2.max_hp
				_watch(t2)
				targets.append(t2)
		_:
			return false
	r.progress = 0.0
	var line := str(r.step.get("say", ""))
	if line != "":
		Game.say(line, 2.6)
	return true


func _watch(v: Vehicle) -> void:
	if not v.exploded.is_connected(_on_down):
		v.exploded.connect(_on_down)


func _on_down(v: Vehicle) -> void:
	if enemies.has(v):
		enemies.erase(v)
		kills += 1
		if not enemies.is_empty():
			Game.say("TANK DOWN  %d LEFT" % enemies.size(), 1.4)
	if targets.has(v):
		targets.erase(v)
		kills += 1
		Game.say("TARGET DESTROYED  %d LEFT" % targets.size() if not targets.is_empty() else "ALL TARGETS DESTROYED", 1.4)
	if trucks.has(v):
		trucks.erase(v)
		Game.say("A CONVOY TRUCK IS LOST" if not trucks.is_empty() else "THE CONVOY IS LOST", 1.6)
	for m: StringName in [&"tank_puppet", &"tank_target", &"hold"]:
		if v.has_meta(m):
			v.remove_meta(m)
	if not enemies.has(v):
		v.scripted = false                                                     # a driven convoy truck that burned stops driving
	if v.exploded.is_connected(_on_down):
		v.exploded.disconnect(_on_down)
	var vm := _vm()
	if vm != null:
		vm._count_fixed()


# --- tick ------------------------------------------------------------------------------------------------------------------------------

func tick(delta: float, p: Vector3) -> void:
	if heat_hold:
		Game.heat = maxf(minf(Game.heat, TASK_HEAT_CAP) - CampaignRunner.HOLD_HEAT_DECAY * delta, 0.0)
	if _wait_for_hero():
		if task == &"convoy" and not road.is_empty():
			_prune(trucks)
			if trucks.is_empty():
				r._fail("THE CONVOY IS LOST")
				return
			_drive_road(delta, true)
		return
	match task:
		&"battle":
			_prune(enemies)
			r.progress = float(kills) / float(maxi(need, 1))
			if enemies.is_empty():
				Game.say("THE GROUND IS OURS", 1.8)
				r._complete_step(p)
				return
			r.pos = _nearest(enemies, p)
		&"convoy":
			_prune(trucks)
			_prune(enemies)
			if trucks.is_empty():
				r._fail("THE CONVOY IS LOST")
				return
			if road.is_empty():
				_drive_convoy(delta)
			else:
				_drive_road(delta, false)
			if state_done():
				return
			r.pos = trucks[0].global_position
			if road.is_empty():
				r.progress = clampf(float(_pi - 1) / float(maxi(_pts.size() - 1, 1)), 0.0, 1.0)
			else:
				r.progress = clampf(_ts[0] / maxf(_cum[_cum.size() - 1], 1.0), 0.0, 1.0)
		&"artillery":
			_prune(targets)
			r.progress = float(kills) / float(maxi(need, 1))
			if targets.is_empty():
				r._complete_step(p)


## w129-tankmis: the hero left his tank: the crews hold still and hold fire, the beacon points at the tank, until he is back in. True while the step waits.
func _wait_for_hero() -> bool:
	if not TankMissions.near_on:
		return false
	var hv := WorldSteps.hero_vehicle()
	if ride != null and (not is_instance_valid(ride) or ride.dead or ride.wreck):
		ride = null                                                          # his tank burned: any tank he boards now is his
	if ride == null and WorldSteps.class_ok(hv, WorldSteps.need_of(r.step)):
		ride = hv
		ride.set_meta(&"hold", true)
	var out := ride == null or hv != ride
	if out != waiting:
		waiting = out
		_hold_crews(out)
		Game.say("GET BACK IN THE TANK" if out else "BACK IN THE TANK", 1.8)
	if out and ride != null:
		r.pos = ride.global_position
	return out


func _hold_crews(hold: bool) -> void:
	var tc := TankCrews.current
	if tc == null:
		return
	for e in enemies:
		if is_instance_valid(e):
			tc.set_hold(e, hold)


func state_done() -> bool:
	return r.state != &"active"


func _prune(list: Array[Vehicle]) -> void:
	for v: Vehicle in list.duplicate():
		if not is_instance_valid(v) or v.dead or v.wreck or not v.active:
			list.erase(v)
			if list == enemies or list == targets:
				kills += 1


func _nearest(list: Array[Vehicle], p: Vector3) -> Vector3:
	var best := r.pos
	var bd := INF
	for v in list:
		if is_instance_valid(v):
			var d := v.global_position.distance_to(p)
			if d < bd:
				bd = d
				best = v.global_position
	return best


## The trucks follow the lead along the road, nose to tail; they halt while an enemy tank is near the lead. A wave of enemy tanks comes in at the 1/3 and 2/3 marks of the road.
func _drive_convoy(delta: float) -> void:
	var lead := trucks[0]
	halted = false
	for e in enemies:
		if is_instance_valid(e) and e.global_position.distance_to(lead.global_position) < HALT_R:
			halted = true
	var total := 0.0
	for i in range(1, _pts.size()):
		total += _pts[i - 1].distance_to(_pts[i])
	var due := int(_lead_d / maxf(total, 1.0) * float(waves + 1))
	if due > wave and wave < waves:
		wave += 1
		_wave_in(lead)
	if not halted:
		_lead_d += CONVOY_SPEED * delta
	if _lead_d >= total:
		Game.say("THE CONVOY GOT THROUGH", 1.8)
		r._complete_step(r._ref_pos())
		return
	for i in trucks.size():
		var t := trucks[i]
		var d := maxf(_lead_d - 14.0 * float(i), 0.0)
		var at := _along(d)
		var ahead := _along(d + 4.0)
		at.y = _ground(at)
		var was := t.global_position
		t.global_position = at
		var vel := (at - was) / maxf(delta, 0.0001)
		t.vel = Vector3(vel.x, 0.0, vel.z)
		t.speed = 0.0 if halted else CONVOY_SPEED
		var dv := ahead - at
		if Vector2(dv.x, dv.z).length() > 0.1:
			t.heading = atan2(-dv.x, -dv.z)
			t.rotation.y = t.heading
	_pi = 1
	var acc := 0.0
	for i in range(1, _pts.size()):
		acc += _pts[i - 1].distance_to(_pts[i])
		if _lead_d >= acc:
			_pi = i + 1


# --- w129-tankmis: the driven convoy ----------------------------------------------------------------------------------------------------

## The lane line of `pts` sampled every ~2 m with each corner rounded (CORNER_R).
static func lane_line(pts: Array[Vector3]) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pts.size() < 2:
		return out
	var corners: Array[Vector3] = [pts[0]]
	for i in range(1, pts.size() - 1):
		var a := pts[i - 1]
		var b := pts[i]
		var c := pts[i + 1]
		var rr := minf(CORNER_R, minf(a.distance_to(b), b.distance_to(c)) * 0.45)
		var p0 := b + (a - b).normalized() * rr
		var p1 := b + (c - b).normalized() * rr
		corners.append(p0)
		for k in range(1, 8):                                                 # a quadratic curve through the corner
			var t := float(k) / 8.0
			corners.append(p0.lerp(b, t).lerp(b.lerp(p1, t), t))
		corners.append(p1)
	corners.append(pts[pts.size() - 1])
	out.append(corners[0])
	for i in range(1, corners.size()):
		var a2 := corners[i - 1]
		var b2 := corners[i]
		var n := maxi(int(ceil(a2.distance_to(b2) / 2.0)), 1)
		for k in range(1, n + 1):
			out.append(a2.lerp(b2, float(k) / float(n)))
	return out


func _begin_road_convoy(vm: VehicleManager) -> bool:
	road = lane_line(_pts)
	_cum.resize(road.size())
	_cum[0] = 0.0
	for i in range(1, road.size()):
		_cum[i] = _cum[i - 1] + road[i - 1].distance_to(road[i])
	_ts.clear()
	_stuck.clear()
	_back.clear()
	var n := int(r.step.get("trucks", 2))
	var kind := StringName(str(r.step.get("truck", "truck")))
	if not VehicleSpecs.SPECS.has(kind):
		kind = &"truck"
	var h0 := WorldMissions.heading_to(road[0], road[mini(4, road.size() - 1)])
	var back := Vector3(sin(h0), 0.0, cos(h0))                              # behind the lead, along the first leg
	for i in n:
		var at := road[0] + back * (GAP * float(i))
		at.y = _ground(at)
		vm._fixed_n += 1
		var t: Vehicle = vm.spawn_parked(kind, at, h0)
		if t == null:
			vm._count_fixed()
			return false
		t.set_meta(&"hold", true)
		t.set_meta(&"tank_puppet", true)                                     # outside the car cap; Vehicle drives it by script_thr / script_steer (scripted)
		vm._count_fixed()
		t.global_position = at
		t.scripted = true
		t.script_thr = 0.0
		t.script_steer = 0.0
		t.max_hp = TRUCK_HP
		t.hp = TRUCK_HP
		_watch(t)
		trucks.append(t)
		_ts.append(-GAP * float(i))
		_stuck.append(0.0)
		_back.append(0.0)
	_lead_d = 0.0
	return true


## The arc length on `road` nearest to `p`, searched round `hint`.
func _project(p: Vector3, hint: float) -> float:
	var best := hint
	var bd := INF
	for i in road.size():
		if absf(_cum[i] - hint) > 30.0:
			continue
		var d := Vector2(road[i].x - p.x, road[i].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = _cum[i]
	if best <= 0.0:                                                            # behind the start: negative, along the first leg
		var back := (p - road[0]).dot((road[1] - road[0]).normalized())
		if back < 0.0:
			return back
	return best


## The point at arc length `d` (before the start and past the end it runs on along the first / last leg).
func _road_at(d: float) -> Vector3:
	var last := road.size() - 1
	if d <= 0.0:
		return road[0] + (road[0] - road[1]).normalized() * -d
	if d >= _cum[last]:
		return road[last] + (road[last] - road[last - 1]).normalized() * (d - _cum[last])
	var lo := 0
	var hi := last
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _cum[mid] <= d:
			lo = mid
		else:
			hi = mid
	return road[lo].lerp(road[hi], (d - _cum[lo]) / maxf(_cum[hi] - _cum[lo], 0.001))


## How sharply the road turns between arc length d and d + ahead (radians).
func _bend(d: float, ahead: float) -> float:
	var a := _road_at(d + 1.0) - _road_at(d)
	var b := _road_at(d + ahead + 1.0) - _road_at(d + ahead)
	return absf(wrapf(atan2(b.x, b.z) - atan2(a.x, a.z), -PI, PI))


## The driven trucks: each steers at a point LOOK m ahead of where it is on the lane line, the lead at CONVOY_SPEED (slower into a bend), the others keeping GAP behind the one ahead;
## all stop while an enemy tank is near the lead, while the escort has not joined or falls behind (KEEP_UP), or while the step waits for the hero. A truck that is stuck backs out.
func _drive_road(delta: float, hold: bool) -> void:
	var lead := trucks[0]
	var hero := Game.player as Node3D
	var hv := WorldSteps.hero_vehicle()
	var hp := (hv.global_position if hv != null else hero.global_position) if is_instance_valid(hero) else lead.global_position
	var dl := Vector2(hp.x - lead.global_position.x, hp.z - lead.global_position.z).length()
	if not joined and not hold and dl < float(r.step.get("join", 45.0)):
		joined = true
		Game.say("CONVOY MOVING OUT  KEEP THE ENEMY OFF THE TRUCKS", 2.2)
	halted = false
	for e in enemies:
		if is_instance_valid(e) and e.global_position.distance_to(lead.global_position) < HALT_R:
			halted = true
	if (joined and dl > KEEP_UP) and not behind:
		Game.say("THE CONVOY WAITS FOR YOU", 1.8)
	behind = joined and dl > KEEP_UP
	var stop := hold or not joined or halted or behind
	var total := _cum[_cum.size() - 1]
	var due := int(maxf(_ts[0], 0.0) / maxf(total, 1.0) * float(waves + 1))
	if not hold and joined and due > wave and wave < waves:
		wave += 1
		_wave_road()
	for i in trucks.size():
		var t := trucks[i]
		if not is_instance_valid(t):
			continue
		var s := _project(t.global_position, _ts[i] if i < _ts.size() else 0.0)
		_ts[i] = s
		var want := CONVOY_SPEED
		if _bend(s, 12.0) > 0.5:
			want = CORNER_SPEED
		if i > 0:
			var gap := _ts[i - 1] - s
			want = minf(want, clampf((gap - GAP * 0.75) * 0.6, 0.0, CONVOY_SPEED + 1.5))
		if stop and i == 0:
			want = 0.0
		var aim := _road_at(s + LOOK)
		var g := aim - t.global_position
		var diff := wrapf(atan2(-g.x, -g.z) - t.heading, -PI, PI)
		var steer := clampf(-diff * 2.2, -1.0, 1.0)
		var thr := clampf((want - t.speed) * 0.5, -1.0, 1.0)
		if want < 0.3 and t.speed < 0.8:
			thr = 0.0
		if _back[i] > 0.0:                                                     # stuck on something: back out with the wheel turned the other way
			_back[i] -= delta
			thr = -0.7
			steer = -steer
		elif thr > 0.3 and absf(t.speed) < 0.4:
			_stuck[i] += delta
			if _stuck[i] > 2.5:
				_stuck[i] = 0.0
				_back[i] = 1.2
		else:
			_stuck[i] = 0.0
		t.script_thr = thr
		t.script_steer = steer
	_lead_d = _ts[0]
	if not hold and _ts[0] >= total - 4.0:
		for t2 in trucks:
			if is_instance_valid(t2):
				t2.script_thr = 0.0
		Game.say("THE CONVOY GOT THROUGH", 1.8)
		r._complete_step(r._ref_pos())


## A wave of the driven convoy: enemy tanks come up the lane line 150 - 190 m ahead of the lead, nose to it.
func _wave_road() -> void:
	var tc := TankCrews.current
	if tc == null:
		return
	var n := int(r.step.get("n", 1))
	var tr: Array = []
	for t in trucks:
		tr.append(t)
	for i in n:
		var d := _ts[0] + 150.0 + 22.0 * float(i)
		var at := _road_at(d)
		var back := _road_at(d - 4.0)
		at += Vector3(4.0 if i % 2 == 0 else -4.0, 0.0, 0.0) if absf(back.z - at.z) > absf(back.x - at.x) else Vector3(0.0, 0.0, 4.0 if i % 2 == 0 else -4.0)
		at.y = _ground(at)
		var v := tc.spawn(&"ltank" if i % 2 == 0 else &"tank", at, WorldMissions.heading_to(at, back), &"mission", {"hp": float(r.step.get("hp", 600.0)) * _easier(), "targets": tr})
		if v != null:
			_watch(v)
			enemies.append(v)
			if waiting:
				tc.set_hold(v, true)
	Game.say("ENEMY TANKS AHEAD OF THE CONVOY  WAVE %d" % wave, 1.8)


func _along(d: float) -> Vector3:
	var acc := 0.0
	for i in range(1, _pts.size()):
		var seg := _pts[i - 1].distance_to(_pts[i])
		if d <= acc + seg:
			return _pts[i - 1].lerp(_pts[i], (d - acc) / maxf(seg, 0.01))
		acc += seg
	return _pts[_pts.size() - 1]


func _wave_in(lead: Vehicle) -> void:
	var tc := TankCrews.current
	if tc == null:
		return
	var n := int(r.step.get("n", 1))
	var fwd := lead.forward()
	var side := lead.right()
	for i in n:
		var at := lead.global_position + fwd * 150.0 + side * (40.0 if i % 2 == 0 else -40.0)
		at.y = _ground(at)
		var tr: Array = []
		for t in trucks:
			tr.append(t)
		var v := tc.spawn(&"ltank" if i % 2 == 0 else &"tank", at, lead.heading + PI, &"mission", {"hp": float(r.step.get("hp", 600.0)) * _easier(), "targets": tr})
		if v != null:
			_watch(v)
			enemies.append(v)
	Game.say("ENEMY TANKS AHEAD OF THE CONVOY  WAVE %d" % wave, 1.8)


# --- HUD and markers -------------------------------------------------------------------------------------------------------------------

func hud_tail() -> String:
	if waiting:
		if ride == null:
			return "  " + WorldSteps.need_text(WorldSteps.need_of(r.step))
		return "  GET BACK IN THE TANK  %d M" % roundi(r._hdist(r._ref_pos(), r.pos))
	if not in_tank():
		return "  " + WorldSteps.need_text(WorldSteps.need_of(r.step))
	if task == &"convoy" and not road.is_empty() and not joined:
		return "  JOIN THE CONVOY  %d M" % roundi(r._hdist(r._ref_pos(), r.pos))
	match task:
		&"battle":
			return "  TANKS %d/%d  %d M" % [kills, need, roundi(r._hdist(r._ref_pos(), r.pos))]
		&"convoy":
			var hpf := 0.0
			for t in trucks:
				if is_instance_valid(t):
					hpf += t.hp / maxf(t.max_hp, 1.0)
			return "  CONVOY %d%%%s  %d M" % [roundi(100.0 * hpf / float(maxi(int(r.step.get("trucks", 2)), 1))), "  WAITING FOR YOU" if behind else ("  HALTED" if halted else ""), roundi(r._hdist(r._ref_pos(), r.pos))]
		&"artillery":
			return "  TARGETS %d/%d  %d M" % [kills, need, roundi(r._hdist(r._ref_pos(), r.pos))]
	return ""


func add_markers(add: Callable) -> void:
	if waiting and is_instance_valid(ride):
		add.call(ride.global_position, ContractTypes.CYAN, &"dest", 0.0)        # w129-tankmis: back to the tank first
	for e in enemies:
		if is_instance_valid(e):
			add.call(e.global_position, ContractTypes.RED, &"target", 0.0)
	for t in targets:
		if is_instance_valid(t):
			add.call(t.global_position, ContractTypes.RED, &"target", 0.0)
	for t in trucks:
		if is_instance_valid(t):
			add.call(t.global_position, ContractTypes.CYAN, &"target", 0.0)


func clean() -> void:
	var vm := _vm()
	var tc := TankCrews.current
	for v in enemies:
		if is_instance_valid(v):
			if v.exploded.is_connected(_on_down):
				v.exploded.disconnect(_on_down)
			if tc != null:
				tc.release(v)
	for list: Array[Vehicle] in [targets, trucks]:
		for v in list:
			if not is_instance_valid(v):
				continue
			if v.exploded.is_connected(_on_down):
				v.exploded.disconnect(_on_down)
			for m: StringName in [&"tank_puppet", &"tank_target", &"hold"]:
				if v.has_meta(m):
					v.remove_meta(m)
			v.scripted = false
			if vm != null and not v.dead and not v.driver_is_player and v.active:
				vm._release(v)
	enemies.clear()
	targets.clear()
	trucks.clear()
	_pts.clear()
	if ride != null and is_instance_valid(ride) and ride.has_meta(&"hold"):
		ride.remove_meta(&"hold")
	ride = null
	waiting = false
	joined = false
	behind = false
	road = PackedVector3Array()
	_cum = PackedFloat32Array()
	_ts.clear()
	task = &""
	if vm != null:
		vm._count_fixed()
