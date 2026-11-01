extends Node
## Shared visual effects: particle bursts, tracers, blasts, camera shake and beam helpers.
## Everything is pooled, so it is safe to call every frame. Colours are additive and unshaded.
##
## Cost control (BUDGETS.md): an emitter or a blast that is not playing is hidden, so an idle pool costs nothing, and none of these meshes casts a shadow
## (a CPUParticles3D that kept its MultiMesh visible and shadow-casting once used cost one draw call per emitter per shadow cascade, forever).
## Look (Direction: gritty, not toy-like): sparks are small soft round sprites that shrink as they fade, never untextured cards. A blast is a real
## explosion (scripts/fx/explosion_pool.gd): flipbook fireball, rising smoke, ground flash with a shock ring, spark streaks, debris, one pooled light,
## heat haze. Tracers have a bright head and every shot gets a star-and-cone muzzle flash. Everything scales with Game.quality (LOW fewer particles, no light).
## Effects keep animating while the game is dead or won (an explosion that kills the player must finish, never freeze on screen); the Game lifecycle
## signals (new game, respawn, next sector) clear everything.

var shake_amount := 0.0      ## 0..1, decays on its own; camera rigs read it each frame

const PARTICLE_POOL := 24
const TRACER_POOL := 20
const MUZZLE_POOL := 10
const MUZZLE_CENTRE_MAX := 0.7   ## flash scale cap at the screen centre
const MUZZLE_CENTRE_GAIN := 0.4  ## flash brightness at the screen centre
const MUZZLE_LIFE := 0.09    ## seconds a muzzle flash shows
const TRACER_LIFE := 0.14
const SPARK_SIZE := 0.16     ## metres: one spark is a small soft dot
const ExplosionPool := preload("res://scripts/fx/explosion_pool.gd")
const TRACER_SHADER := preload("res://assets/shaders/fx_tracer.gdshader")
const MUZZLE_SHADER := preload("res://assets/shaders/fx_muzzle.gdshader")

static var _soft_tex: GradientTexture2D

var _particles: Array[CPUParticles3D] = []
var _particle_left := PackedFloat32Array()
var _tracers: Array[MeshInstance3D] = []
var _tracer_left: Array[float] = []
var _muzzles: Array[MeshInstance3D] = []
var _muzzle_left := PackedFloat32Array()
var explosions: Node3D       ## the ExplosionPool (scripts/fx/explosion_pool.gd)
var _pi := 0
var _ti := 0
var _mi := 0


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
		var t := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.09, 0.09, 1.0)
		t.mesh = box
		var tm := ShaderMaterial.new()
		tm.shader = TRACER_SHADER
		t.material_override = tm
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		add_child(t)
		_tracers.append(t)
		_tracer_left.append(0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 1.2)
	for i in MUZZLE_POOL:
		var m := MeshInstance3D.new()
		m.mesh = quad
		var mm := ShaderMaterial.new()
		mm.shader = MUZZLE_SHADER
		m.material_override = mm
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.extra_cull_margin = 2.0
		m.visible = false
		add_child(m)
		_muzzles.append(m)
		_muzzle_left.append(0.0)
	explosions = ExplosionPool.new()
	explosions.name = &"Explosions"
	add_child(explosions)
	Game.new_game.connect(reset)
	Game.respawn.connect(reset)
	Game.next_sector.connect(reset)


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
			if _tracer_left[i] <= 0.0:
				_tracers[i].visible = false
			else:
				(_tracers[i].material_override as ShaderMaterial).set_shader_parameter(&"fade", _tracer_left[i] / TRACER_LIFE)
	for i in _muzzles.size():
		if _muzzle_left[i] > 0.0:
			_muzzle_left[i] -= delta
			if _muzzle_left[i] <= 0.0:
				_muzzles[i].visible = false
			else:
				(_muzzles[i].material_override as ShaderMaterial).set_shader_parameter(&"fade", _muzzle_left[i] / MUZZLE_LIFE)


## Hide every effect at once (also called on new game, respawn and next sector): nothing of an old fight stays on screen.
func reset() -> void:
	shake_amount = 0.0
	for i in _particles.size():
		_particles[i].emitting = false
		_particles[i].visible = false
		_particle_left[i] = 0.0
	for i in _tracers.size():
		_tracers[i].visible = false
		_tracer_left[i] = 0.0
	for i in _muzzles.size():
		_muzzles[i].visible = false
		_muzzle_left[i] = 0.0
	explosions.clear()


## Radial burst at a world position: `count` soft sprites flying out at up to `speed` m/s for `life` seconds. `size` scales the sprites (1 = small sparks of
## about 0.15 m; about 9 = soft fireball puffs of 1-2 m, usually with a negative `gravity` so they rise).
func burst(pos: Vector3, color: Color, count := 12, speed := 6.0, life := 0.6, gravity := 8.0, size := 1.0) -> void:
	var i := _pi
	var p := _particles[i]
	_pi = (_pi + 1) % _particles.size()
	p.global_position = pos
	var n := maxi(1, roundi(count * ExplosionPool.tier_scale(Game.quality)))
	if p.amount != n:                                  # a change reallocates the emitter's buffer: pooled bursts mostly repeat their count
		p.amount = n
	p.lifetime = maxf(0.05, life)
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -gravity, 0.0)
	p.scale_amount_min = 0.6 * size
	p.scale_amount_max = 1.6 * size
	p.color = color
	if size >= 4.0:                                    # soft fireball puffs: thin out near the lens, a screen full of additive sprites hides the world and freezes phones
		p.color.a = color.a * maxf(0.12, _near_fade(pos, 6.0))
	p.visible = true
	p.restart()
	p.emitting = true
	_particle_left[i] = p.lifetime + 0.1


## Short-lived bullet streak from a to b with a bright head, plus a muzzle flash at a (a star and a short cone along the shot).
func tracer(a: Vector3, b: Vector3, color := Color(1.0, 0.93, 0.6)) -> void:
	var i := _ti
	_ti = (_ti + 1) % _tracers.size()
	var m := _tracers[i].material_override as ShaderMaterial
	m.set_shader_parameter(&"color", Vector3(color.r, color.g, color.b))
	m.set_shader_parameter(&"fade", 1.0)
	place_beam(_tracers[i], a, b)
	_tracer_left[i] = TRACER_LIFE
	var d := b - a
	if d.length() > 0.3:
		muzzle_flash(a, d.normalized(), color)


## Star-and-cone flash at a barrel (shell-free, 0.06 s). Dimmed when the camera is right on top of it.
func muzzle_flash(pos: Vector3, dir: Vector3, color := Color(1.0, 0.85, 0.5), size := 1.5) -> void:
	var i := _mi
	_mi = (_mi + 1) % _muzzles.size()
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var x := dir.cross(up).normalized()
	var z := x.cross(dir)
	var sc := size * randf_range(0.85, 1.2)
	var gain := 1.0
	var cam := get_viewport().get_camera_3d()
	if cam != null:                                       # a flash near the screen centre (the player's own shots) is capped in size and brightness: the target stays visible
		var to := pos - cam.global_position
		var dist := to.length()
		var cosa := (-cam.global_basis.z).dot(to / maxf(dist, 0.001))
		var centre := clampf((cosa - 0.93) / 0.07, 0.0, 1.0) * clampf(1.0 - (dist - 8.0) / 30.0, 0.0, 1.0)     # 1 = on the view axis and close
		sc = minf(sc, lerpf(sc, MUZZLE_CENTRE_MAX, centre))
		gain = lerpf(1.0, MUZZLE_CENTRE_GAIN, centre)
	var node := _muzzles[i]
	node.global_transform = Transform3D(Basis(x * sc, dir * sc, z * sc), pos + dir * 0.1)
	var m := node.material_override as ShaderMaterial
	m.set_shader_parameter(&"color", Vector3(color.r * 0.5 + 0.5, color.g * 0.5 + 0.4, color.b * 0.5 + 0.15))
	m.set_shader_parameter(&"roll", randf() * TAU)
	m.set_shader_parameter(&"gain", gain)
	m.set_shader_parameter(&"fade", 1.0)
	node.visible = true
	_muzzle_left[i] = MUZZLE_LIFE


## An explosion (also teleport flashes, collapses, drone deaths): fireball, smoke, ground ring, spark streaks, debris, one light pulse, heat haze, scaled by
## `radius` and by Game.quality. `style` (optional): -1 picks by colour and size (cyan or magenta = quantum collapse with a ripple ring, radius 8 and
## up = a car wreck that burns for `burn` seconds), or pass ExplosionPool.STYLE_FIRE / STYLE_QUANTUM / STYLE_WRECK. `duration` is kept for API
## compatibility: the length follows the radius.
func blast(pos: Vector3, radius: float, color := Color(1.0, 0.54, 0.19), duration := 0.5, style := -1, burn := 0.0) -> void:
	var st := style
	var burn_s := burn
	if st < 0:
		if color.b >= 0.8:
			st = ExplosionPool.STYLE_QUANTUM
		elif radius >= 8.0:
			st = ExplosionPool.STYLE_WRECK
		else:
			st = ExplosionPool.STYLE_FIRE
	if st == ExplosionPool.STYLE_WRECK and burn_s <= 0.0:
		burn_s = 6.0
	explosions.play(pos, radius, color, st, burn_s)
	if st != ExplosionPool.STYLE_QUANTUM and radius >= 2.5:      # embers drift up out of the fire
		burst(pos + Vector3(0.0, 0.8, 0.0), Color(1.0, 0.62, 0.22), 14, radius * 0.7, 1.1, -1.6, 0.8)


## 0..1: how much of a blast effect may show for a camera this far from it. The hot core billboard and the fireball puffs fade out close to the camera
## (zero within 2 m, full at about 0.8 x the blast radius), so an explosion next to the player never fills the screen with glow.
func _near_fade(pos: Vector3, radius: float) -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 1.0
	return clampf((cam.global_position.distance_to(pos) - 2.0) / maxf(radius * 0.8, 2.0), 0.0, 1.0)


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
