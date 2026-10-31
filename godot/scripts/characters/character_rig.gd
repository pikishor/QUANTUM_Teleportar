class_name CharacterRig
extends RefCounted
## Procedural pose of the articulated alien character models (assets/models/player.glb "Kestrel" and operative.glb "Vael trooper").
##
## The model is ONE skinned mesh ("Body", one surface, one draw call) on a Skeleton3D whose rigid bones are the named pivots of the contract:
##   Hips > Torso > Head, UpperArmL/R > ForeArmL/R, Rifle ;  Hips > ThighL/R > ShinL/R > FootL/R   (+ optional Sec1 > Sec2 > Sec3: the hero's phase cloak / the trooper's tail, swayed by apply())
## The legs may be digitigrade (high hock, forward knee): the thigh / shin / hock heights are read from the rest pose.
## Every bone frame is the model frame at rest (x right, y up, -z forward), so the poses below are written in model axes: a bone is posed with
## `rest * delta` (the delta in the bone's own, model aligned, frame). The model also carries empties at its root: Muzzle (rifle tip), WristL/WristR (where the
## glove cuffs meet the rifle), MagWell (magazine well) and MagPouch (vest pouch).
##
## The owner (PlayerBody, Operative) keeps the state (stride phase, smoothing, timers), writes it into the public fields below and calls apply() once per
## rendered frame. Nothing here allocates per frame: only Basis, Transform3D and Vector3 values.
##   gait     phase  amp  run  fw  lw  air      stride phase (radians), walk/run amount 0..1, run 0..1 (knee lift), forward +1 / back -1, right +1 / left -1, airborne 0..1
##   torso    aim_pitch  lean  twist  roll  breathe  recoil  flinch     radians (aim_pitch: + looks up), recoil/flinch 0..1 kicks
##   weapon   ready  sprint  reload  clock   ready 1 = shouldered, 0 = low ready; reload progress 0..1 (-1 none)
##   dead     dead   0..1 weight of the limp pose; knee_buckle 0..1 (an operative collapsing)
## The arms are solved with two-bone IK on the rifle: both gloves stay on the rifle whatever the rifle does (aim pitch, kick, low ready, reload).

const BONE_NAMES: Array[StringName] = [&"Hips", &"Torso", &"Head", &"UpperArmL", &"ForeArmL", &"UpperArmR", &"ForeArmR", &"Rifle",
		&"ThighL", &"ShinL", &"FootL", &"ThighR", &"ShinR", &"FootR"]
const HIPS := 0
const TORSO := 1
const HEAD := 2
const UARM_L := 3
const FARM_L := 4
const UARM_R := 5
const FARM_R := 6
const RIFLE := 7
const THIGH_L := 8
const SHIN_L := 9
const FOOT_L := 10
const THIGH_R := 11
const SHIN_R := 12
const FOOT_R := 13

const LEG_AMP := 0.62                 ## hip swing at a run (radians)
const KNEE_WALK := 0.5
const KNEE_RUN := 1.35
const LOW_READY_PITCH := -0.5         ## rifle muzzle drop at low ready (radians)
const SPRINT_PITCH := -0.78
const SEC_NAMES: Array[StringName] = [&"Sec1", &"Sec2", &"Sec3"]    ## optional secondary chain (the hero's phase cloak on the Torso, the trooper's tail on the Hips)
const REFLECTION_DIM := 0.4           ## albedo multiplier of the reflection twin (see find())

var skeleton: Skeleton3D
var body_mesh: MeshInstance3D
var rest_mesh: MeshInstance3D           ## an invisible (render layers 0) unskinned twin of the body mesh in the model's own space, for what copies meshes by their transform (the wet-street reflection, the quantum ghost): they show the rest pose
var model: Node3D

# --- inputs (see the header)
var phase := 0.0
var amp := 0.0
var run := 0.0
var fw := 1.0
var lw := 0.0
var air := 0.0
var aim_pitch := 0.0
var lean := 0.0
var twist := 0.0
var roll := 0.0
var breathe := 0.0
var recoil := 0.0
var flinch := 0.0
var ready := 1.0
var sprint := 0.0
var reload := -1.0
var clock := 0.0
var dead := 0.0
var knee_buckle := 0.0
var head_yaw := 0.0
var hip_l := Vector2.ZERO               ## outputs: the thigh angles of the last apply() (x forward swing, y sideways), for the owner's leg proxies and tests
var hip_r := Vector2.ZERO
var extra_torso := Vector3.ZERO        ## added to the torso rotation (the owner's own flourishes, radians x/y/z)
# --- planted-feet mode (`ik` true, written by Locomotion): the sole contact points (model space, x right, y up, z back), heel / toe pitch (+ heel strike, - toe-off) and yaw of
# each foot, how much each foot carries the body (0..1), and the pelvis (sway, roll, yaw, squash = metres the pelvis is pushed down), aim-down-sights, head look (yaw, pitch),
# the direction a hit came from (x right, y forward, zero = none), the fall kind of a dead body (0 side, 1 forward, 2 backward) and the cloak / tail springs.
var ik := false
var sole_l := Vector3.ZERO
var sole_r := Vector3.ZERO
var pitch_l := 0.0
var pitch_r := 0.0
var yaw_l := 0.0
var yaw_r := 0.0
var support_l := 1.0
var support_r := 1.0
var support := 1.0
var sway := 0.0
var pelvis_roll := 0.0
var pelvis_yaw := 0.0
var squash := 0.0
var ads := 0.0
var head_look := Vector2.ZERO
var flinch_dir := Vector2.ZERO
var death_kind := 0
var sec_pitch := PackedFloat32Array([0.0, 0.0, 0.0])
var sec_side := PackedFloat32Array([0.0, 0.0, 0.0])
var use_springs := false

# --- rest data read from the model
var _idx := PackedInt32Array()
var _rest: Array[Transform3D] = []
var _grest: Array[Transform3D] = []     ## bone global rest in skeleton space
var _to_model := Transform3D.IDENTITY   ## skeleton space -> model space
var _sh := [Vector3.ZERO, Vector3.ZERO]            ## shoulder in the torso frame (L, R)
var _e0 := [Vector3.ZERO, Vector3.ZERO]            ## elbow at rest, torso frame
var _w0 := [Vector3.ZERO, Vector3.ZERO]            ## wrist target at rest, torso frame
var _l1 := [0.3, 0.3]
var _l2 := [0.28, 0.28]
var _pole := [Vector3.DOWN, Vector3.DOWN]
var _rifle_o := Vector3.ZERO           ## rifle pivot, torso frame
var _mag_rifle := Vector3.ZERO         ## wrist target at the magazine, in the rifle frame (relative to the rifle pivot)
var _pouch := Vector3.ZERO             ## wrist target at the vest pouch, torso frame
var _muzzle_off := Vector3.ZERO        ## muzzle in the rifle bone's own frame (skeleton space)
var _hulls: Array = []                 ## per bone: points of the convex hull in model space (rest pose)
var _hips_rest_y := 0.93
var _wrist_rest := [Vector3.ZERO, Vector3.ZERO]     ## wrist target of each hand at rest, model space (L, R)
var _leg_x := 0.1
var _rest_thigh := 0.43                ## vertical hip joint to knee, knee to hock / ankle, hock / ankle to sole (metres, read from the model: digitigrade legs have a high hock)
var _rest_shin := 0.40
var _rest_foot := 0.10
var _sec := PackedInt32Array()          ## skeleton indices of the secondary chain bones present in the model
var _sec_rest: Array[Transform3D] = []
var _leg_o: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]     ## thigh joints in the hips frame, rest knee and rest hock vectors (model aligned), lengths of the two leg segments
var _leg_t0: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _leg_s0: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _leg_l1 := 0.4
var _leg_l2 := 0.3
var _d_rest := 0.7
var _hocks: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _sec_tail := false                  ## true: the chain extends backwards (a tail); false: it hangs down (a cloak)


## True when the model has a skeleton with every bone of the contract (cheap: builds nothing).
static func has_rig(root: Node3D) -> bool:
	if root == null:
		return false
	var sks := root.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return false
	for n in BONE_NAMES:
		if (sks[0] as Skeleton3D).find_bone(String(n)) < 0:
			return false
	return true


## Build the rig of an imported model; null when the model has no skeleton or misses a bone of the contract.
static func find(root: Node3D) -> CharacterRig:
	if root == null:
		return null
	var sks := root.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return null
	var r := CharacterRig.new()
	r.skeleton = sks[0] as Skeleton3D
	r.model = root
	r._idx.resize(BONE_NAMES.size())
	for i in BONE_NAMES.size():
		var b := r.skeleton.find_bone(String(BONE_NAMES[i]))
		if b < 0:
			return null
		r._idx[i] = b
	for sn in SEC_NAMES:
		var sb := r.skeleton.find_bone(String(sn))
		if sb >= 0:
			r._sec.append(sb)
	for c in r.skeleton.get_children():
		if c is MeshInstance3D:
			r.body_mesh = c as MeshInstance3D
	if r.body_mesh == null:
		return null
	r._read_rest()
	r.rest_mesh = MeshInstance3D.new()
	r.rest_mesh.name = "RestBody"
	r.rest_mesh.mesh = r.body_mesh.mesh
	r.rest_mesh.layers = 0
	for si in r.body_mesh.mesh.get_surface_count():            # the street reflection brightens albedo by 2.4: the baked atlas is already light, so dim its twin
		var src_mat := r.body_mesh.mesh.surface_get_material(si) as BaseMaterial3D
		if src_mat != null:
			var dim := src_mat.duplicate() as BaseMaterial3D
			dim.albedo_color = Color(REFLECTION_DIM, REFLECTION_DIM, REFLECTION_DIM, 1.0)
			dim.emission_enabled = false                           # MirrorProxy turns an emissive material into one flat bright colour
			r.rest_mesh.material_override = dim
	r.rest_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(r.rest_mesh)
	return r


## Transform of `node` relative to `root` (both in the same tree or not yet in a tree).
static func chain_to(node: Node3D, root: Node3D) -> Transform3D:
	var x := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			x = (n as Node3D).transform * x
		n = n.get_parent()
	return x


func _read_rest() -> void:
	_to_model = chain_to(skeleton, model)
	_rest.clear()
	_grest.clear()
	for i in BONE_NAMES.size():
		_rest.append(skeleton.get_bone_rest(_idx[i]))
		_grest.append(skeleton.get_bone_global_rest(_idx[i]))
	_hips_rest_y = (_to_model * _grest[HIPS]).origin.y
	var y_thigh := (_to_model * _grest[THIGH_L]).origin.y
	var y_shin := (_to_model * _grest[SHIN_L]).origin.y
	_rest_thigh = maxf(y_thigh - y_shin, 0.2)
	_rest_shin = maxf(y_shin - (_to_model * _grest[FOOT_L]).origin.y, 0.15)
	_rest_foot = maxf((_to_model * _grest[FOOT_L]).origin.y, 0.02)
	_sec_rest.clear()
	for sb in _sec:
		_sec_rest.append(skeleton.get_bone_rest(sb))
	if _sec.size() >= 2:
		var seg := _sec_rest[1].origin                  # the second pivot in the first one's frame: a chain that runs along the model's z axis is a tail
		_sec_tail = absf(seg.z) > absf(seg.y)
	_leg_x = absf(_rest[THIGH_R].origin.x)
	_leg_o = [_rest[THIGH_L].origin, _rest[THIGH_R].origin]
	_leg_t0 = [_rest[SHIN_L].origin, _rest[SHIN_R].origin]
	_leg_s0 = [_rest[FOOT_L].origin, _rest[FOOT_R].origin]
	_leg_l1 = _leg_t0[0].length()
	_leg_l2 = _leg_s0[0].length()
	_d_rest = (_leg_t0[0] + _leg_s0[0]).length()
	var torso_w := (_to_model * _grest[TORSO]).origin
	_rifle_o = _rest[RIFLE].origin
	var sides := [UARM_L, UARM_R]
	var fores := [FARM_L, FARM_R]
	var wrist_names := ["WristL", "WristR"]
	for k in 2:
		_sh[k] = _rest[sides[k]].origin
		_e0[k] = _sh[k] + _rest[fores[k]].origin
		var wn := model.get_node_or_null(wrist_names[k]) as Node3D
		var wp: Vector3 = (_e0[k] + Vector3(0.0, -0.28, -0.1)) if wn == null else (chain_to(wn, model).origin - torso_w)
		_w0[k] = wp
		_wrist_rest[k] = torso_w + wp
		var e: Vector3 = _e0[k]
		var s: Vector3 = _sh[k]
		_l1[k] = (e - s).length()
		_l2[k] = (wp - e).length()
		var n: Vector3 = (wp - s).normalized()
		var pv: Vector3 = (e - s) - n * (e - s).dot(n)
		_pole[k] = pv.normalized() if pv.length() > 0.001 else Vector3.DOWN
	var mw := model.get_node_or_null("MagWell") as Node3D
	var rifle_w := (_to_model * _grest[RIFLE]).origin
	_mag_rifle = ((chain_to(mw, model).origin - rifle_w) if mw != null else Vector3(0.0, -0.1, -0.2)) + Vector3(-0.02, -0.03, 0.08)
	var mp := model.get_node_or_null("MagPouch") as Node3D
	_pouch = ((chain_to(mp, model).origin - torso_w) if mp != null else Vector3(-0.09, 0.07, -0.2)) + Vector3(0.0, -0.03, 0.08)
	var mz := model.get_node_or_null("Muzzle") as Node3D
	if mz != null:
		var m0 := _to_model.affine_inverse() * chain_to(mz, model).origin
		_muzzle_off = _grest[RIFLE].affine_inverse() * m0
	_build_hulls()


## Convex hull points (model space, rest pose) of the vertices owned by each bone, for the resting height of a corpse.
func _build_hulls() -> void:
	_hulls.clear()
	for i in BONE_NAMES.size():
		_hulls.append(PackedVector3Array())
	var mesh := body_mesh.mesh
	if mesh == null:
		return
	var pts: Array = []
	for i in BONE_NAMES.size():
		pts.append(PackedVector3Array())
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var bones = arr[Mesh.ARRAY_BONES]
		var weights = arr[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights == null:
			continue
		var per := (bones as PackedInt32Array).size() / maxi(verts.size(), 1)
		var skin_idx := PackedInt32Array()
		skin_idx.resize(skeleton.get_bone_count())
		skin_idx.fill(-1)
		for i in BONE_NAMES.size():
			skin_idx[_idx[i]] = i
		var skin := body_mesh.skin
		var bind_map := PackedInt32Array()                 # the mesh stores skin bind indices; map them to our bone numbers
		if skin != null:
			for bi in skin.get_bind_count():
				var sb := skin.get_bind_bone(bi)
				if sb < 0:
					sb = skeleton.find_bone(String(skin.get_bind_name(bi)))
				bind_map.append(skin_idx[sb] if sb >= 0 and sb < skin_idx.size() else -1)
		for v in verts.size():
			var best := 0
			var bw := -1.0
			for k in per:
				var w: float = (weights as PackedFloat32Array)[v * per + k]
				if w > bw:
					bw = w
					best = (bones as PackedInt32Array)[v * per + k]
			var bi := -1
			if best < bind_map.size():
				bi = bind_map[best]
			elif skin == null and best < skin_idx.size():
				bi = skin_idx[best]
			if bi >= 0 and bw > 0.4:
				pts[bi].append(verts[v])               # the imported mesh is already in the model's own space (skinning ignores the node chain)
	for i in BONE_NAMES.size():
		var p := pts[i] as PackedVector3Array
		if p.size() < 4:
			_hulls[i] = p
			continue
		var hull := _hull_of(p)
		_hulls[i] = hull if not hull.is_empty() else p


static func _hull_of(points: PackedVector3Array) -> PackedVector3Array:
	var m := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var padded := points.duplicate()
	while padded.size() % 3 != 0:
		padded.append(points[0])
	arrays[Mesh.ARRAY_VERTEX] = padded
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var shape := m.create_convex_shape(true, false)
	return shape.points if shape != null else PackedVector3Array()


## World-space y of the lowest point of the body at its current pose (the hulls of the bones, moved by the bone transforms).
func lowest_world_y() -> float:
	var lo := INF
	var to_world := model.global_transform if model.is_inside_tree() else Transform3D.IDENTITY
	var inv_model := _to_model.affine_inverse()
	for i in BONE_NAMES.size():
		var pts := _hulls[i] as PackedVector3Array
		if pts.is_empty():
			continue
		var bone_move := _to_model * (skeleton.get_bone_global_pose(_idx[i]) * _grest[i].affine_inverse()) * inv_model
		var xf := to_world * bone_move
		for pt in pts:
			lo = minf(lo, (xf * pt).y)
	return lo


## The hull points of the bones (all of them, or only the listed bone numbers: THIGH_L ...) in world space (for tests and the corpse).
func world_points(only := PackedInt32Array()) -> PackedVector3Array:
	var out := PackedVector3Array()
	var to_world := model.global_transform if model.is_inside_tree() else Transform3D.IDENTITY
	var inv_model := _to_model.affine_inverse()
	for i in BONE_NAMES.size():
		if not only.is_empty() and not only.has(i):
			continue
		var bone_move := _to_model * (skeleton.get_bone_global_pose(_idx[i]) * _grest[i].affine_inverse()) * inv_model
		var xf := to_world * bone_move
		for pt in (_hulls[i] as PackedVector3Array):
			out.append(xf * pt)
	return out


## The sole contact point of a foot (k: 0 left, 1 right) at rest, model space: the hock's x and z on the floor.
func sole_rest(k: int) -> Vector3:
	var p := (_to_model * _grest[FOOT_L if k == 0 else FOOT_R]).origin
	return Vector3(p.x, 0.0, p.z)


## Where the glove cuff of a hand is now (k: 0 left, 1 right), model space: the forearm bone's pose applied to the rest wrist.
func wrist_position(k: int) -> Vector3:
	var fi := FARM_L if k == 0 else FARM_R
	var rest_wrist := _to_model.affine_inverse() * (_wrist_rest[k] as Vector3)
	var off_bone: Vector3 = _grest[fi].affine_inverse() * rest_wrist
	return _to_model * (skeleton.get_bone_global_pose(_idx[fi]) * off_bone)


## Where that wrist belongs on the rifle at the current pose (model space): the rifle bone's move applied to the rest wrist.
func rifle_grip(k: int) -> Vector3:
	return bone_move(RIFLE) * (_wrist_rest[k] as Vector3)


## The bone transform of a bone index (HIPS ...) in model space relative to its rest pose (identity at rest).
func bone_move(i: int) -> Transform3D:
	return _to_model * (skeleton.get_bone_global_pose(_idx[i]) * _grest[i].affine_inverse()) * _to_model.affine_inverse()


## Model-space transform of the muzzle point, following the rifle bone (assign it to the model's Muzzle node).
func muzzle_transform() -> Transform3D:
	var g := skeleton.get_bone_global_pose(_idx[RIFLE])
	var p: Vector3 = _to_model * (g * _muzzle_off)
	var d := g.basis * _grest[RIFLE].basis.inverse()
	var bm := _to_model.basis * d * _to_model.basis.inverse()
	return Transform3D(bm, p)


func _pose(i: int, delta: Basis, pos := Vector3.ZERO) -> void:
	var r := _rest[i]
	skeleton.set_bone_pose(_idx[i], Transform3D(r.basis * delta, r.origin + r.basis * pos))


func reset() -> void:
	for i in BONE_NAMES.size():
		skeleton.set_bone_pose(_idx[i], _rest[i])
	for k in _sec.size():
		skeleton.set_bone_pose(_sec[k], _sec_rest[k])


static func _smooth(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _frame(dir: Vector3, pole: Vector3) -> Basis:
	var x := pole - dir * pole.dot(dir)
	if x.length_squared() < 1e-8:
		x = dir.cross(Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, dir, x.cross(dir))


## Pose every bone from the input fields. Call once per rendered frame after setting them.
func apply() -> void:
	var d := clampf(dead, 0.0, 1.0)
	var hips_pos := Vector3.ZERO
	var hips_basis := Basis.IDENTITY
	if ik:
		hips_basis = Basis.from_euler(Vector3(0.0, pelvis_yaw, pelvis_roll))
		hips_pos = _legs_ik(d, hips_basis)
	else:
		hips_pos = _legs_legacy(d)
		hips_basis = Basis.from_euler(Vector3(0.0, -twist * 0.7, -roll * 0.5))

	# ------------------------------------------------------------------ pelvis and torso
	var tw := 0.0                                          # reload tilt weight
	if reload >= 0.0:
		tw = _smooth(reload / 0.14) * (1.0 - _smooth((reload - 0.8) / 0.2))
	var fdir := flinch_dir
	var fl_pitch := -flinch * 0.22
	var fl_roll := 0.0
	var fl_yaw := 0.0
	if fdir.length_squared() > 0.01:                       # a directional hit: from the front the chest is knocked back, from the side it rolls and twists away
		fl_pitch = flinch * 0.24 * fdir.y
		fl_roll = flinch * 0.2 * fdir.x
		fl_yaw = -flinch * 0.3 * fdir.x
	var breath_y := breathe * 0.2 - 0.12 * d
	hips_pos.y += breath_y
	hips_pos.z += recoil * 0.012
	_pose(HIPS, hips_basis, hips_pos)
	var tp := aim_pitch * 0.55 + lean + breathe + recoil * 0.05 + fl_pitch + extra_torso.x + 0.05 * tw
	var net_yaw := twist * 1.7 + extra_torso.y + fl_yaw
	var net_roll := roll + extra_torso.z + fl_roll
	if ik:
		_pose(TORSO, Basis.from_euler(Vector3(tp + 0.2 * d + _death_pitch(d), net_yaw - pelvis_yaw, net_roll - pelvis_roll)))
	else:
		_pose(TORSO, Basis.from_euler(Vector3(tp + 0.2 * d, twist * 1.7 + extra_torso.y, roll + extra_torso.z)))
	# the head keeps looking level while the torso leans, twists and bobs (stabilisation), takes the part of the aim pitch the torso does not, and looks where the aim goes
	var hp := aim_pitch * 0.55 - lean * 0.8 - breathe * 0.5 - 0.25 * d
	hp += (flinch * 0.34 * flinch_dir.y) if fdir.length_squared() > 0.01 else flinch * 0.3
	if ik:
		hp += head_look.y - 0.35 * tw - 0.35 * extra_torso.x - sin(phase * 2.0) * 0.015 * amp * (1.0 - air)
		_pose(HEAD, Basis.from_euler(Vector3(hp, head_yaw + head_look.x - net_yaw * 0.9, -net_roll * 0.8)))
	else:
		hp -= sin(phase * 2.0) * 0.02 * amp * (1.0 - air)
		_pose(HEAD, Basis.from_euler(Vector3(hp, head_yaw - twist * 1.0, -roll * 0.6)))

	# ------------------------------------------------------------------ rifle: ready / low ready / sprint carry, recoil and the reload tilt
	var low := (1.0 - ready) * (1.0 - sprint)
	var carry := sprint
	var rp := LOW_READY_PITCH * low + SPRINT_PITCH * carry
	var rr := 0.0
	var ry := -0.12 * low - 0.35 * carry
	var rpos := Vector3(0.0, -0.05 * low - 0.1 * carry, 0.04 * low + 0.06 * carry)
	var a := amp * (1.0 - air)
	var bounce := sin(phase * 2.0) * 0.012 * a
	rpos.y += bounce * (1.0 + carry)
	rp += sin(phase) * 0.03 * a * (1.0 - ready * 0.7)
	if ik:                                                 # the carried rifle rocks with the stride and the pelvis; shouldered, it stays steadier; aiming pulls it to the cheek
		rr += sin(phase) * 0.07 * a * carry
		ry += sin(phase) * 0.04 * a * (0.4 + carry) + ads * 0.13 + 0.5 * pelvis_yaw * ready
		rpos.y += 0.015 * ads - squash * 0.3
		rpos.z += 0.03 * ads
		rp += squash * 0.5 + air * 0.05
	rp += -0.22 * tw
	rr += 0.38 * tw
	rp += recoil * 0.07 + aim_pitch * 0.45 * ready
	rpos.z += recoil * 0.055
	rpos.y += recoil * 0.008
	rp += 0.5 * d
	var rb := Basis.from_euler(Vector3(rp, ry, rr))
	var dead_rb := Basis.from_euler(Vector3(-0.95, 0.15, 0.4))
	if d > 0.0:
		rb = dead_rb.slerp(rb, 1.0 - d) if d < 1.0 else dead_rb
	_pose(RIFLE, rb, rpos)

	# ------------------------------------------------------------------ arms: IK onto the rifle (or the magazine / the pouch while reloading)
	var swing := sin(phase) * a * (1.0 - ready)
	for k in 2:
		var left := k == 0
		var target: Vector3 = _rifle_o + rpos + rb * (_w0[k] - _rifle_o)
		if left and reload >= 0.0:
			target = _reload_hand(reload, target, rpos, rb)
		if left:
			target += Vector3(0.0, 0.0, -0.05 * swing)
		else:
			target += Vector3(0.0, 0.03 * swing, 0.025 * swing)
		if d > 0.0:
			var side := -1.0 if left else 1.0
			var hang: Vector3 = _sh[k] + _death_hang(side)
			target = target.lerp(hang, d)
		_solve_arm(k, target)
	_apply_secondary(d, 1.0 - air)


## The hanging pose of an arm of a body that is down, by the kind of fall (0 onto the side, 1 forward: the arms reach out to break the fall, 2 backward: flung wide).
func _death_hang(side: float) -> Vector3:
	match death_kind:
		1:
			return Vector3(side * 0.16, -0.36, -0.4)
		2:
			return Vector3(side * 0.45, -0.3, 0.12)
	return Vector3(side * 0.09, -0.58, 0.12)


func _death_pitch(d: float) -> float:
	match death_kind:
		1:
			return -0.35 * d
		2:
			return 0.3 * d
	return 0.0


## Legs of the older cycle model (a phase and an amplitude), used when the owner does not plant the feet (`ik` false). Returns the hips offset.
func _legs_legacy(d: float) -> Vector3:
	var grounded := 1.0 - air
	var a := amp * grounded
	var ph_l := phase
	var ph_r := phase + PI
	var sw_l := sin(ph_l) * a
	var sw_r := sin(ph_r) * a
	var ax_l := sw_l * fw * LEG_AMP / 0.62
	var ax_r := sw_r * fw * LEG_AMP / 0.62
	var kmax := lerpf(KNEE_WALK, KNEE_RUN, clampf(run, 0.0, 1.0)) * a
	var kn_l := kmax * maxf(0.0, cos(ph_l)) + 0.1 * a
	var kn_r := kmax * maxf(0.0, cos(ph_r)) + 0.1 * a
	var az_l := -0.18 * absf(lw) * a + 0.5 * sw_l * lw
	var az_r := 0.18 * absf(lw) * a - 0.5 * sw_r * lw
	ax_l = lerpf(ax_l, 0.5, air)
	ax_r = lerpf(ax_r, -0.35, air)
	kn_l = lerpf(kn_l, 0.8, air)
	kn_r = lerpf(kn_r, 0.4, air)
	ax_l = lerpf(ax_l, 0.65, knee_buckle)
	ax_r = lerpf(ax_r, 0.4, knee_buckle)
	kn_l = lerpf(kn_l, 1.5, knee_buckle)
	kn_r = lerpf(kn_r, 1.2, knee_buckle)
	ax_l = lerpf(ax_l, 0.45, d)
	az_l = lerpf(az_l, -0.17, d)
	ax_r = lerpf(ax_r, -0.3, d)
	az_r = lerpf(az_r, 0.09, d)
	kn_l = lerpf(kn_l, 0.35, d)
	kn_r = lerpf(kn_r, 0.15, d)
	hip_l = Vector2(ax_l, az_l)
	hip_r = Vector2(ax_r, az_r)
	var sole_lo := _hips_rest_y - _rest_thigh * cos(ax_l) - _rest_shin * cos(ax_l - kn_l) - _rest_foot
	var sole_hi := _hips_rest_y - _rest_thigh * cos(ax_r) - _rest_shin * cos(ax_r - kn_r) - _rest_foot
	var sink := -minf(sole_lo, sole_hi) * (1.0 - d) * grounded
	if knee_buckle > 0.0:
		sink = lerpf(sink, -0.32, knee_buckle)
	var w_l := 1.0 - _smooth((sole_lo - minf(sole_lo, sole_hi)) / 0.06)
	var w_r := 1.0 - _smooth((sole_hi - minf(sole_lo, sole_hi)) / 0.06)
	_pose(THIGH_L, Basis.from_euler(Vector3(ax_l, 0.0, az_l)))
	_pose(SHIN_L, Basis(Vector3.RIGHT, -kn_l))
	_pose(FOOT_L, Basis(Vector3.RIGHT, -(ax_l - kn_l) * lerpf(0.35, 1.0, w_l * grounded) * (1.0 - d * 0.7) - 0.25 * (1.0 - w_l) * grounded * a))
	_pose(THIGH_R, Basis.from_euler(Vector3(ax_r, 0.0, az_r)))
	_pose(SHIN_R, Basis(Vector3.RIGHT, -kn_r))
	_pose(FOOT_R, Basis(Vector3.RIGHT, -(ax_r - kn_r) * lerpf(0.35, 1.0, w_r * grounded) * (1.0 - d * 0.7) - 0.25 * (1.0 - w_r) * grounded * a))
	var bob := -absf(sin(phase)) * 0.012 * a
	return Vector3(0.0, sink + bob, 0.0)


## Legs on planted feet: the owner gives the sole contact point, heel / toe pitch and yaw of each foot (model space); the pelvis is lowered to what the legs reach
## (so the stance foot with the longest reach decides the height: the pelvis bobs by itself, highest at mid stance), and each leg is a two-bone solve (knee forward, the
## hock behind) with the metatarsal foot rolled about the sole. Returns the hips position offset from the rest pose.
func _legs_ik(d: float, hb: Basis) -> Vector3:
	var l1 := _leg_l1
	var l2 := _leg_l2
	var reach := (l1 + l2) * 0.995
	var dref := lerpf(_d_rest, (l1 + l2) * 0.965, clampf(run, 0.0, 1.0) * (1.0 - air))
	var hs := INF
	var wmax := 0.0
	var h_cap := INF                                       # a planted foot must stay within the reach of its leg whatever the blend below does
	for k in 2:
		var pt: float = pitch_l if k == 0 else pitch_r
		var hock: Vector3 = (sole_l if k == 0 else sole_r) + Basis(Vector3.UP, yaw_l if k == 0 else yaw_r) * Vector3(0.0, cos(pt), sin(pt)) * _rest_foot
		_hocks[k] = hock
		var j0 := Vector3(sway, 0.0, 0.0) + hb * (_leg_o[k] as Vector3)
		var hz := Vector2(hock.x - j0.x, hock.z - j0.z).length()
		var v := sqrt(maxf(dref * dref - hz * hz, 0.04))
		var hk := hock.y + v - j0.y
		var wk: float = support_l if k == 0 else support_r
		if wk > 0.05:
			hs = minf(hs, hk)
			wmax = maxf(wmax, wk)
		if (sole_l if k == 0 else sole_r).y < 0.004:
			var cap_k := hock.y + sqrt(maxf(reach * reach * 0.995 - hz * hz, 0.01)) - j0.y
			if hz >= reach * 0.85:                       # out of reach (a landing after a hard stop, a foot just off the floor): the cap fades in with the weight it carries
				cap_k = lerpf(_hips_rest_y, cap_k, clampf((wk - 0.05) * 2.0, 0.0, 1.0))
			h_cap = minf(h_cap, cap_k)
	var h_free := _hips_rest_y - 0.02
	var h := h_free if hs == INF else lerpf(h_free, hs, wmax)
	if hs != INF:                                          # a long stride must not fold the pelvis: the planted legs straighten first (bob stays a few centimetres)
		var bob_max := lerpf(0.05, 0.09, clampf(run, 0.0, 1.0)) + 0.05 * clampf(ads, 0.0, 1.0)
		h = maxf(h, minf(h_cap, _hips_rest_y - 0.02 - bob_max))
	h = minf(h, h_cap + 0.0) - squash
	var hips_off := Vector3(sway, h - _hips_rest_y, 0.0)
	var kneeling := maxf(d, knee_buckle)
	var hips_world := Vector3(sway, h, 0.0)
	for k in 2:
		var joint := hips_world + hb * (_leg_o[k] as Vector3)
		var p: Vector3 = (_hocks[k] as Vector3) - joint
		var dist := clampf(p.length(), absf(l1 - l2) + 0.03, reach)
		var u := p.normalized() if p.length() > 0.001 else Vector3.DOWN
		var aa := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
		var hh := sqrt(maxf(l1 * l1 - aa * aa, 0.0))
		var pole := Vector3(0.0, 0.0, -1.0)
		pole = pole - u * pole.dot(u)
		pole = pole.normalized() if pole.length() > 0.001 else Vector3.FORWARD
		var t := u * aa + pole * hh
		var s := u * dist - t
		var qt := Basis(Quaternion((_leg_t0[k] as Vector3).normalized(), t.normalized()))
		var qs := Basis(Quaternion((_leg_s0[k] as Vector3).normalized(), s.normalized()))
		var gf := Basis(Vector3.UP, yaw_l if k == 0 else yaw_r) * Basis(Vector3.RIGHT, pitch_l if k == 0 else pitch_r)
		var b_thigh := hb.transposed() * qt
		var b_shin := qt.transposed() * qs
		var b_foot := qs.transposed() * gf
		if kneeling > 0.0:                                 # a collapsing or fallen body: blend to the slack pose of the old model
			var left := k == 0
			var bax := lerpf(0.65 if left else 0.4, 0.45 if left else -0.3, d)
			var bkn := lerpf(1.5 if left else 1.2, 0.35 if left else 0.15, d)
			var baz := lerpf(0.0, -0.17 if left else 0.09, d)
			if death_kind == 1:
				bax = lerpf(bax, -0.25, d)
				bkn = lerpf(bkn, 0.5, d)
			elif death_kind == 2:
				bax = lerpf(bax, 0.2 if left else 0.1, d)
				bkn = lerpf(bkn, 0.15, d)
			var w := kneeling
			b_thigh = Basis(b_thigh.get_rotation_quaternion().slerp(Basis.from_euler(Vector3(bax, 0.0, baz)).get_rotation_quaternion(), w))
			b_shin = Basis(b_shin.get_rotation_quaternion().slerp(Basis(Vector3.RIGHT, -bkn).get_rotation_quaternion(), w))
			b_foot = Basis(b_foot.get_rotation_quaternion().slerp(Basis(Vector3.RIGHT, -(bax - bkn) * (1.0 - d * 0.7)).get_rotation_quaternion(), w))
			hips_off.y = lerpf(hips_off.y, -0.32 * knee_buckle if d < 0.01 else 0.0, w)
		var eu := b_thigh.get_euler()
		if k == 0:
			hip_l = Vector2(eu.x, eu.z)
			_pose(THIGH_L, b_thigh)
			_pose(SHIN_L, b_shin)
			_pose(FOOT_L, b_foot)
		else:
			hip_r = Vector2(eu.x, eu.z)
			_pose(THIGH_R, b_thigh)
			_pose(SHIN_R, b_shin)
			_pose(FOOT_R, b_foot)
	return hips_off


## The secondary chain (cloak or tail) trails the motion. With the owner's springs (`use_springs`) the bend comes from critically damped springs driven by the
## body's acceleration and turn rate; the stride ripple, the idle sway, a hit's whip and the tail's droop are added here. Without them everything is a function of the inputs.
func _apply_secondary(d: float, grounded: float) -> void:
	var n := _sec.size()
	if n == 0:
		return
	var a := amp * grounded
	var spd := a * fw * lerpf(0.6, 1.0, clampf(run, 0.0, 1.0))
	for k in n:
		var lag := float(k)
		var pitch := 0.0
		var side := 0.0
		if use_springs and k < 3:
			pitch = sec_pitch[k]
			side = sec_side[k]
		else:
			pitch = -(0.1 + 0.07 * lag) * spd - 0.3 * air * (1.0 + 0.4 * lag)
			side = -lw * (0.1 + 0.06 * lag) * a - twist * 0.5 * (lag + 1.0)
		pitch += 0.05 * sin(clock * 1.6 - lag * 0.9) + 0.045 * sin(phase * 2.0 - lag * 1.1) * a
		pitch += flinch * 0.12 * (lag + 1.0) + recoil * 0.05
		if _sec_tail:
			pitch += 0.45 * d + 0.08 * lag * d
		side += 0.05 * sin(clock * 1.1 - lag * 0.8 + 1.0) + 0.05 * sin(phase - lag * 1.3) * a
		var axis := Vector3.UP if _sec_tail else Vector3.BACK
		var delta := Basis(Vector3.RIGHT, pitch) * Basis(axis, side)
		var r := _sec_rest[k]
		skeleton.set_bone_pose(_sec[k], Transform3D(r.basis * delta, r.origin))


## Where the support hand (the left one) is during a reload: grip -> magazine well -> vest pouch (old magazine out) -> well (new one in) -> grip.
func _reload_hand(r: float, grip: Vector3, rpos: Vector3, rb: Basis) -> Vector3:
	var well := _rifle_o + rpos + rb * _mag_rifle
	var pouch := _pouch
	var pull := Vector3(0.0, -0.05, 0.0)
	if r < 0.18:
		return grip.lerp(well, _smooth(r / 0.18))
	if r < 0.42:
		return (well + pull).lerp(pouch, _smooth((r - 0.18) / 0.24))
	if r < 0.62:
		return pouch.lerp(well + pull, _smooth((r - 0.42) / 0.2))
	if r < 0.76:
		return (well + pull).lerp(well, _smooth((r - 0.62) / 0.06))
	return well.lerp(grip, _smooth((r - 0.76) / 0.24))


func _solve_arm(k: int, target: Vector3) -> void:
	var s: Vector3 = _sh[k]
	var l1: float = _l1[k]
	var l2: float = _l2[k]
	var n := target - s
	var dist := clampf(n.length(), absf(l1 - l2) + 0.02, (l1 + l2) * 0.995)
	var u := n.normalized() if n.length() > 0.0001 else Vector3.DOWN
	var aa := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - aa * aa, 0.0))
	var pole0: Vector3 = _pole[k]
	var p := pole0 - u * pole0.dot(u)
	p = p.normalized() if p.length() > 0.001 else pole0
	var e := s + u * aa + p * h
	var w := s + u * dist
	var ua := (e - s) / l1
	var fa := (w - e) / maxf((w - e).length(), 0.0001)
	var e0: Vector3 = _e0[k]
	var w0: Vector3 = _w0[k]
	var ua0 := (e0 - s) / l1
	var fa0 := (w0 - e0) / l2
	var r_up := _frame(ua, p) * _frame(ua0, pole0).inverse()
	var r_fa := _frame(fa, p) * _frame(fa0, pole0).inverse()
	var ui := UARM_L if k == 0 else UARM_R
	var fi := FARM_L if k == 0 else FARM_R
	_pose(ui, r_up)
	_pose(fi, r_up.inverse() * r_fa)
