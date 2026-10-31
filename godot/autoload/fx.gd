extends Node
## Shared visual effects: particle bursts, tracers, blasts, camera shake and beam helpers.
## Everything is pooled, so it is safe to call every frame. Colours are additive and unshaded.
##
## Cost control (BUDGETS.md): an emitter or a blast that is not playing is hidden, so an idle pool costs nothing, and none of these meshes casts a shadow
## (a CPUParticles3D that kept its MultiMesh visible and shadow-casting once used cost one draw call per emitter per shadow cascade, forever).
## Look (Direction: gritty, not toy-like): sparks are small soft round sprites that shrink as they fade, never untextured cards; a blast is a hollow glowing
## shell (assets/shaders/blast.gdshader) with a hot core and a real light pulse that lights the wet street around it.

var shake_amount := 0.0      ## 0..1, decays on its own; camera rigs read it each frame

const PARTICLE_POOL := 24
const TRACER_POOL := 20
const BLAST_POOL := 6
const FLASH_LIGHTS := 2
const SPARK_SIZE := 0.16     ## metres: one spark is a small soft dot
const BLAST_SHADER := preload("res://assets/shaders/blast.gdshader")

static var _soft_tex: GradientTexture2D

var _particles: Array[CPUParticles3D] = []
var _particle_left := PackedFloat32Array()
var _tracers: Array[MeshInstance3D] = []
var _tracer_left: Array[float] = []
var _blasts: Array[MeshInstance3D] = []
var _blast_cores: Array[MeshInstance3D] = []
var _blast_left: Array[float] = []
var _blast_dur: Array[float] = []
var _blast_radius: Array[float] = []
var _lights: Array[OmniLight3D] = []
var _light_left := PackedFloat32Array()
var _light_dur := PackedFloat32Array()
var _light_peak := PackedFloat32Array()
var _pi := 0
var _ti := 0
var _bi := 0
var _li := 0


func _ready() -> void:
	var spark_mat := _additive(true)
	spark_mat.albedo_texture = _soft_texture()
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.1))
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.add_point(0.35, Color(1.0, 1.0, 1.0, 0.85))
	ramp.set_color(ramp.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	for i in PARTICLE_POOL:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.visible = false
		p.explosiveness = 1.0
		p.local_coords = false
		p.direction = Vector3.UP
		p.spread = 180.0
		p.damping_min = 1.0
		p.damping_max = 3.0
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.6
		p.scale_amount_curve = shrink
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var quad := QuadMesh.new()
		quad.size = Vector2(SPARK_SIZE, SPARK_SIZE)
		quad.material = spark_mat
		p.mesh = quad
		p.color_ramp = ramp
		add_child(p)
		_particles.append(p)
		_particle_left.append(0.0)
	for i in TRACER_POOL:
		var t := make_beam(Color(1.0, 0.93, 0.6), 0.035)
		add_child(t)
		_tracers.append(t)
		_tracer_left.append(0.0)
	var core_mat := _additive(true)
	core_mat.albedo_texture = _soft_texture()
	for i in BLAST_POOL:
		var b := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 1.0                                # unit sphere: the node's scale is the blast radius, like the prototype
		s.height = 2.0
		s.radial_segments = 24
		s.rings = 12
		b.mesh = s
		var sm := ShaderMaterial.new()
		sm.shader = BLAST_SHADER
		b.material_override = sm
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.visible = false
		add_child(b)
		var core := MeshInstance3D.new()                # the hot flash in the middle: a soft billboard, it scales with the shell
		var cq := QuadMesh.new()
		cq.size = Vector2(1.7, 1.7)
		core.mesh = cq
		core.material_override = core_mat.duplicate()
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.add_child(core)
		_blasts.append(b)
		_blast_cores.append(core)
		_blast_left.append(0.0)
		_blast_dur.append(0.5)
		_blast_radius.append(5.0)
	for i in FLASH_LIGHTS:
		var l := OmniLight3D.new()
		l.shadow_enabled = false
		l.omni_attenuation = 1.4
		l.light_energy = 0.0
		l.visible = false
		add_child(l)
		_lights.append(l)
		_light_left.append(0.0)
		_light_dur.append(0.4)
		_light_peak.append(4.0)


func _process(delta: float) -> void:
	shake_amount = maxf(0.0, shake_amount - delta * 2.5)
	for i in _particles.size():
		if _particle_left[i] > 0.0:
			_particle_left[i] -= delta
			if _particle_left[i] <= 0.0:
				_particles[i].emitting = false
				_particles[i].visible = false
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
			var fade := 1.0 - k
			(_blasts[i].material_override as ShaderMaterial).set_shader_parameter(&"strength", 0.55 * fade)
			(_blast_cores[i].material_override as StandardMaterial3D).albedo_color.a = fade * fade
			if _blast_left[i] <= 0.0:
				_blasts[i].visible = false
	for i in _lights.size():
		if _light_left[i] > 0.0:
			_light_left[i] -= delta
			if _light_left[i] <= 0.0:
				_lights[i].visible = false
			else:
				var f := _light_left[i] / _light_dur[i]
				_lights[i].light_energy = _light_peak[i] * f * f


## Radial burst at a world position: `count` soft sprites flying out at up to `speed` m/s for `life` seconds. `size` scales the sprites (1 = small sparks of
## about 0.15 m; about 9 = soft fireball puffs of 1-2 m, usually with a negative `gravity` so they rise).
func burst(pos: Vector3, color: Color, count := 12, speed := 6.0, life := 0.6, gravity := 8.0, size := 1.0) -> void:
	var i := _pi
	var p := _particles[i]
	_pi = (_pi + 1) % _particles.size()
	p.global_position = pos
	var n := maxi(1, count)
	if p.amount != n:                                  # a change reallocates the emitter's buffer: pooled bursts mostly repeat their count
		p.amount = n
	p.lifetime = maxf(0.05, life)
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -gravity, 0.0)
	p.scale_amount_min = 0.6 * size
	p.scale_amount_max = 1.6 * size
	p.color = color
	p.visible = true
	p.restart()
	p.emitting = true
	_particle_left[i] = p.lifetime + 0.1


## Short-lived bullet streak from a to b.
func tracer(a: Vector3, b: Vector3, color := Color(1.0, 0.93, 0.6)) -> void:
	var i := _ti
	_ti = (_ti + 1) % _tracers.size()
	var m := _tracers[i].material_override as StandardMaterial3D
	m.albedo_color = Color(color.r, color.g, color.b, 1.0)
	place_beam(_tracers[i], a, b)
	_tracer_left[i] = 0.07


## Expanding glow shell with a hot core and a light pulse (explosions, teleports, collapses).
func blast(pos: Vector3, radius: float, color := Color(1.0, 0.54, 0.19), duration := 0.5) -> void:
	var i := _bi
	_bi = (_bi + 1) % _blasts.size()
	_blasts[i].global_position = pos
	(_blasts[i].material_override as ShaderMaterial).set_shader_parameter(&"tint", color)
	var core_color := color.lerp(Color(1.0, 0.95, 0.85), 0.55)
	(_blast_cores[i].material_override as StandardMaterial3D).albedo_color = Color(core_color.r * 1.3, core_color.g * 1.3, core_color.b * 1.3, 1.0)
	_blasts[i].scale = Vector3.ONE * 0.3
	_blasts[i].visible = true
	_blast_left[i] = duration
	_blast_dur[i] = duration
	_blast_radius[i] = radius
	# the light pulse: the street around a blast really lights up (omni lights cost nothing while they are hidden)
	var li := _li
	_li = (_li + 1) % _lights.size()
	var l := _lights[li]
	l.global_position = pos + Vector3(0.0, 0.8, 0.0)
	l.light_color = color.lerp(Color.WHITE, 0.25)
	l.omni_range = clampf(radius * 3.0 + 5.0, 8.0, 36.0)
	_light_peak[li] = clampf(radius * 0.9, 2.0, 8.0)
	_light_dur[li] = maxf(0.1, duration * 0.9)
	_light_left[li] = _light_dur[li]
	l.light_energy = _light_peak[li]
	l.visible = true


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
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	m.disable_receive_shadows = true
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true                  # the particle scale curve and the blast core follow their node's scale
	return m


## One soft round dot (radial gradient, procedural: no import, no file), shared by every spark and blast core.
static func _soft_texture() -> GradientTexture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		g.add_point(0.3, Color(1.0, 1.0, 1.0, 0.55))
		g.set_color(g.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft_tex = t
	return _soft_tex
