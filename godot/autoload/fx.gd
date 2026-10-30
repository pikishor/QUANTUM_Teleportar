extends Node
## Shared visual effects: particle bursts, tracers, blasts, camera shake and beam helpers.
## Everything is pooled, so it is safe to call every frame. Colours are additive and unshaded.

var shake_amount := 0.0      ## 0..1, decays on its own; camera rigs read it each frame

const PARTICLE_POOL := 24
const TRACER_POOL := 20
const BLAST_POOL := 6

var _particles: Array[CPUParticles3D] = []
var _tracers: Array[MeshInstance3D] = []
var _tracer_left: Array[float] = []
var _blasts: Array[MeshInstance3D] = []
var _blast_left: Array[float] = []
var _blast_dur: Array[float] = []
var _blast_radius: Array[float] = []
var _pi := 0
var _ti := 0
var _bi := 0


func _ready() -> void:
	for i in PARTICLE_POOL:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.explosiveness = 1.0
		p.local_coords = false
		p.direction = Vector3.UP
		p.spread = 180.0
		var quad := QuadMesh.new()
		quad.size = Vector2(0.3, 0.3)
		quad.material = _additive(true)
		p.mesh = quad
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 1))
		ramp.set_color(1, Color(1, 1, 1, 0))
		p.color_ramp = ramp
		add_child(p)
		_particles.append(p)
	for i in TRACER_POOL:
		var t := make_beam(Color(1.0, 0.93, 0.6), 0.035)
		add_child(t)
		_tracers.append(t)
		_tracer_left.append(0.0)
	for i in BLAST_POOL:
		var b := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radial_segments = 20
		s.rings = 10
		b.mesh = s
		b.material_override = _additive(false)
		b.visible = false
		add_child(b)
		_blasts.append(b)
		_blast_left.append(0.0)
		_blast_dur.append(0.5)
		_blast_radius.append(5.0)


func _process(delta: float) -> void:
	shake_amount = maxf(0.0, shake_amount - delta * 2.5)
	for i in _tracers.size():
		if _tracer_left[i] > 0.0:
			_tracer_left[i] -= delta
			var m := _tracers[i].material_override as StandardMaterial3D
			m.albedo_color.a = maxf(0.0, _tracer_left[i] / 0.07)
			if _tracer_left[i] <= 0.0:
				_tracers[i].visible = false
	for i in _blasts.size():
		if _blast_left[i] > 0.0:
			_blast_left[i] -= delta
			var k := 1.0 - maxf(0.0, _blast_left[i]) / _blast_dur[i]
			_blasts[i].scale = Vector3.ONE * (0.3 + (_blast_radius[i] - 0.3) * sqrt(k))
			var m := _blasts[i].material_override as StandardMaterial3D
			m.albedo_color.a = 0.55 * (1.0 - k)
			if _blast_left[i] <= 0.0:
				_blasts[i].visible = false


## Radial spark burst at a world position.
func burst(pos: Vector3, color: Color, count := 12, speed := 6.0, life := 0.6, gravity := 8.0) -> void:
	var p := _particles[_pi]
	_pi = (_pi + 1) % _particles.size()
	p.global_position = pos
	p.amount = maxi(1, count)
	p.lifetime = maxf(0.05, life)
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -gravity, 0.0)
	p.color = color
	p.restart()
	p.emitting = true


## Short-lived bullet streak from a to b.
func tracer(a: Vector3, b: Vector3, color := Color(1.0, 0.93, 0.6)) -> void:
	var i := _ti
	_ti = (_ti + 1) % _tracers.size()
	var m := _tracers[i].material_override as StandardMaterial3D
	m.albedo_color = Color(color.r, color.g, color.b, 1.0)
	place_beam(_tracers[i], a, b)
	_tracer_left[i] = 0.07


## Expanding glow sphere (explosions, teleports, collapses).
func blast(pos: Vector3, radius: float, color := Color(1.0, 0.54, 0.19), duration := 0.5) -> void:
	var i := _bi
	_bi = (_bi + 1) % _blasts.size()
	_blasts[i].global_position = pos
	(_blasts[i].material_override as StandardMaterial3D).albedo_color = Color(color.r, color.g, color.b, 0.55)
	_blasts[i].scale = Vector3.ONE * 0.3
	_blasts[i].visible = true
	_blast_left[i] = duration
	_blast_dur[i] = duration
	_blast_radius[i] = radius


func shake(amount: float) -> void:
	shake_amount = maxf(shake_amount, clampf(amount, 0.0, 1.0))


## A thin additive beam mesh (unit length along local Z). Position it with place_beam().
func make_beam(color: Color, width := 0.06) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, width, 1.0)
	m.mesh = box
	var mat := _additive(false)
	mat.albedo_color = color
	m.material_override = mat
	m.visible = false
	return m


## Stretch a beam mesh between two world points (hides it if they coincide).
func place_beam(m: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		m.visible = false
		return
	var dir := d / length
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var basis := Basis.looking_at(dir, up) * Basis.from_scale(Vector3(1.0, 1.0, length))
	m.global_transform = Transform3D(basis, (a + b) * 0.5)
	m.visible = true


func _additive(billboard: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return m
