class_name ImpactSparks
extends Node3D
## Pooled soft-sprite particles for the player's effects: hot sparks, mist, dust puffs and armour chips. FX.burst particles are untextured
## 0.3 m quads (they read as square confetti), so the player module draws its own: small round glowing dots with a falloff, shrinking while
## they fade, plus larger low-alpha puffs. Every emitter is a CPUParticles3D created once; an effect just moves one, aims it along the
## surface normal and restarts it (no nodes, no buffer reallocation, nothing allocated per shot).
## The node is top_level (world space), so the particles live in the world whatever its parent does.
## A finished one-shot CPUParticles3D keeps drawing its (invisible) instances every frame, in the main pass and in every shadow pass, so an emitter is
## shown only while it is alive: hidden at the start, shown when it is launched and hidden again when its lifetime has run out. Emitters never cast shadows.

const SPARK_POOL := 10
const PUFF_POOL := 6
const SPARK_AMOUNT := 9
const PUFF_AMOUNT := 5

static var _dot_tex: GradientTexture2D
static var _spark_mat: StandardMaterial3D
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


## Hot sparks fly off the surface along `normal`. power scales count (visually), speed and lifetime: 1 = a bullet on concrete.
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
	_launch(p, index)


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
	_launch(p, index)


## A shot landing on concrete, metal or asphalt: sparks, a little mist.
func impact_world(pos: Vector3, normal: Vector3) -> void:
	spark(pos + normal * 0.03, normal, Color(1.0, 0.82, 0.5), 1.0)
	puff(pos + normal * 0.05, normal, Color(0.62, 0.68, 0.78, 0.22), 0.8)


## A shot landing on a machine: a brighter, longer spark shower.
func impact_machine(pos: Vector3, normal: Vector3) -> void:
	spark(pos + normal * 0.04, normal, Color(1.0, 0.72, 0.32), 1.35)
	spark(pos + normal * 0.04, normal, Color(1.0, 0.95, 0.85), 0.8)


## A shot landing on a person without gore: fabric dust and armour chips (the red burst is behind Game.graphic_violence).
func impact_person(pos: Vector3, normal: Vector3) -> void:
	puff(pos, normal, Color(0.7, 0.68, 0.64, 0.3), 0.7)
	spark(pos, normal, Color(1.0, 0.86, 0.6), 0.55)


## The red burst of a hit on a human, only while Game.graphic_violence is on.
func impact_blood(pos: Vector3, normal: Vector3) -> void:
	puff(pos, normal, Color(0.55, 0.03, 0.04, 0.55), 0.9)
	spark(pos, normal, Color(0.7, 0.04, 0.05), 0.7)


## A hard landing or a jump: a soft ring of dust at the feet.
func dust(pos: Vector3, strength := 1.0) -> void:
	puff(pos, Vector3.UP, Color(0.55, 0.6, 0.68, 0.22 * strength), 1.1 + strength * 0.5)


## Show the emitter, fire it once and remember when it is done.
func _launch(p: CPUParticles3D, index: int) -> void:
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
	p.spread = 38.0 if not is_puff else 70.0
	p.gravity = Vector3(0.0, -9.5, 0.0) if not is_puff else Vector3(0.0, 0.15, 0.0)
	p.damping_min = 1.0 if not is_puff else 2.0
	p.damping_max = 2.5 if not is_puff else 3.0
	p.lifetime = 0.35 if not is_puff else 0.7
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 4.0 if not is_puff else 1.2
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035) if not is_puff else Vector2(0.3, 0.3)
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


static func _get_dot() -> GradientTexture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		g.add_point(0.4, Color(1.0, 1.0, 1.0, 0.55))
		g.set_color(g.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
		_dot_tex = GradientTexture2D.new()
		_dot_tex.gradient = g
		_dot_tex.fill = GradientTexture2D.FILL_RADIAL
		_dot_tex.fill_from = Vector2(0.5, 0.5)
		_dot_tex.fill_to = Vector2(1.0, 0.5)
		_dot_tex.width = 64
		_dot_tex.height = 64
	return _dot_tex


static func _get_spark_material() -> StandardMaterial3D:
	if _spark_mat == null:
		_spark_mat = StandardMaterial3D.new()
		_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_spark_mat.vertex_color_use_as_albedo = true
		_spark_mat.albedo_texture = _get_dot()
		_spark_mat.albedo_color = Color(3.0, 3.0, 3.0, 1.0)          # HDR: the sparks feed the bloom
		_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_spark_mat.disable_receive_shadows = true
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
