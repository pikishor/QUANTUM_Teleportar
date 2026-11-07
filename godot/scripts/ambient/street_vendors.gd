class_name StreetVendors
extends RefCounted
## Street market stalls and their vendors (owner round 3: "the street is empty, no vendors"). `sites()` is the pure table of stall places on the kerb side of the sidewalks (a stable hash of
## axis / road / span / side, 16 % of the spans, plus two forced stalls in the market street next to the spawn); the world draws one ONE-draw family of stalls on them (city_props.gd
## `stall_mesh`), and this class gives every stall near the hero a person behind its counter: a pooled crowd slot pinned to the site (AmbientCrowd.pin_vendor), wide hat and a tray of glowing
## wares. A vendor stands until he is scared (gunfire: he runs), shot, or the hero leaves; the slot then goes back to the walkers.

const SITE_CHANCE := 160                 ## per mille of the sidewalk spans that carry a stall
const STALL_OFF := 9.1                   ## stall centre, metres from the road centre line (on the parking bay edge, the kerb is at 10)
const VENDOR_OFF := 10.3                 ## the vendor stands behind the counter (1.2 m behind the stall's middle), in front of the lit back panel
const SPAN_MID := 51.3                   ## middle of a sidewalk span (AmbientCrowd.STOP_MID)
const CAPS: Array[int] = [5, 7, 9]       ## vendors standing at once per tier
const EVERY := 0.4
## axis, road index, span index, side: the market street next to the spawn (the road z = 0, the span x -80..0)
const FORCED: Array = [[0, 8, 7, 1], [0, 8, 7, -1]]

static var _sites: Array = []

var crowd: RefCounted
var served := 0                          ## vendors placed so far (tests)
var _slot := PackedInt32Array()
var _t := 0.0
var cap := 7


static func _hash(a: int, k: int, j: int, s: int) -> int:
	var h := (a * 73856093) ^ (k * 19349663) ^ (j * 83492791) ^ ((s + 2) * 50331653)
	h = (h ^ (h >> 15)) * 0x2c1b3c6d
	h = h ^ (h >> 12)
	return h & 0x7fffffff


## Every stall: {pos, yaw, axis, lat, u, off, face, forced}. Computed once.
static func sites() -> Array:
	if not _sites.is_empty():
		return _sites
	var n := CityLayout.N
	for a in 2:
		for k in range(1, n):
			for j in n:
				for s in [-1, 1]:
					var forced := false
					for f: Array in FORCED:
						if f[0] == a and f[1] == k and f[2] == j and f[3] == s:
							forced = true
					if not forced and _hash(a, k, j, s) % 1000 >= SITE_CHANCE:
						continue
					var u := 80.0 * float(j) + SPAN_MID - CityLayout.HALF - 11.3
					if absf(u) > CityLayout.HALF - 40.0:
						continue
					var c := CityLayout.road_center(k)
					var sf := float(s)
					var pos := Vector3(u, 0.0, c + sf * STALL_OFF) if a == 0 else Vector3(c + sf * STALL_OFF, 0.0, u)
					var yaw := (0.0 if s < 0 else PI) if a == 0 else -sf * PI * 0.5
					_sites.append({"pos": pos, "yaw": yaw, "axis": a, "lat": c + sf * 11.3, "u": u, "off": sf * (VENDOR_OFF - 11.3), "face": -s, "forced": forced})
	return _sites


func setup(crowd_ref: RefCounted) -> void:
	crowd = crowd_ref
	_slot.resize(sites().size())
	_slot.fill(-1)


func set_tier(level: int) -> void:
	cap = CAPS[clampi(level, 0, 2)]
	if level == 0:
		cap = LowPlus.scaled(cap, 0.7, 3)


func reset() -> void:
	_slot.fill(-1)
	_t = 0.0


func active_count() -> int:
	var n := 0
	for i in _slot.size():
		if _slot[i] >= 0:
			n += 1
	return n


func step(delta: float, center: Vector3) -> void:
	_t -= delta
	if _t > 0.0 or crowd == null:
		return
	_t = EVERY
	var sit := sites()
	var active := 0
	for i in sit.size():
		var sl := _slot[i]
		if sl >= 0:
			var site: Dictionary = sit[i]
			var p: Vector3 = crowd.person_position(sl)
			var sp: Vector3 = site["pos"]
			if not crowd.is_pinned(sl) or Vector2(p.x - sp.x, p.z - sp.z).length() > 3.5:
				_slot[i] = -1
			else:
				active += 1
	var reach: float = crowd.radius * 0.9
	var r2 := reach * reach
	for i in sit.size():
		if _slot[i] >= 0 or active >= cap:
			continue
		var site: Dictionary = sit[i]
		var sp: Vector3 = site["pos"]
		var dx := sp.x - center.x
		var dz := sp.z - center.z
		if dx * dx + dz * dz > r2:
			continue
		var slot: int = crowd.claim_slot(center)
		if slot < 0:
			break
		crowd.pin_vendor(slot, site["axis"], site["lat"], site["u"], site["off"], site["face"])
		_slot[i] = slot
		active += 1
		served += 1
