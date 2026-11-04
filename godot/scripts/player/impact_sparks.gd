class_name ImpactSparks
extends Node3D
## Pooled soft-sprite particles for the player's effects: hot sparks, mist, dust puffs and armour chips. FX.burst particles are untextured
## 0.3 m quads (they read as square confetti), so the player module draws its own: small round glowing dots with a falloff, shrinking while
## they fade, plus larger low-alpha puffs. Every emitter is a CPUParticles3D created once; an effect just moves one, aims it along the
## surface normal and restarts it (no nodes, no buffer reallocation, nothing allocated per shot).
## The node is top_level (world space), so the particles live in the world whatever its parent does.
## A finished one-shot CPUParticles3D keeps drawing its (invisible) instances every frame, in the main pass and in every shadow pass, so an emitter is
## shown only while it is alive: hidden at the start, shown when it is launched and hidden again when its lifetime has run out. Emitters never cast shadows.

const SPARK_POOL := 12
const PUFF_POOL := 6
const SPARK_AMOUNT := 14
const PUFF_AMOUNT := 5

static var _dot_tex: Texture2D
static var _spark_mat: ShaderMaterial
const STREAK_SHADER := preload("res://assets/shaders/fx_streak.gdshader")
static var _puff_mat: StandardMaterial3D
static var _spark_curve: Curve
static var _puff_curve: Curve

var _sparks: Array[CPUParticles3D] = []
var _puffs: Array[CPUParticles3D] = []
var _all: Array[CPUParticles3D] = []          ## sparks first, then puffs; _left runs parallel to it
var _left := PackedFloat32Array()             ## seconds of life left per emitter, 0 = idle (hidden)
var _live := 0
var _si := 0
var _pi := 0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	for i in SPARK_POOL:
		var p := _make_emitter(false)
		_sparks.append(p)
		_all.append(p)
		add_child(p)
	for i in PUFF_POOL:
		var p := _make_emitter(true)
		_puffs.append(p)
		_all.append(p)
		add_child(p)
	_left.resize(_all.size())
	_left.fill(0.0)
	set_process(false)


## Hot sparks fly off the surface along `normal` as velocity-stretched streaks (fx_streak.gdshader). power scales count (visually), speed and lifetime: 1 = a bullet on concrete.
func spark(pos: Vector3, normal: Vector3, color := Color(1.0, 0.8, 0.45), power := 1.0) -> void:
	var index := _si
	var p := _sparks[index]
	_si = (_si + 1) % _sparks.size()
	p.global_position = pos
	p.direction = normal.normalized() if normal != Vector3.ZERO else Vector3.UP
	p.initial_velocity_min = 1.2 * power
	p.initial_velocity_max = 5.0 * power
	p.lifetime = 0.22 + 0.16 * power
	p.color = color
	_launch(p, index, 1.0 if power >= 0.6 else 0.6)


## A soft puff of dust, mist or smoke. size scales the sprite; tint is the colour (alpha sets how visible it is).
func puff(pos: Vector3, normal: Vector3, tint := Color(0.6, 0.66, 0.75, 0.3), size := 1.0) -> void:
	var index := _sparks.size() + _pi
	var p := _puffs[_pi]
	_pi = (_pi + 1) % _puffs.size()
	p.global_position = pos
	p.direction = normal.normalized() if normal != Vector3.ZERO else Vector3.UP
	p.scale_amount_min = 0.7 * size
	p.scale_amount_max = 1.3 * size
	p.color = tint
	_launch(p, index, 1.0)


## Which surface a world hit is on, from where it is (the city is one static body, so there is no per-surface collider): a street or ground-level
## horizontal hit is wet asphalt, a wall hit between 0.5 and 3.6 m is a shopfront whose window bays (about 2.6 m wide, hashed by position, 55 %) are glass,
## anything else is concrete. Pass `surface` to impact_world() to override (&"asphalt", &"glass", &"concrete", &"metal").
static func surface_at(pos: Vector3, normal: Vector3) -> StringName:
	if normal.y > 0.7:
		return &"asphalt" if pos.y < 0.5 else &"concrete"
	if absf(normal.y) < 0.5 and pos.y > 0.5 and pos.y < 3.6:
		var along := pos.z if absf(normal.x) > absf(normal.z) else pos.x
		var h := (floori(along / 2.6) * 73856093) ^ (floori(pos.y / 1.8) * 19349663) ^ (floori(pos.y + along) * 0)
		if absi(h) % 100 < 55:
			return &"glass"
	return &"concrete"


## A shot landing on the world, by surface: wet asphalt splashes droplets and mist, concrete chips and dust, shopfront glass sprays glittering shards,
## metal throws a hot spark shower.
func impact_world(pos: Vector3, normal: Vector3, surface := &"") -> void:
	var n := normal if normal != Vector3.ZERO else Vector3.UP
	var kind := surface if surface != &"" else surface_at(pos, n)
	Sfx.impact(kind, pos, n)
	var o := pos + n * 0.03
	FX.muzzle_flash(o + n * 0.02, n, Color(1.0, 0.85, 0.55) if kind != &"glass" else Color(0.7, 0.9, 1.0), 0.6 if kind == &"asphalt" else 0.95)     # the hit itself: a short star on the surface
	match kind:
		&"asphalt":
			spark(o, n, Color(0.75, 0.88, 1.0), 0.55)                              # droplets
			puff(pos + n * 0.05, n, Color(0.55, 0.62, 0.72, 0.3), 0.9)             # splash mist
		&"glass":
			spark(o, n, Color(0.85, 0.97, 1.0), 1.1)                               # shards glinting in the light
			spark(o, n, Color(1.0, 1.0, 1.0), 0.7)
			puff(pos + n * 0.05, n, Color(0.7, 0.85, 0.95, 0.16), 0.6)
		&"metal":
			spark(o, n, Color(1.0, 0.8, 0.45), 1.3)
			spark(o, n, Color(1.0, 0.95, 0.85), 0.8)
		_:
			spark(o, n, Color(1.0, 0.8, 0.5), 0.8)                                 # chips
			puff(pos + n * 0.05, n, Color(0.66, 0.62, 0.56, 0.34), 1.0)            # concrete dust


## A shot landing on a machine: a brighter, longer spark shower.
func impact_machine(pos: Vector3, normal: Vector3) -> void:
	Sfx.impact(&"metal", pos, normal)
	FX.muzzle_flash(pos + normal * 0.05, normal, Color(1.0, 0.8, 0.5), 1.2)
	spark(pos + normal * 0.04, normal, Color(1.0, 0.72, 0.32), 1.35)
	spark(pos + normal * 0.04, normal, Color(1.0, 0.95, 0.85), 0.8)


## A shot landing on a person without gore: fabric dust and armour chips (the red burst is behind Game.graphic_violence).
func impact_person(pos: Vector3, normal: Vector3) -> void:
	Sfx.impact(&"flesh", pos, normal)
	puff(pos, normal, Color(0.7, 0.68, 0.64, 0.3), 0.7)
	spark(pos, normal, Color(1.0, 0.86, 0.6), 0.55)


## The red burst of a hit on a human, only while Game.graphic_violence is on.
func impact_blood(pos: Vector3, normal: Vector3) -> void:
	puff(pos, normal, Color(0.2, 0.55, 0.25, 0.55), 0.9)                    # Vael ichor, green: the enemies are aliens
	spark(pos, normal, Color(0.45, 0.95, 0.2), 0.7)


## A hard landing or a jump: a soft ring of dust at the feet.
func dust(pos: Vector3, strength := 1.0) -> void:
	puff(pos, Vector3.UP, Color(0.55, 0.6, 0.68, 0.22 * strength), 1.1 + strength * 0.5)


## Show the emitter, fire it once and remember when it is done.
func _launch(p: CPUParticles3D, index: int, ratio: float) -> void:
	var full := SPARK_AMOUNT if index < _sparks.size() else PUFF_AMOUNT
	var n := maxi(3, roundi(full * ratio * (0.5 if Game.quality == 0 else 1.0)))        # LOW: half the particles (a few discrete counts, a change reallocates)
	if p.amount != n:
		p.amount = n
	p.visible = true
	p.restart()
	p.emitting = true
	if _left[index] <= 0.0:
		_live += 1
	_left[index] = p.lifetime + 0.12
	set_process(true)


func _process(delta: float) -> void:
	for i in _left.size():
		if _left[i] > 0.0:
			_left[i] -= delta
			if _left[i] <= 0.0:
				_left[i] = 0.0
				_live -= 1
				_all[i].emitting = false
				_all[i].visible = false
	if _live <= 0:
		set_process(false)


## True while any emitter is alive (tests, draw call accounting).
func active_count() -> int:
	return _live


func _make_emitter(is_puff: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.visible = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.explosiveness = 1.0
	p.local_coords = false
	p.amount = PUFF_AMOUNT if is_puff else SPARK_AMOUNT
	p.randomness = 0.6
	p.particle_flag_align_y = not is_puff
	p.spread = 38.0 if not is_puff else 70.0
	p.gravity = Vector3(0.0, -9.5, 0.0) if not is_puff else Vector3(0.0, 0.15, 0.0)
	p.damping_min = 1.0 if not is_puff else 2.0
	p.damping_max = 2.5 if not is_puff else 3.0
	p.lifetime = 0.35 if not is_puff else 0.7
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 4.0 if not is_puff else 1.2
	var quad := QuadMesh.new()
	quad.size = Vector2(0.045, 0.3) if not is_puff else Vector2(0.45, 0.45)         # a spark is a streak along its velocity
	quad.material = _get_puff_material() if is_puff else _get_spark_material()
	p.mesh = quad
	p.scale_amount_curve = _get_puff_curve() if is_puff else _get_spark_curve()
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.add_point(0.55, Color(1.0, 1.0, 1.0, 0.7))
	ramp.set_color(ramp.get_point_count() - 1, Color(1.0, 0.55, 0.25, 0.0))
	p.color_ramp = ramp
	return p


static func _get_dot() -> Texture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		g.add_point(0.4, Color(1.0, 1.0, 1.0, 0.55))
		g.set_color(g.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
		_dot_tex = SoftDot.radial(g)
	return _dot_tex


static func _get_spark_material() -> ShaderMaterial:
	if _spark_mat == null:
		_spark_mat = ShaderMaterial.new()
		_spark_mat.shader = STREAK_SHADER
	return _spark_mat


static func _get_puff_material() -> StandardMaterial3D:
	if _puff_mat == null:
		_puff_mat = StandardMaterial3D.new()
		_puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_puff_mat.vertex_color_use_as_albedo = true
		_puff_mat.albedo_texture = _get_dot()
		_puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_puff_mat.disable_receive_shadows = true
	return _puff_mat


static func _get_spark_curve() -> Curve:
	if _spark_curve == null:
		_spark_curve = Curve.new()
		_spark_curve.add_point(Vector2(0.0, 1.0))
		_spark_curve.add_point(Vector2(1.0, 0.15))
	return _spark_curve


static func _get_puff_curve() -> Curve:
	if _puff_curve == null:
		_puff_curve = Curve.new()
		_puff_curve.add_point(Vector2(0.0, 0.35))
		_puff_curve.add_point(Vector2(1.0, 1.6))
	return _puff_curve
