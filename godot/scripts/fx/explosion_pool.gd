extends Node3D
## Pooled explosions for FX.blast / Game.explode. A slot is one explosion: a fireball billboard (additive, flipbook heat ramp), a few dark smoke puffs that
## rise and expand (alpha blended, same flipbook), a flat ground flash with a shock ring on the street (never a sphere), velocity-stretched spark
## streaks and falling debris. Nothing is created after _ready(); an idle slot is hidden and costs no draw call.
## Cost per explosion at most: 1 fire + 3 smoke + 1 ground + 1 sparks + 1 debris = 7 draws (LOW 1+1+1+1+1, MED 1+2+1+1+1). The quantum collapse swaps the
## fire/smoke for a cyan or magenta flash with a ripple ring. A wrecked car (`burn` seconds) keeps a small flame, a smoke column and a flickering light.
## Fill rate: every near-camera layer fades out with the distance to the camera (FX._near_fade), so a blast next to the player never fills the screen,
## and every slot ends by itself (the maximum age is `total`), also while the game is paused-then-dead; Game lifecycle signals clear everything.
## One OmniLight3D is shared by all slots (MED and HIGH only). A global shader uniform `fx_heat` drives a heat-haze ripple in post_film.gdshader.

const SLOTS := 4
const PUFFS := 3
const FLIP := preload("res://assets/textures/fx_flipbook.png")
const FIRE_SHADER := preload("res://assets/shaders/fx_fire.gdshader")
const SMOKE_SHADER := preload("res://assets/shaders/fx_smoke.gdshader")
const GROUND_SHADER := preload("res://assets/shaders/fx_ground.gdshader")
const STREAK_SHADER := preload("res://assets/shaders/fx_streak.gdshader")
const ORANGE := Color(1.0, 0.5, 0.12)
const SMOKE_TINT := Color(0.5, 0.46, 0.44)
const STYLE_FIRE := 0
const STYLE_QUANTUM := 1
const STYLE_WRECK := 2
const SPARKS := 72
const DEBRIS := 22
const GROUND_Y := 0.1                                     ## the ring lies just above the street (kerbs are about 0.15)
const HEAT_PARAM := &"fx_heat"

class Slot:
	extends RefCounted
	var root: Node3D
	var fire: MeshInstance3D
	var fire_mat: ShaderMaterial
	var puffs: Array[MeshInstance3D] = []
	var puff_mats: Array[ShaderMaterial] = []
	var puff_drift := PackedVector3Array()
	var puff_delay := PackedFloat32Array()
	var ground: MeshInstance3D
	var ground_mat: ShaderMaterial
	var sparks: CPUParticles3D
	var debris: CPUParticles3D
	var active := false
	var serial := 0
	var age := 0.0
	var total := 0.0
	var pos := Vector3.ZERO
	var radius := 5.0
	var style := STYLE_FIRE
	var small := false
	var burn := 0.0
	var fire_t := 1.0
	var ring_t := 0.8
	var smoke_t := 2.0
	var n_puffs := 0
	var fire_size := 6.0
	var glow := 1.0

var slots: Array[Slot] = []
var light: OmniLight3D
var _serial := 0
var _light_owner := -1
var _light_t := 0.0
var _light_dur := 0.4
var _light_peak := 4.0
var _heat_on := false
var _heat_value := Vector4.ZERO


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	RenderingServer.global_shader_parameter_add(HEAT_PARAM, RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)    # read by post_film.gdshader
	var unit_quad := QuadMesh.new()
	unit_quad.size = Vector2.ONE
	var ground_quad := QuadMesh.new()
	ground_quad.size = Vector2.ONE
	ground_quad.orientation = PlaneMesh.FACE_Y
	var spark_mesh := QuadMesh.new()
	spark_mesh.size = Vector2(0.07, 0.6)
	var spark_mat := ShaderMaterial.new()
	spark_mat.shader = STREAK_SHADER
	spark_mesh.material = spark_mat
	var debris_mesh := BoxMesh.new()
	debris_mesh.size = Vector3(0.34, 0.2, 0.26)
	var debris_mat := StandardMaterial3D.new()
	debris_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debris_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debris_mat.vertex_color_use_as_albedo = true
	debris_mesh.material = debris_mat
	for i in SLOTS:
		var s := Slot.new()
		s.root = Node3D.new()
		s.root.visible = false
		add_child(s.root)
		s.fire = _layer(s.root, unit_quad, FIRE_SHADER)
		s.fire_mat = s.fire.material_override as ShaderMaterial
		for k in PUFFS:
			var p := _layer(s.root, unit_quad, SMOKE_SHADER)
			s.puffs.append(p)
			s.puff_mats.append(p.material_override as ShaderMaterial)
			s.puff_drift.append(Vector3.ZERO)
			s.puff_delay.append(0.0)
		s.ground = _layer(s.root, ground_quad, GROUND_SHADER)
		s.ground_mat = s.ground.material_override as ShaderMaterial
		s.sparks = _particles(spark_mesh, SPARKS, _spark_ramp())
		s.sparks.particle_flag_align_y = true
		s.root.add_child(s.sparks)
		s.debris = _particles(debris_mesh, DEBRIS, _debris_ramp())
		s.debris.particle_flag_rotate_y = true
		s.debris.angular_velocity_min = -540.0
		s.debris.angular_velocity_max = 540.0
		s.root.add_child(s.debris)
		slots.append(s)
	light = OmniLight3D.new()
	light.shadow_enabled = false
	light.omni_attenuation = 1.4
	light.light_energy = 0.0
	light.visible = false
	add_child(light)
	set_process(false)


func _layer(parent: Node3D, mesh: Mesh, shader: Shader) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	var sm := ShaderMaterial.new()
	sm.shader = shader
	if shader != GROUND_SHADER:
		sm.set_shader_parameter(&"flip", FLIP)
	m.material_override = sm
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.extra_cull_margin = 16.0                              # the billboard is scaled in the vertex shader: never cull it by its small unit AABB
	m.visible = false
	parent.add_child(m)
	return m


func _particles(mesh: Mesh, amount: int, ramp: Gradient) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.visible = false
	p.explosiveness = 1.0
	p.local_coords = false
	p.amount = amount
	p.set_meta(&"max_amount", amount)
	p.mesh = mesh
	p.direction = Vector3.UP
	p.spread = 72.0
	p.randomness = 0.5
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.25))
	p.scale_amount_curve = shrink
	return p


static func _spark_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.97, 0.85, 1.0))
	g.add_point(0.3, Color(1.0, 0.7, 0.3, 0.9))
	g.set_color(g.get_point_count() - 1, Color(1.0, 0.35, 0.1, 0.0))
	return g


static func _debris_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.55, 0.2, 1.0))              # glowing hot at the start, then charcoal
	g.add_point(0.45, Color(0.6, 0.24, 0.08, 1.0))
	g.add_point(0.8, Color(0.12, 0.1, 0.09, 1.0))
	g.set_color(g.get_point_count() - 1, Color(0.05, 0.05, 0.05, 0.0))
	return g


## Number of slots in use at this graphics tier: LOW 2, MED 3, HIGH 4.
static func slot_limit(tier: int) -> int:
	return 2 + clampi(tier, 0, 2) if tier > 0 else 2


## Smoke puffs per large explosion at this tier: LOW 1, MED 2, HIGH 3.
static func puff_count(tier: int) -> int:
	return 1 + clampi(tier, 0, 2)


## Particle count multiplier at this tier (sparks, debris, bursts).
static func tier_scale(tier: int) -> float:
	return [0.5, 0.8, 1.0][clampi(tier, 0, 2)]


## Start an explosion. style STYLE_FIRE / STYLE_QUANTUM / STYLE_WRECK (a burning car: `burn` seconds of flame and smoke).
func play(pos: Vector3, radius: float, color: Color, style := STYLE_FIRE, burn := 0.0) -> void:
	var tier := Game.quality
	var limit := slot_limit(tier)
	var s: Slot = null
	for i in limit:
		if not slots[i].active:
			s = slots[i]
			break
	if s == null:
		s = slots[0]
		for i in limit:
			if slots[i].serial < s.serial:
				s = slots[i]
	_serial += 1
	s.serial = _serial
	var r := clampf(radius, 0.6, 14.0)
	var quantum := style == STYLE_QUANTUM
	s.active = true
	s.age = 0.0
	s.pos = pos
	s.radius = r
	s.style = style
	s.small = r < 3.2
	s.burn = burn if style == STYLE_WRECK else 0.0
	s.fire_t = 0.8 if quantum else clampf(0.45 + 0.09 * r, 0.5, 1.3)
	s.ring_t = s.fire_t * (1.1 if quantum else 0.85)
	s.smoke_t = 0.0 if quantum else clampf(2.1 + 0.12 * r, 2.4, 3.6)
	s.n_puffs = 0 if quantum else (1 if s.small else mini(PUFFS, puff_count(tier)))
	s.fire_size = r * (2.1 if quantum else 1.5)
	s.glow = 1.0
	var mid := color if quantum else color.lerp(ORANGE, 0.4)
	var lo := Color(mid.r * 0.3, mid.g * 0.12, mid.b * 0.1) if not quantum else Color(0.5, 0.05, 0.7)      # the collapse: a cyan core burning out into magenta
	var hot := mid.lerp(Color(1.0, 0.95, 0.85), 0.8)
	s.total = maxf(s.fire_t, maxf(s.ring_t, s.smoke_t + 0.4))
	s.total = maxf(s.total, 0.65 + 0.045 * r if quantum else 1.4 + 0.02 * r)       # the particles of the slot outlive the layers
	if s.burn > 0.0:
		s.total = maxf(s.total, s.burn)
	s.root.visible = true
	# the fireball: centre lifted so the lower edge of the flipbook blob just reaches the street
	s.fire_mat.set_shader_parameter(&"c_lo", lo)
	s.fire_mat.set_shader_parameter(&"c_mid", mid)
	s.fire_mat.set_shader_parameter(&"c_hot", hot)
	s.fire_mat.set_shader_parameter(&"roll", randf() * TAU)
	s.fire_mat.set_shader_parameter(&"gain", 2.4 if quantum else 2.0)
	var floor_y := 0.05 if pos.y < 4.0 else -1000.0
	s.fire_mat.set_shader_parameter(&"floor_y", floor_y)
	s.fire_mat.set_shader_parameter(&"fade_h", s.fire_size * 0.25)
	s.fire.scale = Vector3(s.fire_size, s.fire_size, s.fire_size)
	s.fire.global_position = pos + Vector3(0.0, r * 0.3, 0.0)
	s.fire.visible = true
	# smoke
	for k in PUFFS:
		var p := s.puffs[k]
		if k < s.n_puffs:
			var ang := randf() * TAU
			s.puff_drift[k] = Vector3(cos(ang), 0.0, sin(ang)) * r * randf_range(0.04, 0.16)
			s.puff_delay[k] = 0.1 * k + randf() * 0.05
			s.puff_mats[k].set_shader_parameter(&"roll", randf() * TAU)
			s.puff_mats[k].set_shader_parameter(&"tint", SMOKE_TINT)
			s.puff_mats[k].set_shader_parameter(&"floor_y", floor_y)
			s.puff_mats[k].set_shader_parameter(&"fade_h", r * 0.4)
			s.puff_mats[k].set_shader_parameter(&"glow_color", mid)
			p.global_position = pos + Vector3(0.0, r * 0.3, 0.0)
		p.visible = false
	# ground flash and shock ring
	var gs := r * 2.3
	s.ground.scale = Vector3(gs, 1.0, gs)
	s.ground.global_position = Vector3(pos.x, GROUND_Y if pos.y < 4.0 else pos.y, pos.z)
	s.ground_mat.set_shader_parameter(&"tint", mid)
	s.ground_mat.set_shader_parameter(&"ring2", 1.0 if quantum else 0.0)
	s.ground_mat.set_shader_parameter(&"t", 0.0)
	s.ground.visible = true
	# sparks and debris (a few discrete counts per emitter)
	var ts := tier_scale(tier)
	var big := clampf(0.3 + r / 9.0 * 0.7, 0.3, 1.0)
	_shoot(s.sparks, pos + Vector3(0.0, 0.4, 0.0), r * 0.9, r * 2.4 if not quantum else r * 1.6, 0.5 + 0.045 * r, 14.0 if not quantum else 2.0,
			big * ts, hot if quantum else Color.WHITE, 0.7 if quantum else 1.0)       # the quad is 0.05 x 0.5 m: scale 1 = a half metre streak
	if quantum:
		s.debris.visible = false
		s.debris.emitting = false
	else:
		_shoot(s.debris, pos + Vector3(0.0, 0.5, 0.0), r * 0.5, r * 1.1 + 2.0, 1.0 + 0.02 * r, 16.0, (0.45 if s.small else big) * ts, Color.WHITE, 1.0)
	# the light pulse (one shared light, none on LOW)
	if tier > 0 and (not s.small or r >= 2.0):
		_light_owner = slots.find(s)
		light.global_position = pos + Vector3(0.0, 0.9, 0.0)
		light.light_color = mid.lerp(Color.WHITE, 0.25)
		light.omni_range = clampf(r * 3.0 + 5.0, 8.0, 36.0)
		_light_peak = clampf(r * 0.9, 2.0, 8.0)
		_light_dur = maxf(0.2, s.fire_t * 0.8)
		_light_t = _light_dur
		light.light_energy = _light_peak
		light.visible = true
	_step(s, 0.0)                                           # first frame: progress and alpha are set before anything is drawn
	set_process(true)


## 0..1: how much of a layer of this world size may show for a camera at this position. A billboard that would cover most of the screen fades out
## (nothing below 0.45 x its size, full at 1.1 x its size), so a blast next to the player never whites the screen out; sparks, ring, light and shake remain.
func _cover_fade(pos: Vector3, size: float) -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 1.0
	var k := cam.global_position.distance_to(pos) / maxf(size, 0.5)
	return smoothstep(0.45, 1.1, k)


func _shoot(p: CPUParticles3D, at: Vector3, v_min: float, v_max: float, life: float, grav: float, ratio: float, color: Color, scale_mul: float) -> void:
	p.global_position = at
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.lifetime = life
	p.gravity = Vector3(0.0, -grav, 0.0)
	var n := maxi(4, roundi(p.get_meta(&"max_amount") * snappedf(clampf(ratio, 0.1, 1.0), 0.25)))   # a few discrete counts: a change reallocates the emitter
	if p.amount != n:
		p.amount = n
	p.scale_amount_min = scale_mul * 0.6
	p.scale_amount_max = scale_mul * 1.3
	p.color = color
	p.visible = true
	p.restart()
	p.emitting = true


func _process(delta: float) -> void:
	var any := false
	for s in slots:
		if s.active:
			_step(s, delta)
			any = true
	if _light_t > 0.0:
		_light_t -= delta
		if _light_t <= 0.0:
			light.visible = false
			light.light_energy = 0.0
			_light_owner = -1
		else:
			var f := _light_t / _light_dur
			light.light_energy = _light_peak * f * f
		any = true
	elif _light_owner >= 0 and slots[_light_owner].active and slots[_light_owner].burn > 0.0:
		# a burning wreck keeps flickering low
		var s := slots[_light_owner]
		var fade := clampf((s.burn - s.age) / 1.5, 0.0, 1.0)
		light.visible = fade > 0.0 and Game.quality > 0
		light.light_energy = (1.0 + 0.5 * sin(s.age * 17.0) * sin(s.age * 6.3)) * 1.4 * fade
		light.light_color = Color(1.0, 0.5, 0.2)
		light.omni_range = 11.0
		any = true
	_update_heat()
	if not any and not _heat_on:
		set_process(false)


func _step(s: Slot, dt: float) -> void:
	s.age += dt
	var a := s.age
	if a >= s.total + 0.3:
		_stop(s)
		return
	var r := s.radius
	var near := _cover_fade(s.pos + Vector3(0.0, r * 0.3, 0.0), s.fire_size)
	var ring_near := FX._near_fade(s.pos, r)
	# fire (or the wreck's flame once the fireball has died)
	var uf := a / s.fire_t
	if uf < 0.84:
		s.fire_mat.set_shader_parameter(&"progress", uf)
		s.fire_mat.set_shader_parameter(&"alpha", near)
		s.fire.visible = near > 0.01
	elif s.burn > 0.0 and a < s.burn:
		var wob := 0.5 + 0.5 * sin(a * 5.0 + sin(a * 2.3) * 2.0)
		var flame := minf(3.4, r * 0.5)
		s.fire.scale = Vector3(flame, flame, flame)
		s.fire.global_position = s.pos + Vector3(0.0, flame * 0.3, 0.0)
		s.fire_mat.set_shader_parameter(&"progress", 0.2 + 0.16 * wob)
		s.fire_mat.set_shader_parameter(&"alpha", _cover_fade(s.pos, 3.4) * clampf((s.burn - a) / 1.2, 0.0, 1.0) * 0.9)
		s.fire.visible = true
	else:
		s.fire.visible = false
	# smoke: rising puffs that expand (a wreck keeps a column of smaller ones going)
	for k in s.n_puffs:
		var p := s.puffs[k]
		var pa := a - s.puff_delay[k]
		var cyc := pa / s.smoke_t if pa >= 0.0 else -1.0
		var live := cyc >= 0.0 and (cyc < 1.0 or (s.burn > 0.0 and a < s.burn))
		if not live:
			p.visible = false
			continue
		var n := floorf(cyc)
		var f := cyc - n
		var first := n < 0.5
		var size := r * (1.55 + 0.3 * k) * (1.0 if first else 0.42)
		var rise := (r * 0.5 + 1.5) * (1.0 - (1.0 - f) * (1.0 - f)) * (1.0 if first else 0.7)
		var base := s.pos + Vector3(0.0, r * 0.3 if first else 1.0, 0.0)
		p.global_position = base + s.puff_drift[k] * (f * s.smoke_t) + Vector3(0.0, rise, 0.0)
		p.scale = Vector3(size, size, size)
		var m := s.puff_mats[k]
		m.set_shader_parameter(&"progress", f)
		var al := minf(near, _cover_fade(p.global_position, size * 1.1)) * 0.95 * (1.0 if first else 0.6)
		if not first and s.burn > 0.0:
			al *= clampf((s.burn - a) / 1.0, 0.0, 1.0)
		m.set_shader_parameter(&"alpha", al)
		m.set_shader_parameter(&"glow", maxf(0.0, 1.0 - a * 0.28) if first else 0.0)
		p.visible = al > 0.01
	# the ring on the ground
	var tg := a / s.ring_t
	if tg < 1.0:
		s.ground_mat.set_shader_parameter(&"t", tg)
		s.ground_mat.set_shader_parameter(&"alpha", 0.35 + 0.65 * ring_near)
	else:
		s.ground.visible = false


func _stop(s: Slot) -> void:
	s.active = false
	s.root.visible = false
	s.fire.visible = false
	s.ground.visible = false
	for p in s.puffs:
		p.visible = false
	s.sparks.emitting = false
	s.sparks.visible = false
	s.debris.emitting = false
	s.debris.visible = false
	if _light_owner >= 0 and slots[_light_owner] == s and _light_t <= 0.0:
		light.visible = false
		_light_owner = -1


## Hide everything at once (new game, respawn, next sector, tier change that must not leave anything frozen on screen).
func clear() -> void:
	for s in slots:
		_stop(s)
	_light_t = 0.0
	_light_owner = -1
	light.visible = false
	light.light_energy = 0.0
	_set_heat(Vector4.ZERO)


func active_count() -> int:
	var n := 0
	for s in slots:
		if s.active:
			n += 1
	return n


## The heat-haze ripple of the strongest live blast in front of the camera (screen position, radius in screen heights, strength). MED and HIGH only.
func _update_heat() -> void:
	var cam := get_viewport().get_camera_3d()
	var best := Vector4.ZERO
	if cam != null and Game.quality > 0:
		var tan_half := tan(deg_to_rad(cam.fov) * 0.5)
		var size := get_viewport().get_visible_rect().size
		var best_k := 0.0
		for s in slots:
			if not s.active or s.style == STYLE_QUANTUM or cam.is_position_behind(s.pos):
				continue
			var k := clampf(1.0 - s.age / (s.fire_t * 1.4), 0.0, 1.0)
			var dist := cam.global_position.distance_to(s.pos)
			var rad := clampf(s.radius * 1.3 / (2.0 * maxf(dist, 1.0) * tan_half), 0.04, 0.6)
			k *= clampf(s.radius / 8.0, 0.25, 1.0) * clampf(dist / 4.0, 0.0, 1.0)
			if k > best_k:
				best_k = k
				var uv := cam.unproject_position(s.pos + Vector3(0.0, s.radius * 0.3, 0.0)) / size
				best = Vector4(uv.x, uv.y, rad, k)
	_set_heat(best)


func _set_heat(v: Vector4) -> void:
	_heat_on = v.w > 0.0
	if v != _heat_value:
		_heat_value = v
		RenderingServer.global_shader_parameter_set(HEAT_PARAM, v)
