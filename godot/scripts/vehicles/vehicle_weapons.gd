class_name VehicleWeapons
extends RefCounted
## Mounted weapon of a vehicle (E2): sport = rotary gun, suv = cannon (small blast), hover = bolt gun. Fire button (`fire`) while driving, finite ammo,
## heat builds per shot and locks the weapon at 1.0 until it cools below LOCK_RESUME (overheating). Hitscan from the nose along the heading; no node, no draw call
## besides FX.tracer / FX.burst (pooled). Numbers live in VehicleSpecs.WEAPONS.
## API: tick(dt, fire) -> bool (a shot was fired) · ammo · heat · locked · shots · can_fire() · reload_full() · muzzle() · has_weapon(kind)

var car: Vehicle
var def: Dictionary = {}
var ammo := 0
var heat := 0.0
var locked := false
var shots := 0
var hits := 0
var _cd := 0.0
var alt_def: Dictionary = {}          ## the secondary weapon (VehicleSpecs.ALT_WEAPONS: rockets, missiles): fired by tick_alt on the AIM button
var alt_ammo := 0
var alt_shots := 0
var _alt_cd := 0.0
var _alt_rl := 0.0
var _alt_side := 1.0


static func has_weapon(kind: StringName) -> bool:
	return VehicleSpecs.WEAPONS.has(kind)


func setup(c: Vehicle) -> void:
	car = c
	def = VehicleSpecs.WEAPONS.get(c.kind, {})
	alt_def = VehicleSpecs.ALT_WEAPONS.get(c.kind, {})
	reload_full()


func mounted() -> bool:
	return not def.is_empty()


func reload_full() -> void:
	ammo = int(def.get("ammo", 0))
	heat = 0.0
	locked = false
	_cd = 0.0
	shots = 0
	hits = 0
	alt_ammo = int(alt_def.get("ammo", 0))
	alt_shots = 0
	_alt_cd = 0.0
	_alt_rl = 0.0


func can_fire() -> bool:
	return mounted() and ammo > 0 and not locked and _cd <= 0.0


func muzzle() -> Vector3:
	return car.muzzle_pos()


## One physics tick: cool down, then fire when asked and allowed. Returns true when a shot left the muzzle.
func tick(dt: float, fire: bool) -> bool:
	if not mounted():
		return false
	_cd -= dt
	var shot := false
	if fire and can_fire():
		_shoot()
		shot = true
	else:
		heat = maxf(0.0, heat - float(def["cool"]) * dt)
	if locked and heat <= VehicleSpecs.WEAPON_LOCK_RESUME:
		locked = false
	return shot


func _shoot() -> void:
	_cd = 1.0 / float(def["rate"])
	ammo -= 1
	shots += 1
	heat = minf(1.0, heat + float(def["heat"]))
	if heat >= 1.0:
		locked = true
		Game.say("WEAPON OVERHEATED", 1.0)
	var origin := muzzle()
	var dir := car.aim_dir()
	var spread := float(def.get("spread", 0.0))
	if spread > 0.0:
		dir = dir.rotated(Vector3.UP, randf_range(-spread, spread)).rotated(dir.cross(Vector3.UP).normalized() if absf(dir.y) < 0.99 else Vector3.RIGHT, randf_range(-spread, spread) * 0.5)
	var to := origin + dir * float(def["range"])
	var space := car.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, to, Game.L_WORLD | Game.L_ENEMY | Game.L_VEHICLE)
	q.exclude = [car.get_rid()]
	var r := space.intersect_ray(q)
	var end := to
	if not r.is_empty():
		end = r["position"]
		var col: Object = r["collider"]
		if col != null and col.has_method(&"damage"):
			col.call(&"damage", float(def["dmg"]))
			hits += 1
		var blast := float(def.get("blast", 0.0))
		if blast > 0.0:
			Game.explode(end, blast, {"enemy_dmg": float(def["dmg"]) * 0.5, "car_dmg": float(def["dmg"]) * 0.5, "player_dmg": 0.0, "color": def["color"]})
		else:
			FX.burst(end, def["color"], 4, 4.0, 0.25, 6.0, 0.4)
	FX.tracer(origin, end, def["color"])
	Sfx.play_at(&"shot", origin, -8.0)


# --- the secondary weapon: rockets (gunship) and homing missiles (jet) ---------------------------------------------------------------------

func has_alt() -> bool:
	return not alt_def.is_empty()


func can_fire_alt() -> bool:
	return has_alt() and alt_ammo > 0 and _alt_cd <= 0.0


## One physics tick of the secondary weapon: the cooldown, one round back every `reload` seconds, and a salvo when `fire` is held and the weapon is ready. True when a salvo left the rails.
func tick_alt(dt: float, fire: bool) -> bool:
	if not has_alt():
		return false
	_alt_cd -= dt
	if alt_ammo < int(alt_def["ammo"]):
		_alt_rl += dt
		if _alt_rl >= float(alt_def["reload"]):
			_alt_rl = 0.0
			alt_ammo += 1
	else:
		_alt_rl = 0.0
	if fire and can_fire_alt():
		return fire_alt()
	return false


## Fire a salvo now (a test can call it directly): `salvo` rockets from the pylons, left and right in turn.
func fire_alt() -> bool:
	if not can_fire_alt():
		return false
	_alt_cd = 1.0 / float(alt_def["rate"])
	var fired := false
	var origin := car.muzzle_pos()
	var dir := car.aim_dir()
	var right := dir.cross(Vector3.UP)
	right = right.normalized() if right.length() > 0.01 else car.right()
	var tgt := _lock(dir) if float(alt_def.get("homing", 0.0)) > 0.0 else null
	for i in int(alt_def.get("salvo", 1)):
		if alt_ammo <= 0:
			break
		_alt_side = -_alt_side
		var o := origin + right * _alt_side * (float(car.spec["wid"]) * 0.3) + Vector3(0.0, -0.5, 0.0)
		if AirRockets.launch(car, alt_def, o, dir.rotated(Vector3.UP, _alt_side * 0.012), tgt):
			alt_ammo -= 1
			alt_shots += 1
			fired = true
	return fired


## The nearest enemy or vehicle in a narrow cone in front of the nose (within the weapon's range): the missile steers to it.
func _lock(dir: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := float(alt_def.get("range", 600.0))
	var o := car.global_position
	for grp in [&"enemy", &"vehicle"]:
		for n: Node in car.get_tree().get_nodes_in_group(grp):
			var t := n as Node3D
			if t == null or t == car or not t.is_inside_tree():
				continue
			var d := t.global_position - o
			var dist := d.length()
			if dist < 12.0 or dist > bd:
				continue
			if d.normalized().angle_to(dir) > 0.4:
				continue
			bd = dist
			best = t
	return best
