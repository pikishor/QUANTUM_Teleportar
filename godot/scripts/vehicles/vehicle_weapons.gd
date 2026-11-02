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


static func has_weapon(kind: StringName) -> bool:
	return VehicleSpecs.WEAPONS.has(kind)


func setup(c: Vehicle) -> void:
	car = c
	def = VehicleSpecs.WEAPONS.get(c.kind, {})
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


func can_fire() -> bool:
	return mounted() and ammo > 0 and not locked and _cd <= 0.0


func muzzle() -> Vector3:
	return car.global_position + car.forward() * float(car.spec["len"]) * 0.5 + Vector3(0.0, 0.7 + float(car.spec.get("hover_h", 0.0)), 0.0)


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
	var dir := car.forward()
	var spread := float(def.get("spread", 0.0))
	if spread > 0.0:
		dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
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
