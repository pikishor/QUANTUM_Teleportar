class_name TankArms
extends RefCounted
## TANK AND MILITARY VEHICLE WEAPONS BY CLASS (wave 127, w127-arms; plan line 127). The MAIN gun stays the FIRE button (VehicleSpecs.WEAPONS, VehicleWeapons.tick: the battle / light
## tank's cannon with AP / HE / CLUSTER shells of the blast table on the SHELL chip, the carrier's autocannon, the HOWITZER's indirect fire on a TARGET MARKER, the FLAK cannon). Everything
## else a military vehicle carries is here, on the second round button (the AIM slot) with the ARMS chip to pick the next one, and the SMOKE button:
##   COAX     coaxial machine gun along the gun (hitscan, `light`: it barely scratches armour)
##   HMG      the heavy machine gun on the roof (hitscan, light)
##   ATGM     anti-tank guided missile with LOCK-ON: hold a vehicle inside LOCK_CONE for LOCK_TIME, the button reads LOCKED, the missile homes (blast `ord_atgm`, an AP warhead on the hit zone)
##   SALVO    a salvo of SALVO rockets from the deck launcher, they fan out on the aim point (blast `ord_tank_rocket`)
##   SAM      the anti-air tank's seeker missiles, LOCK-ON prefers aircraft (blast `ord_air_missile` of wave 126)
##   SMOKE    smoke launchers: two smoke grenades ahead, a cloud (blast `veh_smoke`, a smoke zone of BlastOps) that blinds the people in it and hides the tank from enemy tank crews and seekers
## The loadout comes from the class (LOADOUT, a `tank_arms` list in a VehicleSpecs row, or the main gun's kind for a kind nobody classed: w127-tanks' roster gets a kit without a line here).
## One TankArms per armed military vehicle (VehicleWeapons.tarms). Rockets and missiles are AirRockets projectiles (one pool). Every arm reloads by itself (RELOAD clock per arm: the ring
## round the button), the HOWITZER shell snaps to a target within SNAP_R of the crosshair's ground point (a finger cannot place a point 400 m away to the metre).
## W127A_OLD=1 (or TankArms.on = false): the wave 126 state (the coax of two tanks and the anti-air tank's missiles, nothing else).

const LOCK_TIME := 1.0
const LOCK_CONE := 0.3
const LOCK_KEEP := 0.5
const SNAP_R := 22.0                     ## m: the howitzer's marker snaps to a target this close to the crosshair's ground point
const SMOKE_SECS := 14.0
const ARMS := {
	&"coax": {"name": "COAX MACHINE GUN", "short": "COAX", "kind": "gun", "rate": 14.0, "dmg": 11.0, "ammo": 300, "reload": 0.12, "range": 160.0, "spread": 0.02, "color": Color(1.0, 0.85, 0.4)},
	&"roof": {"name": "ROOF MACHINE GUN", "short": "HMG", "kind": "gun", "rate": 9.0, "dmg": 17.0, "ammo": 250, "reload": 0.16, "range": 210.0, "spread": 0.025, "color": Color(1.0, 0.8, 0.35), "roof": true},
	&"atgm": {"name": "GUIDED MISSILE", "short": "ATGM", "blast_id": &"ord_atgm", "rate": 0.7, "salvo": 1, "dmg": 420.0, "blast": 4.0, "speed": 85.0, "life": 7.0, "ammo": 4, "reload": 9.0,
		"color": Color(1.0, 0.75, 0.35), "range": 560.0, "homing": 2.4, "lock": true, "pen": &"ap"},
	&"salvo": {"name": "ROCKET SALVO", "short": "SALVO", "blast_id": &"ord_tank_rocket", "rate": 0.4, "salvo": 6, "dmg": 70.0, "blast": 6.0, "speed": 120.0, "life": 4.5, "ammo": 18, "reload": 2.5,
		"color": Color(1.0, 0.6, 0.2), "range": 480.0},
	&"sam": {"name": "SEEKER MISSILES", "short": "MISSILE", "blast_id": &"ord_air_missile", "rate": 1.6, "salvo": 1, "dmg": 130.0, "blast": 8.0, "speed": 200.0, "life": 3.5, "ammo": 8, "reload": 3.0,
		"color": Color(1.0, 0.8, 0.4), "range": 600.0, "homing": 1.8, "lock": true, "air": true},
	&"smoke": {"name": "SMOKE LAUNCHERS", "short": "SMOKE", "ammo": 3, "reload": 20.0, "rate": 1.0},
}
const LOADOUT := {
	&"tank": [&"coax", &"roof", &"atgm", &"smoke"], &"ltank": [&"coax", &"atgm", &"smoke"], &"apc": [&"roof", &"atgm", &"smoke"],
	&"artillery": [&"roof", &"salvo", &"smoke"], &"aatank": [&"sam", &"roof", &"smoke"],
}

static var on := OS.get_environment("W127A_OLD") != "1"
static var smokes := 0                   ## counters for the tests
static var shots_by := {}                ## arm -> rounds fired, lifetime
static var hits_by := {}                 ## arm -> direct hits, lifetime
static var snapped := 0                  ## howitzer shells that snapped to a target
static var _blasts_done := false

var car: Vehicle
var list: Array[StringName] = []
var has_smoke := false
var idx := 0
var ammo := {}
var shots := {}
var _rl := {}
var _cd := 0.0
var _smoke_cd := 0.0
var _side := 1.0
var lock_target: Node3D = null
var lock_t := 0.0
var _scan_t := 0.0


## The arms of `kind` (with the smoke), [] when it carries none.
static func loadout(kind: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var sp: Dictionary = VehicleSpecs.SPECS.get(kind, {})
	if sp.is_empty() or str(sp.get("cls", "")) != "tank":
		return out
	var src: Variant = null
	if sp.has("tank_arms"):
		src = sp["tank_arms"]
	elif LOADOUT.has(kind):
		src = LOADOUT[kind]
	else:
		var w: Dictionary = VehicleSpecs.WEAPONS.get(kind, {})
		if bool(w.get("indirect", false)):
			src = LOADOUT[&"artillery"]
		elif bool(w.get("flak", false)):
			src = LOADOUT[&"aatank"]
		elif float(w.get("dmg", 0.0)) >= 50.0:
			src = LOADOUT[&"tank"]
		else:
			src = LOADOUT[&"apc"]
	if src is Array:
		for a: Variant in src as Array:
			if ARMS.has(StringName(str(a))):
				out.append(StringName(str(a)))
	return out


static func make(c: Vehicle) -> TankArms:
	if not on or c == null or c.cls != &"tank":
		return null
	var lo := loadout(c.kind)
	if lo.is_empty():
		return null
	ensure_actions()                                                              # w127-integrator: the blasts join the table when they first go off (ensure_blast)
	var a := TankArms.new()
	a.car = c
	for k in lo:
		if k == &"smoke":
			a.has_smoke = true
		else:
			a.list.append(k)
	a.reload_full()
	return a


## The vehicle blasts of the table (category `tankarms`: the 65-entry arsenal and its lists stay as they are).
## w127-integrator: each entry joins the table when it first goes off (AirRockets._detonate and fire_smoke call ensure_blast), not when an armed vehicle is set up (an entry that never went
## off would sit in the table unused: tests/test_blast_arsenal.gd checks that every entry went off). ensure_blasts registers them all (kept for callers that want them all).
static func ensure_blasts() -> void:
	if _blasts_done:
		return
	_blasts_done = true
	for id: StringName in [&"ord_atgm", &"ord_tank_rocket", &"veh_smoke", &"ord_air_missile"]:
		ensure_blast(id)


## Registers one runtime blast of the vehicles or the aircraft if it is not in the table yet; true when the id is one of them.
static func ensure_blast(id: StringName) -> bool:
	if id == &"ord_atgm":
		if not BlastTable.has_entry(id):
			BlastTable.register(&"ord_atgm", {"cat": &"tankarms", "name": "GUIDED MISSILE", "radius": 4.0, "core": 1.0, "enemy": 160.0, "vehicle": 180.0, "element": &"fire", "tag": "ATG", "tier": 4,
					"note": "A TANDEM WARHEAD  LOCKS ON  CRACKS ARMOUR WHERE IT STRIKES", "knock": 8.0, "lift": 6.0, "debris": &"metal"})
		return true
	if id == &"ord_tank_rocket":
		if not BlastTable.has_entry(id):
			BlastTable.register(&"ord_tank_rocket", {"cat": &"tankarms", "name": "SALVO ROCKET", "radius": 6.0, "core": 1.2, "enemy": 110.0, "vehicle": 120.0, "element": &"fire", "tag": "SLV", "tier": 3,
					"note": "SIX ROCKETS FAN OUT ON THE AIM POINT", "knock": 9.0, "lift": 8.0})
		return true
	if id == &"veh_smoke":
		if not BlastTable.has_entry(id):
			BlastTable.register(&"veh_smoke", {"cat": &"tankarms", "name": "VEHICLE SMOKE", "radius": 9.0, "core": 9.0, "enemy": 0.0, "vehicle": 0.0, "element": &"fire", "tag": "VSM", "tier": 1,
					"note": "A CLOUD IN FRONT OF THE TANK  HIDES IT FROM CREWS AND SEEKERS", "curve": &"flat", "knock": 0.0, "lift": 0.0, "status": {"k": &"smoke", "t": SMOKE_SECS, "p": 1.0},
					"hold": SMOKE_SECS, "fx": &"smoke", "wave": &"none", "snd": &"explosion_small", "snd_pitch": 0.8, "crater": 0.0, "scorch": 0.0, "debris": &"none", "prop": 0, "level": 0,
					"civ": 0.0, "hero": 0.0, "animal": 0.0, "cover": false})
		return true
	return AirArms.ensure_blast(id)


## ARMS (the next arm) and SMOKE (`flare`, shared with the aircraft's FLARE: never on screen together) exist as actions for the touch buttons, a keyboard and a controller.
static func ensure_actions() -> void:
	AirArms.ensure_actions()
	if InputMap.has_action(&"arms_next"):
		return
	InputMap.add_action(&"arms_next")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_G
	InputMap.action_add_event(&"arms_next", k)


func reload_full() -> void:
	for k in list:
		ammo[k] = int(ARMS[k]["ammo"])
		shots[k] = 0
		_rl[k] = 0.0
	if has_smoke:
		ammo[&"smoke"] = int(ARMS[&"smoke"]["ammo"])
		shots[&"smoke"] = 0
		_rl[&"smoke"] = 0.0
	_cd = 0.0
	_smoke_cd = 0.0
	idx = 0                                                                 # a recycled tank starts on its first arm
	lock_target = null
	lock_t = 0.0


func current() -> StringName:
	return list[idx] if idx < list.size() else &""


func def() -> Dictionary:
	var k := current()
	return ARMS[k] if k != &"" else {}


func cycle() -> void:
	if list.size() < 2:
		return
	idx = (idx + 1) % list.size()
	_cd = minf(_cd, 0.15)
	lock_target = null
	lock_t = 0.0
	if car.driver_is_player:
		Game.say(String(ARMS[current()]["name"]), 0.9)
		Sfx.play(&"ui_tap")


func select(k: StringName) -> bool:
	var i := list.find(k)
	if i < 0:
		return false
	idx = i
	return true


func locked() -> bool:
	return bool(def().get("lock", false)) and is_instance_valid(lock_target) and lock_t >= LOCK_TIME


## The words on the arm button: "COAX 300", "ATGM 4", "LOCKED 4", "SALVO 18".
func label() -> String:
	var k := current()
	if k == &"":
		return ""
	var n := int(ammo.get(k, 0))
	if bool(ARMS[k].get("lock", false)) and is_instance_valid(lock_target):
		return ("LOCKED %d" if locked() else "LOCK %d") % n
	var sh := String(ARMS[k]["short"])
	return "%s %d" % [sh.replace(" ", ""), n]


func smoke_label() -> String:
	return "SMOKE %d" % int(ammo.get(&"smoke", 0))


## 0..1 of the reload of arm `k` (1 = full rounds); the ring round its button.
func reload_fraction(k: StringName) -> float:
	if not ARMS.has(k) or not ammo.has(k):
		return 1.0
	var full := int(ARMS[k]["ammo"])
	if int(ammo[k]) >= full:
		return 1.0
	if float(ARMS[k]["reload"]) < 1.0:                                # a machine gun's belt: the count is the clock
		return float(ammo[k]) / float(full)
	return clampf(float(_rl.get(k, 0.0)) / float(ARMS[k]["reload"]), 0.0, 1.0)


## One physics tick from VehicleWeapons.tick_alt: reloads, the seeker, the ARMS / SMOKE presses, a shot while `fire` is held. True when something left the vehicle.
func tick(dt: float, fire: bool) -> bool:
	_cd -= dt
	_smoke_cd -= dt
	for k: StringName in _rl.keys():
		var full := int(ARMS[k]["ammo"])
		if int(ammo[k]) < full:
			_rl[k] = float(_rl[k]) + dt
			if float(_rl[k]) >= float(ARMS[k]["reload"]):
				_rl[k] = 0.0
				ammo[k] = int(ammo[k]) + 1
		else:
			_rl[k] = 0.0
	if car.driver_is_player:
		if InputMap.has_action(&"arms_next") and Input.is_action_just_pressed(&"arms_next"):
			cycle()
		if has_smoke and InputMap.has_action(&"flare") and Input.is_action_just_pressed(&"flare"):
			fire_smoke()
	if bool(def().get("lock", false)):
		_seek(dt)
	if fire and _cd <= 0.0 and int(ammo.get(current(), 0)) > 0:
		return fire_now()
	return false


func fire_now() -> bool:
	var k := current()
	if k == &"" or int(ammo.get(k, 0)) <= 0 or _cd > 0.0:
		return false
	var d: Dictionary = ARMS[k]
	_cd = 1.0 / float(d["rate"])
	var fired := false
	match k:
		&"coax", &"roof":
			_gun(k, d)
			ammo[k] = int(ammo[k]) - 1
			fired = true
		&"atgm", &"sam":
			var tgt: Node3D = lock_target if locked() else null
			_side = -_side
			var o := VehicleCraft.muzzle_origin(car) + car.aim_dir() * 0.8 + car.aim_dir().cross(Vector3.UP).normalized() * _side * float(car.spec["wid"]) * 0.32 + Vector3(0.0, 0.5, 0.0)
			var aim := car.aim_dir()
			if tgt == null:
				var to := VehicleCraft.aim_point(car) - o
				if to.length() > 12.0 and to.normalized().angle_to(aim) < 0.3:
					aim = to.normalized()
			if AirRockets.launch(car, d, o, aim, tgt):
				ammo[k] = int(ammo[k]) - 1
				fired = true
		&"salvo":
			var aimp := VehicleCraft.aim_point(car)
			var base := car.global_position - car.forward() * float(car.spec["len"]) * 0.25 + Vector3(0.0, float(car.spec["hgt"]) * 1.05, 0.0)
			var right := car.aim_dir().cross(Vector3.UP).normalized()
			for i in int(d["salvo"]):
				if int(ammo[k]) <= 0:
					break
				var fan := (float(i) - float(int(d["salvo"]) - 1) * 0.5) * 2.4
				var to2 := aimp + right * fan - base
				if to2.length() < 6.0:
					to2 = car.aim_dir() * 60.0
				if AirRockets.launch(car, d, base + right * fan * 0.15, to2.normalized(), null):
					ammo[k] = int(ammo[k]) - 1
					fired = true
	if fired:
		shots[k] = int(shots[k]) + 1
		shots_by[k] = int(shots_by.get(k, 0)) + 1
		if k == &"atgm" or k == &"sam" or k == &"salvo":
			Sfx.play_at(&"boom", car.global_position, -6.0, 1.4)
	return fired


## A machine-gun round along the gun (coax) or from the roof (roof MG): the hit zone rule of TankArmour (`light`), a spark, a tracer.
func _gun(k: StringName, d: Dictionary) -> void:
	var dir := car.aim_dir()
	var origin := car.muzzle_pos() if not bool(d.get("roof", false)) else car.global_position + Vector3(0.0, float(car.spec["hgt"]) * 1.08, 0.0) + dir * 0.6
	if bool(d.get("roof", false)):
		var to0 := VehicleCraft.aim_point(car) - origin
		if to0.length() > 4.0 and to0.normalized().angle_to(dir) < 0.25:
			dir = to0.normalized()
	var spread := float(d.get("spread", 0.0))
	dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
	var to := origin + dir * float(d["range"])
	var q := PhysicsRayQueryParameters3D.create(origin, to, Game.L_WORLD | Game.L_ENEMY | Game.L_VEHICLE)
	q.exclude = [car.get_rid()]
	var r := car.get_world_3d().direct_space_state.intersect_ray(q)
	var end := to
	if not r.is_empty():
		end = r["position"]
		var col: Object = r["collider"]
		if col != null and col.has_method(&"damage"):
			if TankArmour.hit(col, end, dir, float(d["dmg"]), &"light") == &"":
				col.call(&"damage", float(d["dmg"]))
			if car.driver_is_player and col is Node and (col as Node).is_in_group(&"enemy"):
				BlastCredit.dealt(col, float(d["dmg"]))
			hits_by[k] = int(hits_by.get(k, 0)) + 1
			if car.weapons != null:
				car.weapons.alt_hits += 1
		FX.burst(end, d["color"], 3, 3.0, 0.2, 5.0, 0.35)
	FX.tracer(origin, end, d["color"])
	Sfx.play_at(&"shot_flux", origin, -10.0, 1.1 if k == &"coax" else 0.85)


## Two smoke grenades ahead of the turret: one cloud (veh_smoke) for SMOKE_SECS.
func fire_smoke() -> bool:
	if not has_smoke or int(ammo.get(&"smoke", 0)) <= 0 or _smoke_cd > 0.0:
		return false
	_smoke_cd = 1.0 / float(ARMS[&"smoke"]["rate"])
	ammo[&"smoke"] = int(ammo[&"smoke"]) - 1
	shots[&"smoke"] = int(shots[&"smoke"]) + 1
	smokes += 1
	var f := car.forward()
	var at := car.global_position + f * (float(car.spec["len"]) * 0.5 + 6.0)
	ensure_blast(&"veh_smoke")
	BlastTable.apply(&"veh_smoke", at, car)
	FX.burst(car.global_position + Vector3(0.0, float(car.spec["hgt"]), 0.0), Color(0.8, 0.8, 0.78), 8, 6.0, 0.6, 2.0, 0.7)
	if car.driver_is_player:
		Game.say("SMOKE OUT", 1.0)
	return true


## True when `p` stands inside a live smoke cloud (any smoke zone of BlastOps: the tank's smoke, a smoke screen strike).
static func in_smoke(p: Vector3) -> bool:
	var ops := BlastOps.instance
	if ops == null or not is_instance_valid(ops):
		return false
	for z: Dictionary in ops._zones:
		if z.get("kind", &"") == &"smoke" and float(z.get("left", 0.0)) > 0.0 and (z["pos"] as Vector3).distance_to(p) < float(z["radius"]) + 2.0:
			return true
	return false


## True when a smoke cloud stands on the line from `a` to `b` (a crew does not see through it).
static func smoke_between(a: Vector3, b: Vector3) -> bool:
	var ops := BlastOps.instance
	if ops == null or not is_instance_valid(ops):
		return false
	for z: Dictionary in ops._zones:
		if z.get("kind", &"") == &"smoke" and float(z.get("left", 0.0)) > 0.0 and Throwables._seg_dist(a, b, z["pos"]) < float(z["radius"]):
			return true
	return false


# --- the seeker ------------------------------------------------------------------------------------------------------------------------

func _seek(dt: float) -> void:
	var dir := car.aim_dir()
	var rng := float(def().get("range", 500.0))
	if is_instance_valid(lock_target) and _valid(lock_target):
		var to := lock_target.global_position - car.global_position
		if to.length() <= rng and to.normalized().angle_to(dir) <= (LOCK_KEEP if lock_t >= LOCK_TIME else LOCK_CONE) and not in_smoke(lock_target.global_position):
			var was := lock_t >= LOCK_TIME
			lock_t += dt
			if not was and lock_t >= LOCK_TIME and car.driver_is_player:
				Sfx.play(&"ui_contract_accept")
			return
	lock_target = null
	lock_t = 0.0
	_scan_t -= dt
	if _scan_t > 0.0:
		return
	_scan_t = 0.1
	lock_target = find_target(dir)


func _valid(t: Node3D) -> bool:
	if t == null or not is_instance_valid(t) or not t.is_inside_tree() or t == car:
		return false
	if t is Vehicle:
		var v := t as Vehicle
		return v.active and not v.dead and not v.wreck and not v.driver_is_player
	return not bool(t.get(&"dead")) if t.get(&"dead") != null else true


## The best target in the seeker cone: enemy tanks (and aircraft for the SAM) first, then other vehicles and enemies, nearest to the aim line; nothing inside smoke.
func find_target(dir: Vector3) -> Node3D:
	var best: Node3D = null
	var bs := INF
	var o := car.global_position
	var air := bool(def().get("air", false))
	var rng := float(def().get("range", 500.0))
	for grp in [&"vehicle", &"enemy"]:
		for n: Node in car.get_tree().get_nodes_in_group(grp):
			var t := n as Node3D
			if not _valid(t):
				continue
			var d := t.global_position - o
			var dist := d.length()
			if dist < 12.0 or dist > rng:
				continue
			var ang := d.normalized().angle_to(dir)
			if ang > LOCK_CONE or in_smoke(t.global_position):
				continue
			var score := ang * 400.0 + dist * 0.1
			if t.has_meta(&"enemy_tank") or t.has_meta(&"tank_target"):
				score -= 800.0
			if air and t is Vehicle and (t as Vehicle).is_aloft():
				score -= 1000.0
			if score < bs:
				bs = score
				best = t
	return best


# --- the main gun's helpers ---------------------------------------------------------------------------------------------------------------

## What kind of round the main gun of `car` fires for the hit-zone rule: &"ap" / &"he" (the selected shell of the hero's battle or light tank), &"light" (a small-calibre gun), &"" (a cannon).
static func round_kind(car: Vehicle, def0: Dictionary) -> StringName:
	if car.driver_is_player and BlastOps.is_shell_gun(car.kind):
		var id: StringName = BlastOps.SHELL_IDS[BlastOps.shell_index % BlastOps.SHELL_IDS.size()]
		return &"ap" if id == &"ord_tank_ap" else (&"he" if id == &"ord_tank_he" else &"")
	return &"light" if float(def0.get("dmg", 0.0)) < 25.0 else &""


## The howitzer's landing point for the crosshair's ground point `aim`: the nearest target (an enemy tank, a mission's artillery target, an armed vehicle, an enemy) within SNAP_R.
static func artillery_aim(car: Vehicle, aim: Vector3) -> Vector3:
	if not on:
		return aim
	var best := aim
	var bd := SNAP_R
	for grp in [&"vehicle", &"enemy"]:
		for n: Node in car.get_tree().get_nodes_in_group(grp):
			var t := n as Node3D
			if t == null or t == car or not t.is_inside_tree():
				continue
			if t is Vehicle and ((t as Vehicle).dead or not (t as Vehicle).active or (t as Vehicle).driver_is_player or not (t.has_meta(&"enemy_tank") or t.has_meta(&"tank_target"))):
				continue
			var d := Vector2(t.global_position.x - aim.x, t.global_position.z - aim.z).length()
			if d < bd:
				bd = d
				best = t.global_position
	if best != aim:
		snapped += 1
	return best


## Where the howitzer's shell lands now (the marker): the crosshair's ground point inside the range, snapped like the shell. INF when the vehicle has no indirect gun.
static func marker_point(car: Vehicle) -> Vector3:
	if car == null or car.weapons == null or not bool(car.weapons.def.get("indirect", false)):
		return Vector3.INF
	var aim: Vector3 = VehicleCraft.aim_point(car)
	var off := aim - car.global_position
	var rng := float(car.weapons.def["range"])
	if Vector2(off.x, off.z).length() > rng:
		off = off.normalized() * rng
		aim = car.global_position + off
	var was := snapped
	var p := artillery_aim(car, aim)
	snapped = was
	return p


# --- the HUD ----------------------------------------------------------------------------------------------------------------------------

## The rings round the buttons (TouchControls): the main gun's reload on FIRE, the selected arm's reload on its button, SMOKE's on SMOKE.
static func button_arcs(b: Dictionary, arcs: Array, centre: Vector2, r: float, s: float, v: Vehicle) -> void:
	if v == null or v.weapons == null or v.cls != &"tank":
		return
	var f := 1.0
	var act: StringName = b["action"]
	if act == &"fire" and v.weapons.mounted():
		f = v.weapons.ready_fraction()
	elif v.weapons.tarms != null:
		var ta := v.weapons.tarms as TankArms
		if act == &"aim":
			f = ta.reload_fraction(ta.current())
		elif act == &"flare":
			f = ta.reload_fraction(&"smoke")
		else:
			return
	else:
		return
	if f < 0.995:
		arcs.append([centre, r + 4.0 * s, -PI * 0.5 + TAU * maxf(f, 0.01), Color(1.0, 0.72, 0.25, 0.95)])


## Over the world (Hud, after FlightHud): the ATGM / SAM seeker box on its target and the HOWITZER's target marker (a ring on the ground where the shell will land).
static func draw_hud(c: Control, v: Vehicle, s: float) -> void:
	if not on or v == null or v.cls != &"tank" or v.weapons == null:
		return
	var cam := c.get_viewport().get_camera_3d()
	if cam == null:
		return
	var ta := v.weapons.tarms as TankArms
	if ta != null and bool(ta.def().get("lock", false)) and is_instance_valid(ta.lock_target):
		var tp := ta.lock_target.global_position + Vector3(0.0, 1.2, 0.0)
		if not cam.is_position_behind(tp):
			var sp := cam.unproject_position(tp)
			var k := clampf(ta.lock_t / LOCK_TIME, 0.0, 1.0)
			var box := 34.0 * s * (1.8 - 0.8 * k)
			var col := Color(1.0, 0.3, 0.25, 0.95) if ta.locked() else Color(1.0, 0.85, 0.3, 0.9)
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					var corner := sp + Vector2(sx, sy) * box
					c.draw_line(corner, corner - Vector2(sx, 0.0) * box * 0.5, col, 3.0 * s)
					c.draw_line(corner, corner - Vector2(0.0, sy) * box * 0.5, col, 3.0 * s)
	var mp := marker_point(v)
	if mp.is_finite() and not cam.is_position_behind(mp):
		var rr := float(v.weapons.def.get("blast", 10.0))
		var pts := PackedVector2Array()
		var ok := true
		for i in 25:
			var a := TAU * float(i) / 24.0
			var w := mp + Vector3(cos(a) * rr, 0.3, sin(a) * rr)
			if cam.is_position_behind(w):
				ok = false
				break
			pts.append(cam.unproject_position(w))
		var col2 := Color(1.0, 0.45, 0.15, 0.95) if v.weapons.can_fire() else Color(1.0, 0.8, 0.4, 0.6)
		if ok:
			c.draw_polyline(pts, col2, 3.0 * s)
		var cp := cam.unproject_position(mp)
		c.draw_line(cp - Vector2(10.0, 0.0) * s, cp + Vector2(10.0, 0.0) * s, col2, 2.0 * s)
		c.draw_line(cp - Vector2(0.0, 10.0) * s, cp + Vector2(0.0, 10.0) * s, col2, 2.0 * s)
		var pin := cp - Vector2(0.0, 34.0) * s                                  # a pin over the ring: far away the ring is a thin line
		c.draw_line(pin, cp - Vector2(0.0, 12.0) * s, col2, 2.0 * s)
		c.draw_colored_polygon(PackedVector2Array([pin + Vector2(-9.0, -14.0) * s, pin + Vector2(9.0, -14.0) * s, pin]), col2)
		var font := UiUtil.font()
		var dist := Vector2(mp.x - v.global_position.x, mp.z - v.global_position.z).length()
		c.draw_string(font, cp + Vector2(14.0, -10.0) * s, "%d M" % roundi(dist), HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(18.0 * s), col2)
