extends RefCounted
## Pedestrian crowd of the living city: ONE MultiMesh of simple lit silhouettes (assets/shaders/prop_crowd_core.gdshaderinc: walk cycle in the vertex
## stage, coat palette by seed, umbrellas on some) that walk the sidewalk lines of the road grid, cross the roads on the zebras, sometimes turn at a
## corner and run away from gunfire.
##
## The sidewalk lines are the two kerb-side lines of every road (11.3 m from the road centre, along x and along z); the line continues straight over
## the zebra of the crossing road, and a pedestrian that reaches a corner turns onto the crossing line with probability TURN_CHANCE. A fixed pool
## (HIGH count) lives in a ring around the player: whoever leaves it re-appears in the outer part of the ring on another sidewalk, so nothing is
## created, freed or allocated while the game runs. The tiers change the pool in use and the ring (LOW: at most 24 people and nobody beyond 40 m).

const SHADER := preload("res://assets/shaders/prop_crowd.gdshader")
const MIRROR_SHADER := preload("res://assets/shaders/prop_crowd_mirror.gdshader")
const MB := preload("res://scripts/world/mesh_builder.gd")

const BUILT := 100                       ## pool size = MultiMesh instances (the HIGH count)
const COUNTS: Array[int] = [24, 56, 100]
const RADII: Array[float] = [40.0, 70.0, 90.0]
const LINE_OFF := 11.3                   ## sidewalk line offset from the road centre (kerb at 10, building faces from 12)
const ROAD_SPAN := 22.6                  ## the part of a line that lies on a crossing road (zebra) : 2 * LINE_OFF
const MIN_SPAWN := 7.0
const TURN_CHANCE := 0.3
const FLEE_SPEED := 4.4
const FLEE_TIME := 5.0
const SHOT_RADIUS: Array[float] = [30.0, 38.0, 45.0]
const SPAWNS_PER_STEP := 10
const EDGE := 336.0
const STRIDE := 20

var mm: MultiMesh
var material: ShaderMaterial
var mirror_material: ShaderMaterial
var count := 0                           ## pool in use (tier)
var radius := 70.0
var quality := 1
var rng := RandomNumberGenerator.new()

var _u := PackedFloat32Array()           ## position along the line
var _lat := PackedFloat32Array()         ## the line (fixed coordinate)
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
var _fled := 0                           ## people sent running so far (tests, debugging)


func build(light_map: Texture2D) -> void:
	rng.seed = 424242
	mm = MB.new_multimesh(_person_mesh(), BUILT, true, true)
	for a: PackedFloat32Array in [_u, _lat, _dir, _spd, _phase, _flee, _age, _seed, _size, _umb]:
		a.resize(BUILT)
	_axis.resize(BUILT)
	_alive.resize(BUILT)
	_first.resize(BUILT)
	_first.fill(1)
	_reg.resize(BUILT)
	_buf.resize(BUILT * STRIDE)
	for i in BUILT:
		_seed[i] = rng.randf()
		_size[i] = 0.93 + 0.14 * rng.randf()
		_umb[i] = 1.0 if rng.randf() < 0.28 else 0.0
		for c in 4:
			_buf[i * STRIDE + 12 + c] = 1.0                       # white instance colour (vertex colours need one in the Compatibility renderer)
	material = ShaderMaterial.new()
	material.shader = SHADER
	mirror_material = ShaderMaterial.new()
	mirror_material.shader = MIRROR_SHADER
	for m: ShaderMaterial in [material, mirror_material]:
		m.set_shader_parameter(&"light_map", light_map)
	mm.buffer = _buf
	set_tier(quality)


## One pedestrian, 1.76 m, origin at the feet, facing -Z. COLOR.r = surface (0 skin, 0.5 trousers, 1 coat), COLOR.a = part tag (see the shader).
static func _person_mesh() -> ArrayMesh:
	var b := MB.new()
	b.uv2 = Vector2(0.0, 0.8)
	var coat := 1.0
	var legs := 0.5
	var skin := 0.0
	b.box(Vector3(-0.1, 0.45, 0.0), Vector3(0.17, 0.9, 0.2), Color(legs, 0, 0, 0.2), false)        # left leg (swings about the hip)
	b.box(Vector3(0.1, 0.45, 0.0), Vector3(0.17, 0.9, 0.2), Color(legs, 0, 0, 0.4), false)         # right leg
	b.box(Vector3(0.0, 1.17, 0.0), Vector3(0.46, 0.58, 0.25), Color(coat, 0, 0, 0.0))              # torso (coat)
	b.box(Vector3(0.0, 0.93, 0.0), Vector3(0.44, 0.1, 0.24), Color(legs, 0, 0, 0.0), false)         # hips
	b.box(Vector3(-0.285, 1.14, 0.0), Vector3(0.11, 0.56, 0.13), Color(coat, 0, 0, 0.6), false)    # left arm (swings about the shoulder)
	b.box(Vector3(0.285, 1.14, 0.0), Vector3(0.11, 0.56, 0.13), Color(coat, 0, 0, 0.8), false)      # right arm
	b.sphere(Vector3(0.0, 1.62, 0.0), Vector3(0.105, 0.125, 0.115), 6, 3, Color(skin, 0, 0, 0.0))     # head
	b.box(Vector3(0.0, 1.5, 0.0), Vector3(0.12, 0.08, 0.12), Color(skin, 0, 0, 0.0), false)          # neck
	# umbrella (tag 1.0): a shallow dome above the head and a thin shaft
	b.cylinder(Vector3(0.0, 1.5, 0.0), 0.012, 0.5, 4, Color(legs, 0, 0, 1.0), -1.0, false)
	b.cylinder(Vector3(0.0, 1.98, 0.0), 0.62, 0.1, 8, Color(coat, 0, 0, 1.0), 0.04, true)
	return b.build(null, true, true)


## The tier: pool in use, ring radius. Newly used people appear at once; the ones no longer used stay where they are (not drawn).
func set_tier(level: int) -> void:
	quality = clampi(level, 0, 2)
	var n: int = COUNTS[quality]
	for i in range(n, count):
		_alive[i] = 0
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
	_fled = 0


## Gunfire at `pos`: pedestrians within the shot radius run away along their sidewalk (cheap: one pass over the pool in use).
func on_shot(pos: Vector3) -> int:
	var r2: float = SHOT_RADIUS[quality] * SHOT_RADIUS[quality]
	var n := 0
	for i in count:
		if _alive[i] == 0:
			continue
		var p := _position(i)
		var dx := p.x - pos.x
		var dz := p.z - pos.z
		if dx * dx + dz * dz < r2:
			var along := pos.x if _axis[i] == 0 else pos.z
			var d := signf(_u[i] - along)
			_dir[i] = d if d != 0.0 else (1.0 if rng.randf() < 0.5 else -1.0)
			_flee[i] = FLEE_TIME + rng.randf() * 2.0
			n += 1
	_fled += n
	return n


func fled_total() -> int:
	return _fled


func is_alive(i: int) -> bool:
	return _alive[i] != 0


func is_fleeing(i: int) -> bool:
	return _flee[i] > 0.0


func _position(i: int) -> Vector3:
	return Vector3(_u[i], 0.0, _lat[i]) if _axis[i] == 0 else Vector3(_lat[i], 0.0, _u[i])


## World position of pedestrian `i` (tests, hooks).
func person_position(i: int) -> Vector3:
	return _position(i)


func alive_count() -> int:
	var n := 0
	for i in count:
		n += _alive[i]
	return n


static func _region(u: float) -> int:
	var s := u + 320.0 + LINE_OFF
	var k := floori(s / 80.0)
	return 2 * k + (0 if s - float(k) * 80.0 < ROAD_SPAN else 1)


func _spawn(i: int, c: Vector3, min_dist: float) -> bool:
	for attempt in 6:
		var ax := rng.randi() & 1
		var perp := c.z if ax == 0 else c.x
		var along_c := c.x if ax == 0 else c.z
		var lo := maxi(0, ceili((perp - radius + 320.0 - LINE_OFF) / 80.0))
		var hi := mini(8, floori((perp + radius + 320.0 + LINE_OFF) / 80.0))
		if hi < lo:
			continue
		var k := lo + rng.randi() % (hi - lo + 1)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var line := -320.0 + 80.0 * float(k) + side * (LINE_OFF + rng.randf_range(-0.2, 0.2))
		var dl := line - perp
		if absf(dl) >= radius:
			continue
		var half := sqrt(radius * radius - dl * dl)
		var u := along_c + rng.randf_range(-half, half)
		if absf(u) > EDGE or Vector2(dl, u - along_c).length() < min_dist:
			continue
		if fposmod(u + 320.0 + LINE_OFF, 80.0) < ROAD_SPAN + 1.5:          # only on the sidewalk spans, never in the road
			continue
		_axis[i] = ax
		_lat[i] = line
		_u[i] = u
		_dir[i] = 1.0 if rng.randf() < 0.5 else -1.0
		_spd[i] = rng.randf_range(1.05, 1.65)
		_phase[i] = rng.randf() * TAU
		_flee[i] = 0.0
		_age[i] = 0.0
		_reg[i] = _region(u)
		_alive[i] = 1
		return true
	return false


## Advance everything by `delta` seconds around `center` and refresh the MultiMesh (one buffer write).
func step(delta: float, center: Vector3) -> void:
	var spawned := 0
	var r2 := radius * radius * 1.04
	for i in count:
		if _alive[i] == 0:
			if spawned < SPAWNS_PER_STEP:
				spawned += 1
				# first fill: anywhere in the ring; later: at its outer edge, so nobody pops into the street in front of the player
				if _spawn(i, center, MIN_SPAWN if _first[i] == 1 else radius * 0.7):
					_first[i] = 0
			_write(i, 0.0)
			continue
		var sp := FLEE_SPEED if _flee[i] > 0.0 else _spd[i]
		_flee[i] = maxf(0.0, _flee[i] - delta)
		var u := _u[i] + _dir[i] * sp * delta
		_phase[i] += sp * delta * 2.7
		_age[i] += delta
		if absf(u) > EDGE:
			_dir[i] = -_dir[i]
			u = clampf(u, -EDGE, EDGE)
		var reg := _region(u)
		if reg != _reg[i]:
			_reg[i] = reg
			if rng.randf() < TURN_CHANCE:
				# a corner: turn onto the crossing line (the corner point is where this pedestrian stands)
				var s := u + 320.0 + LINE_OFF
				var kk := floorf(s / 80.0)
				var rem := s - kk * 80.0
				var th := kk * 80.0 - 320.0 - LINE_OFF                  # the span boundary just crossed: at rem 0 / ROAD_SPAN, or at 80 when walking down
				if rem > ROAD_SPAN + 28.7:
					th += 80.0
				elif rem > LINE_OFF:
					th += ROAD_SPAN
				var old_lat := _lat[i]
				_lat[i] = th
				u = old_lat
				_axis[i] = 1 - _axis[i]
				_dir[i] = 1.0 if rng.randf() < 0.5 else -1.0
				_reg[i] = _region(u + _dir[i] * 0.02)
		_u[i] = u
		var p := _position(i)
		var dx := p.x - center.x
		var dz := p.z - center.z
		if dx * dx + dz * dz > r2:
			_alive[i] = 0
			_write(i, 0.0)
			continue
		_write(i, minf(1.0, _age[i] * 1.5))
	mm.buffer = _buf


func _write(i: int, fade: float) -> void:
	var o := i * STRIDE
	var k := _size[i] * fade
	var c := 0.0
	var s := 0.0
	if _axis[i] == 0:
		s = -_dir[i]
	else:
		c = -_dir[i]
	var x := _u[i] if _axis[i] == 0 else _lat[i]
	var z := _lat[i] if _axis[i] == 0 else _u[i]
	if _alive[i] == 0:
		x = 0.0
		z = 0.0
		k = 0.0
		s = 0.0
		c = 0.0
	# Basis(UP, yaw) scaled by k, row-major 3x4: [c 0 s x; 0 1 0 y; -s 0 c z]
	_buf[o] = c * k
	_buf[o + 1] = 0.0
	_buf[o + 2] = s * k
	_buf[o + 3] = x
	_buf[o + 4] = 0.0
	_buf[o + 5] = k
	_buf[o + 6] = 0.0
	_buf[o + 7] = 0.0
	_buf[o + 8] = -s * k
	_buf[o + 9] = 0.0
	_buf[o + 10] = c * k
	_buf[o + 11] = z
	_buf[o + 16] = _seed[i]
	_buf[o + 17] = _phase[i]
	_buf[o + 18] = 0.5 + 0.38 * (FLEE_SPEED if _flee[i] > 0.0 else _spd[i])
	_buf[o + 19] = _umb[i]
