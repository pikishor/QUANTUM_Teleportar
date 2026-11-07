class_name HeroPresentation
extends RefCounted
## Hero presentation for a tall realistic character: a camera profile scaled by the hero's height, hand-bone attachment points (hand_r / hand_l of the 65-bone skeleton,
## also the contract names HandR / HandL), and quantum particle bursts for hit and death (one pooled CPUParticles3D per body: one draw call, additive, no new textures).
## Everything here is generic: it measures the model it is given and falls back to the reference height when none is known.

const REF_HEIGHT := 1.8                 ## the height the camera constants of CameraRig were tuned for
const SCALE_MIN := 0.9
const SCALE_MAX := 1.25
const DIST_GAIN := 0.8                  ## the arm grows by 80 % of the height ratio (a taller hero needs a little more room, not proportionally more)
const SHOULDER_GAIN := 0.6
const DEADBAND := 0.1                   ## heroes within 10 % of the reference height keep the tuned camera exactly (bind-pose bounds include gear and hair)
const HIT_MOTES := 10
const DEATH_MOTES := 36
const MOTE_COLOR := Color(0.35, 0.95, 1.0)
const MOTE_SIZE := 0.06            ## metres: one quantum mote (hit and death bursts)
const HAND_NAMES := {&"r": ["handr", "hand_r", "righthand", "mixamorig_righthand", "hand.r"], &"l": ["handl", "hand_l", "lefthand", "mixamorig_lefthand", "hand.l"]}

static var height := REF_HEIGHT


static func set_height(h: float) -> void:
	height = h if h > 0.5 and h < 4.0 else REF_HEIGHT


static func scale_factor(h := -1.0) -> float:
	var r := (height if h <= 0.0 else h) / REF_HEIGHT
	if absf(r - 1.0) <= DEADBAND:
		return 1.0
	return clampf(r, SCALE_MIN, SCALE_MAX)


## {eye, dist, shoulder} multipliers for the camera: eye height follows the hero fully, distance and shoulder offset partly.
static func camera_scale(h := -1.0) -> Dictionary:
	var s := scale_factor(h)
	return {"eye": s, "dist": 1.0 + (s - 1.0) * DIST_GAIN, "shoulder": 1.0 + (s - 1.0) * SHOULDER_GAIN}


## Model-space height of the visible meshes below `root` (bind-pose AABB), or -1 when there is none.
static func measure_height(root: Node) -> float:
	var lo := INF
	var hi := -INF
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var bb := mi.get_aabb()
		lo = minf(lo, bb.position.y * mi.scale.y)
		hi = maxf(hi, bb.end.y * mi.scale.y)
	return hi - lo if hi > lo else -1.0


## Bone index of a hand (side &"r" / &"l") in `sk`, or -1.
static func hand_bone(sk: Skeleton3D, side: StringName) -> int:
	if sk == null:
		return -1
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i).to_lower().replace(" ", "").replace(":", "_")
		if HAND_NAMES[side].has(n):
			return i
	return -1


## A BoneAttachment3D riding on a hand (child of the skeleton, named Hand<R|L>Mount) or null when the skeleton has no such bone. Reuses an existing mount.
static func hand_mount(sk: Skeleton3D, side: StringName) -> BoneAttachment3D:
	var b := hand_bone(sk, side)
	if b < 0:
		return null
	var nm := "Hand%sMount" % String(side).to_upper()
	var ex := sk.get_node_or_null(nm) as BoneAttachment3D
	if ex != null:
		return ex
	var m := BoneAttachment3D.new()
	m.name = nm
	m.bone_name = sk.get_bone_name(b)
	sk.add_child(m)
	return m


## The pooled burst emitter (CPUParticles3D, one draw) parented to `host`.
static func make_burst(host: Node3D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "QuantumBurst"
	p.emitting = false
	p.visible = false                     # no draw while idle; shown only for the burst
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = DEATH_MOTES
	p.lifetime = 0.9
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 80.0
	p.gravity = Vector3(0.0, 0.6, 0.0)
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.6
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.color = MOTE_COLOR
	p.top_level = true                    # world-space motes: nothing inherited from the hero's body (its height scale)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var q := QuadMesh.new()
	q.size = Vector2(MOTE_SIZE, MOTE_SIZE)  # a 6 cm soft dot. Was a 1 m quad whose size came from scale_amount, which a BILLBOARD_ENABLED material without billboard_keep_scale ignores: metre-wide untextured additive squares at the lens
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1, 1, 1, 0.9)
	m.albedo_texture = MissionVisuals.soft_texture()
	q.material = m
	p.mesh = q
	p.finished.connect(func() -> void: p.visible = false)
	host.add_child(p)
	return p


## Fire the burst at `at` (world) with a mote count; restart-safe, no allocation.
static func burst(p: CPUParticles3D, at: Vector3, count: int, color := MOTE_COLOR) -> void:
	if p == null or not is_instance_valid(p):
		return
	p.global_position = at
	p.color = color
	p.amount = clampi(count, 2, DEATH_MOTES)
	p.visible = true
	p.restart()
	p.emitting = true
