extends RefCounted
## Alien fauna of the living city: ONE MultiMesh (one draw, no mirror copy) of harmless creatures animated in the vertex stage
## (assets/shaders/ambient_fauna.gdshader): flocks of flyers circling above the rooftops and crawlers working the streets.
## Positions are simulated on the CPU for a small pool (tier LOW 28 / MED 48 / HIGH 72) and the buffer is rewritten in place (nothing allocated per frame).
## They react to the player: close approach or gunfire (`on_shot`) scatters flyers upward and away and sends crawlers running along their street.
## Day / night: by day fewer flyers (inactive ones are scaled to zero) and dark silhouettes, at night the creatures glow and crawlers are all out.
## There are no canals in this city, so there are no fish.

const SHADER := preload("res://assets/shaders/ambient_fauna.gdshader")
const BUILT := 72
const COUNTS: Array[int] = [28, 48, 72]
const FLOCK := 6
const RING_MIN := 22.0                   ## flocks circle from this far out (was 50: nothing lived within 40 m of the hero)
const NEAR_LEN := 55.0                   ## street crawlers are seeded within this far along the road of the hero
const RING_MAX := 150.0
const FAR := 175.0                       ## beyond this distance (xz) from the player a creature is re-seeded near him
const SHOT_RADIUS := 45.0
const APPROACH := 9.0
const ALARM_TIME := 5.0

var mm: MultiMesh
var material: ShaderMaterial
var count := 0
var night := 1.0                         ## 0 day .. 1 night, set by AmbientCity from the global shader parameter
var kind := PackedByteArray()            ## 0 flyer, 1 crawler
var pos := PackedVector3Array()
var alarm := PackedFloat32Array()        ## seconds of fright left
var active := PackedByteArray()
var _head := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _ang := PackedFloat32Array()         ## flyer: orbit angle; crawler: signed speed
var _rad := PackedFloat32Array()         ## flyer: orbit radius; crawler: lateral offset on the road
var _alt := PackedFloat32Array()
var _cen := PackedVector3Array()         ## flyer: orbit centre (x, extra rise, z); crawler: (road coordinate, axis, along)
var _flee := PackedVector3Array()
var _day_rank := PackedFloat32Array()    ## 0..1: a flyer is out while rank < day fraction
var _buf := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _time := 0.0


func build() -> void:
	_rng.seed = 7741
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _mesh()
	mm.instance_count = BUILT
	kind.resize(BUILT)
	active.resize(BUILT)
	alarm.resize(BUILT)
	_head.resize(BUILT)
	_phase.resize(BUILT)
	_ang.resize(BUILT)
	_rad.resize(BUILT)
	_alt.resize(BUILT)
	_day_rank.resize(BUILT)
	pos.resize(BUILT)
	_cen.resize(BUILT)
	_flee.resize(BUILT)
	_buf.resize(BUILT * 20)
	material = ShaderMaterial.new()
	material.shader = SHADER
	for i in BUILT:
		kind[i] = 0 if i % 5 < 3 else 1
		_phase[i] = _rng.randf()
		_day_rank[i] = _rng.randf()
		var tint := Color(0.25, 1.0, 0.85).lerp(Color(0.8, 0.35, 1.0), _rng.randf()) if kind[i] == 0 else Color(1.0, 0.55, 0.2).lerp(Color(0.5, 1.0, 0.3), _rng.randf())
		var o := i * 20
		_buf[o + 12] = tint.r
		_buf[o + 13] = tint.g
		_buf[o + 14] = tint.b
		_buf[o + 15] = 1.0
		_buf[o + 17] = _phase[i]
		_buf[o + 18] = _rng.randf_range(5.0, 8.0) if kind[i] == 0 else _rng.randf_range(10.0, 16.0)
		_seed(i, Vector3(0.0, 0.0, 0.0))
	mm.buffer = _buf
	set_tier(1)


func set_tier(level: int) -> void:
	count = COUNTS[clampi(level, 0, 2)]
	if level == 0:
		count = LowPlus.scaled(count, LowPlus.FAUNA_SHARE, 6)
	mm.visible_instance_count = count


func reset() -> void:
	_time = 0.0
	for i in BUILT:
		alarm[i] = 0.0
		_flee[i] = Vector3.ZERO


func alive_count() -> int:
	var n := 0
	for i in count:
		n += active[i]
	return n


## Place creature `i` (re)seeded in a ring around `center`. Flock members share a base angle so they fly together.
func _seed(i: int, center: Vector3) -> void:
	alarm[i] = 0.0
	_flee[i] = Vector3.ZERO
	if kind[i] == 0:
		var f := i / FLOCK
		var a := fposmod(float(f) * 2.399963 + float(int(_time / 40.0)) * 0.7, TAU)
		var r := lerpf(RING_MIN, RING_MAX, fposmod(float(f) * 0.6180339, 1.0))
		_cen[i] = Vector3(center.x + cos(a) * r + _rng.randf_range(-8.0, 8.0), 0.0, center.z + sin(a) * r + _rng.randf_range(-8.0, 8.0))
		_rad[i] = _rng.randf_range(10.0, 26.0)
		_ang[i] = _rng.randf() * TAU
		_alt[i] = _rng.randf_range(24.0, 48.0)
	else:
		var ax := _rng.randi_range(0, 1)
		var other := center.z if ax == 0 else center.x          # a road near the player's own coordinate across the street axis
		var k := clampi(roundi((other + CityLayout.HALF) / CityLayout.PITCH) + (0 if _rng.randf() < 0.7 else _rng.randi_range(-1, 1)), 0, CityLayout.N)
		var rc := CityLayout.road_center(k)
		var al := clampf((center.x if ax == 0 else center.z) + _rng.randf_range(-NEAR_LEN, NEAR_LEN), -CityLayout.HALF, CityLayout.HALF)
		_cen[i] = Vector3(rc, float(ax), al)
		_rad[i] = _rng.randf_range(-7.0, 7.0)
		_ang[i] = _rng.randf_range(0.8, 1.8) * (1.0 if _rng.randf() < 0.5 else -1.0)
		_alt[i] = 0.0
	pos[i] = _place(i)


func _place(i: int) -> Vector3:
	if kind[i] == 0:
		var c := _cen[i]
		return Vector3(c.x + cos(_ang[i]) * _rad[i], _alt[i] + c.y, c.z + sin(_ang[i]) * _rad[i])
	var c2 := _cen[i]
	if c2.y < 0.5:
		return Vector3(c2.z, 0.18, c2.x + _rad[i])
	return Vector3(c2.x + _rad[i], 0.18, c2.z)


## Gunfire (or any bang) at `at`: creatures within `r` metres panic. Returns how many were scared.
func on_shot(at: Vector3, r: float = SHOT_RADIUS) -> int:
	var n := 0
	for i in count:
		if active[i] == 0:
			continue
		var d := pos[i] - at
		d.y = 0.0
		if d.length_squared() < r * r:
			_scare(i, at)
			n += 1
	return n


func _scare(i: int, from: Vector3) -> void:
	alarm[i] = ALARM_TIME
	var d := pos[i] - from
	d.y = 0.0
	d = d.normalized() if d.length_squared() > 0.01 else Vector3.RIGHT
	if kind[i] == 0:
		_flee[i] = d * 14.0
	else:
		var ax := _cen[i].y
		var s := signf(d.z if ax < 0.5 else d.x)         # run away along the street, not through buildings
		_ang[i] = 6.0 * (s if s != 0.0 else 1.0)


func step(delta: float, player: Vector3, night_level: float) -> void:
	_time += delta
	night = night_level
	var day_frac := lerpf(1.0, 0.4, night_level)
	material.set_shader_parameter(&"ambient_time", _time)
	for i in BUILT:
		if i >= count:
			break
		var fl := kind[i] == 0
		var on := (_day_rank[i] < day_frac) if fl else true
		active[i] = 1 if on else 0
		var o := i * 20
		if not on:
			for j in 12:
				_buf[o + j] = 0.0
			continue
		var dx := pos[i].x - player.x
		var dz := pos[i].z - player.z
		var dist2 := dx * dx + dz * dz
		if dist2 > FAR * FAR:
			_seed(i, player)
			dx = pos[i].x - player.x
			dz = pos[i].z - player.z
			dist2 = dx * dx + dz * dz
		if dist2 < APPROACH * APPROACH and alarm[i] <= 0.0:
			_scare(i, player)
		var old := pos[i]
		if fl:
			_ang[i] += delta * (0.25 if alarm[i] <= 0.0 else 0.9) * (14.0 / maxf(_rad[i], 8.0))
			var c := _cen[i]
			c.x += _flee[i].x * delta
			c.z += _flee[i].z * delta
			c.y += (6.0 * delta) if alarm[i] > 0.0 else (-1.5 * delta if c.y > 0.0 else 0.0)
			c.y = clampf(c.y, 0.0, 40.0)
			_cen[i] = c
			_flee[i] *= maxf(0.0, 1.0 - delta * 0.6)
		else:
			var c2 := _cen[i]
			var sp := _ang[i]
			c2.z += sp * delta
			if absf(sp) > 2.0:
				_ang[i] = move_toward(sp, signf(sp) * 1.2, delta * 1.5)
			if absf(c2.z) > CityLayout.HALF:
				c2.z = clampf(c2.z, -CityLayout.HALF, CityLayout.HALF)
				_ang[i] = -_ang[i]
			_cen[i] = c2
		alarm[i] = maxf(0.0, alarm[i] - delta)
		var p := _place(i)
		pos[i] = p
		var v := p - old
		if v.x * v.x + v.z * v.z > 1e-8:
			_head[i] = atan2(-v.x, -v.z)
		var h := _head[i]
		var s := (0.9 if fl else 0.55)
		var cs := cos(h) * s
		var sn := sin(h) * s
		_buf[o] = cs
		_buf[o + 1] = 0.0
		_buf[o + 2] = sn
		_buf[o + 3] = p.x
		_buf[o + 4] = 0.0
		_buf[o + 5] = s
		_buf[o + 6] = 0.0
		_buf[o + 7] = p.y
		_buf[o + 8] = -sn
		_buf[o + 9] = 0.0
		_buf[o + 10] = cs
		_buf[o + 11] = p.z
		_buf[o + 16] = float(kind[i])
		_buf[o + 19] = clampf(alarm[i] / ALARM_TIME * 2.0, 0.0, 1.0)
	mm.buffer = _buf


## A winged body: centre triangle strip plus two wing triangles per side (UV2.x = side, UV2.y = tip weight).
static func _mesh() -> ArrayMesh:
	var v := PackedVector3Array([
		Vector3(0.0, 0.0, -0.7), Vector3(-0.18, 0.0, 0.2), Vector3(0.18, 0.0, 0.2),
		Vector3(-0.15, 0.0, -0.2), Vector3(-1.3, 0.0, 0.1), Vector3(-0.15, 0.0, 0.3),
		Vector3(0.15, 0.0, -0.2), Vector3(1.3, 0.0, 0.1), Vector3(0.15, 0.0, 0.3)])
	var uv2 := PackedVector2Array([
		Vector2(0, 0), Vector2(0, 0), Vector2(0, 0),
		Vector2(-1, 0), Vector2(-1, 1), Vector2(-1, 0),
		Vector2(1, 0), Vector2(1, 1), Vector2(1, 0)])
	var norms := PackedVector3Array()
	for i in v.size():
		norms.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-1300, -4, -1300), Vector3(2600, 140, 2600))
	return mesh
