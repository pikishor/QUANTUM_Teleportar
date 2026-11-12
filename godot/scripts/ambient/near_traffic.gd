class_name NearTraffic
extends RefCounted
## Near traffic of the living city (owner round 3: "the street is empty, no cars"): ONE MultiMesh of small lit cars (assets/shaders/prop_nearcar.gdshader, about 150 triangles each) that drive
## the lanes of the road grid in a ring around the hero, between the real VehicleManager cars (a few, expensive) and the far traffic lights (zero CPU, 46 m and beyond).
## They follow the same rules as the real AI cars (right-hand lanes on LANE, junction lights, cruise 9-14 m/s, stop for what is ahead: the hero, a real car, another car, a person on a
## zebra) and turn at junctions on a curve. The hero can still take any of them: `promote_near` swaps the car for a real Vehicle at the same place and speed (VehicleManager.reach_car,
## and any of them within a few metres of the car the hero drives, so the crash is a real one). One draw call, no node per car, nothing allocated while playing.

const SHADER := preload("res://assets/shaders/prop_nearcar.gdshader")
const MB := preload("res://scripts/world/mesh_builder.gd")
const Districts := preload("res://scripts/world/city_districts.gd")

const BUILT := 124
const SHARED_EXTRA := 120                ## more instances in the same MultiMesh after the near cars: the road cars (RoadTraffic.DRAWN) and the parked cars (ParkedCars.DRAWN) ride in this draw call (the phone's draw budget)
const SHARED := BUILT + SHARED_EXTRA
const COUNTS: Array[int] = [72, 88, 100]
const RADII: Array[float] = [72.0, 84.0, 96.0]
const MIN_SPAWN := 16.0                  ## first fill: anywhere in the ring but not on top of the hero
const AVENUE := 8 + CityLayout.SHIFT      ## road index of the market avenue (z = 0)
const AVENUE_GREEN := 12.0
const CORE_SHARE := 0.8
const CORE_R := 42.0
const RESPAWN_MIN := 0.55                ## later: this share of the radius away, so nobody appears in front of the hero
## The archetypes of the traffic (round 6: variety). Index = the body variant of the shader (assets/shaders/prop_nearcar.gdshader SHAPE): commuters (sedan, compact, SUV), taxis, delivery vans and box trucks,
## pickups, city buses, police patrols and ambulances (their roofs flash), speeders (the sport car). The names are VehicleSpecs kinds, so a promoted car is the real vehicle of that kind.
const KINDS: Array[StringName] = [&"sedan", &"compact", &"suv", &"van", &"taxi", &"sport", &"pickup", &"truck", &"bus", &"interceptor", &"ambulance", &"delivery"]
const KIND_SPEED: Array[float] = [1.0, 1.0, 0.95, 0.86, 1.04, 1.28, 0.95, 0.88, 0.9, 1.12, 1.18, 0.92]
const KIND_HALF: Array[float] = [2.25, 1.9, 2.4, 2.7, 2.25, 2.15, 2.55, 3.2, 4.75, 2.35, 2.7, 2.9]    ## half the car length, for gaps
const KIND_HW: Array[float] = [0.93, 0.88, 0.99, 1.02, 0.93, 0.98, 0.98, 1.1, 1.25, 0.97, 1.02, 1.05]    ## half the car width (the mesh is 1.84 wide, scaled by the variant): the hull the TrafficField holds
const KIND_VARIANT: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
const KIND_LAMP: Array[float] = [0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.5, 0.5, 1.0, 1.0, 0.5]       ## the far lamp flag (RoadTraffic): 0.5 = tall (truck, bus, van), 1 = emergency strobes
## The share of every archetype by place: the city grid by district zone (CityDistricts.zone_at, 8 zones), the highways and the dirt tracks. Each row sums to 1.
##                                      sedan compact suv   van   taxi  sport pickup truck bus   police ambul. deliv.
const KIND_MIX: Array[float] =        [0.25, 0.17, 0.13, 0.06, 0.13, 0.08, 0.05, 0.02, 0.025, 0.03, 0.015, 0.04]
const KIND_MIX_HIGHWAY: Array[float] = [0.30, 0.08, 0.15, 0.06, 0.02, 0.08, 0.10, 0.08, 0.03, 0.02, 0.005, 0.075]
const KIND_MIX_TRACK: Array[float] =   [0.14, 0.04, 0.26, 0.08, 0.00, 0.02, 0.30, 0.10, 0.00, 0.02, 0.00, 0.04]
const ZONE_BIAS := {                                                                    ## multipliers by zone for the kinds that change with the district: [taxi, truck, delivery, bus, sport, pickup, compact]
	0: [1.5, 0.4, 1.2, 1.4, 1.2, 0.4, 1.0],      # NEON MARKET: taxis, buses, delivery vans
	1: [0.5, 2.2, 1.4, 0.6, 0.6, 1.6, 0.8],      # FOUNDRY ROW: trucks and vans
	2: [0.5, 0.8, 0.8, 0.8, 0.5, 1.2, 1.7],      # RAIN SLUMS: small old cars
	3: [1.6, 0.2, 0.7, 1.0, 2.0, 0.2, 0.6],      # GLASS TOWERS: taxis and fast cars
	4: [0.4, 3.0, 1.6, 0.4, 0.5, 1.8, 0.6],      # DOCKYARDS: lorries
	5: [1.0, 0.8, 1.5, 1.6, 0.8, 0.8, 1.0],      # AMBER TERRACES
	6: [0.4, 1.2, 0.8, 0.6, 0.4, 2.2, 1.3],      # GROW FIELDS: pickups
	7: [1.4, 0.3, 0.8, 1.2, 1.8, 0.3, 0.7],      # OUTER SPIRES
}
const EDGE := CityLayout.HALF - 14.0
const ACCEL := 4.0
const BRAKE := 7.0
const LOOK := 17.0                       ## obstacle look-ahead (m)
const SIDE_CAR := 2.3
const FAR_LOOK := 22.0                   ## other cars farther than this on either axis cannot be in the way
const SIDE_FOOT := 1.35                  ## a person within this of the car's centre line is in its way (the car is 0.95 each side, a person 0.4)
const STOP_GAP := 2.3
const STOP_LINE := 11.5                  ## m before the junction centre where a car waits for a red
const LIGHT_LOOK := 24.0
const TURN_CHANCE := 0.22
const TURN_R := 6.0                      ## the curve starts and ends this far from the crossing point of the two lanes
const TURN_LEN := 1.62 * TURN_R
const DECIDE_AT := 34.0
const HURT_CD := 1.4
const PANIC_TIME := 4.0
const PANIC_SPEED := 1.45
const GUN_HEAR := 45.0
const FRAME_STAGGER := 4                 ## the pedestrian list is refreshed once in this many frames
const SUBSTEP := 0.05                   ## a frame longer than this is run as several short steps (a slow phone, the audit at 4x): no car ever moves more than a third of a metre per look
const SPAWN_EVERY := 0.1                ## s between two spawn passes (at most 3 cars each)
const LOOK_FAR := 0.2                  ## ... and the cars beyond LOOK_NEAR metres of the hero
const LOOK_NEAR := 42.0
const LOOK_EVERY := 0.1                 ## seconds of game time between two looks of one car
const HARD_BRAKE := 11.0                 ## m/s2 when something is much closer than the planned stop (the car brakes as hard as a real one)
const OVERLAP_KILL := 0.55                ## seconds a near car may sit inside another hull before it is taken out of the ring
const TURN_PATIENCE := 1.2               ## s a car waits for a gap to turn before it drives straight on instead
const BOX_COMMIT := 10.0                 ## m from the junction centre: a car this close (it stopped at the line, 11.7 m, or is past it) is committed
const BOX_HALF := 8.5                    ## half size of the junction box a car does not enter while crossing traffic stands in it
const PEDS_MAX := 48
const SWERVE_CLEAR := 1.55               ## a car passes a person standing in its lane at least this far off (half the car 0.95 + a person 0.4 + a little)
const CAM_CLEAR := 2.7                   ## a car passes the game camera at least this far off when it can (it is 2 m above the road: a roof at the lens fills half the screen)
const CAM_KILL := 1.9                    ## a car whose body is this close to the lens (a hero hop onto the road, a camera swing) is taken out: its roof would fill the screen (frames of the life bot)
const SWERVE_MAX := 1.9                  ## drift towards the kerb
const SWERVE_LEFT := 3.0                 ## drift towards the middle of the road (the lane is 5 m from the centre line, so the car still keeps its side)
const DRAW_R: Array[float] = [42.0, 42.0, 58.0]    ## cars beyond this are not drawn (the far traffic layer covers 46 m and beyond; the triangles are what MED / HIGH budgets)
const VIEW_NEAR := 16.0                  ## cars this close are always drawn (the camera swings, shadows fall into the view)
const VIEW_COS := 0.2                    ## a car more than about 78 degrees off the camera's heading is not drawn
const SWERVE_RATE := 2.0                 ## m/s of sideways drift
const JAM_AFTER := 40.0                  ## seconds stuck behind cars with no light or person to explain it: an unseen car is removed
const JAM_FORCE := 70.0                  ## ... and a seen one too
const CAR_PAD := 0.3                     ## m of margin on each side of the corridor a car looks along
const GHOST_TIME := 3.5

static var instance: NearTraffic

var mm: MultiMesh
var material: ShaderMaterial
var count := 0
var enabled := true                      ## false (tests that want a bare street): no cars, whatever the tier and the hour ask for
var radius := 105.0
var quality := 1
var rng := RandomNumberGenerator.new()
var promoted := 0                        ## cars handed over to the VehicleManager so far (tests)
var honks := 0                           ## horns sounded so far (tests)
var hurt_total := 0                      ## times a car hurt the hero (tests)
var stops_light := 0                     ## cars that began braking for a red (tests)

var _alive := PackedByteArray()
var _axis := PackedByteArray()
var _dir := PackedFloat32Array()
var _line := PackedFloat32Array()
var _u := PackedFloat32Array()
var _spd := PackedFloat32Array()
var _cruise := PackedFloat32Array()
var _allow := PackedFloat32Array()       ## the speed the road ahead allows (set by the look-around)
var _kind := PackedByteArray()
var _paint := PackedByteArray()
var _brake := PackedFloat32Array()
var _panic := PackedFloat32Array()
var _stun := PackedFloat32Array()
var _hurt_cd := PackedFloat32Array()
var _shift := PackedFloat32Array()       ## sideways drift (m, along the car's right) round a person or the hero standing in its lane
var _shift_t := PackedFloat32Array()
var _jam := PackedFloat32Array()         ## seconds stuck behind a car with no light or person to explain it
var _ghost := PackedFloat32Array()       ## seconds left of driving through the cars ahead (the jam breaker)
var _ldt := 0.07                         ## seconds between two looks of one car
var _wait := PackedFloat32Array()        ## seconds stuck behind a person / the hero (for the horn)
var _age := PackedFloat32Array()
var _pos := PackedVector2Array()         ## world x, z
var _yaw := PackedFloat32Array()
var _tmode := PackedByteArray()          ## 0 straight, 1 a turn is decided, 2 on the curve
var _tdir := PackedFloat32Array()
var _tcross := PackedFloat32Array()      ## the lane-B coordinate along lane A's travel (where the two lanes cross)
var _tdone := PackedInt32Array()         ## the junction index already decided (-1 none)
var _tp := PackedFloat32Array()          ## curve parameter 0..1
var _tE := PackedVector2Array()
var _tI := PackedVector2Array()
var _tX := PackedVector2Array()
var _buf := PackedFloat32Array()
var _peds := PackedVector2Array()
var _n_peds := 0
var _obs := PackedFloat32Array()         ## sideways offsets of the obstacles one car is looking at (the drift solver)
var _obs_cam := PackedByteArray()
var _n_obs := 0
var _nw := 0                             ## cars written into the MultiMesh this step
var _total := 0                          ## instances of the MultiMesh drawn this frame: the near cars + what append_cars added (the road and the parked cars)
var _cam_ok := false
var _cam_fwd := Vector2.ZERO
var _cam_pos := Vector2.ZERO
var desync := true                       ## every junction has its own light phase (junction_offset); tests switch it off
var signal_clock_override := -1.0        ## tests: a fixed junction clock (>= 0)
var _frame := 0
var _clock := 0.0
var _hero := Vector3.INF
var _hero_foot := true
var _cam := Vector2(INF, INF)           ## the game camera behind the hero on foot: a car must not drive through the lens either
var _light_seen := PackedByteArray()
var _look_t := PackedFloat32Array()
var _twait := PackedFloat32Array()
var _why := PackedFloat32Array()          ## the last look: 4 numbers per car (light, box, car, person allowances), for the audit
var _ovl := PackedFloat32Array()
var _ovl_t := PackedFloat32Array()
var rej := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])   ## why a spawn attempt failed: no lane, junction, ring edge, spot taken, hull, queue ahead, car behind, ok (tests)
var _spawn_t := 0.0
var jam_breaks := 0                      ## cars removed from a jam that never cleared (tests, the audit)
var overlap_kills := 0                   ## near cars taken out of the ring because their hull stayed inside another vehicle (tests, the audit)


func build(light_map: Texture2D) -> void:
	instance = self
	rng.seed = 90211
	mm = MB.new_multimesh(car_mesh(), SHARED, false, true)
	_buf = MB.new_buffer(SHARED, false, true)
	for a: PackedFloat32Array in [_dir, _line, _u, _spd, _cruise, _allow, _brake, _panic, _stun, _hurt_cd, _shift, _shift_t, _jam, _ghost, _wait, _age, _yaw, _tdir, _tcross, _tp, _look_t, _twait, _ovl, _ovl_t]:
		a.resize(BUILT)
	for a: PackedByteArray in [_alive, _axis, _kind, _paint, _tmode, _light_seen]:
		a.resize(BUILT)
	_pos.resize(BUILT)
	_why.resize(BUILT * 4)
	_tE.resize(BUILT)
	_tI.resize(BUILT)
	_tX.resize(BUILT)
	_tdone.resize(BUILT)
	_tdone.fill(-1)
	_peds.resize(PEDS_MAX)
	_obs.resize(PEDS_MAX + 4)
	_obs_cam.resize(PEDS_MAX + 4)
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"light_map", light_map)
	mm.buffer = _buf
	set_tier(quality)


## The car body: lower hull, glass cabin, roof, four wheels, lamps (about 150 triangles). Nose is -Z, length 4.5 m, wheels at y 0.34. UV.x = surface tag, UV.y = wheel centre z.
static var _near_mesh: ArrayMesh

## The car every near car draws: the decimated Rgsdev sedan (assets/models/rv_near.glb, 445 triangles, one surface, tags in UV.x as below) when it exists, else the procedural box car
## (`procedural_car_mesh`, about 300 triangles). QT_RV_MODELS=0 puts the box car back (before captures).
static func car_mesh() -> ArrayMesh:
	if OS.get_environment("QT_RV_MODELS") != "0":
		if _near_mesh == null:
			var root := Game.load_model("cv2_near") if CarV2.enabled() else null         # round 6 (Cars v2): the sedan of the new set, 426 triangles, same tags (tools/blender/build_cars_v2.py --near)
			if root == null:
				root = Game.load_model("rv_near")
			if root != null:
				for n in root.find_children("*", "MeshInstance3D", true, false):
					var m := (n as MeshInstance3D).mesh as ArrayMesh
					if m != null and m.get_surface_count() == 1:
						_near_mesh = _without_vertex_colours(m)
						break
				root.free()
		if _near_mesh != null:
			return _near_mesh
	return procedural_car_mesh()


## The near car's shader never reads COLOR and its MultiMesh has no instance colours, so a COLOR array from the glTF would only be an unused stream (and the GL renderer
## then multiplies it by an instance colour nobody writes). The copy has the same surface without it.
static func _without_vertex_colours(m: ArrayMesh) -> ArrayMesh:
	var arrays := m.surface_get_arrays(0)
	if arrays[Mesh.ARRAY_COLOR] == null:
		return m
	arrays[Mesh.ARRAY_COLOR] = null
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, m.surface_get_material(0))
	return out


static func procedural_car_mesh() -> ArrayMesh:
	var b := MB.new()
	var turn := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)       # profile x (nose +) -> model -Z
	b.uv = Vector2(0.0, 0.0)
	var hull := PackedVector2Array([Vector2(-2.2, 0.28), Vector2(2.2, 0.28), Vector2(2.3, 0.46), Vector2(2.2, 0.7), Vector2(1.4, 0.84), Vector2(-1.9, 0.86), Vector2(-2.3, 0.7), Vector2(-2.3, 0.46)])
	var s0 := b.verts.size()
	b.prism(hull, -0.92, 0.92)
	b.xform_from(s0, turn)
	b.uv = Vector2(0.25, 0.0)
	var cab := PackedVector2Array([Vector2(-1.35, 0.84), Vector2(1.0, 0.84), Vector2(0.45, 1.36), Vector2(-0.9, 1.36)])
	s0 = b.verts.size()
	b.prism(cab, -0.8, 0.8)
	b.xform_from(s0, turn)
	b.uv = Vector2(0.0, 0.0)
	b.box(Vector3(0.0, 1.375, 0.225), Vector3(1.64, 0.05, 1.4), Color.WHITE, false, Vector2.ZERO, MB.F_BOTTOM)             # roof
	for sx: float in [-0.8, 0.8]:                                                                      # pillars break the glass band (no end caps: about 300 triangles a car in all)
		b.strut(Vector3(sx, 0.84, -1.0), Vector3(sx, 1.36, -0.45), 0.09, Color.WHITE, false)
		b.strut(Vector3(sx, 0.84, 1.35), Vector3(sx, 1.36, 0.9), 0.1, Color.WHITE, false)
	b.uv = Vector2(0.55, 0.0)
	b.box(Vector3(0.0, 0.3, -2.27), Vector3(1.74, 0.17, 0.08), Color.WHITE, false)              # bumpers
	b.box(Vector3(0.0, 0.3, 2.27), Vector3(1.74, 0.17, 0.08), Color.WHITE, false)
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * 0.926
		var n := Vector3(sx, 0.0, 0.0)
		b.quad(Vector3(x, 0.47, -2.0), Vector3(x, 0.47, 2.0), Vector3(x, 0.52, 2.0), Vector3(x, 0.52, -2.0), n)      # belt line
		b.quad(Vector3(x, 0.28, -1.5), Vector3(x, 0.28, 1.5), Vector3(x, 0.4, 1.5), Vector3(x, 0.4, -1.5), n)        # sill
	b.uv = Vector2(0.8, 0.0)
	for sx: float in [-1.0, 1.0]:
		b.quad(Vector3(sx * 0.5, 0.52, -2.285), Vector3(sx * 0.82, 0.52, -2.285), Vector3(sx * 0.82, 0.62, -2.285), Vector3(sx * 0.5, 0.62, -2.285), Vector3.FORWARD)
	b.uv = Vector2(1.0, 0.0)
	for sx: float in [-1.0, 1.0]:
		b.quad(Vector3(sx * 0.5, 0.58, 2.285), Vector3(sx * 0.84, 0.58, 2.285), Vector3(sx * 0.84, 0.68, 2.285), Vector3(sx * 0.5, 0.68, 2.285), Vector3.BACK)
	for zc in [-1.4, 1.4]:
		for sx: float in [-1.0, 1.0]:
			b.uv = Vector2(0.47, zc)                                                            # wheel arch: a dark patch on the flank
			b.quad(Vector3(sx * 0.926, 0.28, zc - 0.42), Vector3(sx * 0.926, 0.28, zc + 0.42), Vector3(sx * 0.926, 0.74, zc + 0.42), Vector3(sx * 0.926, 0.74, zc - 0.42), Vector3(sx, 0.0, 0.0))
			b.uv = Vector2(0.45, zc)                                                            # tyre
			var st := b.verts.size()
			b.cylinder(Vector3(0.0, -0.11, 0.0), 0.32, 0.22, 7, Color.WHITE, -1.0, true, true)
			b.xform_from(st, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 0.89, 0.32, zc)))
			b.uv = Vector2(0.65, zc)                                                            # rim
			st = b.verts.size()
			b.cylinder(Vector3(0.0, -0.005, 0.0), 0.15, 0.01, 8, Color.WHITE, -1.0, true, false)
			b.xform_from(st, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 1.0, 0.32, zc)))
	return b.build(null, false, false)


func set_tier(level: int, density := 1.0) -> void:
	quality = clampi(level, 0, 2)
	var n := int(COUNTS[quality] * density)
	if quality == 0:
		n = LowPlus.scaled(n, LowPlus.TRAFFIC_SHARE + 0.15, 6)
	n = mini(n, BUILT)
	if not enabled:
		n = 0
	for i in range(n, count):
		_alive[i] = 0
		TrafficField.remove(TrafficField.NEAR, i)
	for i in range(count, n):
		_alive[i] = 0
		_age[i] = -1.0
	count = n
	radius = RADII[quality] * (0.85 if quality == 0 and LowPlus.on() else 1.0)
	mm.visible_instance_count = 0                                      # the step writes the cars the camera sees (a tier switch must not draw 100 cars at the origin)


func reset() -> void:
	for i in BUILT:
		_alive[i] = 0
		_age[i] = -1.0
		_tmode[i] = 0
		_tdone[i] = -1
	_clock = 0.0
	TrafficField.clear_source(TrafficField.NEAR)


func alive_count() -> int:
	var n := 0
	for i in count:
		n += _alive[i]
	return n


func car_position(i: int) -> Vector3:
	return Vector3(_pos[i].x, 0.0, _pos[i].y)


func car_speed(i: int) -> float:
	return _spd[i]


func car_kind(i: int) -> StringName:
	return KINDS[_kind[i]]


func car_alive(i: int) -> bool:
	return _alive[i] != 0


func car_yaw(i: int) -> float:
	return _yaw[i]


func car_turning(i: int) -> bool:
	return _tmode[i] == 2


## Living cars within `r` m of `pos` (flat) that drive at least `min_speed`.
func moving_near(pos: Vector3, r: float, min_speed := 3.0) -> int:
	var n := 0
	for i in count:
		if _alive[i] != 0 and _spd[i] >= min_speed:
			var d := _pos[i] - Vector2(pos.x, pos.z)
			if d.length_squared() <= r * r:
				n += 1
	return n


# --- the ring: spawning ------------------------------------------------------------------------------------------------------

func _spawn(i: int, c: Vector3, min_dist: float) -> bool:
	for attempt in 12:
		var rr := radius if rng.randf() >= CORE_SHARE else minf(radius, CORE_R)         # half of the spawns land in the core: the street around the hero keeps its traffic on every tier
		var ax := rng.randi() & 1
		var perp := c.z if ax == 0 else c.x
		var along_c := c.x if ax == 0 else c.z
		var lo := maxi(0, ceili((perp - rr + CityLayout.HALF) / CityLayout.PITCH))
		var hi := mini(CityLayout.N, floori((perp + rr + CityLayout.HALF) / CityLayout.PITCH))
		if hi < lo:
			continue
		var k := lo + rng.randi() % (hi - lo + 1)
		var dir := 1 if rng.randf() < 0.5 else -1
		var line := CityLayout.road_center(k) + VehicleSpecs.lane_offset(ax, dir, CityLayout.LANE)
		var dl := line - perp
		if absf(dl) >= rr:
			continue
		var half := sqrt(rr * rr - dl * dl)
		var u := along_c + rng.randf_range(-half, half)
		if absf(u) > EDGE:
			rej[0] += 1
			continue
		var ci := roundi((u + CityLayout.HALF) / CityLayout.PITCH)
		if absf(u - CityLayout.road_center(ci)) < 13.0:                         # not inside a junction
			rej[1] += 1
			continue
		var p := Vector2(u, line) if ax == 0 else Vector2(line, u)
		if (p - Vector2(c.x, c.z)).length() < minf(min_dist, rr * 0.8):
			continue
		var kind := pick_kind(Districts.zone_at(p.x, p.y), DayNight.night_now, rng.randf())
		var cruise := rng.randf_range(VehicleSpecs.AI_CRUISE_MIN, VehicleSpecs.AI_CRUISE_MAX) * KIND_SPEED[kind]
		var share := rng.randf_range(0.7, 1.0)
		var f := Vector2(float(dir), 0.0) if ax == 0 else Vector2(0.0, float(dir))
		var khl := KIND_HALF[kind]
		var khw := KIND_HW[kind]
		if not TrafficField.clear(p.x, p.y, f.x, f.y, khl, khw, 1.0, TrafficField.NEAR, i):
			rej[4] += 1
			continue                                                                  # the spot is taken by a real car, a bridge car, a parked car or a wreck: never a car on top of another
		var ahead := TrafficField.lead(p.x, p.y, f.x, f.y, khl, khw, 45.0, TrafficField.NEAR, i, CAR_PAD)
		var v0 := cruise * share
		if ahead.x < INF:
			var vs := TrafficBrain.safe_speed(ahead.x, ahead.y, BRAKE * 0.7, 0.5, STOP_GAP + 1.0)
			if vs < 2.0 and ahead.x < 9.0:
				rej[5] += 1
				continue                                                              # a standing queue right ahead: the car would be born into it
			v0 = minf(v0, vs * 0.85)
		var behind := TrafficField.lead(p.x, p.y, -f.x, -f.y, khl, khw, 45.0, TrafficField.NEAR, i, CAR_PAD)
		if behind.x < INF:
			var vb := maxf(-behind.y, 0.0)                                            # the speed of the car coming up behind
			if behind.x < 7.0 + vb * 0.7:
				rej[6] += 1
				continue                                                              # too close for it to react
			v0 = clampf(maxf(v0, vb * 0.9), 0.0, cruise * 1.15)                      # the newborn travels with the flow: the car behind needs no hard brake
		place(i, ax, dir, line, u, kind, cruise, rng.randi() % 8, clampf(v0 / maxf(cruise, 0.1), 0.0, 1.0))
		rej[7] += 1
		return true
	return false


## The archetype of a new car by district zone and time of night (0 day .. 1 night): the shares of KIND_MIX scaled by the zone's bias (taxis and buses in the market, lorries on the docks, pickups on the
## fields ...) and by the hour (the buses and delivery vans sleep at night, the taxis, patrols and ambulances stay out). `r` is a random 0..1. Pure: the density test reads it.
static func pick_kind(zone: int, night: float, r: float) -> int:
	var bias: Array = ZONE_BIAS.get(zone, [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
	var total := 0.0
	var w: Array[float] = []
	for k in KINDS.size():
		var x := KIND_MIX[k]
		match k:
			4: x *= float(bias[0]) * (1.0 + 0.4 * night)
			7: x *= float(bias[1]) * (1.0 - 0.3 * night)
			11: x *= float(bias[2]) * (1.0 - 0.6 * night)
			8: x *= float(bias[3]) * (1.0 - 0.7 * night)
			5: x *= float(bias[4])
			6: x *= float(bias[5])
			1: x *= float(bias[6])
			9: x *= 1.0 + 1.2 * night
			10: x *= 1.0 + 0.6 * night
		w.append(x)
		total += x
	var roll := r * total
	var acc := 0.0
	for k in w.size():
		acc += w[k]
		if roll < acc:
			return k
	return 0


## Put car `i` into play in lane `line` of a road along `axis` travelling `dir` at coordinate `u` (the spawner and the tests).
func place(i: int, ax: int, dir: int, line: float, u: float, kind: int, cruise: float, paint: int, speed_share := 1.0) -> void:
	_axis[i] = ax
	_dir[i] = float(dir)
	_line[i] = line
	_u[i] = u
	_kind[i] = kind
	_paint[i] = paint
	_cruise[i] = cruise
	_spd[i] = cruise * speed_share
	_allow[i] = 99.0
	_brake[i] = 0.0
	_panic[i] = 0.0
	_stun[i] = 0.0
	_hurt_cd[i] = 0.0
	_shift[i] = 0.0
	_shift_t[i] = 0.0
	_jam[i] = 0.0
	_ghost[i] = 0.0
	_wait[i] = 0.0
	_age[i] = 0.0
	_tmode[i] = 0
	_tdone[i] = -1
	_alive[i] = 1
	_pos[i] = Vector2(u, line) if ax == 0 else Vector2(line, u)
	_yaw[i] = VehicleSpecs.heading_for(ax, dir)
	_look_t[i] = float(i % 4) * 0.015
	_twait[i] = 0.0
	_ovl[i] = 0.0
	_ovl_t[i] = 0.4 + float(i % 5) * 0.04
	TrafficField.put_yaw(TrafficField.NEAR, i, _pos[i].x, _pos[i].y, _yaw[i], KIND_HALF[kind], KIND_HW[kind], _spd[i], TrafficField.F_AI)


func car_panic(i: int) -> float:
	return _panic[i]


func car_axis(i: int) -> int:
	return _axis[i]


## The sideways drift expressed along the across-lane coordinate (z for a car on an x road, x for one on a z road).
func car_shift_world(i: int) -> float:
	return _dir[i] * _shift[i] if _axis[i] == 0 else -_dir[i] * _shift[i]


func car_shift(i: int) -> float:
	return _shift[i]


func car_dir(i: int) -> int:
	return int(_dir[i])


func car_line(i: int) -> float:
	return _line[i]


## Everything a look-around decides about car `i` (the traffic audit prints it for the cars of an overlap).
func debug_state(i: int) -> Dictionary:
	return {"age": _age[i], "axis": _axis[i], "dir": _dir[i], "u": _u[i], "line": _line[i], "spd": _spd[i], "cruise": _cruise[i], "allow": _allow[i], "tmode": _tmode[i], "ghost": _ghost[i], "jam": _jam[i],
			"panic": _panic[i], "stun": _stun[i], "shift": _shift[i], "kind": KINDS[_kind[i]], "wait": _wait[i],
			"why": [snappedf(_why[i * 4], 0.1), snappedf(_why[i * 4 + 1], 0.1), snappedf(_why[i * 4 + 2], 0.1), snappedf(_why[i * 4 + 3], 0.1)], "alive": _alive[i]}


func _spot_free(skip: int, p: Vector2, d: float) -> bool:
	for j in count:
		if j != skip and _alive[j] != 0 and (_pos[j] - p).length_squared() < d * d:
			return false
	var mgr := Game.vehicles as VehicleManager
	if mgr != null:
		for v in mgr.list:
			if v.active and not v.dead and Vector2(v.global_position.x - p.x, v.global_position.z - p.y).length() < d - 1.0:
				return false
	return true


# --- stepping -------------------------------------------------------------------------------------------------------------

func step(delta: float, center: Vector3) -> void:
	_frame += 1
	_clock += delta
	_ldt = LOOK_EVERY
	var spawned := 0
	var r2 := radius * radius * 1.06
	var mgr := Game.vehicles as VehicleManager
	var sig_clock := signal_clock_override if signal_clock_override >= 0.0 else (mgr.signal_clock if mgr != null else 0.0)
	var lights := mgr == null or mgr.lights_on
	_hero = center
	_nw = 0
	_cam_ok = false
	if is_instance_valid(Game.camera):
		var cf := -Game.camera.global_transform.basis.z
		var cp3 := Game.camera.global_position
		var fl := Vector2(cf.x, cf.z)
		if fl.length_squared() > 0.04:
			_cam_ok = true
			_cam_fwd = fl.normalized()
			_cam_pos = Vector2(cp3.x, cp3.z)
	var pl := Game.player
	_hero_foot = not is_instance_valid(pl) or pl.get(&"vehicle") == null
	_cam = Vector2(INF, INF)
	if _hero_foot and is_instance_valid(Game.camera):
		var cpos := Game.camera.global_position
		if Vector2(cpos.x - center.x, cpos.z - center.z).length() < 9.0:
			_cam = Vector2(cpos.x, cpos.z)
	if _frame % FRAME_STAGGER == 0:
		_collect_peds()
	# a slow frame (a phone at 15 fps, the audit at 4x speed) is run as several short steps: every look-around, braking and move sees at most SUBSTEP seconds
	var n_sub := clampi(ceili(delta / SUBSTEP), 1, 6)
	var dt := delta / float(n_sub)
	for k in n_sub:
		for i in count:
			if _alive[i] != 0:
				_sim_car(i, dt, sig_clock, lights, r2, center, pl)
	_spawn_t -= delta
	var may_spawn := _spawn_t <= 0.0
	if may_spawn:
		_spawn_t = SPAWN_EVERY
	for i in count:
		if _alive[i] == 0:
			if may_spawn and spawned < 3 and _age[i] <= 0.0:
				spawned += 1
				if _spawn(i, center, MIN_SPAWN if _age[i] < 0.0 else radius * RESPAWN_MIN):
					pass
				else:
					_age[i] = -0.5 if _age[i] < 0.0 else 0.0
		_write(i)
	_total = _nw
	mm.visible_instance_count = _nw
	mm.buffer = _buf


## Adds `n` more instances (16 floats each, the layout of `_buf`) behind the ones of this frame: the road cars and the parked cars share the near cars' MultiMesh, so a street full of kerb cars is
## still ONE draw call. Called after step() in the same frame (AmbientCity order); returns how many fitted.
func append_cars(src: PackedFloat32Array, n: int) -> int:
	n = mini(n, SHARED - _total)
	if n <= 0:
		return 0
	var o := _total * 16
	for k in n * 16:
		_buf[o + k] = src[k]
	_total += n
	mm.visible_instance_count = _total
	mm.buffer = _buf
	return n


## One car for `dt` seconds: timers, the look-around (every LOOK_EVERY seconds of game time, whatever the frame rate), speed, move, and the ways a car leaves the ring.
func _sim_car(i: int, dt: float, sig_clock: float, lights: bool, r2: float, center: Vector3, pl: Node) -> void:
	_age[i] += dt
	_panic[i] = maxf(_panic[i] - dt, 0.0)
	_stun[i] = maxf(_stun[i] - dt, 0.0)
	_hurt_cd[i] = maxf(_hurt_cd[i] - dt, 0.0)
	_look_t[i] -= dt
	if _look_t[i] <= 0.0:
		var dh := (_pos[i] - Vector2(center.x, center.z)).length_squared()
		_look_t[i] = LOOK_EVERY if dh < LOOK_NEAR * LOOK_NEAR else LOOK_FAR                 # a car far from the hero looks around less often (the safe-distance rule keeps a margin for it)
		_look(i, sig_clock, lights)
	var want := minf(_cruise[i] * (PANIC_SPEED if _panic[i] > 0.0 else 1.0), _allow[i])
	if _stun[i] > 0.0:
		want = 0.0
	var v := _spd[i]
	v = move_toward(v, want, (ACCEL if want > v else (HARD_BRAKE if want < v - 5.0 else BRAKE)) * dt)
	_spd[i] = v
	_brake[i] = move_toward(_brake[i], 1.0 if (want < v - 0.2 or v < 0.4) else 0.0, dt * 8.0)
	_move(i, dt)
	if _alive[i] == 0:
		return
	var d := _pos[i] - Vector2(center.x, center.z)
	if d.length_squared() > r2:
		_alive[i] = 0
		_age[i] = 0.0
	elif _cam.is_finite() and (_pos[i] - _cam).length_squared() < CAM_KILL * CAM_KILL:
		_alive[i] = 0
		_age[i] = 0.0
	elif _hero_foot and v > 3.0 and _hurt_cd[i] <= 0.0:
		_run_over(i, pl)
	if _alive[i] != 0:
		TrafficField.put_yaw(TrafficField.NEAR, i, _pos[i].x, _pos[i].y, _yaw[i], KIND_HALF[_kind[i]], KIND_HW[_kind[i]], v, TrafficField.F_AI | (TrafficField.F_CROSSING_OK if _tmode[i] == 2 else 0))
		_overlap_check(i, dt)


## The safety net under every rule above: a car whose hull sits inside another vehicle for more than OVERLAP_KILL seconds is taken out of the ring (the one the hero cannot reach, the farther from him).
## Real cars, parked cars and bridge cars are never removed by this, only the near car is.
func _overlap_check(i: int, dt: float) -> void:
	_ovl_t[i] -= dt
	if _ovl_t[i] > 0.0:
		return
	if _spd[i] > 6.0:                                                             # two cars that overlap while moving fast part again within a second: only slow or standing ones can be stuck inside each other
		_ovl_t[i] = 0.6
		_ovl[i] = 0.0
		return
	_ovl_t[i] = 0.3
	var f := Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
	var k := TrafficField.first_overlap(_pos[i].x, _pos[i].y, f.x, f.y, KIND_HALF[_kind[i]], KIND_HW[_kind[i]], -0.12, TrafficField.NEAR, i)
	if k < 0:
		_ovl[i] = 0.0
		return
	_ovl[i] += 0.3
	if _ovl[i] < OVERLAP_KILL:
		return
	if k / 1000 == TrafficField.NEAR:
		var j := k % 1000
		if (_pos[j] - Vector2(_hero.x, _hero.z)).length_squared() < (_pos[i] - Vector2(_hero.x, _hero.z)).length_squared() and _age[j] > 0.0:
			_ovl[i] = 0.0
			return                                                  # the other one is farther from the hero: it is the one that goes (its own check does it)
	_alive[i] = 0
	_age[i] = 0.0
	_ovl[i] = 0.0
	overlap_kills += 1
	TrafficField.remove(TrafficField.NEAR, i)


func _move(i: int, dt: float) -> void:
	var v := _spd[i]
	if _tmode[i] == 2:
		_tp[i] += v * dt / TURN_LEN
		var t := _tp[i]
		if t >= 1.0:                                                   # out of the curve: onto lane B
			var ax := 1 - _axis[i]
			var db := _tdir[i]
			_axis[i] = ax
			_dir[i] = db
			var x: Vector2 = _tX[i]
			_line[i] = x.x if ax == 1 else x.y
			_u[i] = x.y if ax == 1 else x.x
			_tmode[i] = 0
			_shift[i] = 0.0
			_shift_t[i] = 0.0
			_pos[i] = x
			_yaw[i] = VehicleSpecs.heading_for(ax, int(db))
			return
		var e: Vector2 = _tE[i]
		var m: Vector2 = _tI[i]
		var x2: Vector2 = _tX[i]
		var a := e.lerp(m, t)
		var b2 := m.lerp(x2, t)
		_pos[i] = a.lerp(b2, t)
		var tan := (b2 - a)
		if tan.length_squared() > 1e-6:
			_yaw[i] = atan2(-tan.x, -tan.y)
		return
	var ax2 := _axis[i]
	var dir := _dir[i]
	var u := _u[i] + dir * v * dt
	_u[i] = u
	if absf(u) > EDGE + 6.0:
		_alive[i] = 0
		_age[i] = 0.0
		return
	_shift[i] = move_toward(_shift[i], _shift_t[i], SWERVE_RATE * dt)
	var sh := _shift[i]
	var rgt := Vector2(0.0, dir) if ax2 == 0 else Vector2(-dir, 0.0)        # the car's right-hand side (forward (dir, 0) -> +z, (0, dir) -> -dir x)
	_pos[i] = (Vector2(u, _line[i]) if ax2 == 0 else Vector2(_line[i], u)) + rgt * sh
	var h := VehicleSpecs.heading_for(ax2, int(dir))
	_yaw[i] = _damp_angle(_yaw[i], h, 9.0, dt)
	# junction ahead: decide once whether to turn, start the curve at its entry point
	var idx_f := (u + CityLayout.HALF) / CityLayout.PITCH
	var ci := ceili(idx_f) if dir > 0.0 else floori(idx_f)
	if ci < 0 or ci > CityLayout.N:
		return
	var c := CityLayout.road_center(ci)
	var d := (c - u) * dir
	if _tmode[i] == 0 and _tdone[i] != ci and d <= DECIDE_AT and d > 0.0:
		_tdone[i] = ci
		if rng.randf() < TURN_CHANCE and ci > 0 and ci < CityLayout.N and _panic[i] <= 0.0:
			var db := 1.0 if rng.randf() < 0.5 else -1.0
			var across := _line[i]
			if across > CityLayout.HALF - 40.0:
				db = -1.0
			elif across < -CityLayout.HALF + 40.0:
				db = 1.0
			_tmode[i] = 1
			_tdir[i] = db
			_tcross[i] = c + VehicleSpecs.lane_offset(1 - ax2, int(db), CityLayout.LANE)
	if _tmode[i] == 1:
		var entry := _tcross[i] - dir * TURN_R
		if (u - entry) * dir >= 0.0:
			var ln := _line[i]
			var iv := Vector2(_tcross[i], ln) if ax2 == 0 else Vector2(ln, _tcross[i])
			var fa := Vector2(dir, 0.0) if ax2 == 0 else Vector2(0.0, dir)
			var db2 := _tdir[i]
			var fb := Vector2(0.0, db2) if ax2 == 0 else Vector2(db2, 0.0)
			_tE[i] = iv - fa * TURN_R
			_tI[i] = iv
			_tX[i] = iv + fb * TURN_R
			_tp[i] = 0.0
			_tmode[i] = 2


static func _damp_angle(a: float, b: float, rate: float, dt: float) -> float:
	return lerp_angle(a, b, 1.0 - exp(-rate * dt))


# --- what is ahead ------------------------------------------------------------------------------------------------------------

func _collect_peds() -> void:
	_n_peds = 0
	var w := Game.world as City
	if w == null or w.ambient == null:
		return
	_n_peds = w.ambient.crowd.fill_crossing(_peds)


func _look(i: int, sig_clock: float, lights: bool) -> void:
	var p := _pos[i]
	var f: Vector2
	if _tmode[i] == 2:
		f = Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
	else:
		f = Vector2(_dir[i], 0.0) if _axis[i] == 0 else Vector2(0.0, _dir[i])
	var allow_light := 99.0
	var allow_ped := 99.0
	var allow_car := 99.0
	var half := KIND_HALF[_kind[i]]
	var hw := KIND_HW[_kind[i]]
	var blocked_by_person := false
	var u := _u[i]
	var in_junction := _tmode[i] == 2
	if not in_junction:
		var rc := CityLayout.road_center(roundi((u + CityLayout.HALF) / CityLayout.PITCH))
		in_junction = absf(u - rc) < 10.5
	# junction lights
	if lights and _tmode[i] != 2 and _panic[i] <= 0.0:
		var dir := _dir[i]
		var idx_f := (u + CityLayout.HALF) / CityLayout.PITCH
		var ci := ceili(idx_f) if dir > 0.0 else floori(idx_f)
		if ci >= 0 and ci <= CityLayout.N:
			var d := (CityLayout.road_center(ci) - u) * dir
			if d > VehicleSpecs.LIGHT_COMMIT and d <= LIGHT_LOOK:
				var st := signal_for(_axis[i], roundi((_line[i] + CityLayout.HALF) / CityLayout.PITCH), ci, sig_clock, desync)
				if st == 2 or (st == 1 and d > VehicleSpecs.AMBER_STOP):
					var room := d - STOP_LINE - half + 2.0
					allow_light = 0.0 if room <= 0.4 else sqrt(2.0 * BRAKE * 0.7 * room)
					if _light_seen[i] == 0 and room > 0.0:
						_light_seen[i] = 1
						stops_light += 1
				else:
					_light_seen[i] = 0
			else:
				_light_seen[i] = 0
	# the hero and the people on a zebra: stop for one in the way, drift round one standing at the edge of the lane
	var pe := p                                                                  # where the body really is
	var pl := p - (Vector2(0.0, _dir[i]) if _axis[i] == 0 else Vector2(-_dir[i], 0.0)) * _shift[i]      # the lane's centre line under it
	var rv := Vector2(-f.y, f.x)
	_n_obs = 0
	if _hero.is_finite():
		var hq := Vector2(_hero.x, _hero.z)
		_obs_add(pl, f, rv, hq, half)
		allow_ped = gap_allow(pe, f, hq, half, 0.6, SIDE_FOOT)
		if allow_ped < 0.5 and _hero_foot:
			blocked_by_person = true
	if _cam.is_finite():
		_obs_add(pl, f, rv, _cam, half, true)
		allow_ped = minf(allow_ped, gap_allow(pe, f, _cam, half, 0.5, SIDE_FOOT))
	for k in _n_peds:
		_obs_add(pl, f, rv, _peds[k], half)
		var a := gap_allow(pe, f, _peds[k], half, 0.5, SIDE_FOOT)
		if a < allow_ped:
			allow_ped = a
		if a < 0.5:
			blocked_by_person = true
	var target := _pick_shift()
	if target != 0.0 and _tmode[i] != 2:                                          # never drift into a car beside the lane (a parked car on the bay, a car in the next lane): try the other side, else wait for the person
		var sp := pl + rv * target
		if not TrafficField.clear(sp.x, sp.y, f.x, f.y, half + 0.6, hw, 0.15, TrafficField.NEAR, i):
			var alt := _solve_shift(SWERVE_CLEAR, -1.0 if target > 0.0 else 1.0)
			target = 0.0
			if alt != INF and alt != 0.0:
				var sp2 := pl + rv * alt
				if TrafficField.clear(sp2.x, sp2.y, f.x, f.y, half + 0.6, hw, 0.15, TrafficField.NEAR, i):
					target = alt
	_shift_t[i] = target if _tmode[i] != 2 else 0.0
	# the other cars (real, near, road, bridge, parked, wrecks): the nearest hull in this car's swept corridor and the speed from which it can still stop short of it
	var ld := TrafficField.lead(p.x, p.y, f.x, f.y, half, hw, TrafficBrain.look_for(_spd[i]) + 4.0, TrafficField.NEAR, i, CAR_PAD)
	if ld.x < INF:
		allow_car = TrafficBrain.safe_speed(ld.x, ld.y, BRAKE * 0.7, 0.3, STOP_GAP, HARD_BRAKE)
	var allow_box := _box_allow(i, p, f, half, hw, ld)
	if _tmode[i] == 1:                                                            # a car that waits too long to turn (oncoming traffic, a taken lane) gives the turn up and drives straight on: no queue stands behind one left-turner
		if allow_box < 0.5:
			_twait[i] += _ldt
			if _twait[i] > TURN_PATIENCE:
				_tmode[i] = 0
				_twait[i] = 0.0
				allow_box = _box_allow(i, p, f, half, hw, ld)
		else:
			_twait[i] = 0.0
	_allow[i] = minf(minf(allow_light, allow_box), minf(allow_ped, allow_car))
	_why[i * 4] = allow_light
	_why[i * 4 + 1] = allow_box
	_why[i * 4 + 2] = allow_car
	_why[i * 4 + 3] = allow_ped
	# a jam that nothing explains (no light, nobody on foot) for a long time: a car that nobody sees is taken out of the ring, a seen one after JAM_FORCE (a queue at a red light is never a jam: it lasts one cycle)
	if _spd[i] < 0.3 and (allow_car < TrafficBrain.CREEP or allow_box < TrafficBrain.CREEP) and allow_light >= 0.5 and allow_ped >= 0.5:
		_jam[i] += _ldt
		if (_jam[i] > JAM_AFTER and not _seen(i)) or _jam[i] > JAM_FORCE:
			_jam[i] = 0.0
			_alive[i] = 0
			_age[i] = 0.0
			TrafficField.remove(TrafficField.NEAR, i)
			jam_breaks += 1
			return
	else:
		_jam[i] = 0.0
	if blocked_by_person and _spd[i] < 0.5:
		_wait[i] += _ldt
		if _wait[i] > 1.8:
			_wait[i] = -3.0
			honk(i)
	elif not blocked_by_person:
		_wait[i] = minf(_wait[i], 0.0)
		_wait[i] = minf(_wait[i] + 0.05, 0.0)


## True when the camera can see car `i` (the same window as the draw: in front of it within DRAW_R, or very close).
func _seen(i: int) -> bool:
	if not _cam_ok:
		return true
	var dx := _pos[i].x - _cam_pos.x
	var dz := _pos[i].y - _cam_pos.y
	var d2 := dx * dx + dz * dz
	if d2 > DRAW_R[quality] * DRAW_R[quality]:
		return false
	return d2 <= VIEW_NEAR * VIEW_NEAR or (dx * _cam_fwd.x + dz * _cam_fwd.y) >= VIEW_COS * sqrt(d2)


## The junction box ahead (rules a driver keeps): do not enter it while crossing traffic stands in it, do not enter it when a queue beyond it would leave the car standing in the box, do not turn
## into a lane whose first metres are taken (or that a car is about to arrive in), and give way to oncoming traffic when turning across it. Returns the speed that still stops at the stop line, 99 when free.
func _box_allow(i: int, p: Vector2, f: Vector2, half: float, hw: float, ld: Vector3) -> float:
	if _tmode[i] == 2 or _panic[i] > 0.0:
		return 99.0
	var dir := _dir[i]
	var u := _u[i]
	var ci := ceili((u + CityLayout.HALF) / CityLayout.PITCH) if dir > 0.0 else floori((u + CityLayout.HALF) / CityLayout.PITCH)
	if ci < 0 or ci > CityLayout.N:
		return 99.0
	var c := CityLayout.road_center(ci)
	var d := (c - u) * dir
	if d <= BOX_COMMIT or d > LIGHT_LOOK:
		return 99.0                                                                 # past the stop line a car is in the junction: it drives on (it would block the crossing by stopping there)
	var rc := CityLayout.road_center(roundi((_line[i] + CityLayout.HALF) / CityLayout.PITCH))
	var jc := Vector2(c, rc) if _axis[i] == 0 else Vector2(rc, c)
	var blocked := TrafficField.box_busy(jc.x, jc.y, BOX_HALF, f.x, f.y, TrafficField.NEAR, i)
	if not blocked and ld.x < INF and ld.y < 2.5 and ld.x < d + BOX_HALF + 2.0 * half + 1.0:
		blocked = true                                                              # a standing queue reaches into or just past the box: the car would stop in the middle of the crossing
	if not blocked and _tmode[i] == 1:
		var db := _tdir[i]
		var ln := _line[i]
		var iv := Vector2(_tcross[i], ln) if _axis[i] == 0 else Vector2(ln, _tcross[i])
		var fb := Vector2(0.0, db) if _axis[i] == 0 else Vector2(db, 0.0)
		var tx := iv + fb * TURN_R
		var l2 := TrafficField.lead(tx.x - fb.x * (half + 0.5), tx.y - fb.y * (half + 0.5), fb.x, fb.y, half, hw, 6.0 + 2.0 * half, TrafficField.NEAR, i, 0.1)
		if l2.x < half + 2.0 and l2.y < 3.5:
			blocked = true                                                          # the first metres of the lane it turns into are taken
		if not blocked:
			var l3 := TrafficField.lead(tx.x, tx.y, -fb.x, -fb.y, 0.4, hw, 16.0, TrafficField.NEAR, i, 0.1)
			if l3.x < INF and l3.x < 6.0 + 2.5 * maxf(-l3.y, 0.0):
				blocked = true                                                      # a car is coming down that lane towards the spot
		if not blocked and fb.dot(Vector2(-f.y, f.x)) < 0.0:                        # a turn to the left crosses the oncoming lane
			var left := Vector2(f.y, -f.x)
			var far := jc + left * CityLayout.LANE + f * 36.0
			var l4 := TrafficField.lead(far.x, far.y, -f.x, -f.y, 0.4, 1.0, 36.0, TrafficField.NEAR, i, 0.2)
			if l4.x < INF:
				var their := l4.y                                                   # its speed towards the junction (it travels along -f, the direction of this query)
				var dist_j := 36.0 - l4.x
				if dist_j < 7.0 + 1.7 * maxf(their, 0.0):
					blocked = true
	if not blocked:
		return 99.0
	var room := d - STOP_LINE - half + 2.0
	return 0.0 if room <= 0.4 else sqrt(2.0 * BRAKE * 0.7 * room)


## The light a near car sees: the city's two-phase light (`VehicleSpecs.signal_state`), staggered per junction when `staggered`. The market avenue (road AVENUE, the street next to the spawn) is the main road:
## its lights (one phase for every junction of the avenue) stay green 12 s of 18 and the cross roads wait, so traffic is always rolling in the street the hero starts in (owner round 3: "the street is empty"). The two axes are never green together.
static func signal_for(axis: int, ri: int, ci: int, clock: float, staggered: bool) -> int:
	var off := junction_offset(axis, ri, ci) if staggered else 0.0
	if not staggered or not ((axis == 0 and ri == AVENUE) or (axis == 1 and ci == AVENUE)):
		return VehicleSpecs.signal_state(axis, clock + off)
	var t := fposmod(clock, VehicleSpecs.SIGNAL_CYCLE)                               # one phase along the whole avenue: a wave that stops and releases the street together
	if axis == 0:
		return 0 if t < AVENUE_GREEN else (1 if t < AVENUE_GREEN + VehicleSpecs.SIGNAL_AMBER else 2)
	var cross_start := AVENUE_GREEN + VehicleSpecs.SIGNAL_AMBER + 0.5               # half a second of red for everybody, then the cross road
	if t < cross_start:
		return 2
	return 0 if t < VehicleSpecs.SIGNAL_CYCLE - VehicleSpecs.SIGNAL_AMBER else 1


## Seconds this junction's lights run ahead of the city clock: every junction has its own phase (like the lamps that are drawn on the poles), so the cars of one road are
## never all held at once and some traffic moves on every street at any time. `ri` is the road index of the car's lane, `ci` the junction road it approaches.
static func junction_offset(axis: int, ri: int, ci: int) -> float:
	var xi := ci if axis == 0 else ri
	var yi := ri if axis == 0 else ci
	return float((xi * 5 + yi * 11 + xi * yi) % 9) * 2.0


## Remember an obstacle for the drift: its sideways offset (along the car's right `rv`) from the lane's centre line `p`, when it is within reach ahead of the car.
func _obs_add(p: Vector2, f: Vector2, rv: Vector2, q: Vector2, half: float, is_cam := false) -> void:
	var r := q - p
	var ahead := r.dot(f)
	if ahead < -(half + 0.8) or ahead > 15.0 or _n_obs >= _obs.size():
		return
	var lat := r.dot(rv)
	if absf(lat) >= CAM_CLEAR + SWERVE_LEFT:
		return
	_obs[_n_obs] = lat
	_obs_cam[_n_obs] = 1 if is_cam else 0
	_n_obs += 1


## The sideways drift (m, along the car's right) that clears EVERY remembered obstacle at once (the hero, the camera behind him, people): 0 when nobody is near the lane, else the smallest
## drift that leaves SWERVE_CLEAR round all of them (the old per-obstacle drift took the camera's side into the hero: the whole avenue queued behind him at the spawn). 0 when no drift fits (the car then stops).
func _pick_shift() -> float:
	if _n_obs == 0:
		return 0.0
	var res := _solve_shift(CAM_CLEAR)                       # first with a wide berth for the camera (a roof right at the lens fills the screen), then with the plain one
	if res == INF:
		res = _solve_shift(SWERVE_CLEAR)
	return 0.0 if res == INF else res


## The smallest drift that leaves SWERVE_CLEAR round every obstacle and `cam_clear` round the camera; 0 when nothing is near; INF when no drift fits.
func _solve_shift(cam_clear: float, only_sign := 0.0) -> float:
	var ok0 := true
	for k in _n_obs:
		if absf(_obs[k]) < (cam_clear if _obs_cam[k] != 0 else SWERVE_CLEAR):
			ok0 = false
			break
	if ok0:
		return 0.0
	var best := INF
	for k in _n_obs:
		var ck: float = cam_clear if _obs_cam[k] != 0 else SWERVE_CLEAR
		for sg in [-1.0, 1.0]:
			if only_sign != 0.0 and sg != only_sign:
				continue
			var sh: float = clampf(_obs[k] + sg * (ck + 0.1), -SWERVE_LEFT, SWERVE_MAX)
			var fits := true
			for m in _n_obs:
				if absf(_obs[m] - sh) < (cam_clear if _obs_cam[m] != 0 else SWERVE_CLEAR) - 0.02:
					fits = false
					break
			if fits and absf(sh) < absf(best):
				best = sh
	return best


## The speed that still lets a car at `p` heading `f` stop short of an obstacle at `q` (half length `their_half`): 99 when nothing is in the way, 0 when it must stop now.
func gap_allow(p: Vector2, f: Vector2, q: Vector2, half: float, their_half: float, side_half: float) -> float:
	var r := q - p
	var ahead := r.dot(f)
	if ahead <= 0.0 or ahead > LOOK + half:
		return 99.0
	if absf(r.x * f.y - r.y * f.x) >= side_half:
		return 99.0
	var gap := ahead - half - their_half - STOP_GAP
	if gap <= 0.0:
		return 0.0
	return sqrt(2.0 * BRAKE * 0.7 * gap)


## True when a car in the lane is within `look` m ahead of `pos` along (fx, fz) and `side` of its line: the real traffic (Vehicle._blocked) stops for it too.
func blocks(pos: Vector3, fx: float, fz: float, side: float, look: float) -> bool:
	for j in count:
		if _alive[j] == 0:
			continue
		var rx := _pos[j].x - pos.x
		var rz := _pos[j].y - pos.z
		var ahead := rx * fx + rz * fz
		if ahead > 0.0 and ahead < look + 1.5 and absf(rx * fz - rz * fx) < side + 0.2:
			return true
	return false


# --- reactions --------------------------------------------------------------------------------------------------------------

func honk(i: int) -> void:
	honks += 1
	if _hero.is_finite() and (_pos[i] - Vector2(_hero.x, _hero.z)).length() < 60.0:
		Sfx.play_at(&"horn", car_position(i), -8.0)


func _run_over(i: int, pl: Node) -> void:
	if not is_instance_valid(pl) or not pl.has_method(&"damage"):
		return
	var q := Vector2(pl.global_position.x, pl.global_position.z) - _pos[i]
	var f := Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
	var along := q.dot(f)
	var lat := absf(q.x * f.y - q.y * f.x)
	if along > -KIND_HALF[_kind[i]] and along < KIND_HALF[_kind[i]] + 0.3 and lat < 1.25 and absf(pl.global_position.y - 0.0) < 2.0:
		hurt_total += 1
		_hurt_cd[i] = HURT_CD
		_spd[i] *= 0.3
		_stun[i] = 0.8
		pl.call(&"damage", 8.0 + _spd[i] * 2.0, car_position(i))


## Gunfire, a horn or a crash at `pos` (the real traffic's Vehicle.hear): cars within earshot flee or hurry on.
func hear(pos: Vector3, what: StringName) -> int:
	var n := 0
	for i in count:
		if _alive[i] == 0:
			continue
		var d := _pos[i] - Vector2(pos.x, pos.z)
		match what:
			&"gun":
				if d.length() < GUN_HEAR:
					_panic[i] = PANIC_TIME
					n += 1
			&"horn":
				var f := Vector2(_dir[i], 0.0) if _axis[i] == 0 else Vector2(0.0, _dir[i])
				if d.length() < 16.0 and d.dot(f) > 0.0:
					_panic[i] = maxf(_panic[i], 1.5)
					n += 1
			&"crash":
				if d.length() < 20.0:
					_stun[i] = 1.4
					n += 1
	return n


# --- a real vehicle against the near cars -------------------------------------------------------------------------------------------

const NEAR_MASS := 1450.0

## The near cars that were not promoted (the manager had no free slot) are still solid: a real vehicle whose hull overlaps one gets a real crash (impulse, damage, the horn) and the near car is shoved
## clear, stunned for a moment and loses its lane speed. Returns how many cars were hit. Called by VehicleManager for the driven car and every real car that moves.
func collide_vehicle(v: Vehicle) -> int:
	var hits := 0
	var vp := Vector2(v.global_position.x, v.global_position.z)
	var vf3 := v.forward()
	var vf := Vector2(vf3.x, vf3.z)
	var vhl := float(v.spec["len"]) * 0.5
	var vhw := float(v.spec["wid"]) * 0.5
	for i in count:
		if _alive[i] == 0:
			continue
		var dp := _pos[i] - vp
		if absf(dp.x) > 9.0 or absf(dp.y) > 9.0:
			continue
		var f := Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
		var depth := TrafficField.obb_depth(vp.x, vp.y, vf.x, vf.y, vhl, vhw, _pos[i].x, _pos[i].y, f.x, f.y, KIND_HALF[_kind[i]], KIND_HW[_kind[i]])
		if depth <= 0.03:
			continue
		hits += 1
		var n2 := vp - _pos[i]
		if n2.length_squared() < 1e-6:
			n2 = vf
		n2 = n2.normalized()                                                      # from the near car towards the vehicle
		var n := Vector3(n2.x, 0.0, n2.y)
		var at := Vector3((vp.x + _pos[i].x) * 0.5, 0.0, (vp.y + _pos[i].y) * 0.5)
		var near_v := f * _spd[i]
		var vrel := (v.point_velocity(at) - Vector3(near_v.x, 0.0, near_v.y)).dot(n)
		_pos[i] -= n2 * (depth + 0.08)                                           # the near car is shoved clear
		_u[i] = _pos[i].x if _axis[i] == 0 else _pos[i].y
		_stun[i] = maxf(_stun[i], 1.6)
		_spd[i] *= 0.25
		_hurt_cd[i] = HURT_CD
		v.global_position += Vector3(n2.x, 0.0, n2.y) * depth * 0.25            # the vehicle gives a little too (the shove above is most of the separation)
		if vrel < 0.0:
			var inv := v.inverse_mass_at(n, at) + 1.0 / NEAR_MASS
			var j := -(1.0 + VehicleSpecs.RESTITUTION) * vrel / inv
			v.apply_impulse(n * j, at)
			var closing := -vrel
			if closing > VehicleSpecs.CAR_HIT_SPEED:
				var mgr := Game.vehicles as VehicleManager
				if mgr != null:
					mgr.hear(Vector3(_pos[i].x, 0.0, _pos[i].y), &"crash")
				if v.driver_is_player:
					FX.shake(clampf(closing / 22.0, 0.15, 0.9))
				FX.burst(Vector3(at.x, 0.7, at.z), Color(1.0, 0.75, 0.38), 6, 4.0, 0.3, 7.0, 0.3)
				Sfx.play_at(&"hit", at, -3.0)
				honk(i)
				v.crash(closing, at, n, NEAR_MASS)
			v.lane_lost(closing)
	return hits


# --- the hero takes a car ---------------------------------------------------------------------------------------------------

## The nearest near car whose hull is within `reach` m of `pos` (flat), or -1.
func car_near(pos: Vector3, reach: float) -> int:
	var best := -1
	var best_d := INF
	for i in count:
		if _alive[i] == 0:
			continue
		var q := Vector2(pos.x, pos.z) - _pos[i]
		var f := Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
		var along := absf(q.dot(f)) - KIND_HALF[_kind[i]]
		var lat := absf(q.x * f.y - q.y * f.x) - 0.95
		var d := Vector2(maxf(along, 0.0), maxf(lat, 0.0)).length()
		if d <= reach and d < best_d:
			best_d = d
			best = i
	return best


## Swap car `i` for a real Vehicle at the same place, heading, lane and speed (null when the manager has no room). The near car disappears and respawns far away.
func promote(i: int) -> Vehicle:
	var mgr := Game.vehicles as VehicleManager
	if mgr == null or _alive[i] == 0:
		return null
	var pos := car_position(i)
	var v := mgr.spawn_promoted(KINDS[_kind[i]], pos, _yaw[i], _axis[i], int(_dir[i]), _line[i], _spd[i], _cruise[i], int(_paint[i]))
	if v == null:
		return null
	_alive[i] = 0
	_age[i] = 0.0
	TrafficField.remove(TrafficField.NEAR, i)
	promoted += 1
	return v


## For VehicleManager.reach_car: promote the near car within `reach` of `pos` and return the real car, or null.
func promote_near(pos: Vector3, reach: float) -> Vehicle:
	var i := car_near(pos, reach)
	return null if i < 0 else promote(i)


## Cars within `r` of the driven car become real ones, so a crash with them is a real crash (called a few times a second while the hero drives).
func promote_around(pos: Vector3, r: float) -> int:
	var n := 0
	for i in count:
		if _alive[i] != 0 and (_pos[i] - Vector2(pos.x, pos.z)).length() < r:
			if promote(i) != null:
				n += 1
			else:
				break
	return n


# --- the buffer ------------------------------------------------------------------------------------------------------------

## Writes car `i` into the next free MultiMesh slot when the camera can see it (the cars behind the hero cost nothing: one draw, the triangles of the cars in front only).
func _write(i: int) -> void:
	if _alive[i] == 0:
		TrafficField.remove(TrafficField.NEAR, i)
		return
	if _cam_ok:
		var dx := _pos[i].x - _cam_pos.x
		var dz := _pos[i].y - _cam_pos.y
		var d2 := dx * dx + dz * dz
		if d2 > DRAW_R[quality] * DRAW_R[quality]:
			return
		if d2 > VIEW_NEAR * VIEW_NEAR and (dx * _cam_fwd.x + dz * _cam_fwd.y) < VIEW_COS * sqrt(d2):
			return
	var o := _nw * 16
	_nw += 1
	var fade := minf(1.0, _age[i] * 1.2 + 0.05)
	var y := _yaw[i]
	var c := cos(y)
	var s := sin(y)
	var sc := fade
	# Basis(UP, yaw): x axis (c, 0, -s), y axis (0, 1, 0), z axis (s, 0, c); row-major 3x4
	_buf[o] = c * sc
	_buf[o + 1] = 0.0
	_buf[o + 2] = s * sc
	_buf[o + 3] = _pos[i].x
	_buf[o + 4] = 0.0
	_buf[o + 5] = sc
	_buf[o + 6] = 0.0
	_buf[o + 7] = 0.0
	_buf[o + 8] = -s * sc
	_buf[o + 9] = 0.0
	_buf[o + 10] = c * sc
	_buf[o + 11] = _pos[i].y
	_buf[o + 12] = float(_paint[i])
	_buf[o + 13] = float(_kind[i])
	_buf[o + 14] = _brake[i]
	_buf[o + 15] = 1.0
