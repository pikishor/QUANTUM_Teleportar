class_name StreetLife
extends RefCounted
## Wave 123 (w123-life): street life and the wave 122 leftovers. `fix` is the switch of every w123-life change (W123_LIFE_OLD=1 in the checks: the wave 122 behaviour):
##   buses        a near-traffic bus brakes at a bus stop on its side of the road, stands BUS_DWELL s with the doors open, then drives on (NearTraffic._bus_allow)
##   wall run     the wall run starts only on a wall that is whole across the body (both shoulders and the head): no run up a door frame (HeroVerbs._wall_normal)
##   shops        the SNAKE button (and its CLIMB word) is hidden inside a walk-in shop, as under a tower's ceilings (SnakeTraversal.button_shown)

static var fix := OS.get_environment("W123_LIFE_OLD") != "1"

const BUS_DWELL := 5.0                   ## seconds a bus stands at a stop
const BUS_LOOK := 34.0                   ## m ahead a bus starts to brake for its stop
const BUS_SIDE := 9.0                    ## a stop serves the lane within this of it (the stop stands 11.8 m from the road centre, the lane at 3.5 on the same side)
const WALL_SIDE := 0.5                   ## m to each side of the chest ray: the shoulder rays of the wall-run check
const WALL_HEAD := 0.8                   ## m over the chest ray: the head ray

static var bus_stops: Array[Vector3] = []        ## every bus stop of the city (CityProps._place_bus_stops)
static var bus_dwells := 0                       ## buses that stood at a stop (tests)
static var bus_leaves := 0                       ## ... and drove on
const SIT_CAPS: Array[int] = [3, 5, 6]   ## people sitting on benches at once per tier (crowd slots: nothing new is built)
const SIT_EVERY := 0.5
const SIT_STAY := Vector2(14.0, 40.0)    ## seconds before a sitter stands up and walks on (the bench is free for the next one)
const SIT_REACH := 40.0                  ## benches within this of the hero get people

const WAIT_CAPS: Array[int] = [2, 4, 5]  ## people waiting at bus stops at once per tier
const WAIT_SPOTS: Array[float] = [-1.4, 0.9, 2.6]   ## where they stand along the kerb beside a shelter (m from its middle)
const WAIT_LAT := 10.8                   ## m from the road centre: between the kerb (10) and the shelter (11.8)

static var benches: Array[Vector3] = []          ## bench seats (x, face, z): CityProps street dressing (y holds the facing: +1 = +z)

var crowd: RefCounted
var cap := 5
var sat := 0                                     ## people seated so far (tests)
var wait_cap := 4
var waited := 0                                  ## people placed at bus stops so far (tests)
var boarded := 0                                 ## ... who got on a bus
var _wslot := PackedInt32Array()                 ## per bus stop and WAIT_SPOTS spot: the crowd slot standing there (-1 none)
var _slot := PackedInt32Array()                  ## per bench: the crowd slot on it (-1 none)
var _until := PackedFloat32Array()
var _t := 0.0
var _clock := 0.0
var _rng := RandomNumberGenerator.new()
var _bad_b := PackedByteArray()                  ## w123-critic: per bench, 1 = its seat is inside a solid prop (a kiosk, a kit cluster): nobody sits there
var _bad_w := PackedByteArray()                  ## ... per bus-stop spot, 1 = a lamp / kit pole stands on it: nobody waits there


## w123-critic: which seats and wait spots stand inside a solid prop (computed once, when the city's collider sources exist).
func _mark_bad() -> void:
	_bad_b.resize(benches.size())
	_bad_b.fill(0)
	_bad_w.resize(bus_stops.size() * WAIT_SPOTS.size())
	_bad_w.fill(0)
	if not critic:
		return
	for k in benches.size():
		if solid_at(benches[k].x, benches[k].z, 0.3, "StreetDress") != "":
			_bad_b[k] = 1
	for s in bus_stops.size():
		for j in WAIT_SPOTS.size():
			var w := wait_spot(bus_stops[s], j)
			if solid_at(w[0], w[1], 0.3) != "":
				_bad_w[s * WAIT_SPOTS.size() + j] = 1


func setup(crowd_ref: RefCounted) -> void:
	crowd = crowd_ref
	_rng.seed = 12301
	reset()


func set_tier(level: int) -> void:
	cap = SIT_CAPS[clampi(level, 0, 2)]
	wait_cap = WAIT_CAPS[clampi(level, 0, 2)]


func reset() -> void:
	_slot.resize(benches.size())
	_slot.fill(-1)
	_until.resize(benches.size())
	_wslot.resize(bus_stops.size() * WAIT_SPOTS.size())
	_wslot.fill(-1)
	_t = 0.0


func sitting_count() -> int:
	var n := 0
	for s in _slot:
		if s >= 0:
			n += 1
	return n


## Seated people within `r` of `pos` (tests, the census).
func sitting_near(pos: Vector3, r: float) -> int:
	var n := 0
	for k in _slot.size():
		if _slot[k] >= 0:
			var b := benches[k]
			if Vector2(b.x - pos.x, b.z - pos.z).length() <= r:
				n += 1
	return n


## People waiting at bus stops within `r` of `pos` (tests).
func waiting_near(pos: Vector3, r: float) -> int:
	var n := 0
	for k in _wslot.size():
		if _wslot[k] >= 0 and crowd.is_waiting(_wslot[k]):
			var p: Vector3 = crowd.person_position(_wslot[k])
			if Vector2(p.x - pos.x, p.z - pos.z).length() <= r:
				n += 1
	return n


## Spot `j` beside bus stop `sp`: [x, z, face, axis].
static func wait_spot(sp: Vector3, j: int) -> Array:
	var cz := CityLayout.road_center(roundi((sp.z + CityLayout.HALF) / CityLayout.PITCH))
	var cx := CityLayout.road_center(roundi((sp.x + CityLayout.HALF) / CityLayout.PITCH))
	if absf(absf(sp.z - cz) - 11.8) < 0.3:
		var side := signf(sp.z - cz)
		return [sp.x + WAIT_SPOTS[j], cz + side * WAIT_LAT, -int(side), 0]
	var side2 := signf(sp.x - cx)
	return [cx + side2 * WAIT_LAT, sp.z + WAIT_SPOTS[j], -int(side2), 1]


func _step_waiters(center: Vector3) -> void:
	var nt := NearTraffic.instance
	var bus := nt.bus_at_stop() if nt != null else -1
	var bpos := nt.car_position(bus) if bus >= 0 else Vector3.INF
	var active := 0
	var ns := WAIT_SPOTS.size()
	for k in _wslot.size():
		var sl := _wslot[k]
		if sl < 0:
			continue
		var sp := bus_stops[k / ns]
		if not crowd.is_waiting(sl):
			_wslot[k] = -1
		elif bpos != Vector3.INF and Vector2(bpos.x - sp.x, bpos.z - sp.z).length() < 11.0:     # the bus in the kerb lane beside the shelter
			crowd.board(sl)                              # the bus is here: they get on
			_wslot[k] = -1
			boarded += 1
		else:
			active += 1
	var r2 := SIT_REACH * SIT_REACH
	for s in bus_stops.size():
		if active >= wait_cap:
			break
		var sp := bus_stops[s]
		if (sp.x - center.x) * (sp.x - center.x) + (sp.z - center.z) * (sp.z - center.z) > r2:
			continue
		if bpos != Vector3.INF and Vector2(bpos.x - sp.x, bpos.z - sp.z).length() < 20.0:
			continue
		for j in ns:
			if active >= wait_cap or _wslot[s * ns + j] >= 0 or (j == 2 and (s % 2) == 0) or _bad_w[s * ns + j] != 0:
				continue
			var slot: int = crowd.claim_slot(center)
			if slot < 0:
				return
			var w := wait_spot(sp, j)
			crowd.pin_sitter(slot, w[0], w[1], w[2], w[3], 2)
			_wslot[s * ns + j] = slot
			active += 1
			waited += 1


func step(delta: float, center: Vector3) -> void:
	_clock += delta
	_t -= delta
	if not fix or _t > 0.0 or crowd == null:
		return
	_t = SIT_EVERY
	if _slot.size() != benches.size() or _wslot.size() != bus_stops.size() * WAIT_SPOTS.size():
		reset()
	if _bad_b.size() != benches.size() or _bad_w.size() != _wslot.size():
		_mark_bad()
	_step_waiters(center)
	var active := 0
	for k in _slot.size():
		var sl := _slot[k]
		if sl < 0:
			continue
		var b := benches[k]
		var p: Vector3 = crowd.person_position(sl)
		if not crowd.is_sitting(sl) or Vector2(p.x - b.x, p.z - b.z).length() > 1.0:
			_slot[k] = -1
		elif _clock > _until[k]:
			if critic and crowd.has_method(&"stand_up"):
				crowd.stand_up(sl)                       # w123-critic: back to the sidewalk line (the old way walked on along the bench row, through the bench sets and shop fronts)
			else:
				crowd.call(&"_unpin", sl)                # he stands up and walks on along the sidewalk
			_slot[k] = -1
		else:
			active += 1
	var r2 := SIT_REACH * SIT_REACH
	for k in benches.size():
		if active >= cap:
			break
		if _slot[k] >= 0 or _bad_b[k] != 0:
			continue
		var b := benches[k]
		if (b.x - center.x) * (b.x - center.x) + (b.z - center.z) * (b.z - center.z) > r2:
			continue
		var slot: int = crowd.claim_slot(center)
		if slot < 0:
			break
		crowd.pin_sitter(slot, b.x, b.z, 1 if b.y > 0.0 else -1)
		_slot[k] = slot
		_until[k] = _clock + _rng.randf_range(SIT_STAY.x, SIT_STAY.y)
		active += 1
		sat += 1


## w123-critic: the solid street prop (city collider source: lamps, bins, kit props, planters ...) whose shape covers (x, z) within `r`, "" when none. Reads the source list,
## not the 56-body pool, so it works anywhere. `critic` (env W123C_OLD=1: off) keeps waiters and sitters out of props.
static var critic := OS.get_environment("W123C_OLD") != "1"


static func solid_at(x: float, z: float, r: float, skip := "") -> String:
	var city = Game.world
	if city == null or not is_instance_valid(city) or not city.has_method(&"prop_colliders"):
		return ""
	var pc = city.prop_colliders()
	if pc == null:
		return ""
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for id in (pc._grid.get(pc._key(x + dx * 8.0, z + dz * 8.0), PackedInt32Array()) as PackedInt32Array):
				var xf: Transform3D = pc._xf[id]
				if absf(xf.origin.y) > 1.5:
					continue
				var spec: Array = pc._spec_list[pc._spec[id]]
				if str(spec[3]) == skip:
					continue
				var sz: Vector3 = spec[1]
				var off: Vector3 = spec[2]
				var l: Vector3 = xf.basis.inverse() * (Vector3(x, xf.origin.y, z) - xf.origin) - off
				if int(spec[0]) == 0:
					if absf(l.x) < sz.x * 0.5 + r and absf(l.z) < sz.z * 0.5 + r:
						return str(spec[3])
				elif Vector2(l.x, l.z).length() < sz.x + r:
					return str(spec[3])
	return ""
