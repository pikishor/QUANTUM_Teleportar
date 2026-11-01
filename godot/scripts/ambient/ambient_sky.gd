extends RefCounted
## Overhead life: an occasional patrol airship far above the city sweeping a searchlight over the streets (one additive cone plus a flat pool of
## light on the ground, ONE draw call and only while a sweep is on), and distant sirens that follow the emergency vehicles of the far traffic.
## Everything is timed in game time (it only advances while the game plays) and resets on the lifecycle signals.

const SHADER := preload("res://assets/shaders/prop_searchlight.gdshader")

const FIRST_SWEEP := Vector2(14.0, 26.0)       ## seconds after a (re)start until the first patrol
const GAP := Vector2(45.0, 90.0)
const DURATION := 34.0
const ALTITUDE := 150.0
const AIRSHIP_SPEED := 16.0
const SIREN_GAP := Vector2(12.0, 24.0)
const SIREN_RANGE := Vector2(60.0, 260.0)
const SIREN_SOUND := &"siren"                    ## the one-shot fallback (assets/audio/siren.wav, 3 s) when the loop file is missing
const SIREN_LOOP := &"siren_loop"                ## a seamless wail (assets/audio/siren_loop.wav) played by ONE follow emitter that rides the emergency car
const SIREN_DB := -11.0
const SIREN_LIVE := 9.0                           ## seconds a siren call keeps the emitter on one car

var node: MeshInstance3D
var material: ShaderMaterial
var active := false
var enabled := true                              ## false on the LOW tier: no sweeps (the cone is the one extra draw call)
var rng := RandomNumberGenerator.new()
var sweeps := 0                                   ## sweeps started so far
var sirens := 0                                   ## siren sounds requested so far
var siren_player: AudioStreamPlayer3D             ## the follow emitter (one node, created in build)

var _next_in := 20.0
var _t := 0.0
var _p0 := Vector3.ZERO
var _dir := Vector3.RIGHT
var _swing := 0.0
var _siren_in := 15.0
var _siren_car := -1                              ## traffic index the emitter follows
var _siren_left := 0.0


func build(parent: Node3D) -> void:
	rng.seed = 777
	node = MeshInstance3D.new()
	node.name = "Searchlight"
	node.mesh = _beam_mesh()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.custom_aabb = AABB(Vector3(-400, -400, -400), Vector3(800, 800, 800))
	material = ShaderMaterial.new()
	material.shader = SHADER
	node.material_override = material
	node.visible = false
	parent.add_child(node)
	siren_player = AudioStreamPlayer3D.new()
	siren_player.name = "SirenLoop"
	siren_player.bus = Sfx.SFX_BUS
	siren_player.unit_size = 14.0
	siren_player.max_distance = 260.0
	siren_player.volume_db = SIREN_DB
	parent.add_child(siren_player)
	reset()


## Cone (apex at the origin, axis -Y, base radius 0.11 per unit of length) and a flat unit disc for the ground pool (COLOR.a = 1).
static func _beam_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var seg := 14
	for s in seg + 1:
		var a := TAU * float(s) / float(seg)
		var d := Vector3(cos(a), 0.0, sin(a))
		verts.append(Vector3.ZERO)
		norms.append(Vector3(d.x, 0.1, d.z).normalized())
		uvs.append(Vector2(float(s) / float(seg), 0.0))
		cols.append(Color(1, 1, 1, 0))
		verts.append(Vector3(d.x * 0.11, -1.0, d.z * 0.11))
		norms.append(Vector3(d.x, 0.1, d.z).normalized())
		uvs.append(Vector2(float(s) / float(seg), 1.0))
		cols.append(Color(1, 1, 1, 0))
	for s in seg:
		var i0 := s * 2
		idx.append_array([i0, i0 + 1, i0 + 2, i0 + 1, i0 + 3, i0 + 2])
	var c0 := verts.size()
	verts.append(Vector3.ZERO)
	norms.append(Vector3.UP)
	uvs.append(Vector2.ZERO)
	cols.append(Color(1, 1, 1, 1))
	for s in seg + 1:
		var a := TAU * float(s) / float(seg)
		verts.append(Vector3(cos(a), 0.0, sin(a)))
		norms.append(Vector3.UP)
		uvs.append(Vector2.ZERO)
		cols.append(Color(1, 1, 1, 1))
	for s in seg:
		idx.append_array([c0, c0 + 1 + s, c0 + 2 + s])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func reset() -> void:
	active = false
	_t = 0.0
	_next_in = rng.randf_range(FIRST_SWEEP.x, FIRST_SWEEP.y)
	_siren_in = rng.randf_range(SIREN_GAP.x, SIREN_GAP.y)
	_stop_siren()
	if node != null:
		node.visible = false


func set_enabled(on: bool) -> void:
	enabled = on
	if not on and active:
		_end()


## Begin a patrol now: the airship enters over one edge of the city and flies across it.
func start_sweep() -> void:
	var edge := rng.randi() % 4
	var along := rng.randf_range(-220.0, 220.0)
	match edge:
		0:
			_p0 = Vector3(-420.0, ALTITUDE, along)
			_dir = Vector3.RIGHT
		1:
			_p0 = Vector3(420.0, ALTITUDE, along)
			_dir = Vector3.LEFT
		2:
			_p0 = Vector3(along, ALTITUDE, -420.0)
			_dir = Vector3.BACK
		_:
			_p0 = Vector3(along, ALTITUDE, 420.0)
			_dir = Vector3.FORWARD
	_t = 0.0
	_swing = rng.randf() * TAU
	active = true
	sweeps += 1
	node.visible = true
	_place()


func _end() -> void:
	active = false
	node.visible = false
	_next_in = rng.randf_range(GAP.x, GAP.y)


func _place() -> void:
	var p := _p0 + _dir * (AIRSHIP_SPEED * _t) + Vector3(0, 6.0 * sin(_t * 0.3), 0)
	var side := Vector3(-_dir.z, 0.0, _dir.x)
	var tgt := Vector3(p.x, 0.0, p.z) + side * (55.0 * sin(_t * 0.42 + _swing)) + _dir * (34.0 * sin(_t * 0.27 + 1.3 + _swing)) + _dir * 40.0
	var up := (p - tgt).normalized()
	var sd := up.cross(Vector3.RIGHT)
	if sd.length() < 0.1:
		sd = up.cross(Vector3.FORWARD)
	sd = sd.normalized()
	var fw := sd.cross(up)
	var len := p.distance_to(tgt)
	node.transform = Transform3D(Basis(sd * len, up * len, fw * len), p)
	var fade := minf(1.0, minf(_t / 2.5, (DURATION - _t) / 3.0))
	material.set_shader_parameter(&"strength", clampf(fade, 0.0, 1.0))
	material.set_shader_parameter(&"pool_pos", tgt)
	material.set_shader_parameter(&"pool_radius", 12.0)


## Advance in game seconds. `center` is the player's position, `traffic` the far-traffic object (for the sirens), `t` the ambient clock.
func step(delta: float, center: Vector3, traffic, t: float, quality: int) -> void:
	if enabled:
		if active:
			_t += delta
			if _t >= DURATION:
				_end()
			else:
				_place()
		else:
			_next_in -= delta
			if _next_in <= 0.0:
				start_sweep()
	_follow_siren(delta, traffic, t)
	_siren_in -= delta
	if _siren_in <= 0.0:
		_siren_in = rng.randf_range(SIREN_GAP.x, SIREN_GAP.y)
		if traffic != null:
			_siren(center, traffic, t)


func _siren(center: Vector3, traffic, t: float) -> void:
	for i in traffic.count:
		if not traffic.is_emergency(i):
			continue
		var p: Vector3 = traffic.car_position(i, t)
		var d := Vector2(p.x - center.x, p.z - center.z).length()
		if d >= SIREN_RANGE.x and d <= SIREN_RANGE.y:
			sirens += 1
			if not _start_siren(i, p):
				Sfx.play_at(SIREN_SOUND, p + Vector3(0, 1.0, 0), -10.0, rng.randf_range(0.95, 1.05))
			return


## Starts the seamless wail on the follow emitter, riding traffic car `i` for SIREN_LIVE seconds. False when the loop file is missing (the caller falls back to the one-shot).
func _start_siren(i: int, p: Vector3) -> bool:
	if siren_player == null:
		return false
	if siren_player.stream == null:
		var v := Sfx.variants_of(SIREN_LOOP)
		if v.is_empty():
			return false
		siren_player.stream = v[0]
	_siren_car = i
	_siren_left = SIREN_LIVE
	siren_player.global_position = p + Vector3(0, 1.0, 0)
	siren_player.pitch_scale = rng.randf_range(0.95, 1.05)
	if not siren_player.playing:
		siren_player.play()
	return true


## Per frame while the emitter is on: it follows the car (one position lookup), fades in over 1 s and out over the last 1.5 s, and stops when the car is far away.
func _follow_siren(delta: float, traffic, t: float) -> void:
	if siren_player == null or _siren_left <= 0.0:
		return
	siren_player.stream_paused = false
	_siren_left -= delta
	var p: Vector3 = traffic.car_position(_siren_car, t) if traffic != null else Vector3.INF
	if _siren_left <= 0.0 or not p.is_finite():
		_stop_siren()
		return
	siren_player.global_position = p + Vector3(0, 1.0, 0)
	var fade := minf(minf((SIREN_LIVE - _siren_left) / 1.0, _siren_left / 1.5), 1.0)
	siren_player.volume_db = SIREN_DB - 40.0 * (1.0 - fade)


func _stop_siren() -> void:
	_siren_left = 0.0
	if siren_player != null and siren_player.playing:
		siren_player.stop()


## The city is not simulating (menu, pause, dead): the wail holds its breath.
func pause_siren() -> void:
	if siren_player != null and siren_player.playing and not siren_player.stream_paused:
		siren_player.stream_paused = true
