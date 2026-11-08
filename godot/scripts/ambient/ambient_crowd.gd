extends RefCounted
## Pedestrian crowd of the living city: ONE MultiMesh of ONE clothed human-alien-hybrid citizen mesh (assets/models/citizen.glb, built by tools/blender/model_citizen.py, 6 archetypes
## chosen per person in assets/shaders/prop_crowd_core.gdshaderinc: hood, long coat, backpack, crest and visor, scarf, umbrella; walk cycle, build and palette in the vertex /
## fragment stage, so the crowd is still one draw call) that walk the sidewalk lines of the road grid, cross the roads on the zebras, sometimes turn at a
## corner and run away from gunfire.
##
## The sidewalk lines are the two kerb-side lines of every road (11.3 m from the road centre, along x and along z); the line continues straight over
## the zebra of the crossing road, and a pedestrian that reaches a corner turns onto the crossing line with probability TURN_CHANCE. A fixed pool
## (HIGH count) lives in a ring around the player: whoever leaves it re-appears in the outer part of the ring on another sidewalk, so nothing is
## created, freed or allocated while the game runs. The tiers change the pool in use and the ring (LOW: at most 24 people and nobody beyond 40 m).

const SHADER := preload("res://assets/shaders/prop_crowd.gdshader")
const MIRROR_SHADER := preload("res://assets/shaders/prop_crowd_mirror.gdshader")
const MB := preload("res://scripts/world/mesh_builder.gd")

const MODEL := "res://assets/models/citizen.glb"
const NEAR_CAP := 24                     ## people drawn with the full mesh (about 730 triangles): the nearest ones, within NEAR_RADIUS of the player
const NEAR_RADIUS := 24.0                ## everybody else is drawn with the cut-down mesh "CitizenFar" (about 250 triangles)
const ARCHETYPES := 6                    ## the shader shows archetype floor(seed * 5.999) of the citizen mesh
const BUILT := 100                       ## pool size = MultiMesh instances (the HIGH count)
const COUNTS: Array[int] = [48, 84, 96]            ## LOW 48 (was 24: the market street must always hold 20+ people within 40 m of the hero, see LifeCensus / test_slice_life)
const RADII: Array[float] = [42.0, 58.0, 68.0]
const LINE_OFF := 11.3                   ## sidewalk line offset from the road centre (kerb at 10, building faces from 12)
const ROAD_SPAN := 22.6                  ## the part of a line that lies on a crossing road (zebra) : 2 * LINE_OFF
const MIN_SPAWN := 7.0
const RESPAWN_MIN := 0.5                 ## a person who left the ring re-appears at least this share of the radius away (was 0.7: the street around the player stayed empty)
const TURN_CHANCE := 0.3
const FLEE_SPEED := 4.4
const FLEE_TIME := 5.0
const SHOT_RADIUS: Array[float] = [30.0, 38.0, 45.0]
const SPAWNS_PER_STEP := 10
const CORE_SHARE := 0.7                 ## share of the spawns that are drawn inside CORE_R of the hero whatever the tier's ring is
const CORE_R := 46.0
const VIEW_BIAS := 0.3                   ## share of the spawns that are refused when they would land behind the camera: the street in front of the hero fills first
const VENDOR_SEED := 0.7 / 6.0           ## seed of a stall vendor: group 0, archetype 9 (wide hat, tray of glowing wares)
const EDGE := CityLayout.HALF + 16.0
const STRIDE := 20
const OFF_MIN := -0.75                   ## lateral offset range around the sidewalk line (metres)
const OFF_MAX := 0.62
const GROUP_CHANCE := 0.15               ## a fresh spawn that starts a little group chatting on the pavement (2-3 people, facing each other)
const IDLE_CHANCE := 0.012               ## per second, for a walker: stop for a moment
const SHOP_STAY := Vector2(5.0, 14.0)    ## seconds a person lingers at a shop front / a bus stop (see _assign_goal, NpcLife)
const BUS_STAY := Vector2(10.0, 24.0)
const STOP_MID := 51.3                   ## middle of a sidewalk span, in line coordinates (from the span's road crossing)
const STOP_SHOP := 1
const STOP_BUS := 2
const HP := 28.0                         ## a person's health: two body hits of the carbine, one head hit (a shot at the head is 2x), a blast kills outright
const DIE_TIME := 1.6                    ## seconds from the hit to the last mote: fall (first FALL_AT), lie, then dissolve into quantum light (from DISSOLVE_FROM)
const FALL_AT := 0.2
const DISSOLVE_FROM := 0.6
const BODY_R := 0.36                     ## the hit cylinder of a standing person (the carbine's ray must find them in the street)
const BODY_H := 1.85
const HEAD_FROM := 1.45                  ## a hit above this is a head shot
const DISSOLVE_COLOR := Color(0.55, 0.95, 1.0)
const LOOK_ALONG := 0                    ## facing: along the walking direction / sideways (+ or - lateral) / along the line (+ or -)
const LOOK_LAT_POS := 1
const LOOK_LAT_NEG := 2
const LOOK_U_POS := 3
const LOOK_U_NEG := 4

var mm: MultiMesh                        ## the far crowd (cut-down mesh, every pool slot; a person who is near has a zero-scale record here)
var mm_near: MultiMesh                   ## the near crowd (full mesh), compacted every step
var material: ShaderMaterial
var mirror_material: ShaderMaterial
var count := 0                           ## pool in use (tier)
var radius := 70.0
var quality := 1
var rng := RandomNumberGenerator.new()

var _u := PackedFloat32Array()           ## position along the line
var _lat := PackedFloat32Array()         ## the line (fixed coordinate)
var _off := PackedFloat32Array()         ## this person's own sideways offset from the line (the sidewalk is about 2 m wide: nobody walks in a ruler-straight file)
var _idle := PackedFloat32Array()        ## seconds left standing still (a chat, a glance at the phone); the animation stops with it
var _dir := PackedFloat32Array()         ## +1 / -1 along the line
var _spd := PackedFloat32Array()         ## walking speed
var _phase := PackedFloat32Array()
var _flee := PackedFloat32Array()        ## seconds of running left
var _age := PackedFloat32Array()         ## fade-in time after (re)spawning
var _seed := PackedFloat32Array()
var _size := PackedFloat32Array()
var _umb := PackedFloat32Array()
var _axis := PackedByteArray()           ## 0: walks along x (z = line), 1: along z
var _alive := PackedByteArray()
var _first := PackedByteArray()          ## 1 until the first successful spawn after a reset: the first fill may use the whole ring
var _reg := PackedInt32Array()           ## region id along the line (sidewalk / zebra spans), a change = a corner was passed
var _buf := PackedFloat32Array()
var _nbuf := PackedFloat32Array()
var _nn := 0                             ## people in the near buffer this step
var _fled := 0                           ## people sent running so far (tests, debugging)
var _look := PackedByteArray()           ## LOOK_* while a person stands (facing a shop, the road, the player); 0 = along the walk
var _cower := PackedFloat32Array()       ## seconds left crouching still (a scare that did not make them run)
var _goal := PackedFloat32Array()        ## the next stop (position along the line) when _gkind != 0
var _gkind := PackedByteArray()          ## 0 none, STOP_SHOP, STOP_BUS
var _stopk := PackedByteArray()          ## the kind of the last stop person i made (shop / bus), for the right bark
var _pin := PackedByteArray()            ## 1: a stall vendor, stands where it is (StreetVendors) until scared, shot or the hero leaves
var _seed0 := PackedFloat32Array()       ## the slot's own seed (a vendor borrows the vendor look)
var _cam_fwd := Vector2.ZERO             ## flat camera forward (spawn bias), set every step
var _hide := PackedByteArray()           ## 1: this person is drawn by a real 3D actor (CitizenActors), the MultiMesh skips them
var _hp := PackedFloat32Array()          ## health per person (HP at spawn)
var _dying := PackedFloat32Array()       ## seconds of the death left (0 = not dying): the person stands still, falls, dissolves; then the slot is free and respawns elsewhere
var _fall := PackedFloat32Array()        ## +1 falls backwards, -1 forwards
var killed_total := 0                    ## people killed so far (tests, stats); a dying person is not alive (is_alive) and is not scared, promoted or drawn by a 3D actor
var _lingers := 0                        ## stops made at shops / bus stops so far (tests, debugging)


func build(light_map: Texture2D) -> void:
	rng.seed = 424242
	var meshes := _person_meshes()
	mm_near = MB.new_multimesh(meshes[0], NEAR_CAP, true, true)
	mm = MB.new_multimesh(meshes[1], BUILT, true, true)
	_nbuf.resize(NEAR_CAP * STRIDE)
	for i in NEAR_CAP:
		for c in 4:
			_nbuf[i * STRIDE + 12 + c] = 1.0
	for a: PackedFloat32Array in [_u, _lat, _off, _idle, _dir, _spd, _phase, _flee, _age, _seed, _size, _umb]:
		a.resize(BUILT)
	_axis.resize(BUILT)
	_alive.resize(BUILT)
	_first.resize(BUILT)
	_first.fill(1)
	_reg.resize(BUILT)
	_look.resize(BUILT)
	_gkind.resize(BUILT)
	_stopk.resize(BUILT)
	_hide.resize(BUILT)
	_pin.resize(BUILT)
	_seed0.resize(BUILT)
	for a: PackedFloat32Array in [_cower, _goal, _hp, _dying, _fall]:
		a.resize(BUILT)
	_hp.fill(HP)
	_buf.resize(BUILT * STRIDE)
	for i in BUILT:
		_seed[i] = (float(i % ARCHETYPES) + 0.02 + 0.96 * rng.randf()) / float(ARCHETYPES)        # archetype = i % 6 (an even mix), the rest of the seed picks the palette
		_size[i] = 0.93 + 0.14 * rng.randf()
		_seed0[i] = _seed[i]
		_umb[i] = 1.0 if (i % ARCHETYPES == 2 or rng.randf() < 0.1) else 0.0
		for c in 4:
			_buf[i * STRIDE + 12 + c] = 1.0                       # white instance colour (vertex colours need one in the Compatibility renderer)
	material = ShaderMaterial.new()
	material.shader = SHADER
	mirror_material = ShaderMaterial.new()
	mirror_material.shader = MIRROR_SHADER
	for m: ShaderMaterial in [material, mirror_material]:
		m.set_shader_parameter(&"light_map", light_map)
	mm.buffer = _buf
	mm_near.buffer = _nbuf
	mm_near.visible_instance_count = 0
	set_tier(quality)


## The two citizen meshes of the model [near, far] (1.76 m, origin at the feet, facing -Z, vertex colours = surface / piece / shadow / part tag); the box silhouette below
## is only the fallback of a checkout whose models were not imported yet.
static func _person_meshes() -> Array[Mesh]:
	var near: Mesh = null
	var far: Mesh = null
	var ps := load(MODEL) as PackedScene
	if ps != null:
		var root := ps.instantiate()
		for n in root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			if String(mi.name).begins_with("CitizenFar"):
				far = mi.mesh
			elif String(mi.name).begins_with("Citizen"):
				near = mi.mesh
		root.free()
	if near == null:
		near = _box_person_mesh()
	if far == null:
		far = near
	return [near, far]


## COLOR.r = surface (0 skin, 0.5 trousers, 1 coat), g = piece 0, b = 1 (lit), a = part tag (see the shader).
static func _box_person_mesh() -> ArrayMesh:
	var b := MB.new()
	b.uv2 = Vector2(0.0, 0.8)
	var coat := 1.0
	var legs := 0.5
	var skin := 0.0
	b.box(Vector3(-0.1, 0.45, 0.0), Vector3(0.17, 0.9, 0.2), Color(legs, 0, 1, 0.2), false)
	b.box(Vector3(0.1, 0.45, 0.0), Vector3(0.17, 0.9, 0.2), Color(legs, 0, 1, 0.4), false)
	b.box(Vector3(0.0, 1.17, 0.0), Vector3(0.46, 0.58, 0.25), Color(coat, 0, 1, 0.0))
	b.box(Vector3(0.0, 0.93, 0.0), Vector3(0.44, 0.1, 0.24), Color(legs, 0, 1, 0.0), false)
	b.box(Vector3(-0.285, 1.14, 0.0), Vector3(0.11, 0.56, 0.13), Color(coat, 0, 1, 0.6), false)
	b.box(Vector3(0.285, 1.14, 0.0), Vector3(0.11, 0.56, 0.13), Color(coat, 0, 1, 0.8), false)
	b.sphere(Vector3(0.0, 1.62, 0.0), Vector3(0.105, 0.125, 0.115), 6, 3, Color(skin, 0, 1, 0.0))
	b.box(Vector3(0.0, 1.5, 0.0), Vector3(0.12, 0.08, 0.12), Color(skin, 0, 1, 0.0), false)
	b.cylinder(Vector3(0.0, 1.5, 0.0), 0.012, 0.5, 4, Color(legs, 0, 1, 1.0), -1.0, false)
	b.cylinder(Vector3(0.0, 1.98, 0.0), 0.62, 0.1, 8, Color(coat, 0, 1, 1.0), 0.04, true)
	return b.build(null, true, true)


## The tier: pool in use, ring radius. Newly used people appear at once; the ones no longer used stay where they are (not drawn).
func set_tier(level: int, density := 1.0) -> void:
	quality = clampi(level, 0, 2)
	var n := mini(LowPlus.scaled(int(COUNTS[quality] * density), LowPlus.CROWD_SHARE, 4) if quality == 0 else int(COUNTS[quality] * density), BUILT)
	for i in range(n, count):
		_alive[i] = 0
		_unpin(i)
	for i in range(count, n):
		_alive[i] = 0
		_first[i] = 1
	count = n
	radius = RADII[quality]
	mm.visible_instance_count = count


## Everybody is put on a sidewalk again around `center` (new game, respawn, next sector).
func reset() -> void:
	for i in BUILT:
		_alive[i] = 0
		_first[i] = 1
	_hide.fill(0)
	for i in BUILT:
		_unpin(i)
	_dying.fill(0.0)
	_hp.fill(HP)
	_fled = 0


## Gunfire at `pos`: pedestrians within the shot radius run away along their sidewalk (cheap: one pass over the pool in use).
func on_shot(pos: Vector3) -> int:
	return scare_from(pos, SHOT_RADIUS[quality])


## Everybody within `r` metres of `pos` runs away from it (gunfire, explosions, a speeding car). Returns how many were sent running.
func scare_from(pos: Vector3, r: float) -> int:
	var r2 := r * r
	var n := 0
	for i in count:
		if _alive[i] == 0 or _dying[i] > 0.0:
			continue
		var p := _position(i)
		var dx := p.x - pos.x
		var dz := p.z - pos.z
		if dx * dx + dz * dz < r2:
			scare_person(i, pos)
			n += 1
	return n


## Person `i` runs away from `pos` (along its sidewalk line, away from the point's coordinate).
func scare_person(i: int, pos: Vector3) -> void:
	_unpin(i)
	var along := pos.x if _axis[i] == 0 else pos.z
	var d := signf(_u[i] - along)
	_dir[i] = d if d != 0.0 else (1.0 if rng.randf() < 0.5 else -1.0)
	_flee[i] = FLEE_TIME + rng.randf() * 2.0
	_cower[i] = 0.0
	_idle[i] = 0.0
	_look[i] = LOOK_ALONG
	_fled += 1


## Person `i` freezes and crouches for `seconds` (no walk, no animation).
func cower_person(i: int, seconds: float) -> void:
	_flee[i] = 0.0
	_idle[i] = 0.0
	_look[i] = LOOK_ALONG
	_cower[i] = seconds


## Person `i` stops for `seconds` and turns to face `toward` (pointing, listening, answering).
func attend(i: int, toward: Vector3, seconds: float) -> void:
	var p := _position(i)
	var d := toward - p
	var lat := d.z if _axis[i] == 0 else d.x
	var al := d.x if _axis[i] == 0 else d.z
	if absf(lat) >= absf(al):
		_look[i] = LOOK_LAT_POS if lat > 0.0 else LOOK_LAT_NEG
	else:
		_look[i] = LOOK_U_POS if al > 0.0 else LOOK_U_NEG
	_flee[i] = 0.0
	_cower[i] = 0.0
	_idle[i] = seconds


## What person `i` does now: &"flee", &"cower", &"linger" (at a shop or bus stop or turned to someone), &"idle" (a chat) or &"walk".
func state_of(i: int) -> StringName:
	if _alive[i] == 0:
		return &"gone"
	if _flee[i] > 0.0:
		return &"flee"
	if _cower[i] > 0.0:
		return &"cower"
	if _idle[i] > 0.0:
		return &"linger" if _look[i] != LOOK_ALONG else &"idle"
	return &"walk"


## 0 / STOP_SHOP / STOP_BUS: the stop person `i` is walking to.
func goal_kind(i: int) -> int:
	return _gkind[i]


func goal_u(i: int) -> float:
	return _goal[i]


func is_cowering(i: int) -> bool:
	return _cower[i] > 0.0


func last_stop_kind(i: int) -> int:
	return _stopk[i]


func lingers_total() -> int:
	return _lingers


## The kind of stop in span `k` of the line (axis, lateral coordinate): a pure hash, so a street keeps its shops and bus stops.
static func stop_kind(axis: int, lat: float, k: int) -> int:
	var h := ((axis + 1) * 73856093) ^ (int(roundf(lat)) * 19349663) ^ (k * 83492791)
	h = (h ^ (h >> 15)) * 0x2c1b3c6d
	h = h ^ (h >> 12)
	match (h & 0x7fffffff) % 4:
		0:
			return STOP_BUS
		1, 2:
			return STOP_SHOP
	return 0


## The next shop front / bus stop ahead of person `i` along its line (a middle of a sidewalk span); none = keep walking.
func _assign_goal(i: int) -> void:
	_gkind[i] = 0
	var d := _dir[i]
	var step := 1 if d > 0.0 else -1
	var k0 := floori((_u[i] + CityLayout.HALF + LINE_OFF) / 80.0)
	for n in 6:
		var kk := k0 + n * step
		var mid := 80.0 * float(kk) + STOP_MID - CityLayout.HALF - LINE_OFF
		if (mid - _u[i]) * d < 0.8:
			continue
		if absf(mid) > EDGE - 4.0:
			return
		var kind := stop_kind(_axis[i], _lat[i], kk)
		if kind != 0:
			_goal[i] = mid
			_gkind[i] = kind
			return


## Arrived at the stop: stand there for a while facing the shop window (shop) or the road (bus stop).
func _start_linger(i: int, kind: int) -> void:
	var building := 1 if fposmod(_lat[i] + CityLayout.HALF, 80.0) < 40.0 else -1
	var face := building if kind == STOP_SHOP else -building
	_look[i] = LOOK_LAT_POS if face > 0 else LOOK_LAT_NEG
	var r := SHOP_STAY if kind == STOP_SHOP else BUS_STAY
	_idle[i] = rng.randf_range(r.x, r.y)
	_gkind[i] = 0
	_stopk[i] = kind
	_lingers += 1


func _end_linger(i: int) -> void:
	_look[i] = LOOK_ALONG
	_assign_goal(i)


func _forward(i: int) -> Vector2:
	var lk := _look[i]
	var ax := _axis[i]
	if lk == LOOK_LAT_POS or lk == LOOK_LAT_NEG:
		var l := 1.0 if lk == LOOK_LAT_POS else -1.0
		return Vector2(0.0, l) if ax == 0 else Vector2(l, 0.0)
	var a := _dir[i]
	if lk == LOOK_U_POS or lk == LOOK_U_NEG:
		a = 1.0 if lk == LOOK_U_POS else -1.0
	return Vector2(a, 0.0) if ax == 0 else Vector2(0.0, a)


func fled_total() -> int:
	return _fled


## A person drawn by a real actor is skipped by both MultiMeshes.
func set_hidden(i: int, on: bool) -> void:
	_hide[i] = 1 if on else 0


func is_hidden(i: int) -> bool:
	return _hide[i] != 0


## Facing (yaw about +Y, model forward = -Z) and walking speed of person `i` (0 while standing, lingering or cowering), for the 3D actors.
func person_yaw(i: int) -> float:
	var f := _forward(i)
	return atan2(-f.x, -f.y)


func person_speed(i: int) -> float:
	if _idle[i] > 0.0 or _cower[i] > 0.0 or _dying[i] > 0.0:
		return 0.0
	return FLEE_SPEED if _flee[i] > 0.0 else _spd[i]


func is_alive(i: int) -> bool:
	return _alive[i] != 0 and _dying[i] <= 0.0


## A stall vendor (pinned behind his counter). A shot at him passes over the counter: the stall is a waist-high table, not a wall (director review 5, defect 5).
func is_vendor(i: int) -> bool:
	return i >= 0 and i < count and _pin[i] != 0


func is_dying(i: int) -> bool:
	return _alive[i] != 0 and _dying[i] > 0.0


func is_fleeing(i: int) -> bool:
	return _flee[i] > 0.0


func _position(i: int) -> Vector3:
	var l := _lat[i] + _off[i]
	return Vector3(_u[i], 0.0, l) if _axis[i] == 0 else Vector3(l, 0.0, _u[i])


## World position of pedestrian `i` (tests, hooks).
func person_position(i: int) -> Vector3:
	return _position(i)


## Living pedestrians within `r` metres (flat distance) of `pos`: the visual QA street check.
func count_near(pos: Vector3, r: float) -> int:
	var n := 0
	for i in count:
		if _alive[i] == 1:
			var d := _position(i) - pos
			if d.x * d.x + d.z * d.z <= r * r:
				n += 1
	return n


func alive_count() -> int:
	var n := 0
	for i in count:
		n += _alive[i]
	return n


## Slot for a new stall vendor: a free one, else the walker farthest from `center` (not a vendor, not drawn by an actor, not dying). -1 when the pool is empty.
func claim_slot(center: Vector3) -> int:
	var best := -1
	var best_d := -1.0
	for i in count:
		if _pin[i] != 0 or _hide[i] != 0 or _dying[i] > 0.0:
			continue
		if _alive[i] == 0:
			return i
		var p := _position(i) - center
		var d := p.x * p.x + p.z * p.z
		if d > best_d:
			best_d = d
			best = i
	return best


## Person `i` becomes the vendor of a stall: stands on sidewalk line `lat` of axis `axis` at `u`, offset `off` from the line, facing sideways towards the road (`face` +1 / -1).
func pin_vendor(i: int, axis: int, lat: float, u: float, off: float, face: int) -> void:
	_axis[i] = axis
	_lat[i] = lat
	_u[i] = u
	_off[i] = off
	_dir[i] = 1.0
	_spd[i] = 0.0
	_phase[i] = rng.randf() * TAU
	_flee[i] = 0.0
	_cower[i] = 0.0
	_age[i] = 0.0
	_reg[i] = _region(u)
	_alive[i] = 1
	_hp[i] = HP
	_dying[i] = 0.0
	_look[i] = LOOK_LAT_POS if face > 0 else LOOK_LAT_NEG
	_idle[i] = 1.0e9
	_gkind[i] = 0
	_first[i] = 0
	_pin[i] = 1
	_seed[i] = VENDOR_SEED


func _unpin(i: int) -> void:
	if _pin[i] != 0:
		_pin[i] = 0
		_seed[i] = _seed0[i]
		if _idle[i] > 1.0e8:
			_idle[i] = 0.0
			_look[i] = LOOK_ALONG


func is_pinned(i: int) -> bool:
	return _pin[i] != 0


func vendors_near(pos: Vector3, r: float) -> int:
	var n := 0
	for i in count:
		if _pin[i] != 0 and _alive[i] == 1:
			var d := _position(i) - pos
			if d.x * d.x + d.z * d.z <= r * r:
				n += 1
	return n


## World (x, z) of the living people who are crossing a road right now (on a zebra), written into `out` (at most its size); returns how many. The near traffic stops for them.
func fill_crossing(out: PackedVector2Array) -> int:
	var n := 0
	for i in count:
		if _alive[i] == 1 and _dying[i] <= 0.0 and (_reg[i] & 1) == 0:
			var p := _position(i)
			out[n] = Vector2(p.x, p.z)
			n += 1
			if n >= out.size():
				break
	return n


# --- being shot (scripts/npc/npc_life.gd decides the consequences) -----------------------------------------------------------

## Pose of a dying person: x the fall angle about the body's side axis (radians), y the scale (1 -> 0 while the body dissolves), z the lift of the origin.
func death_pose(i: int) -> Vector3:
	if _dying[i] <= 0.0:
		return Vector3(0.0, 1.0, 0.0)
	var t := 1.0 - _dying[i] / DIE_TIME
	var f := smoothstep(0.0, FALL_AT, t)
	var dis := smoothstep(DISSOLVE_FROM, 1.0, t)
	return Vector3(_fall[i] * f * (PI * 0.5 - 0.1), 1.0 - dis, 0.12 * f - 0.25 * dis)


## Death progress 0..1 of person i (0 not dying): tests and the look bots read it.
func death_t(i: int) -> float:
	return 0.0 if _dying[i] <= 0.0 else 1.0 - _dying[i] / DIE_TIME


func _tick_dying(i: int, delta: float, center: Vector3, r2: float) -> void:
	var was := 1.0 - _dying[i] / DIE_TIME
	_dying[i] -= delta
	_age[i] += delta
	var now := 1.0 - _dying[i] / DIE_TIME
	var p := _position(i)
	if was < DISSOLVE_FROM and now >= DISSOLVE_FROM:                       # the body starts to come apart: a column of quantum light
		FX.burst(p + Vector3(0.0, 0.9, 0.0), DISSOLVE_COLOR, 16, 3.5, 0.9, -1.2, 1.4)
	if _dying[i] <= 0.0:
		_dying[i] = 0.0
		_alive[i] = 0
		_hide[i] = 0
		_write(i, 0.0, false)
		return
	var dx := p.x - center.x
	var dz := p.z - center.z
	_write(i, 1.0, dx * dx + dz * dz < NEAR_RADIUS * NEAR_RADIUS)


## First person a ray hits within `max_t` metres: Vector3(index, t, 1 for a head shot else 0), index -1 when nobody is hit. A person is a vertical cylinder; nobody is hit from inside it.
func ray(origin: Vector3, dir: Vector3, max_t: float) -> Vector3:
	var best := Vector3(-1.0, max_t, 0.0)
	var a := dir.x * dir.x + dir.z * dir.z
	if a < 1.0e-6:
		return best
	var reach := max_t + BODY_R + 1.0
	for i in count:
		if _alive[i] == 0 or _dying[i] > 0.0:
			continue
		var p := _position(i)
		var ox := origin.x - p.x
		var oz := origin.z - p.z
		if ox * ox + oz * oz > reach * reach:
			continue
		var h := _size[i]
		var b := 2.0 * (ox * dir.x + oz * dir.z)
		var c := ox * ox + oz * oz - BODY_R * BODY_R
		if c < 0.0:
			continue
		var disc := b * b - 4.0 * a * c
		if disc < 0.0:
			continue
		var t := (-b - sqrt(disc)) / (2.0 * a)
		if t < 0.0 or t >= best.y:
			continue
		var y := origin.y + dir.y * t - p.y
		if y < 0.0 or y > BODY_H * h:
			continue
		best = Vector3(float(i), t, 1.0 if y > HEAD_FROM * h else 0.0)
	return best


## Person i takes `amount` from a source at `from`. Returns true when it killed. A hurt survivor runs.
func damage_person(i: int, amount: float, from: Vector3) -> bool:
	if _alive[i] == 0 or _dying[i] > 0.0:
		return false
	_hp[i] -= amount
	if _hp[i] <= 0.0:
		kill_person(i, from)
		return true
	scare_person(i, from)
	return false


## Person i dies now: stands still, falls away from `from`, dissolves (see death_pose), then the slot respawns elsewhere.
func kill_person(i: int, from: Vector3) -> void:
	if _alive[i] == 0 or _dying[i] > 0.0:
		return
	var p := _position(i)
	var f := _forward(i)
	var to_src := Vector2(from.x - p.x, from.z - p.z)
	_fall[i] = 1.0 if (to_src.dot(f) > 0.0 or to_src.length() < 0.1) else -1.0       # shot from the front: falls on the back; from behind: on the face
	_unpin(i)
	_hp[i] = 0.0
	_dying[i] = DIE_TIME
	_flee[i] = 0.0
	_cower[i] = 0.0
	_idle[i] = 0.0
	_look[i] = LOOK_ALONG
	_gkind[i] = 0
	killed_total += 1
	FX.burst(p + Vector3(0.0, 1.1, 0.0), DISSOLVE_COLOR, 10, 4.5, 0.45, 1.0, 1.1)       # the hit: a puff of light at the chest, the body follows


## Everybody within `r` metres (flat) of `pos` takes `amount` (a blast, a swing, a car); returns the killed. Damage falls off to 40 % at the edge.
func damage_in_radius(pos: Vector3, r: float, amount: float) -> int:
	var killed := 0
	var r2 := r * r
	for i in count:
		if _alive[i] == 0 or _dying[i] > 0.0:
			continue
		var p := _position(i)
		var dx := p.x - pos.x
		var dz := p.z - pos.z
		var d2 := dx * dx + dz * dz
		if d2 >= r2:
			continue
		if damage_person(i, amount * (1.0 - 0.6 * sqrt(d2) / maxf(r, 0.01)), pos):
			killed += 1
	return killed


static func _region(u: float) -> int:
	var s := u + CityLayout.HALF + LINE_OFF
	var k := floori(s / 80.0)
	return 2 * k + (0 if s - float(k) * 80.0 < ROAD_SPAN else 1)


func _spawn(i: int, c: Vector3, min_dist: float) -> bool:
	for attempt in 12:
		var rr := radius if rng.randf() >= CORE_SHARE else minf(radius, CORE_R)          # half of the spawns land in the core: the street around the hero is as full on MED / HIGH as on LOW
		var ax := rng.randi() & 1
		var perp := c.z if ax == 0 else c.x
		var along_c := c.x if ax == 0 else c.z
		var lo := maxi(0, ceili((perp - rr + CityLayout.HALF - LINE_OFF) / 80.0))
		var hi := mini(CityLayout.N, floori((perp + rr + CityLayout.HALF + LINE_OFF) / 80.0))
		if hi < lo:
			continue
		var k := lo + rng.randi() % (hi - lo + 1)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var line := -CityLayout.HALF + 80.0 * float(k) + side * (LINE_OFF + rng.randf_range(-0.2, 0.2))
		var dl := line - perp
		if absf(dl) >= rr:
			continue
		var half := sqrt(rr * rr - dl * dl)
		var u := along_c + rng.randf_range(-half, half)
		if absf(u) > EDGE or Vector2(dl, u - along_c).length() < min_dist:
			continue
		if fposmod(u + CityLayout.HALF + LINE_OFF, 80.0) < ROAD_SPAN + 1.5:          # only on the sidewalk spans, never in the road
			continue
		if _cam_fwd != Vector2.ZERO and rng.randf() < VIEW_BIAS:
			var to := Vector2(dl, u - along_c) if ax == 1 else Vector2(u - along_c, dl)
			if to.normalized().dot(_cam_fwd) < 0.3:
				continue
		_axis[i] = ax
		_lat[i] = line
		_u[i] = u
		_dir[i] = 1.0 if rng.randf() < 0.5 else -1.0
		_spd[i] = rng.randf_range(1.05, 1.65) if rng.randf() > 0.18 else rng.randf_range(0.55, 0.95)      # a few dawdlers; the rest a brisk, uneven mix
		_off[i] = rng.randf_range(OFF_MIN, OFF_MAX)
		_idle[i] = 0.0
		_phase[i] = rng.randf() * TAU
		_flee[i] = 0.0
		_age[i] = 0.0
		_reg[i] = _region(u)
		_alive[i] = 1
		_hp[i] = HP
		_dying[i] = 0.0
		_look[i] = LOOK_ALONG
		_cower[i] = 0.0
		_assign_goal(i)
		if rng.randf() < GROUP_CHANCE:
			_spawn_group(i)
		return true
	return false


## Two or three people stand together around person `i` (the next free slots), facing each other, until the chat ends and they drift apart.
func _spawn_group(i: int) -> void:
	var stay := rng.randf_range(8.0, 24.0)
	_idle[i] = stay
	var made := 0
	var want := 1 + (rng.randi() & 1)
	for j in range(i + 1, count):
		if made >= want:
			break
		if _alive[j] != 0:
			continue
		made += 1
		_axis[j] = _axis[i]
		_lat[j] = _lat[i]
		_off[j] = clampf(_off[i] + rng.randf_range(-0.6, 0.6), OFF_MIN, OFF_MAX)
		_u[j] = _u[i] + float(made) * rng.randf_range(0.75, 1.25) * (1.0 if (made & 1) == 1 else -1.0)
		_dir[j] = -_dir[i] if made == 1 else (1.0 if rng.randf() < 0.5 else -1.0)
		_spd[j] = rng.randf_range(1.0, 1.5)
		_phase[j] = rng.randf() * TAU
		_flee[j] = 0.0
		_age[j] = 0.0
		_idle[j] = stay + rng.randf_range(-2.0, 3.0)
		_reg[j] = _region(_u[j])
		_alive[j] = 1
		_hp[j] = HP
		_dying[j] = 0.0
		_look[j] = LOOK_ALONG
		_cower[j] = 0.0
		_gkind[j] = 0
		_first[j] = 0


## Advance everything by `delta` seconds around `center` and refresh the MultiMesh (one buffer write).
func step(delta: float, center: Vector3) -> void:
	var spawned := 0
	_nn = 0
	var r2 := radius * radius * 1.04
	_cam_fwd = Vector2.ZERO
	if is_instance_valid(Game.camera):
		var cf := -Game.camera.global_transform.basis.z
		var cv := Vector2(cf.x, cf.z)
		if cv.length_squared() > 0.04:
			_cam_fwd = cv.normalized()
	for i in count:
		if _alive[i] == 0:
			if spawned < SPAWNS_PER_STEP:
				spawned += 1
				# first fill: anywhere in the ring; later: at its outer edge, so nobody pops into the street in front of the player
				if _spawn(i, center, MIN_SPAWN if _first[i] == 1 else radius * RESPAWN_MIN):
					_first[i] = 0
			_write(i, 0.0, false)
			continue
		if _dying[i] > 0.0:
			_tick_dying(i, delta, center, r2)
			continue
		if _pin[i] != 0:                                   # a stall vendor: stands, fades in, leaves with the ring
			_age[i] += delta
			var pp := _position(i)
			var pdx := pp.x - center.x
			var pdz := pp.z - center.z
			if pdx * pdx + pdz * pdz > r2:
				_unpin(i)
				_alive[i] = 0
				_write(i, 0.0, false)
				continue
			_write(i, minf(1.0, _age[i] * 1.5), pdx * pdx + pdz * pdz < NEAR_RADIUS * NEAR_RADIUS)
			continue
		var fleeing := _flee[i] > 0.0
		var sp := FLEE_SPEED if fleeing else _spd[i]
		if fleeing:
			_idle[i] = 0.0
			_cower[i] = 0.0
			_look[i] = LOOK_ALONG
		elif _cower[i] > 0.0:
			_cower[i] -= delta                           # crouching: no walk, no animation
			sp = 0.0
		elif _idle[i] > 0.0:
			_idle[i] -= delta                            # standing: no walk, no animation
			sp = 0.0
			if _idle[i] <= 0.0 and _look[i] != LOOK_ALONG:
				_end_linger(i)
		elif rng.randf() < IDLE_CHANCE * delta:
			_idle[i] = rng.randf_range(4.0, 12.0)
		else:
			_idle[i] = 0.0
		_flee[i] = maxf(0.0, _flee[i] - delta)
		if fleeing and _flee[i] <= 0.0:
			_assign_goal(i)
		var prev_u := _u[i]
		var u := _u[i] + _dir[i] * sp * delta
		_phase[i] += sp * delta * 2.7
		_age[i] += delta
		if absf(u) > EDGE:
			_dir[i] = -_dir[i]
			u = clampf(u, -EDGE, EDGE)
			_u[i] = u
			_assign_goal(i)
		var reg := _region(u)
		if reg != _reg[i]:
			_reg[i] = reg
			if rng.randf() < TURN_CHANCE:
				# a corner: turn onto the crossing line (the corner point is where this pedestrian stands)
				var s := u + CityLayout.HALF + LINE_OFF
				var kk := floorf(s / 80.0)
				var rem := s - kk * 80.0
				var th := kk * 80.0 - CityLayout.HALF - LINE_OFF                  # the span boundary just crossed: at rem 0 / ROAD_SPAN, or at 80 when walking down
				if rem > ROAD_SPAN + 28.7:
					th += 80.0
				elif rem > LINE_OFF:
					th += ROAD_SPAN
				var old_lat := _lat[i] + _off[i]
				_lat[i] = th
				_off[i] = rng.randf_range(OFF_MIN, OFF_MAX)
				u = old_lat
				_axis[i] = 1 - _axis[i]
				_dir[i] = 1.0 if rng.randf() < 0.5 else -1.0
				_reg[i] = _region(u + _dir[i] * 0.02)
				_u[i] = u
				_assign_goal(i)
		elif _gkind[i] != 0 and not fleeing and sp > 0.0 and (prev_u - _goal[i]) * _dir[i] < 0.0 and (u - _goal[i]) * _dir[i] >= 0.0:
			u = _goal[i]
			_start_linger(i, _gkind[i])
		_u[i] = u
		var p := _position(i)
		var dx := p.x - center.x
		var dz := p.z - center.z
		if dx * dx + dz * dz > r2:
			_alive[i] = 0
			_write(i, 0.0, false)
			continue
		_write(i, minf(1.0, _age[i] * 1.5), dx * dx + dz * dz < NEAR_RADIUS * NEAR_RADIUS)
	mm.buffer = _buf
	mm_near.buffer = _nbuf
	mm_near.visible_instance_count = _nn


func _write(i: int, fade: float, near: bool) -> void:
	if _hide[i] != 0:
		_fill(_buf, i * STRIDE, i, 0.0)
		return
	if near and _nn < NEAR_CAP and _alive[i] != 0:
		_fill(_nbuf, _nn * STRIDE, i, fade)
		_nn += 1
		_fill(_buf, i * STRIDE, i, 0.0)                              # the far mesh draws nobody who is drawn near
	else:
		_fill(_buf, i * STRIDE, i, fade)


func _fill(buf: PackedFloat32Array, o: int, i: int, fade: float) -> void:
	var k := _size[i] * fade
	var f := _forward(i)
	var c := -f.y                                             # forward is -Z in the model: Basis(UP, yaw) maps it to (-s, -c)
	var s := -f.x
	var l := _lat[i] + _off[i]
	var x := _u[i] if _axis[i] == 0 else l
	var z := l if _axis[i] == 0 else _u[i]
	if _alive[i] == 0:
		x = 0.0
		z = 0.0
		k = 0.0
		s = 0.0
		c = 0.0
	var ca := 1.0
	var sa := 0.0
	var lift := 0.0
	var dying := _dying[i] > 0.0
	if dying:
		var pose := death_pose(i)
		ca = cos(pose.x)
		sa = sin(pose.x)
		k *= pose.y
		lift = pose.z
	# Basis(UP, yaw) * Basis(RIGHT, fall angle), scaled by k, row-major 3x4: standing it is [c 0 s x; 0 1 0 y; -s 0 c z]; a fallen person lies along the walking line
	buf[o] = c * k
	buf[o + 1] = s * sa * k
	buf[o + 2] = s * ca * k
	buf[o + 3] = x
	buf[o + 4] = 0.0
	buf[o + 5] = ca * k
	buf[o + 6] = -sa * k
	buf[o + 7] = lift
	buf[o + 8] = -s * k
	buf[o + 9] = c * sa * k
	buf[o + 10] = c * ca * k
	buf[o + 11] = z
	buf[o + 16] = _seed[i]
	buf[o + 17] = _phase[i]
	buf[o + 18] = 0.0 if (dying or ((_idle[i] > 0.0 or _cower[i] > 0.0) and _flee[i] <= 0.0)) else 0.5 + 0.38 * (FLEE_SPEED if _flee[i] > 0.0 else _spd[i])
	if _cower[i] > 0.0 and _flee[i] <= 0.0:
		buf[o + 18] = -1.0                                           # the shader crouches them, hands over the head
	# w: bit 0 umbrella, bit 1 (+2) a chatting group (standing, not at a shop / stop, not looking anywhere): the shader gestures and nods
	buf[o + 19] = _umb[i] + (2.0 if (_idle[i] > 0.0 and _cower[i] <= 0.0 and _flee[i] <= 0.0 and _gkind[i] == 0 and _look[i] == LOOK_ALONG) else 0.0)
