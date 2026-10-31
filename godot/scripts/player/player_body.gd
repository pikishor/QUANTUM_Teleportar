class_name PlayerBody
extends Node3D
## The player's visible body. Uses Game.load_model("player") (nodes Body, LegL, LegR, Muzzle per the assets contract) and falls back to
## a believable humanoid built from capsules and boxes when the model is missing. Both variants expose the same parts:
##   upper   pivot at the hips that carries the torso, arms and rifle (aim pitch, sprint lean, recoil, breathing)
##   leg_l / leg_r   pivots at the hip joints; they swing along the (smoothed) movement direction, so strafing and backpedalling read right
##   muzzle  the rifle tip: tracers and the muzzle flash start here
## The node is top_level and placed every rendered frame from the interpolated physics position, so it never judders
## when the display refresh rate and the physics tick rate differ.

const HIP_Y := 0.93
const LEG_AMP := 0.62                ## radians of hip swing at run speed
const STRIDE_RATE := 1.6             ## leg phase per metre travelled (src/player.js)
const FLASH_TIME := 0.055
const LIGHT_TIME := 0.075
const LIGHT_ENERGY := 3.4
const LIGHT_COUNT := 2
## Visual layer (1..20) reserved for the player's meshes, so the two character lights (a soft key and a rim) light only the hero and never the world.
const CHARACTER_LAYER := 20

## Tests flip this to exercise the primitive fallback.
static var force_primitive := false

static var _flash_star_tex: ImageTexture
static var _flash_streak_tex: ImageTexture
static var _flash_mat_star: StandardMaterial3D
static var _flash_mat_streak: StandardMaterial3D

var muzzle: Node3D
var leg_l: Node3D
var leg_r: Node3D
var upper: Node3D
var uses_model := false

var _phase := 0.0
var _amp := 0.0
var _air := 0.0
var _sprint := 0.0
var _aim_pitch := 0.0
var _dir := Vector2(0.0, -1.0)        ## smoothed local movement direction (x right, y back)
var _recoil_push := 0.0
var _recoil_pitch := 0.0
var _clock := 0.0
var _dead_t := -1.0
var _flash_root: Node3D
var _flash_t := 0.0
var _lights: Array[OmniLight3D] = []
var _light_t := PackedFloat32Array()
var _li := 0
var _key_light: DirectionalLight3D
var _rim_light: DirectionalLight3D
## Switch the character lights off (tests, or a graphics tier that wants the extra directional lights gone).
var character_light := true:
	set(v):
		character_light = v
		if _key_light != null:
			_key_light.visible = v
			_rim_light.visible = v


func _ready() -> void:
	top_level = true
	_build()


# ---------------------------------------------------------------------------------------------------------------------
# per-frame animation
# ---------------------------------------------------------------------------------------------------------------------

## Place the body at the interpolated world position and pose it from the player's state. Called by Player._process.
func update_view(p: Player, dt: float, view_pos: Vector3, yaw: float) -> void:
	_clock += dt
	var v := p.velocity
	var hv := Vector3(v.x, 0.0, v.z)
	var speed := hv.length()
	var grounded := p.air_time < 0.14                  # rolling off a curb is not a jump
	var local := hv.rotated(Vector3.UP, -yaw)          # body space: x right, z back

	# --- legs: swing about the axis perpendicular to the movement direction
	var target_amp := minf(1.0, speed / 5.0) * LEG_AMP if grounded else 0.0
	_amp = PlayerUtil.damp(_amp, target_amp, 14.0, dt)
	_air = PlayerUtil.damp(_air, 0.0 if grounded else 1.0, 12.0, dt)
	if speed > 0.4:
		var td := Vector2(local.x, local.z) / speed
		_dir += (td - _dir) * (1.0 - exp(-16.0 * dt))
		if _dir.length_squared() < 0.0004:
			_dir = td
	_phase += dt * speed * STRIDE_RATE
	var m := Vector3(_dir.x, 0.0, _dir.y).normalized()
	var fw := -m.z                                       # +1 moving forward, -1 backing up
	var lw := m.x                                        # +1 moving right, -1 moving left
	var sl := sin(_phase) * _amp
	# forward / back swing about X (positive = foot forward); sideways swing about Z with a splay that keeps the feet apart while strafing
	var ax_l := lerpf(sl * fw, 0.42, _air)
	var ax_r := lerpf(-sl * fw, -0.3, _air)
	var az_l := -0.2 * absf(lw) + 0.5 * sl * lw
	var az_r := 0.2 * absf(lw) - 0.5 * sl * lw
	if leg_l != null:
		leg_l.basis = Basis.from_euler(Vector3(ax_l, 0.0, az_l))
	if leg_r != null:
		leg_r.basis = Basis.from_euler(Vector3(ax_r, 0.0, az_r))

	# --- torso: aim pitch, sprint lean, strafe roll, run twist, breathing, recoil
	var rig := p.camera_rig
	var look_pitch := rig.pitch + rig.recoil_pitch if rig != null else 0.0
	_aim_pitch = PlayerUtil.damp(_aim_pitch, clampf(look_pitch * 0.6, -0.55, 0.65), 18.0, dt)
	_sprint = PlayerUtil.damp(_sprint, 1.0 if p.sprinting else 0.0, 9.0, dt)
	_recoil_push = PlayerUtil.damp(_recoil_push, 0.0, 17.0, dt)
	_recoil_pitch = PlayerUtil.damp(_recoil_pitch, 0.0, 13.0, dt)
	var lean := -(0.10 * _sprint + 0.03 * minf(1.0, speed / 6.2))
	var roll := -local.x * 0.011
	var twist := sin(_phase) * 0.055 * (_amp / LEG_AMP)
	var calm := 1.0 - minf(1.0, speed / 2.0)
	var breathe := sin(_clock * 2.1) * 0.006 * calm
	var bob := -absf(sin(_phase)) * 0.016 * (_amp / LEG_AMP)
	upper.rotation = Vector3(_aim_pitch + lean + _recoil_pitch + breathe, twist, roll)
	upper.position = Vector3(0.0, HIP_Y + bob + sin(_clock * 1.7) * 0.0025 * calm, _recoil_push)

	# --- placement (and the death fall)
	var fall := 0.0
	var sink := 0.0
	if _dead_t >= 0.0:
		_dead_t += dt
		var k := clampf(_dead_t / 0.75, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)
		fall = deg_to_rad(86.0) * e
		sink = 0.1 * e
	global_position = Vector3(view_pos.x, view_pos.y - sink, view_pos.z)
	rotation = Vector3(fall, yaw, 0.0)

	# --- character lights follow the camera, so the hero is always modelled from the viewer's side and edged from behind
	if character_light and rig != null:
		var f := PlayerUtil.forward_of(rig.yaw, 0.0)
		var right := Vector3(-f.z, 0.0, f.x)
		_key_light.global_basis = Basis.looking_at((f * 0.82 - right * 0.28 + Vector3(0.0, -0.5, 0.0)).normalized(), Vector3.UP)
		_rim_light.global_basis = Basis.looking_at((-f * 0.8 + right * 0.55 + Vector3(0.0, -0.22, 0.0)).normalized(), Vector3.UP)

	# --- muzzle flash decay
	if _flash_t > 0.0:
		_flash_t -= dt
		if _flash_t <= 0.0:
			_flash_root.visible = false
	for i in _lights.size():
		if _light_t[i] > 0.0:
			_light_t[i] -= dt
			if _light_t[i] <= 0.0:
				_lights[i].visible = false
			else:
				var f := _light_t[i] / LIGHT_TIME
				_lights[i].light_energy = LIGHT_ENERGY * f * f


## One shot: flash card, light pulse and the body's recoil. intensity scales the flash.
func fire_flash(intensity := 1.0) -> void:
	if _flash_root != null:
		_flash_t = FLASH_TIME
		_flash_root.visible = true
		var s := randf_range(0.8, 1.25) * intensity
		_flash_root.rotation = Vector3(0.0, 0.0, randf() * TAU)
		_flash_root.scale = Vector3(s, s, s * randf_range(0.8, 1.5))
	if not _lights.is_empty():
		var l := _lights[_li]
		_light_t[_li] = LIGHT_TIME
		_li = (_li + 1) % _lights.size()
		l.light_energy = LIGHT_ENERGY
		l.visible = true
	_recoil_push = minf(_recoil_push + 0.045, 0.12)
	_recoil_pitch = minf(_recoil_pitch + 0.04, 0.16)


## A hit reaction: the torso snaps back for a moment.
func flinch(strength := 1.0) -> void:
	_recoil_pitch = minf(_recoil_pitch + 0.1 * strength, 0.25)
	_recoil_push = minf(_recoil_push + 0.06 * strength, 0.15)


func set_dead(is_dead: bool) -> void:
	_dead_t = 0.0 if is_dead else -1.0
	if not is_dead:
		rotation.x = 0.0


## Hide the flash and clear every transient pose (respawn, teleport).
func reset_pose() -> void:
	_dead_t = -1.0
	_flash_t = 0.0
	_recoil_push = 0.0
	_recoil_pitch = 0.0
	if _flash_root != null:
		_flash_root.visible = false
	for i in _lights.size():
		_light_t[i] = 0.0
		_lights[i].visible = false


# ---------------------------------------------------------------------------------------------------------------------
# construction
# ---------------------------------------------------------------------------------------------------------------------

func _build() -> void:
	upper = Node3D.new()
	upper.name = "Upper"
	upper.position = Vector3(0.0, HIP_Y, 0.0)
	add_child(upper)
	var model: Node3D = null if force_primitive else Game.load_model("player")
	if model != null and model.get_node_or_null("Body") != null:
		_adopt_model(model)
	else:
		if model != null:
			model.free()
		_build_primitive()
	_build_flash()
	_build_character_lights()


func _adopt_model(model: Node3D) -> void:
	uses_model = true
	var body := model.get_node("Body") as Node3D
	model.remove_child(body)
	body.owner = null
	upper.add_child(body)
	body.position = Vector3(0.0, -HIP_Y, 0.0)
	var mz := model.get_node_or_null("Muzzle") as Node3D
	var mz_pos := Vector3(0.118, 1.384, -1.055)
	if mz != null:
		mz_pos = mz.position
	muzzle = Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = mz_pos - Vector3(0.0, HIP_Y, 0.0)
	upper.add_child(muzzle)
	for leg_name: String in ["LegL", "LegR"]:
		var leg := model.get_node_or_null(leg_name) as Node3D
		if leg != null:
			model.remove_child(leg)
			leg.owner = null
			add_child(leg)
			if leg_name == "LegL":
				leg_l = leg
			else:
				leg_r = leg
	model.free()


# --- primitive fallback ----------------------------------------------------------------------------------------------

## Collects parts per material and bakes each material group into one surface of one ArrayMesh.
class Batch:
	var _tools := {}
	var _mats := {}

	func add(key: StringName, mat: Material, mesh: Mesh, xf: Transform3D) -> void:
		if not _tools.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_material(mat)
			_tools[key] = st
		(_tools[key] as SurfaceTool).append_from(mesh, 0, xf)

	func box(key: StringName, mat: Material, center: Vector3, size: Vector3, rot := Vector3.ZERO) -> void:
		var m := BoxMesh.new()
		m.size = size
		add(key, mat, m, Transform3D(Basis.from_euler(rot), center))

	func sphere(key: StringName, mat: Material, center: Vector3, radius: float, squash := Vector3.ONE) -> void:
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = 16
		m.rings = 8
		add(key, mat, m, Transform3D(Basis.from_scale(squash), center))

	func limb(key: StringName, mat: Material, a: Vector3, b: Vector3, radius: float) -> void:
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = a.distance_to(b) + radius * 2.0
		m.radial_segments = 12
		m.rings = 4
		var dir := (b - a).normalized()
		var basis := Basis.IDENTITY
		if absf(dir.dot(Vector3.UP)) < 0.9999:
			basis = Basis(Quaternion(Vector3.UP, dir))
		elif dir.y < 0.0:
			basis = Basis(Vector3.RIGHT, PI)
		add(key, mat, m, Transform3D(basis, (a + b) * 0.5))

	func cylinder(key: StringName, mat: Material, center: Vector3, radius: float, height: float, rot := Vector3.ZERO) -> void:
		var m := CylinderMesh.new()
		m.top_radius = radius
		m.bottom_radius = radius
		m.height = height
		m.radial_segments = 12
		m.rings = 1
		add(key, mat, m, Transform3D(Basis.from_euler(rot), center))

	func build() -> ArrayMesh:
		var am := ArrayMesh.new()
		for key: StringName in _tools:
			(_tools[key] as SurfaceTool).commit(am)
		return am


static func _pbr(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _build_primitive() -> void:
	uses_model = false
	var fabric := _pbr(Color(0.105, 0.12, 0.125), 0.93, 0.0)
	fabric.resource_name = "Fabric"
	var armor := _pbr(Color(0.17, 0.2, 0.215), 0.52, 0.35)
	armor.resource_name = "Armor"
	var gun := _pbr(Color(0.06, 0.065, 0.075), 0.36, 0.85)
	gun.resource_name = "Gunmetal"
	var visor := _pbr(Color(0.02, 0.035, 0.045), 0.07, 0.9)
	visor.resource_name = "Visor"
	var glow := StandardMaterial3D.new()
	glow.resource_name = "Glow"
	glow.albedo_color = Color.BLACK
	glow.emission_enabled = true
	glow.emission = Color(0.15, 0.9, 1.0)
	glow.emission_energy_multiplier = 3.5

	# upper body, authored with the feet at the origin like the glb (the Upper pivot carries the -HIP_Y offset)
	var b := Batch.new()
	b.box(&"fabric", fabric, Vector3(0.0, 0.98, 0.0), Vector3(0.34, 0.2, 0.22))            # pelvis
	b.box(&"gun", gun, Vector3(0.0, 1.06, 0.0), Vector3(0.37, 0.055, 0.245))               # belt
	b.box(&"fabric", fabric, Vector3(0.0, 1.19, 0.0), Vector3(0.37, 0.22, 0.235))          # abdomen
	b.box(&"fabric", fabric, Vector3(0.0, 1.41, 0.0), Vector3(0.43, 0.28, 0.26))           # chest
	b.box(&"armor", armor, Vector3(0.0, 1.41, -0.15), Vector3(0.37, 0.29, 0.06))           # front plate
	b.box(&"armor", armor, Vector3(-0.225, 1.4, 0.0), Vector3(0.045, 0.22, 0.19))          # side plates
	b.box(&"armor", armor, Vector3(0.225, 1.4, 0.0), Vector3(0.045, 0.22, 0.19))
	for px: float in [-0.11, 0.0, 0.11]:
		b.box(&"gun", gun, Vector3(px, 1.25, -0.165), Vector3(0.085, 0.11, 0.05))          # ammo pouches
	b.box(&"armor", armor, Vector3(0.0, 1.38, 0.2), Vector3(0.3, 0.34, 0.13))              # backpack
	b.cylinder(&"gun", gun, Vector3(-0.1, 1.62, 0.2), 0.008, 0.3)                          # antenna
	b.cylinder(&"fabric", fabric, Vector3(0.0, 1.575, 0.0), 0.05, 0.1)                     # neck
	b.sphere(&"fabric", fabric, Vector3(0.0, 1.685, 0.0), 0.105, Vector3(1.0, 1.12, 1.06)) # head
	b.sphere(&"armor", armor, Vector3(0.0, 1.715, 0.012), 0.135, Vector3(1.0, 0.92, 1.1))  # helmet
	b.box(&"gun", gun, Vector3(0.0, 1.79, 0.0), Vector3(0.05, 0.02, 0.2))                  # helmet rail
	b.box(&"visor", visor, Vector3(0.0, 1.69, -0.108), Vector3(0.175, 0.055, 0.075))       # visor
	b.box(&"glow", glow, Vector3(0.0, 1.69, -0.148), Vector3(0.15, 0.011, 0.008))          # visor light strip
	b.sphere(&"armor", armor, Vector3(-0.258, 1.515, 0.0), 0.085, Vector3(1.0, 0.9, 1.0))  # shoulder pads
	b.sphere(&"armor", armor, Vector3(0.258, 1.515, 0.0), 0.085, Vector3(1.0, 0.9, 1.0))
	# right arm (trigger hand) and left arm (foregrip)
	b.limb(&"fabric", fabric, Vector3(0.258, 1.5, 0.0), Vector3(0.275, 1.27, -0.11), 0.05)
	b.limb(&"fabric", fabric, Vector3(0.275, 1.27, -0.11), Vector3(0.158, 1.31, -0.4), 0.045)
	b.limb(&"fabric", fabric, Vector3(-0.258, 1.5, 0.0), Vector3(-0.3, 1.31, -0.24), 0.05)
	b.limb(&"fabric", fabric, Vector3(-0.3, 1.31, -0.24), Vector3(0.1, 1.345, -0.72), 0.045)
	b.box(&"gun", gun, Vector3(0.158, 1.31, -0.41), Vector3(0.07, 0.07, 0.09))             # gloves
	b.box(&"gun", gun, Vector3(0.1, 1.345, -0.73), Vector3(0.075, 0.075, 0.1))
	# rifle, muzzle at z = -1.06
	b.box(&"gun", gun, Vector3(0.14, 1.34, -0.5), Vector3(0.07, 0.115, 0.44))              # receiver
	b.box(&"gun", gun, Vector3(0.14, 1.345, -0.86), Vector3(0.075, 0.075, 0.32))           # handguard
	b.cylinder(&"gun", gun, Vector3(0.14, 1.345, -1.0), 0.013, 0.14, Vector3(PI * 0.5, 0.0, 0.0))  # barrel
	b.box(&"gun", gun, Vector3(0.14, 1.205, -0.47), Vector3(0.05, 0.17, 0.08), Vector3(0.18, 0.0, 0.0))  # magazine
	b.box(&"gun", gun, Vector3(0.14, 1.32, -0.14), Vector3(0.05, 0.1, 0.22))               # stock
	b.box(&"gun", gun, Vector3(0.14, 1.425, -0.5), Vector3(0.05, 0.05, 0.13))              # optic
	b.box(&"glow", glow, Vector3(0.14, 1.426, -0.57), Vector3(0.012, 0.012, 0.012))        # optic reticle glint
	var body_mi := MeshInstance3D.new()
	body_mi.name = "Body"
	body_mi.mesh = b.build()
	body_mi.position = Vector3(0.0, -HIP_Y, 0.0)
	upper.add_child(body_mi)

	muzzle = Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.14, 1.345, -1.07) - Vector3(0.0, HIP_Y, 0.0)
	upper.add_child(muzzle)

	# legs, pivots at the hips
	for side: int in [-1, 1]:
		var lb := Batch.new()
		var s := float(side)
		lb.limb(&"fabric", fabric, Vector3(0.0, -0.06, 0.0), Vector3(0.0, -0.45, 0.0), 0.088)       # thigh
		lb.limb(&"fabric", fabric, Vector3(0.0, -0.49, 0.0), Vector3(0.0, -0.8, 0.0), 0.068)        # shin
		lb.box(&"armor", armor, Vector3(0.0, -0.47, -0.075), Vector3(0.115, 0.1, 0.05))             # knee pad
		lb.box(&"armor", armor, Vector3(s * 0.085, -0.25, 0.0), Vector3(0.03, 0.2, 0.12))           # thigh holster plate
		lb.box(&"gun", gun, Vector3(0.0, -0.885, -0.05), Vector3(0.115, 0.1, 0.27))                 # boot
		lb.box(&"gun", gun, Vector3(0.0, -0.925, -0.055), Vector3(0.12, 0.025, 0.285))              # sole
		var leg := MeshInstance3D.new()
		leg.mesh = lb.build()
		leg.position = Vector3(s * 0.098, HIP_Y, 0.0)
		add_child(leg)
		if side < 0:
			leg.name = "LegL"
			leg_l = leg
		else:
			leg.name = "LegR"
			leg_r = leg


# --- character lights ---------------------------------------------------------------------------------------------------

func _build_character_lights() -> void:
	var mask := 1 << (CHARACTER_LAYER - 1)
	_set_layer(self, mask)
	_key_light = _make_character_light("KeyLight", Color(0.8, 0.88, 1.0), 1.15, mask)
	_rim_light = _make_character_light("RimLight", Color(0.5, 0.85, 0.95), 1.8, mask)
	_key_light.visible = character_light
	_rim_light.visible = character_light


func _make_character_light(light_name: String, color: Color, energy: float, mask: int) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.name = light_name
	l.light_color = color
	l.light_energy = energy
	l.light_specular = 0.8
	l.light_cull_mask = mask
	l.shadow_enabled = false
	add_child(l)
	return l


## Put every mesh of `node` on the character layer in addition to the default layer 1.
static func _set_layer(node: Node, mask: int) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).layers |= mask
	for c in node.get_children():
		_set_layer(c, mask)


# --- muzzle flash -----------------------------------------------------------------------------------------------------

func _build_flash() -> void:
	_flash_root = Node3D.new()
	_flash_root.name = "Flash"
	_flash_root.visible = false
	muzzle.add_child(_flash_root)
	var star := MeshInstance3D.new()
	var star_mesh := QuadMesh.new()
	star_mesh.size = Vector2(0.5, 0.5)
	star.mesh = star_mesh
	star.material_override = _get_flash_material(true)
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_root.add_child(star)
	# two crossed streaks that jet forward from the barrel
	var streak_mesh := QuadMesh.new()
	streak_mesh.size = Vector2(0.2, 0.75)
	for i in 2:
		var streak := MeshInstance3D.new()
		streak.mesh = streak_mesh
		streak.material_override = _get_flash_material(false)
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var flat := Basis(Vector3.RIGHT, -PI * 0.5)                  # long axis along -Z, lying flat
		streak.transform = Transform3D(Basis(Vector3.FORWARD, i * PI * 0.5) * flat, Vector3(0.0, 0.0, -0.37))
		_flash_root.add_child(streak)
	for i in LIGHT_COUNT:
		var l := OmniLight3D.new()
		l.name = "FlashLight%d" % i
		l.light_color = Color(1.0, 0.72, 0.38)
		l.omni_range = 9.0
		l.omni_attenuation = 1.5
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.visible = false
		l.position = Vector3(0.0, 0.05, -0.25)
		muzzle.add_child(l)
		_lights.append(l)
	_light_t.resize(LIGHT_COUNT)
	_light_t.fill(0.0)


static func _get_flash_material(star: bool) -> StandardMaterial3D:
	if _flash_mat_star == null:
		_paint_flash_textures()
		for is_star: bool in [true, false]:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.disable_receive_shadows = true
			if is_star:
				m.albedo_texture = _flash_star_tex
				m.albedo_color = Color(2.2, 1.7, 1.0)
				m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
				_flash_mat_star = m
			else:
				m.albedo_texture = _flash_streak_tex
				m.albedo_color = Color(2.4, 1.6, 0.8)
				_flash_mat_streak = m
	return _flash_mat_star if star else _flash_mat_streak


static func _paint_flash_textures() -> void:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var ang := atan2(v, u)
			var core := exp(-r * r * 16.0)
			var halo := exp(-r * 3.4) * 0.5
			var rays := pow(absf(cos(ang * 3.0 + 0.3)), 14.0) * exp(-r * 2.4) * 0.9
			var a := clampf(core + halo + rays, 0.0, 1.0) * (1.0 - smoothstep(0.85, 1.0, r))
			img.set_pixel(x, y, Color(1.0, 0.95, 0.8, a))
	_flash_star_tex = ImageTexture.create_from_image(img)
	var w := 32
	var h := 64
	var img2 := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var t := (y + 0.5) / h                        # 0 at the tip, 1 at the barrel
			var s := (x + 0.5) / w * 2.0 - 1.0
			var a := pow(t, 1.6) * exp(-s * s * 5.0)
			img2.set_pixel(x, y, Color(1.0, 0.9, 0.7, clampf(a, 0.0, 1.0)))
	_flash_streak_tex = ImageTexture.create_from_image(img2)
