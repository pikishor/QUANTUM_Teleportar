class_name Garage
extends RefCounted
## E3 / E6: the player's own car. One car is kept in the garage (kind, paint, four upgrade tracks); the phone button CALL CAR brings it to the player outdoors.
## Data only (no nodes): Progress owns an instance and saves it in [garage]; VehicleManager.summon_garage() builds the car; Vehicle.apply_garage() applies the tuning.
## API: save_car(v) · clear() · reset() · set_paint(i) · price(stat) · can_upgrade(stat, wallet) · upgrade(stat, wallet) · level(stat) · to_save() · from_save(d)

const STATS: Array[StringName] = [&"speed", &"armour", &"grip", &"weapon"]
const LABELS := {&"speed": "SPEED", &"armour": "ARMOUR", &"grip": "GRIP", &"weapon": "WEAPON"}
const MAX_LEVEL := 3
const BASE_PRICE := {&"speed": 300, &"armour": 250, &"grip": 200, &"weapon": 400}
const SPEED_STEP := 0.06            ## top speed and acceleration per level
const ARMOUR_STEP := 0.2            ## hit points per level
const GRIP_STEP := 0.08             ## lateral grip per level
const WEAPON_STEP := 0.25           ## weapon damage and ammo per level (level 1 also mounts a rail gun on a car without one)
const SUMMON_COOLDOWN := 10.0       ## seconds between two CALL CAR uses
const DEFAULT_PAINT := 5

var kind: StringName = &""          ## the car kind kept here, &"" = empty garage
var paint := DEFAULT_PAINT          ## index into VehicleSpecs.COLORS
var levels := {}                    ## stat -> level 0..MAX_LEVEL


func has_car() -> bool:
	return kind != &"" and VehicleSpecs.SPECS.has(kind)


## Whether this car can be kept (a live ordinary car, not a husk or a Vael patrol).
static func can_keep(v: Vehicle) -> bool:
	return is_instance_valid(v) and v.active and not v.dead and not v.wreck and not v.patrol and VehicleSpecs.SPECS.has(v.kind)


## Keeps `v`. The upgrades stay when it is the same kind as the car already kept (re-saving a repaired car), a new kind starts stock.
func save_car(v: Vehicle) -> bool:
	if not can_keep(v):
		return false
	if v.kind != kind:
		levels = {}
	kind = v.kind
	if v.paint_i >= 0:
		paint = clampi(v.paint_i, 0, VehicleSpecs.COLORS.size() - 1)
	return true


func clear() -> void:
	kind = &""
	paint = DEFAULT_PAINT
	levels = {}


func reset() -> void:
	clear()


func level(stat: StringName) -> int:
	return clampi(int(levels.get(stat, 0)), 0, MAX_LEVEL)


func set_paint(i: int) -> bool:
	if i < 0 or i >= VehicleSpecs.COLORS.size():
		return false
	paint = i
	return true


## Credits for the next level of `stat` (0 when maxed).
func price(stat: StringName) -> int:
	var l := level(stat)
	if l >= MAX_LEVEL or not BASE_PRICE.has(stat):
		return 0
	return Economy.garage_base(stat) * (l + 1)


func can_upgrade(stat: StringName, wallet: Object) -> bool:
	return has_car() and STATS.has(stat) and level(stat) < MAX_LEVEL and wallet != null and int(wallet.get(&"credits")) >= price(stat)


## Buys the next level through `wallet.spend(n)` (the Progress node). False when empty, maxed or too poor (nothing is charged).
func upgrade(stat: StringName, wallet: Object) -> bool:
	if not can_upgrade(stat, wallet):
		return false
	if not bool(wallet.call(&"spend", price(stat))):
		return false
	levels[stat] = level(stat) + 1
	return true


## Spec of the kept car with the upgrades applied (a copy; the shared VehicleSpecs.SPECS entry stays untouched).
func tuned_spec() -> Dictionary:
	var s: Dictionary = (VehicleSpecs.SPECS[kind] as Dictionary).duplicate(true)
	var sp := 1.0 + SPEED_STEP * level(&"speed")
	s["max"] = float(s["max"]) * sp
	s["acc"] = float(s["acc"]) * sp
	s["grip"] = float(s["grip"]) * (1.0 + GRIP_STEP * level(&"grip"))
	s["hp"] = float(s["hp"]) * (1.0 + ARMOUR_STEP * level(&"armour"))
	return s


## Weapon definition of the kept car (native weapon, or a rail gun from level 1), upgraded; {} when it has none.
func weapon_def() -> Dictionary:
	var d: Dictionary = VehicleSpecs.WEAPONS.get(kind, {})
	var l := level(&"weapon")
	if d.is_empty() and l > 0:
		d = VehicleSpecs.WEAPONS[&"sport"]
	if d.is_empty():
		return {}
	d = d.duplicate()
	d["dmg"] = float(d["dmg"]) * (1.0 + WEAPON_STEP * l)
	d["ammo"] = int(float(d["ammo"]) * (1.0 + WEAPON_STEP * l))
	return d


func to_save() -> Dictionary:
	var lv := {}
	for st in STATS:
		lv[String(st)] = level(st)
	return {"kind": String(kind), "paint": paint, "levels": lv}


## Loads a saved dictionary; unknown or damaged data gives an empty garage (never an error).
func from_save(d: Dictionary) -> void:
	clear()
	var k := StringName(str(d.get("kind", "")))
	if k == &"" or not VehicleSpecs.SPECS.has(k) or bool((VehicleSpecs.SPECS[k] as Dictionary).get("patrol", false)):
		return
	kind = k
	var pv: Variant = d.get("paint", DEFAULT_PAINT)
	paint = clampi(int(pv) if pv is int or pv is float else DEFAULT_PAINT, 0, VehicleSpecs.COLORS.size() - 1)
	var lv: Variant = d.get("levels", {})
	if lv is Dictionary:
		for st in STATS:
			var n: Variant = (lv as Dictionary).get(String(st), 0)
			levels[st] = clampi(int(n) if n is int or n is float else 0, 0, MAX_LEVEL)
