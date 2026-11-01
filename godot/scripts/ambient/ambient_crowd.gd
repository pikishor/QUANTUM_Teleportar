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
const ARCHETYPES := 6                    ## the shader shows archetype floor(seed * 5.999) of the citizen mesh
const BUILT := 100                       ## pool size = MultiMesh instances (the HIGH count)
const COUNTS: Array[int] = [24, 48, 100]
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
const OFF_MIN := -0.75                   ## lateral offset range around the sidewalk line (metres)
const OFF_MAX := 0.62
const GROUP_CHANCE := 0.22               ## a fresh spawn that starts a little group chatting on the pavement (2-3 people, facing each other)
const IDLE_CHANCE := 0.012               ## per second, for a walker: stop for a moment

var mm: MultiMesh
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
var _fled := 0                           ## people sent running so far (tests, debugging)


func build(light_map: Texture2D) -> void:
	rng.seed = 424242
	mm = MB.new_multimesh(_person_mesh(), BUILT, true, true)
	for a: PackedFloat32Array in [_u, _lat, _off, _idle, _dir, _spd, _phase, _flee, _age, _seed, _size, _umb]:
		a.resize(BUILT)
	_axis.resize(BUILT)
	_alive.resize(BUILT)
	_first.resize(BUILT)
	_first.fill(1)
	_reg.resize(BUILT)
	_buf.resize(BUILT * STRIDE)
	for i in BUILT:
		_seed[i] = (float(i % ARCHETYPES) + 0.02 + 0.96 * rng.randf()) / float(ARCHETYPES)        # archetype = i % 6 (an even mix), the rest of the seed picks the palette
		_size[i] = 0.93 + 0.14 * rng.randf()
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
	set_tier(quality)


## The citizen mesh of the model (1.76 m, origin at the feet, facing -Z, vertex colours = surface / piece / shadow / part tag); the box silhouette below is only the
## fallback of a checkout whose models were not imported yet.
static func _person_mesh() -> Mesh:
	var ps := load(MODEL) as PackedScene
	if ps != null:
		var root := ps.instantiate()
		var found: Mesh = null
		var stack: Array[Node] = [root]
		while not stack.is_empty() and found == null:
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				found = (n as MeshInstance3D).mesh
			stack.append_array(n.get_children())
		root.free()
		if found != null:
			return found
	return _box_person_mesh()


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
	var l := _lat[i] + _off[i]
	return Vector3(_u[i], 0.0, l) if _axis[i] == 0 else Vector3(l, 0.0, _u[i])


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
		_spd[i] = rng.randf_range(1.05, 1.65) if rng.randf() > 0.18 else rng.randf_range(0.55, 0.95)      # a few dawdlers; the rest a brisk, uneven mix
		_off[i] = rng.randf_range(OFF_MIN, OFF_MAX)
		_idle[i] = 0.0
		_phase[i] = rng.randf() * TAU
		_flee[i] = 0.0
		_age[i] = 0.0
		_reg[i] = _region(u)
		_alive[i] = 1
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
		_first[j] = 0


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
		if _idle[i] > 0.0 and _flee[i] <= 0.0:
			_idle[i] -= delta                            # standing: no walk, no animation
			sp = 0.0
		elif _flee[i] <= 0.0 and rng.randf() < IDLE_CHANCE * delta:
			_idle[i] = rng.randf_range(4.0, 12.0)
		else:
			_idle[i] = 0.0
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
				var old_lat := _lat[i] + _off[i]
				_lat[i] = th
				_off[i] = rng.randf_range(OFF_MIN, OFF_MAX)
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
	var l := _lat[i] + _off[i]
	var x := _u[i] if _axis[i] == 0 else l
	var z := l if _axis[i] == 0 else _u[i]
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
	_buf[o + 18] = 0.0 if (_idle[i] > 0.0 and _flee[i] <= 0.0) else 0.5 + 0.38 * (FLEE_SPEED if _flee[i] > 0.0 else _spd[i])
	_buf[o + 19] = _umb[i]
