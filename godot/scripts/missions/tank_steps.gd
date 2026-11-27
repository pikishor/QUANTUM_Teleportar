class_name TankSteps
extends RefCounted
## The campaign step kind `tank_task` of the TANK MISSIONS (wave 127, w127-arms; recipes in scripts/missions/tank_missions.gd, runner scripts/missions/campaign_runner.gd, `runner.tank`).
## The hero must sit in a military vehicle (`veh` "tank"). `task`:
##   battle     `n` ENEMY TANKS (TankCrews, mode mission) hold the ground at `pos`; done when every one is destroyed
##   convoy     `trucks` CONVOY TRUCKS drive the road `pts` (puppets, meta tank_puppet, CONVOY_SPEED m/s); enemy tanks come at them in `waves` (each wave appears ahead of the lead truck
##              and goes for the nearest truck or the hero); the convoy HALTS while an enemy tank is within HALT_R of the lead; done when the lead reaches the last point, failed when every truck burns
##   artillery  `n` TARGETS (parked armour, meta tank_target) stand around `pos`; done when all are wrecked (the howitzer's marker snaps onto a target close to the crosshair, TankArms.SNAP_R)
## EASY like the other board missions: weak crews (their hp), slow reloads, generous clocks, every failed run makes the enemies weaker. One instance per runner; reset at every step.

const CONVOY_SPEED := 7.0
const HALT_R := 130.0
const TRUCK_HP := 1600.0

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
	match task:
		&"battle":
			if tc == null:
				return false
			need = int(r.step.get("n", 2))
			var kinds: Array = r.step.get("kinds", ["ltank", "tank"])
			for i in need:
				var a := float(i) * TAU / float(need) + 0.4
				var at := r.pos + Vector3(cos(a), 0.0, sin(a)) * 26.0
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
	if v.exploded.is_connected(_on_down):
		v.exploded.disconnect(_on_down)
	var vm := _vm()
	if vm != null:
		vm._count_fixed()


# --- tick ------------------------------------------------------------------------------------------------------------------------------

func tick(delta: float, p: Vector3) -> void:
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
			_drive_convoy(delta)
			if state_done():
				return
			r.pos = trucks[0].global_position
			r.progress = clampf(float(_pi - 1) / float(maxi(_pts.size() - 1, 1)), 0.0, 1.0)
		&"artillery":
			_prune(targets)
			r.progress = float(kills) / float(maxi(need, 1))
			if targets.is_empty():
				r._complete_step(p)


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
	if not in_tank():
		return "  " + WorldSteps.need_text(WorldSteps.need_of(r.step))
	match task:
		&"battle":
			return "  TANKS %d/%d  %d M" % [kills, need, roundi(r._hdist(r._ref_pos(), r.pos))]
		&"convoy":
			var hpf := 0.0
			for t in trucks:
				if is_instance_valid(t):
					hpf += t.hp / maxf(t.max_hp, 1.0)
			return "  CONVOY %d%%%s  %d M" % [roundi(100.0 * hpf / float(maxi(int(r.step.get("trucks", 2)), 1))), "  HALTED" if halted else "", roundi(r._hdist(r._ref_pos(), r.pos))]
		&"artillery":
			return "  TARGETS %d/%d  %d M" % [kills, need, roundi(r._hdist(r._ref_pos(), r.pos))]
	return ""


func add_markers(add: Callable) -> void:
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
			if vm != null and not v.dead and not v.driver_is_player and v.active:
				vm._release(v)
	enemies.clear()
	targets.clear()
	trucks.clear()
	_pts.clear()
	task = &""
	if vm != null:
		vm._count_fixed()
