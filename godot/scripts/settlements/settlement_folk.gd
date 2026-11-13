class_name SettlementFolk
extends RefCounted
## The people of the towns (wave 112): farmers, fishers, hikers, workers, shopkeepers, police, tourists and traders standing at their doors, counters and quays. They are pedestrians of the CITY crowd
## (AmbientCrowd): a pooled crowd slot pinned to the spot (AmbientCrowd.pin_vendor with an archetype seed and the ground height), exactly like the stall vendors (StreetVendors), so they cost no draw call,
## idle and gesture by the crowd shader, can be shot or run when scared, and the slot goes back to the walkers when the hero leaves. The crowd is empty out in the country, so the pool is free there.
##   SettlementFolk.entries()   every place: {key, role, pos (ground), face (unit world x, z), town, seed}
##   SettlementFolk.seed_of(role)  the crowd seed that gives the role its look (archetype: floor(seed * 6) = group, the fraction picks inside it)

const CAPS: Array[int] = [8, 12, 16]
const EVERY := 0.5

## role -> [group, fraction]: villager hoodie, farmer stocky porter, shopkeeper vendor (wide hat, tray), worker and police hi-vis, fisher heavy coat, tourist umbrella, hiker backpack, trader mantle, child.
const LOOKS := {&"villager": [1, 0.3], &"farmer": [5, 0.8], &"shopkeeper": [0, 0.7], &"worker": [4, 0.8], &"police": [4, 0.92], &"fisher": [5, 0.2], &"tourist": [2, 0.3], &"hiker": [4, 0.2],
	&"trader": [2, 0.9], &"child": [1, 0.8]}

static var _entries: Array[Dictionary] = []

var crowd: RefCounted
var served := 0                          ## people placed so far (tests)
var _slot := {}                          ## entry key -> crowd slot
var _t := 0.0
var cap := 12


static func seed_of(role: StringName, key := 0) -> float:
	var l: Array = LOOKS.get(role, LOOKS[&"villager"])
	var jitter := (fposmod(sin(float(key) * 12.9898 + 1.3) * 43758.5453, 1.0) - 0.3) * 0.02          # a little off the look's seed: another palette, the same archetype (r moves by -0.04 .. +0.08)
	return (float(int(l[0])) + float(l[1])) / 6.0 + jitter


static func reset_entries() -> void:
	_entries.clear()


static func entries() -> Array[Dictionary]:
	if not _entries.is_empty():
		return _entries
	var ti := 0
	for s in SettlementData.towns():
		var plan := SettlementData.plan_of(s)
		var yaw: float = s["yaw"]
		var k := 0
		for f in plan.folk:
			var w := OutskirtsSites.to_world(s, Vector3(float(f["x"]), 0.0, float(f["z"])))
			var fd := Basis(Vector3.UP, yaw + float(f["yaw"])) * Vector3(0.0, 0.0, -1.0)
			_entries.append({"key": ti * 1000 + k, "role": f["role"], "pos": Vector3(w.x, TerrainHeight.height_at(w.x, w.z), w.z), "face": Vector2(fd.x, fd.z).normalized(), "town": s["id"],
				"seed": seed_of(f["role"], ti * 1000 + k)})
			k += 1
		ti += 1
	return _entries


func setup(crowd_ref: RefCounted) -> void:
	crowd = crowd_ref
	_slot.clear()


func set_tier(level: int) -> void:
	cap = CAPS[clampi(level, 0, 2)]


func reset() -> void:
	_slot.clear()
	_t = 0.0


func active_count() -> int:
	return _slot.size()


func step(delta: float, center: Vector3) -> void:
	_t -= delta
	if _t > 0.0 or crowd == null:
		return
	_t = EVERY
	var all := entries()
	var by_key := {}
	for e in all:
		by_key[e["key"]] = e
	var gone: Array = []
	for key in _slot.keys():                                                     # still standing at the post?
		var e: Dictionary = by_key[key]
		var sl: int = _slot[key]
		var p: Vector3 = crowd.person_position(sl)
		var sp: Vector3 = e["pos"]
		if not crowd.is_pinned(sl) or Vector2(p.x - sp.x, p.z - sp.z).length() > 3.5:
			gone.append(key)
	for key in gone:
		_slot.erase(key)
	var reach: float = float(crowd.radius) * 0.9
	var near: Array = []
	for e in all:
		if _slot.has(e["key"]):
			continue
		var sp2: Vector3 = e["pos"]
		var d := Vector2(sp2.x - center.x, sp2.z - center.z).length()
		if d <= reach:
			near.append([d, e])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for pair in near:
		if _slot.size() >= cap:
			break
		var e2: Dictionary = pair[1]
		var slot: int = crowd.claim_slot(center)
		if slot < 0:
			break
		var sp3: Vector3 = e2["pos"]
		var fc: Vector2 = e2["face"]
		if absf(fc.y) >= absf(fc.x):                                             # facing along z: stand on a line of axis 0 (z is the lateral), looking to its + or - side
			crowd.pin_vendor(slot, 0, sp3.z, sp3.x, 0.0, 1 if fc.y > 0.0 else -1, float(e2["seed"]), sp3.y)
		else:
			crowd.pin_vendor(slot, 1, sp3.x, sp3.z, 0.0, 1 if fc.x > 0.0 else -1, float(e2["seed"]), sp3.y)
		_slot[e2["key"]] = slot
		served += 1
