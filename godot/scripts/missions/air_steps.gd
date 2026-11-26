class_name AirSteps
extends RefCounted
## The campaign step kind `air_task` of the AIR MISSIONS (wave 126, w126-air; recipes in scripts/missions/air_missions.gd, runner scripts/missions/campaign_runner.gd, `runner.air`).
## `task` says what the step wants from the hero, who must sit in an aircraft (`veh` as in WorldSteps: air / heli / plane):
##   dogfight   `n` BANDITS (hostile aircraft, `bandit` kind) circle over `pos`; done when every one is shot down. They fire missiles at the hero now and then (flares fool them).
##   escort     an AIRLINER flies the waypoints `pts`; bandits come at it in `waves`; done when it reaches the last point, failed when it goes down (`liner_hp`).
##   bomb       `n` ground TARGETS (`target` kind, armoured vehicles that stand still) at `pos`; done when all are wrecked. The aircraft's BOMB arm is selected at the start.
##   drop       drop `n` cargo crates (the DROP arm) inside `radius` of `pos`; crates that land outside do not count (the arm reloads).
##   board      land inside `radius` of `pos` and stay down `hold` seconds (survivors climb aboard).
## The bandits and the airliner are real Vehicles (they take hits from the guns, rockets and missiles, a missile locks on them) flown here as PUPPETS (meta air_puppet: Vehicle.sim leaves
## them alone, VehicleManager keeps them outside the car cap). Everything is EASY: slow circles, weak missiles, generous clocks, nothing fails at once. One instance per runner; reset at every step.

const BANDIT_SPEED := 46.0                ## m/s along their circle
const BANDIT_R := 260.0                   ## circle radius
const BANDIT_SHOT_EVERY := 7.5            ## s between two missiles of one bandit
const BANDIT_REACH := 650.0               ## a bandit only shoots at what is this close
const BANDIT_MISSILE := {"name": "BANDIT MISSILE", "short": "MISSILE", "rate": 1.0, "salvo": 1, "dmg": 45.0, "blast": 5.0, "speed": 120.0, "life": 6.0, "ammo": 1, "reload": 1.0,
		"color": Color(1.0, 0.4, 0.3), "range": 800.0, "homing": 1.1}
const LINER_SPEED := 62.0
const LINER_HP := 1200.0
const LINER_HIT := 9.0                    ## hp a second each bandit within ATTACK_R takes off the airliner
const ATTACK_R := 320.0

var r: CampaignRunner
var task: StringName = &""
var bandits: Array[Vehicle] = []
var targets: Array[Vehicle] = []
var liner: Vehicle = null
var falling: Array[Vehicle] = []           ## shot-down puppets on their way to the ground
var kills := 0
var need := 0
var hold_t := 0.0
var drops0 := 0
var dropped_in := 0
var wave := 0
var waves := 0
var liner_hp := 0.0
var _pts: Array[Vector3] = []
var _pi := 0
var _ang := {}                             ## bandit -> angle on its circle
var _centre := {}                          ## bandit -> circle centre
var _shot_t := {}                          ## bandit -> seconds to its next missile
var _warned := 0.0


func _init(runner: CampaignRunner) -> void:
	r = runner


static func hero_vehicle() -> Vehicle:
	return WorldSteps.hero_vehicle()


func _vm() -> VehicleManager:
	return Game.vehicles as VehicleManager


func in_aircraft() -> bool:
	return WorldSteps.class_ok(hero_vehicle(), WorldSteps.need_of(r.step))


# --- begin ---------------------------------------------------------------------------------------------------------------------------

func begin() -> bool:
	clean()
	task = StringName(str(r.step.get("task", "")))
	kills = 0
	hold_t = 0.0
	match task:
		&"dogfight":
			need = int(r.step.get("n", 2))
			for i in need:
				var b := _puppet(StringName(str(r.step.get("bandit", "plane"))), r.pos, float(i) * TAU / float(need))
				if b == null:
					clean()
					return false
				bandits.append(b)
		&"escort":
			_pts.clear()
			for q: Variant in r.step.get("pts", []) as Array:
				_pts.append(q as Vector3)
			if _pts.size() < 2:
				return false
			liner = _spawn_puppet(StringName(str(r.step.get("liner", "airliner"))), _pts[0], WorldMissions.heading_to(_pts[0], _pts[1]))
			if liner == null:
				return false
			_pi = 1
			liner_hp = float(r.step.get("liner_hp", LINER_HP))
			waves = int(r.step.get("waves", 2))
			wave = 0
			need = _pts.size()
		&"bomb":
			need = int(r.step.get("n", 3))
			var vm := _vm()
			for i in need:
				var a := float(i) * TAU / float(need)
				var at := r.pos + Vector3(cos(a), 0.0, sin(a)) * 12.0
				at.y = _ground(at)
				if vm == null:
					return false
				vm._fixed_n += 1                                          # room above the cap (VehicleManager._count_fixed counts air_target)
				var t: Vehicle = vm.spawn_parked(StringName(str(r.step.get("target", "apc"))), at, a)
				if t == null:
					vm._count_fixed()
					clean()
					return false
				t.set_meta(&"hold", true)
				t.set_meta(&"air_target", true)
				vm._count_fixed()
				t.max_hp = float(r.step.get("hp", 260.0))                   # one good bomb wrecks one (an armoured car's own hp would need five)
				t.hp = t.max_hp
				targets.append(t)
			_arm(&"bomb")
		&"drop":
			need = int(r.step.get("n", 1))
			drops0 = AirRockets.instance.drops.size() if AirRockets.instance != null else 0
			dropped_in = 0
			_arm(&"drop")
		&"board":
			need = 1
		_:
			return false
	r.progress = 0.0
	return true


## Select the arm the task needs on the hero's aircraft (the bomb run arms the bombs, the cargo run the crates).
func _arm(k: StringName) -> void:
	var v := hero_vehicle()
	if v != null and v.weapons != null and v.weapons.arms != null and v.weapons.arms.select(k):
		v.weapons._arms_sync(false)


func _ground(p: Vector3) -> float:
	if absf(p.x) > TerrainHeight.CITY_HALF or absf(p.z) > TerrainHeight.CITY_HALF:
		return TerrainHeight.height_at(p.x, p.z)
	return 0.0


## A bandit on its circle round `centre` (the circle's height is the step's pos height), starting at angle `a`.
func _puppet(kind: StringName, centre: Vector3, a: float) -> Vehicle:
	var c := centre + Vector3(cos(a), 0.0, sin(a)) * BANDIT_R
	var v := _spawn_puppet(kind, c, a)
	if v == null:
		return null
	v.set_meta(&"air_bandit", true)
	v.max_hp = float(r.step.get("hp", 160.0)) * maxf(1.0 - 0.15 * float(mini(maxi(r.fails, 0), 3)), 0.5)       # every failed run makes them easier
	v.hp = v.max_hp
	_ang[v] = a
	_centre[v] = centre
	_shot_t[v] = 4.0 + 2.5 * float(bandits.size())
	return v


func _spawn_puppet(kind: StringName, at: Vector3, heading: float) -> Vehicle:
	var vm := _vm()
	if vm == null:
		return null
	vm._fixed_n += 1                                              # room above the cap (VehicleManager._count_fixed counts air_puppet)
	var v: Vehicle = vm.spawn_parked(kind, at, heading)
	if v == null:
		vm._count_fixed()
		return null
	v.set_meta(&"air_puppet", true)
	v.set_meta(&"hold", true)
	vm._count_fixed()
	v.global_position = at
	v.heading = heading
	v.rotation.y = heading
	if v.craft != null:
		v.craft.airborne = true
		v.craft.spool = 1.0
	v.speed = BANDIT_SPEED
	if not v.exploded.is_connected(_on_down):
		v.exploded.connect(_on_down)
	return v


func _on_down(v: Vehicle) -> void:
	if bandits.has(v):
		bandits.erase(v)
		kills += 1
		Game.say("BANDIT DOWN  %d LEFT" % bandits.size() if not bandits.is_empty() else "BANDIT DOWN", 1.4)
	if v == liner:
		liner_hp = 0.0
	if targets.has(v):
		targets.erase(v)
		kills += 1
	if v.has_meta(&"air_puppet"):
		falling.append(v)
	var vm := _vm()
	if vm != null:
		vm._count_fixed()


# --- tick ----------------------------------------------------------------------------------------------------------------------------

func tick(delta: float, p: Vector3) -> void:
	_fall(delta)
	match task:
		&"dogfight":
			_fly_bandits(delta)
			r.progress = float(kills) / float(maxi(need, 1))
			if bandits.is_empty():
				r._complete_step(p)
				return
			r.pos = _nearest(bandits, p)
		&"escort":
			_fly_liner(delta)
			if state_done():
				return
			_fly_bandits(delta)
			for b in bandits:
				if is_instance_valid(b) and is_instance_valid(liner) and b.global_position.distance_to(liner.global_position) < ATTACK_R:
					liner_hp -= LINER_HIT * delta
			if liner_hp <= 0.0 or not is_instance_valid(liner) or liner.dead:
				r._fail("THE AIRLINER WENT DOWN")
				return
			r.pos = liner.global_position if is_instance_valid(liner) else r.pos
			r.progress = float(_pi) / float(maxi(_pts.size(), 1))
		&"bomb":
			r.progress = float(kills) / float(maxi(need, 1))
			for t: Vehicle in targets.duplicate():
				if not is_instance_valid(t) or t.dead or t.wreck or not t.active:
					targets.erase(t)
					kills += 1
			if targets.is_empty():
				r._complete_step(p)
		&"drop":
			var ar := AirRockets.instance
			if ar != null:
				while drops0 < ar.drops.size():
					var at: Vector3 = ar.drops[drops0]
					drops0 += 1
					if Vector2(at.x - r.pos.x, at.z - r.pos.z).length() <= float(r.step.get("radius", 50.0)):
						dropped_in += 1
						Game.say("ON TARGET  %d OF %d" % [dropped_in, need], 1.4)
					else:
						Game.say("MISSED  %d M OFF" % roundi(Vector2(at.x - r.pos.x, at.z - r.pos.z).length()), 1.4)
			r.progress = float(dropped_in) / float(maxi(need, 1))
			if dropped_in >= need:
				r._complete_step(p)
		&"board":
			var v := hero_vehicle()
			var rad := float(r.step.get("radius", 30.0))
			if in_aircraft() and WorldSteps.landed(v) and Vector2(p.x - r.pos.x, p.z - r.pos.z).length() < rad:
				hold_t += delta
			else:
				hold_t = maxf(hold_t - delta * 0.5, 0.0)
			r.progress = clampf(hold_t / float(r.step.get("hold", 4.0)), 0.0, 1.0)
			if r.progress >= 1.0:
				Game.say("EVERYONE IS ABOARD", 1.6)
				r._complete_step(p)


func state_done() -> bool:
	return r.state != &"active"


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


## The bandits fly their circles (escort: they chase the airliner) and fire a missile at the hero (escort: at the airliner or the hero) now and then.
func _fly_bandits(delta: float) -> void:
	var hv := hero_vehicle()
	for b: Vehicle in bandits.duplicate():
		if not is_instance_valid(b) or b.dead:
			bandits.erase(b)
			continue
		var centre: Vector3 = _centre.get(b, r.pos)
		if task == &"escort" and is_instance_valid(liner):
			centre = liner.global_position + Vector3(0.0, 30.0, 0.0)
			_centre[b] = centre
		var a := float(_ang.get(b, 0.0)) + BANDIT_SPEED / BANDIT_R * delta
		_ang[b] = a
		var to := centre + Vector3(cos(a), 0.0, sin(a)) * BANDIT_R + Vector3(0.0, sin(a * 2.0) * 12.0, 0.0)
		var gy := _ground(to) + 60.0
		to.y = maxf(to.y, gy)
		var was := b.global_position
		var step := to - was
		var dist := step.length()
		var mv := BANDIT_SPEED * 1.6 * delta
		var np := to if dist <= mv else was + step / dist * mv
		b.global_position = np
		var vel := (np - was) / maxf(delta, 0.0001)
		b.vel = Vector3(vel.x, 0.0, vel.z)
		if Vector2(vel.x, vel.z).length() > 0.5:
			b.heading = atan2(-vel.x, -vel.z)
			b.rotation.y = b.heading
		if b.craft != null:
			b.craft.roll = -0.45
			b.craft.vy = vel.y
			b.craft.airborne = true
		_shot_t[b] = float(_shot_t.get(b, 5.0)) - delta
		if float(_shot_t[b]) <= 0.0:
			_shot_t[b] = BANDIT_SHOT_EVERY
			var tgt: Node3D = hv
			if task == &"escort" and is_instance_valid(liner) and (hv == null or randf() < 0.5):
				tgt = liner
			if tgt != null and is_instance_valid(tgt) and tgt.global_position.distance_to(np) < BANDIT_REACH:
				var dir := (tgt.global_position - np).normalized()
				AirRockets.launch(b, BANDIT_MISSILE, np + dir * 8.0, dir, tgt)
				if tgt == hv and _warned <= 0.0:
					_warned = 6.0
					Game.say("MISSILE INBOUND  FLARE!", 1.6)
	_warned -= delta


## The airliner flies its waypoints; a new wave of bandits comes at it on each third of the way.
func _fly_liner(delta: float) -> void:
	if not is_instance_valid(liner) or liner.dead:
		return
	if _pi >= _pts.size():
		Game.say("THE AIRLINER IS SAFE", 1.8)
		r._complete_step(r._ref_pos())
		return
	var tgt := _pts[_pi]
	var was := liner.global_position
	var step := tgt - was
	var mv := LINER_SPEED * delta
	if step.length() <= maxf(mv, 6.0):
		_pi += 1
		var due := int(float(_pi) / float(_pts.size()) * float(waves + 1))
		if due > wave and wave < waves:
			wave += 1
			_wave_in()
		return
	var np := was + step.normalized() * mv
	liner.global_position = np
	var vel := (np - was) / maxf(delta, 0.0001)
	liner.vel = Vector3(vel.x, 0.0, vel.z)
	liner.heading = atan2(-vel.x, -vel.z)
	liner.rotation.y = liner.heading
	if liner.craft != null:
		liner.craft.airborne = true
		liner.craft.vy = vel.y


func _wave_in() -> void:
	var n := int(r.step.get("n", 2))
	for i in n:
		var b := _puppet(StringName(str(r.step.get("bandit", "plane"))), liner.global_position, float(i) * TAU / float(n) + float(wave))
		if b != null:
			bandits.append(b)
	Game.say("BANDITS ON THE AIRLINER  WAVE %d" % wave, 1.8)


## Shot-down puppets fall to the ground, then stay as wrecks (the manager clears them like any wreck).
func _fall(delta: float) -> void:
	for v: Vehicle in falling.duplicate():
		if not is_instance_valid(v):
			falling.erase(v)
			continue
		var gy := _ground(v.global_position)
		v.global_position.y = maxf(v.global_position.y - 32.0 * delta, gy)
		v.global_position += v.vel * delta * 0.5
		if v.global_position.y <= gy + 0.05:
			falling.erase(v)
			if v.has_meta(&"air_puppet"):
				v.remove_meta(&"air_puppet")


# --- text and markers ----------------------------------------------------------------------------------------------------------------

func hud_tail() -> String:
	if not in_aircraft():
		return "  " + WorldSteps.need_text(WorldSteps.need_of(r.step))
	match task:
		&"dogfight":
			return "  BANDITS %d/%d  %d M" % [kills, need, roundi(r._hdist(r._ref_pos(), r.pos))]
		&"escort":
			return "  AIRLINER %d%%  %d M" % [roundi(100.0 * maxf(liner_hp, 0.0) / LINER_HP), roundi(r._hdist(r._ref_pos(), r.pos))]
		&"bomb":
			return "  TARGETS %d/%d  %d M" % [kills, need, roundi(r._hdist(r._ref_pos(), r.pos))]
		&"drop":
			return "  CRATES %d/%d  %d M" % [dropped_in, need, roundi(r._hdist(r._ref_pos(), r.pos))]
		&"board":
			return "  %d M%s" % [roundi(r._hdist(r._ref_pos(), r.pos)), "  HOLD STILL" if hold_t > 0.0 else "  LAND IN THE RING"]
	return ""


## The minimap markers of the step (the runner's _add_marker: pos, colour, kind, radius).
func add_markers(add: Callable) -> void:
	match task:
		&"dogfight", &"escort":
			for b in bandits:
				if is_instance_valid(b):
					add.call(b.global_position, ContractTypes.RED, &"target", 0.0)
			if is_instance_valid(liner):
				add.call(liner.global_position, ContractTypes.CYAN, &"target", 0.0)
		&"bomb":
			for t in targets:
				if is_instance_valid(t):
					add.call(t.global_position, ContractTypes.RED, &"target", 0.0)
		&"drop", &"board":
			add.call(r.pos, ContractTypes.CYAN, &"zone", float(r.step.get("radius", 40.0)))


## Everything the step made goes back: the bandits, the airliner and the targets to the pool (wrecks stay for the manager).
func clean() -> void:
	var vm := _vm()
	var all: Array = []
	all.append_array(bandits)
	all.append_array(targets)
	all.append(liner)
	for x: Variant in all:
		if x == null or not is_instance_valid(x):
			continue
		var v := x as Vehicle
		if v == null:
			continue
		if v.exploded.is_connected(_on_down):
			v.exploded.disconnect(_on_down)
		if v.has_meta(&"air_puppet"):
			v.remove_meta(&"air_puppet")
		if v.has_meta(&"air_target"):
			v.remove_meta(&"air_target")
		if v.has_meta(&"hold"):
			v.remove_meta(&"hold")
		if vm != null and not v.dead and not v.driver_is_player and v.active:
			vm._release(v)
	for v in falling:
		if is_instance_valid(v) and v.has_meta(&"air_puppet"):
			v.remove_meta(&"air_puppet")
	bandits.clear()
	targets.clear()
	falling.clear()
	liner = null
	_ang.clear()
	_centre.clear()
	_shot_t.clear()
	task = &""
	if vm != null:
		vm._count_fixed()
