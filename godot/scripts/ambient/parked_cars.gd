class_name ParkedCars
extends RefCounted
## Parked cars of the world (owner round 6: "many cars outside and even houses, right now it is blank"): the cars that stand along the kerbs of every street, in the car parks and on the driveways of the
## villages and farms. They are decor with a real body: ONE MultiMesh (the near traffic's car, assets/shaders/prop_nearcar) for the cars in view, a hull in the TrafficField for every one of them (nothing is
## spawned or driven through them), a few pooled StaticBody3Ds under the hero (he and the real cars can not walk or drive through a parked car) and a swap for a REAL Vehicle when it matters: the
## hero reaches for the door (`promote_near`, so any parked car can be taken), a driven car comes close (`promote_around`: it can be pushed and hit like any real car) or a blast reaches it
## (`on_blast`: it is wrecked and burns like a real one).
## Placement is deterministic from the block (a hash of the street, side and slot), so the street looks the same every time: a bay every 6.4 m along both sides of every block between the junctions,
## filled by district and hour (a busy market street is full, the slums half, the fields a few pickups, the small hours add cars). Cells of 80 m (one block edge) are generated when the hero comes within
## the ring and dropped when he leaves it; at most CAP cars live at once. Sites of the outskirts add their own driveways (`SITE_SLOTS`).

const MB := preload("res://scripts/world/mesh_builder.gd")
const Districts := preload("res://scripts/world/city_districts.gd")

const CAP := 420
const DRAWN := 80
const RADII: Array[float] = [75.0, 100.0, 130.0]
const DRAW_R: Array[float] = [52.0, 60.0, 72.0]
const OCC_TIER: Array[float] = [0.55, 0.85, 1.0]
const VIEW_COS := 0.1
const VIEW_NEAR := 14.0
const ACCIDENT_CHANCE := 0.03          ## share of the block edges that hold an accident scene (not in the market quarter around the spawn)
const SLOT := 6.4                         ## bay pitch along the kerb (car 4.7 + gaps)
const END_MARGIN := 15.5                  ## clear of the junction on both ends
const BODIES := 22                        ## pooled static bodies
const BODY_R := 26.0                      ## cars within this of the hero get a body
const ZONE_OCC: Array[float] = [0.66, 0.5, 0.58, 0.44, 0.34, 0.5, 0.3, 0.4]     ## by CityDistricts zone: market, foundry, slums, towers, docks, terraces, fields, spires
const NO_KINDS: Array[int] = [8, 9, 10]                                         ## no bus, patrol car or ambulance parks at a kerb (they are traffic)

## Driveways of the outskirts sites: site kind -> [local x, local z, local heading (radians), kind index into NearTraffic.KINDS (-1 = any pickup / SUV / sedan)]. The frame is the site's own (see
## OutskirtsSites.to_world); the village street runs along z with houses at |x| >= 11, so a car stands at x = +-6.5 on the verge of the street. Slots round props (the well, the stalls, the towers) are left out.
const SITE_SLOTS := {
	&"village": [[-6.6, -46.0, 1.57, -1], [6.6, -46.0, -1.57, 6], [-6.6, -28.0, 1.57, 2], [6.6, -28.0, -1.57, -1], [-6.6, -9.0, 1.57, 6], [6.6, -8.0, -1.57, -1], [-6.6, 24.0, 1.57, 0], [6.6, 30.0, -1.57, 2],
		[-6.6, 44.0, 1.57, -1], [6.6, 46.0, -1.57, 6], [-6.6, 60.0, 1.57, 1], [6.6, 62.0, -1.57, -1]],
	&"farm": [[2.0, 10.0, 0.3, 6], [-8.0, 8.0, -0.4, 2], [26.0, -10.0, 1.2, -1], [30.0, 6.0, 1.9, 7]],
	&"cabins": [[-8.0, 6.0, 0.2, 2], [10.0, 4.0, -0.5, 6], [0.0, 16.0, 3.1, -1]],
	&"observatory": [[-14.0, 6.0, 1.57, 2], [-14.0, 12.5, 1.57, -1]],
	&"tower": [[-9.0, 8.0, 0.3, 2], [8.0, 10.0, -0.3, 6]],
	&"mine": [[-10.0, 6.0, 0.4, 6], [-14.0, 12.0, 0.8, 7]],
}

static var instance: ParkedCars

var drawn := 0                            ## kerb cars written into the shared MultiMesh this frame
var host: Node3D                          ## the node the static bodies live under (the ambient city)
var quality := 1
var radius := 100.0
var density := 1.0
var enabled := true                       ## false (tests that want a bare street): no cars are generated and the ones that stand are removed
var promoted := 0
var destroyed := 0
var generated := 0

var _alive := PackedByteArray()           ## 0 free, 1 parked, 2 taken by a real vehicle / wrecked
var _x := PackedFloat32Array()
var _z := PackedFloat32Array()
var _yaw := PackedFloat32Array()
var _kind := PackedByteArray()
var _paint := PackedByteArray()
var _cell := PackedInt32Array()           ## cell key of every car (a cell is freed as a whole)
var _n := 0                               ## high-water mark of used slots
var _cells := {}                          ## cell key -> true (generated)
var _site_cells := {}                     ## site index -> true
var _buf := PackedFloat32Array()
var _nw := 0
var _cam_ok := false
var _cam_fwd := Vector2.ZERO
var _cam_pos := Vector2.ZERO
var _hero := Vector3.INF
var _clock := 0.0
var _cell_t := 0.0
var _body_t := 0.0
var _bodies: Array[StaticBody3D] = []
var _body_of := PackedInt32Array()        ## body -> car index (-1 free)
var _rng := RandomNumberGenerator.new()
var _hooked := false


func build(light_map: Texture2D, host_node: Node3D) -> void:
	instance = self
	host = host_node
	_buf = MB.new_buffer(DRAWN, false, true)                 # the drawn cars are written into the near traffic's MultiMesh (NearTraffic.append_cars): no draw call of its own
	_ensure_bodies()
	for a: PackedFloat32Array in [_x, _z, _yaw]:
		a.resize(CAP)
	for a: PackedByteArray in [_alive, _kind, _paint]:
		a.resize(CAP)
	_cell.resize(CAP)
	_wreck.resize(CAP)
	_body_of.resize(BODIES)
	_body_of.fill(-1)
	set_tier(quality)


func set_tier(level: int, dens := 1.0) -> void:
	quality = clampi(level, 0, 2)
	density = dens
	radius = RADII[quality]
	if quality == 0 and LowPlus.on():
		radius *= 0.8
	_cells_reset()


func reset() -> void:
	_cells_reset()


func _cells_reset() -> void:
	for i in CAP:
		_alive[i] = 0
	TrafficField.clear_source(TrafficField.PARKED)
	_cells.clear()
	_site_cells.clear()
	_n = 0
	_cell_t = 0.0
	_free_bodies()
	_nw = 0


func alive_count() -> int:
	var c := 0
	for i in _n:
		if _alive[i] == 1:
			c += 1
	return c


func car_position(i: int) -> Vector3:
	return Vector3(_x[i], 0.0, _z[i])


func car_alive(i: int) -> bool:
	return _alive[i] == 1


func car_kind(i: int) -> StringName:
	return NearTraffic.KINDS[_kind[i]]


func car_yaw(i: int) -> float:
	return _yaw[i]


func cell_count() -> int:
	return _cells.size() + _site_cells.size()


# --- generation ---------------------------------------------------------------------------------------------------------------------------

static func _hash(a: int, b: int, c: int, d: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791) ^ (d * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0


func _alloc() -> int:
	for i in CAP:
		if _alive[i] == 0:
			if i >= _n:
				_n = i + 1
			return i
	return -1


## Adds a parked car and returns its index, -1 when the spot is taken (another vehicle's hull, the flooded quarter) or the pool is full.
func _add(x: float, z: float, yaw: float, kind: int, paint: int, cell: int) -> int:
	var hl: float = NearTraffic.KIND_HALF[kind]
	var hw: float = NearTraffic.KIND_HW[kind]
	var fx := -sin(yaw)
	var fz := -cos(yaw)
	if not TrafficField.clear(x, z, fx, fz, hl, hw, 0.35):
		return -1
	if FloodZone.contains(x, z, -2.0):
		return -1
	var i := _alloc()
	if i < 0:
		return -1
	_alive[i] = 1
	_wreck[i] = 0
	_x[i] = x
	_z[i] = z
	_yaw[i] = yaw
	_kind[i] = kind
	_paint[i] = paint
	_cell[i] = cell
	TrafficField.put(TrafficField.PARKED, i, x, z, fx, fz, hl, hw, 0.0, TrafficField.F_STATIC)
	generated += 1
	return i


func _cell_key(i: int, j: int) -> int:
	return (i + 64) * 1000 + (j + 64)


## One block edge cell (i, j): the bays along the road j between junction i and i + 1 (axis 0) and along road i between junction j and j + 1 (axis 1), on both sides.
func _gen_cell(i: int, j: int) -> void:
	var key := _cell_key(i, j)
	_cells[key] = true
	if i < 0 or j < 0 or i >= CityLayout.N or j >= CityLayout.N:
		return
	var night := clampf(DayNight.night_now, 0.0, 1.0)
	var tier := OCC_TIER[quality] * clampf(density, 0.5, 1.3)
	if _hash(i, j, 91, 3) < ACCIDENT_CHANCE and Districts.zone_at(CityLayout.road_center(i) + 40.0, CityLayout.road_center(j) + 40.0) != 0:
		_gen_accident(i, j, key)                              # first: the kerb cars of the cell fill the bays that are left (every car checks the hulls already there)
	for axis in 2:
		var road := j if axis == 0 else i                     # the road the bays line
		var seg := i if axis == 0 else j                      # the block along it
		var c := CityLayout.road_center(road)
		var u0 := CityLayout.road_center(seg) + END_MARGIN
		var u1 := CityLayout.road_center(seg + 1) - END_MARGIN
		var slots := int((u1 - u0) / SLOT)
		for side: int in [-1, 1]:
			var dir: int = side if axis == 0 else -side              # the direction of the lane next to this kerb (right-hand traffic): the car parks nose that way
			var heading := VehicleSpecs.heading_for(axis, dir)
			for n in slots:
				var r := _hash(road * 31 + axis, seg * 17 + side, n, 7)
				var u := u0 + (float(n) + 0.5) * SLOT + (_hash(road, seg, n * 5 + side, 11) - 0.5) * 0.7
				var across := c + float(side) * (VehicleSpecs.BAY + (_hash(road, seg, n, 13) - 0.5) * 0.35)
				var x := u if axis == 0 else across
				var z := across if axis == 0 else u
				var zone := Districts.zone_at(x, z)
				var occ := ZONE_OCC[zone] * tier * (1.0 + 0.18 * night)
				if r > occ:
					continue
				var kind := NearTraffic.pick_kind(zone, night, _hash(road, seg * 7 + side, n, 19))
				if kind in NO_KINDS:
					kind = 0
				_add(x, z, heading + (_hash(road, seg, n, 23) - 0.5) * 0.06, kind, int(_hash(road, seg, n, 29) * 8.0) % 8, key)


## An accident scene on the kerb side of a block edge: two or three cars thrown across the bay at odd angles (dark, burnt paint, smoking), a patrol car with its roof flashing and an ambulance beside
## them. They stand on the bay line (a car at 8.6 m turned 40 degrees reaches 6.4 m: the lane at 5 m stays free, traffic drives by). Rare (3 % of the block edges) and deterministic.
func _gen_accident(i: int, j: int, key: int) -> void:
	var axis := int(_hash(i, j, 41, 1) * 2.0) % 2
	var side: int = 1 if _hash(i, j, 43, 1) > 0.5 else -1
	var road := j if axis == 0 else i
	var seg := i if axis == 0 else j
	var c := CityLayout.road_center(road)
	var u := CityLayout.road_center(seg) + 40.0 + _hash(i, j, 47, 1) * 8.0
	var dir: int = side if axis == 0 else -side
	var heading := VehicleSpecs.heading_for(axis, dir)
	var made := 0
	for n in 3:
		var du := float(n) * 6.6 + (_hash(i, j, 50 + n, 1) - 0.5) * 1.4
		var x := u + du
		var across := c + float(side) * (8.5 + _hash(i, j, 60 + n, 1) * 0.6)
		var px := x if axis == 0 else across
		var pz := across if axis == 0 else x
		var yaw := heading + (_hash(i, j, 70 + n, 1) - 0.5) * 1.5
		var kind: int = [0, 2, 6][int(_hash(i, j, 80 + n, 1) * 3.0) % 3]
		var k := _add(px, pz, yaw, kind, 7, key)
		if k >= 0:
			_wreck[k] = 1
			made += 1
	var ex := u + 24.0
	var ax := ex if axis == 0 else c + float(side) * 8.5
	var az := c + float(side) * 8.5 if axis == 0 else ex
	_add(ax, az, heading, 9, 0, key)                       # the patrol car (its roof flashes: the shader's siren variant)
	var bx := ex + 7.0
	_add(bx if axis == 0 else c + float(side) * 8.5, c + float(side) * 8.5 if axis == 0 else bx, heading + 0.12, 10, 0, key)      # the ambulance
	if made > 0:
		accidents += 1


## The cars broken down or parked on the verge of the highways around the hero (RoadLanes): a few hundred metres apart, deterministic per road sample, 7 m from the centre line on the right of the direction
## of travel they were driving (or the other side), nose along the road with a small angle.
func _gen_roadside(c: Vector3) -> void:
	RoadLanes.ensure()
	if RoadLanes.roads.is_empty():
		return
	for gx in range(int(floor((c.x - radius) / RoadLanes.CELL)), int(floor((c.x + radius) / RoadLanes.CELL)) + 1):
		for gz in range(int(floor((c.z - radius) / RoadLanes.CELL)), int(floor((c.z + radius) / RoadLanes.CELL)) + 1):
			var key := 800000 + (gx + 100) * 200 + (gz + 100)
			if _cells.has(key):
				continue
			_cells[key] = true
			var arr = RoadLanes._cells.get(RoadLanes._key(gx, gz))
			if arr == null:
				continue
			for code: int in (arr as PackedInt32Array):
				var ri := code / 100000
				var si := code % 100000
				if si % 36 != 7:
					continue
				var rd: Dictionary = RoadLanes.roads[ri]
				if String(rd["kind"]) != "highway":
					continue
				var r := _hash(ri, si, 5, 77)
				if r > 0.55 * clampf(density, 0.4, 1.4):
					continue
				var cum: PackedFloat32Array = rd["cum"]
				var sm := RoadLanes.sample(ri, cum[si])
				if absf(sm[0]) < CityLayout.HALF + 20.0 and absf(sm[1]) < CityLayout.HALF + 20.0:
					continue
				var tg := Vector2(sm[2], sm[3])
				var side := 1.0 if _hash(ri, si, 6, 77) > 0.5 else -1.0
				var right := Vector2(-tg.y, tg.x)
				var pos := Vector2(sm[0], sm[1]) + right * side * (float(rd["lane"]) + 4.6)
				var yaw := atan2(-tg.x * side, -tg.y * side) + (_hash(ri, si, 7, 77) - 0.5) * 0.3
				var kind: int = [0, 2, 6, 7, 3, 1][int(_hash(ri, si, 8, 77) * 6.0) % 6]
				var k := _add(pos.x, pos.y, yaw, kind, int(_hash(ri, si, 9, 77) * 8.0) % 8, key)
				if k >= 0:
					_y_site[k] = sm[4]
					roadside += 1


## The driveway cars of a site (SITE_SLOTS), generated once while the hero is near it.
func _gen_site(si: int) -> void:
	_site_cells[si] = true
	var site: Dictionary = OutskirtsSites.list[si]
	var kind_name: StringName = StringName(site["kind"])
	if not SITE_SLOTS.has(kind_name):
		return
	var slots: Array = SITE_SLOTS[kind_name]
	var key := 900000 + si
	var rides: Array[Vector3] = []                          # the roster rides of the site (VehicleSpawns) wait on their own driveway spot: no decor car stands on one
	for pt in OutskirtsSites.vehicle_points():
		rides.append(pt["pos"])
	for n in slots.size():
		var sl: Array = slots[n]
		var w := OutskirtsSites.to_world(site, Vector3(float(sl[0]), 0.0, float(sl[1])))
		var on_ride := false
		for rp in rides:
			if Vector2(rp.x - w.x, rp.z - w.z).length() < 7.0:
				on_ride = true
				break
		if on_ride:
			continue
		var kind: int = int(sl[3])
		if kind < 0:
			kind = [0, 2, 6, 1, 6][int(_hash(si, n, 3, 5) * 5.0) % 5]
		var yaw := float(site["yaw"]) + float(sl[2]) + (_hash(si, n, 9, 3) - 0.5) * 0.08
		var i := _add(w.x, w.z, yaw, kind, int(_hash(si, n, 1, 8) * 8.0) % 8, key)
		if i >= 0:
			_y_site[i] = TerrainHeight.height_at(w.x, w.z)           # outside the city the ground is the terrain


var _y_site := {}                         ## car index -> ground height (cars of the outskirts)
var _wreck := PackedByteArray()           ## 1: a burnt-out car of an accident scene (dark paint, smokes)
var accidents := 0                        ## accident scenes generated so far (tests)
var roadside := 0                         ## cars parked on the verge of a highway so far (tests)
var _smoke_t := 0.0


func _free_cell(key: int) -> void:
	for i in _n:
		if _alive[i] != 0 and _cell[i] == key:
			_alive[i] = 0
			TrafficField.remove(TrafficField.PARKED, i)
			_y_site.erase(i)
	_cells.erase(key)
	_site_cells.erase(key - 900000)


# --- stepping -----------------------------------------------------------------------------------------------------------------------------

func step(delta: float, center: Vector3) -> void:
	if not enabled:
		if _n > 0:
			_cells_reset()
		return
	_clock += delta
	_hero = center
	_cam_ok = false
	if is_instance_valid(Game.camera):
		var cf := -Game.camera.global_transform.basis.z
		var cp3 := Game.camera.global_position
		var fl := Vector2(cf.x, cf.z)
		if fl.length_squared() > 0.04:
			_cam_ok = true
			_cam_fwd = fl.normalized()
			_cam_pos = Vector2(cp3.x, cp3.z)
	if not _hooked:
		_hooked = true
		if not Game.exploded.is_connected(on_blast):
			Game.exploded.connect(on_blast)
	_cell_t -= delta
	if _cell_t <= 0.0:
		_cell_t = 0.4
		_window(center)
	_smoke_t -= delta
	if _smoke_t <= 0.0:
		_smoke_t = 0.7
		_smoke(center)
	_body_t -= delta
	if _body_t <= 0.0:
		_body_t = 0.2
		_assign_bodies(center)
	_write_all()


## A thin grey wisp over the burnt-out cars of an accident within 55 m of the hero (a few pooled particles per second, none beyond).
func _smoke(c: Vector3) -> void:
	var n := 0
	for i in _n:
		if _alive[i] == 1 and _wreck[i] == 1:
			var dx := _x[i] - c.x
			var dz := _z[i] - c.z
			if dx * dx + dz * dz < 55.0 * 55.0:
				FX.burst(Vector3(_x[i], float(_y_site.get(i, 0.0)) + 1.2, _z[i]), Color(0.34, 0.34, 0.36), 2, 1.4, 1.6, -0.6, 1.4)
				n += 1
				if n >= 4:
					return


## Generate the cells inside the ring, free the ones that left it.
func _window(c: Vector3) -> void:
	var inside := absf(c.x) < CityLayout.HALF + radius and absf(c.z) < CityLayout.HALF + radius
	if inside:
		var pi := int(floor((c.x + CityLayout.HALF) / CityLayout.PITCH))
		var pj := int(floor((c.z + CityLayout.HALF) / CityLayout.PITCH))
		var span := int(ceil(radius / CityLayout.PITCH)) + 1
		var made := 0
		for di in range(-span, span + 1):
			for dj in range(-span, span + 1):
				var i := pi + di
				var j := pj + dj
				var key := _cell_key(i, j)
				if _cells.has(key):
					continue
				var cx := CityLayout.road_center(i) + CityLayout.PITCH * 0.5
				var cz := CityLayout.road_center(j) + CityLayout.PITCH * 0.5
				if Vector2(cx - c.x, cz - c.z).length() > radius:
					continue
				_gen_cell(i, j)
				made += 1
				if made >= 3:
					break                                           # a few cells per pass: the ring fills in over a second, never in one frame
			if made >= 3:
				break
	if not inside or absf(c.x) > CityLayout.HALF - 80.0 or absf(c.z) > CityLayout.HALF - 80.0:
		_gen_roadside(c)                                          # the highways: a verge car every few hundred metres
	# outskirts sites
	if OutskirtsSites.built:
		for si in OutskirtsSites.list.size():
			var sp: Vector3 = OutskirtsSites.list[si]["pos"]
			var d := Vector2(sp.x - c.x, sp.z - c.z).length()
			if d < radius + 80.0 and not _site_cells.has(si):
				_gen_site(si)
			elif d > radius + 160.0 and _site_cells.has(si):
				_free_cell(900000 + si)
	var drop: Array[int] = []
	for key: int in _cells:
		if key >= 800000:                                          # a highway cell: dropped when the hero is far from it
			var rx := ((key - 800000) / 200 - 100) * RoadLanes.CELL + RoadLanes.CELL * 0.5
			var rz := ((key - 800000) % 200 - 100) * RoadLanes.CELL + RoadLanes.CELL * 0.5
			if Vector2(rx - c.x, rz - c.z).length() > radius + RoadLanes.CELL * 2.0:
				drop.append(key)
			continue
		var i2 := int(key / 1000) - 64
		var j2 := key % 1000 - 64
		var cx2 := CityLayout.road_center(i2) + CityLayout.PITCH * 0.5
		var cz2 := CityLayout.road_center(j2) + CityLayout.PITCH * 0.5
		if Vector2(cx2 - c.x, cz2 - c.z).length() > radius + CityLayout.PITCH * 1.5:
			drop.append(key)
	for key in drop:
		_free_cell(key)


# --- bodies ---------------------------------------------------------------------------------------------------------------------------------

func _ensure_bodies() -> void:
	if not _bodies.is_empty() or host == null:
		return
	for k in BODIES:
		var b := StaticBody3D.new()
		b.name = "ParkedBody%d" % k
		b.collision_layer = Game.L_WORLD
		b.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		cs.disabled = true
		b.add_child(cs)
		host.add_child(b)
		_bodies.append(b)


func _free_bodies() -> void:
	for k in _body_of.size():
		_body_of[k] = -1
	for b in _bodies:
		(b.get_child(0) as CollisionShape3D).disabled = true


func _assign_bodies(c: Vector3) -> void:
	_ensure_bodies()
	if _bodies.is_empty():
		return
	# the nearest BODIES cars within BODY_R of the hero (or of the car he drives: he is in it, so the same point)
	var best_i: Array[int] = []
	var best_d: Array[float] = []
	for i in _n:
		if _alive[i] != 1:
			continue
		var d2 := (_x[i] - c.x) * (_x[i] - c.x) + (_z[i] - c.z) * (_z[i] - c.z)
		if d2 > BODY_R * BODY_R:
			continue
		var pos := best_d.size()
		while pos > 0 and best_d[pos - 1] > d2:
			pos -= 1
		if pos < BODIES:
			best_d.insert(pos, d2)
			best_i.insert(pos, i)
			if best_d.size() > BODIES:
				best_d.pop_back()
				best_i.pop_back()
	for k in BODIES:
		var b := _bodies[k]
		var cs := b.get_child(0) as CollisionShape3D
		if k >= best_i.size():
			cs.disabled = true
			_body_of[k] = -1
			continue
		var i := best_i[k]
		if _body_of[k] != i:
			var spec: Dictionary = VehicleSpecs.SPECS[NearTraffic.KINDS[_kind[i]]]
			var box := cs.shape as BoxShape3D
			var h := float(spec["hgt"]) * 0.8
			box.size = Vector3(float(spec["wid"]) - 0.1, h, float(spec["len"]) - 0.2)
			var gy: float = float(_y_site.get(i, 0.0))
			b.global_transform = Transform3D(Basis(Vector3.UP, _yaw[i]), Vector3(_x[i], gy + h * 0.5 + 0.12, _z[i]))
			_body_of[k] = i
		cs.disabled = false


# --- drawing -------------------------------------------------------------------------------------------------------------------------------

func _write_all() -> void:
	_nw = 0
	var dr := DRAW_R[quality]
	for i in _n:
		if _alive[i] != 1:
			continue
		var dx := _x[i] - _cam_pos.x
		var dz := _z[i] - _cam_pos.y
		if _cam_ok:
			var d2 := dx * dx + dz * dz
			if d2 > dr * dr:
				continue
			if d2 > VIEW_NEAR * VIEW_NEAR and (dx * _cam_fwd.x + dz * _cam_fwd.y) < VIEW_COS * sqrt(d2):
				continue
		if _nw >= DRAWN:
			break
		var o := _nw * 16
		_nw += 1
		var y := _yaw[i]
		var cs := cos(y)
		var sn := sin(y)
		var gy: float = float(_y_site.get(i, 0.0))
		_buf[o] = cs
		_buf[o + 1] = 0.0
		_buf[o + 2] = sn
		_buf[o + 3] = _x[i]
		_buf[o + 4] = 0.0
		_buf[o + 5] = 1.0
		_buf[o + 6] = 0.0
		_buf[o + 7] = gy
		_buf[o + 8] = -sn
		_buf[o + 9] = 0.0
		_buf[o + 10] = cs
		_buf[o + 11] = _z[i]
		_buf[o + 12] = float(_paint[i])
		_buf[o + 13] = float(_kind[i])
		_buf[o + 14] = 0.0
		_buf[o + 15] = 0.12
	if NearTraffic.instance != null:
		drawn = NearTraffic.instance.append_cars(_buf, _nw)


# --- the swap for a real vehicle ---------------------------------------------------------------------------------------------------------

func car_near(pos: Vector3, reach: float) -> int:
	var best := -1
	var best_d := INF
	for i in _n:
		if _alive[i] != 1:
			continue
		var q := Vector2(pos.x - _x[i], pos.z - _z[i])
		var f := Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
		var along := absf(q.dot(f)) - NearTraffic.KIND_HALF[_kind[i]]
		var lat := absf(q.x * f.y - q.y * f.x) - NearTraffic.KIND_HW[_kind[i]]
		var d := Vector2(maxf(along, 0.0), maxf(lat, 0.0)).length()
		if d <= reach and d < best_d:
			best_d = d
			best = i
	return best


## Swap parked car `i` for a real parked Vehicle on the same spot (null when the manager has no slot): the decor car and its hull go, the body is freed.
func promote(i: int) -> Vehicle:
	var mgr := Game.vehicles as VehicleManager
	if mgr == null or _alive[i] != 1:
		return null
	var gy: float = float(_y_site.get(i, 0.0))
	TrafficField.remove(TrafficField.PARKED, i)
	var kind := NearTraffic.KINDS[_kind[i]]
	var v := mgr.spawn_parked(kind, Vector3(_x[i], gy, _z[i]), _yaw[i])
	if v == null:
		var f := Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
		TrafficField.put(TrafficField.PARKED, i, _x[i], _z[i], f.x, f.y, NearTraffic.KIND_HALF[_kind[i]], NearTraffic.KIND_HW[_kind[i]], 0.0, TrafficField.F_STATIC)
		return null
	_alive[i] = 2
	for k in _body_of.size():
		if _body_of[k] == i:
			(_bodies[k].get_child(0) as CollisionShape3D).disabled = true
			_body_of[k] = -1
	if v.visual != null and _paint[i] < VehicleSpecs.COLORS.size():
		v.visual.set_paint(VehicleSpecs.COLORS[_paint[i]])
		v.paint_i = _paint[i]
	promoted += 1
	return v


func promote_near(pos: Vector3, reach: float) -> Vehicle:
	var i := car_near(pos, reach)
	return null if i < 0 else promote(i)


## Cars within `r` of `pos` (a driven car coming closer) become real so a crash is a real crash. At most `max_n` at a time.
func promote_around(pos: Vector3, r: float, max_n := 2) -> int:
	var n := 0
	for i in _n:
		if n >= max_n:
			break
		if _alive[i] == 1 and (Vector2(_x[i], _z[i]) - Vector2(pos.x, pos.z)).length() < r:
			if promote(i) != null:
				n += 1
			else:
				break
	return n


## The kerb cars whose hull touches (or comes within `margin` metres of) the oriented box (centre `pos`, forward `fwd` on the ground, half length `hl`, half width `hw`) of a real vehicle become real
## ones, at ANY speed: a car that creeps or stands against a kerb car (a stuck bot, a police car on a turn) used to sit inside the decor hull for as long as it stayed, because the speed gates of
## `promote_around` skip it. Once real, the manager's own collision response pushes the two apart. Returns how many were swapped (at most `max_n`).
func promote_touching(pos: Vector3, fwd: Vector2, hl: float, hw: float, margin := 0.12, max_n := 2) -> int:
	var n := 0
	for i in _n:
		if n >= max_n:
			break
		if _alive[i] != 1:
			continue
		var dx := _x[i] - pos.x
		var dz := _z[i] - pos.z
		if dx * dx + dz * dz > 49.0:
			continue
		var f := Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
		var depth := TrafficField.obb_depth(pos.x, pos.z, fwd.x, fwd.y, hl, hw, _x[i], _z[i], f.x, f.y, NearTraffic.KIND_HALF[_kind[i]], NearTraffic.KIND_HW[_kind[i]])
		if depth > -margin:
			if promote(i) != null:
				n += 1
			else:
				break
	return n


## A real car that is inside a kerb car's hull and could not be swapped for a real one (no slot, no room) is shoved out of it: the decor car is a wall. The depth goes back along the line of the two
## centres, the velocity into the wall is taken off (a real impulse against an immovable body, a crash when it was fast). Returns the number of kerb cars it touched.
func push_out_vehicle(v: Vehicle) -> int:
	var hits := 0
	var vp := Vector2(v.global_position.x, v.global_position.z)
	var vf3 := v.forward()
	var vf := Vector2(vf3.x, vf3.z)
	var vhl := float(v.spec["len"]) * 0.5
	var vhw := float(v.spec["wid"]) * 0.5 - 0.1
	for i in _n:
		if _alive[i] != 1:
			continue
		var dx := _x[i] - vp.x
		var dz := _z[i] - vp.y
		if dx * dx + dz * dz > 49.0:
			continue
		var f := Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
		var depth := TrafficField.obb_depth(vp.x, vp.y, vf.x, vf.y, vhl, vhw, _x[i], _z[i], f.x, f.y, NearTraffic.KIND_HALF[_kind[i]], NearTraffic.KIND_HW[_kind[i]])
		if depth <= 0.02:
			continue
		hits += 1
		var n2 := vp - Vector2(_x[i], _z[i])
		if n2.length_squared() < 1e-6:
			n2 = -vf
		n2 = n2.normalized()                                              # from the kerb car towards the vehicle
		var n := Vector3(n2.x, 0.0, n2.y)
		var at := Vector3((vp.x + _x[i]) * 0.5, 0.0, (vp.y + _z[i]) * 0.5)
		v.global_position += n * (depth + 0.03)
		vp += n2 * (depth + 0.03)
		var vrel := v.point_velocity(at).dot(n)
		if vrel < 0.0:
			var inv := v.inverse_mass_at(n, at)
			if inv > 0.0:
				v.apply_impulse(n * (-(1.0 + VehicleSpecs.RESTITUTION * 0.5) * vrel / inv), at)
			if -vrel > VehicleSpecs.CAR_HIT_SPEED:
				v.crash(-vrel, at, n, INF)
	return hits


## A blast (Game.exploded): the parked cars within reach are swapped for real ones that take the blast and burn. Cars the manager has no slot for are removed as burnt-out (the blast already shook the street).
func on_blast(pos: Vector3, blast_r: float) -> void:
	var mgr := Game.vehicles as VehicleManager
	for i in _n:
		if _alive[i] != 1:
			continue
		var d := Vector2(_x[i] - pos.x, _z[i] - pos.z).length()
		if d > blast_r + 2.4:
			continue
		var v: Vehicle = null
		if mgr != null:
			v = promote(i)
			if v == null and mgr.list.size() >= mgr.cap() and mgr._free_slot():
				v = promote(i)
		if v != null:
			v.damage(maxf(160.0 * (1.0 - d / (blast_r + 2.4)), 40.0))
			destroyed += 1
		else:
			_alive[i] = 2
			TrafficField.remove(TrafficField.PARKED, i)
			destroyed += 1
