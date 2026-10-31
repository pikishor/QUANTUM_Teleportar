class_name CharacterRig
extends RefCounted
## Procedural pose of the articulated character models (assets/models/player.glb and operative.glb).
##
## The model is ONE skinned mesh ("Body", one surface, one draw call) on a Skeleton3D whose rigid bones are the named pivots of the contract:
##   Hips > Torso > Head, UpperArmL/R > ForeArmL/R, Rifle ;  Hips > ThighL/R > ShinL/R > FootL/R
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
const REST_THIGH := 0.43              ## hip joint to knee, knee to ankle, ankle to sole (metres, from the model)
const REST_SHIN := 0.40
const REST_FOOT := 0.10
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
	_leg_x = absf(_rest[THIGH_R].origin.x)
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
	# ------------------------------------------------------------------ legs (hip swing, knee flexion, flat feet, the pelvis follows the lowest foot)
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
	# a collapsing body: the knees give way
	ax_l = lerpf(ax_l, 0.65, knee_buckle)
	ax_r = lerpf(ax_r, 0.4, knee_buckle)
	kn_l = lerpf(kn_l, 1.5, knee_buckle)
	kn_r = lerpf(kn_r, 1.2, knee_buckle)
	# slack legs of the fallen body
	ax_l = lerpf(ax_l, 0.45, d)
	az_l = lerpf(az_l, -0.17, d)
	ax_r = lerpf(ax_r, -0.3, d)
	az_r = lerpf(az_r, 0.09, d)
	kn_l = lerpf(kn_l, 0.35, d)
	kn_r = lerpf(kn_r, 0.15, d)
	hip_l = Vector2(ax_l, az_l)
	hip_r = Vector2(ax_r, az_r)
	# height of the two soles above the floor with the pelvis at rest height (flat feet), the lower one decides how far the pelvis sinks
	var sole_l := _hips_rest_y - REST_THIGH * cos(ax_l) - REST_SHIN * cos(ax_l - kn_l) - REST_FOOT
	var sole_r := _hips_rest_y - REST_THIGH * cos(ax_r) - REST_SHIN * cos(ax_r - kn_r) - REST_FOOT
	var sink := -minf(sole_l, sole_r) * (1.0 - d) * grounded
	if knee_buckle > 0.0:
		sink = lerpf(sink, -0.32, knee_buckle)
	var w_l := 1.0 - _smooth((sole_l - minf(sole_l, sole_r)) / 0.06)    # 1 = this foot carries the weight
	var w_r := 1.0 - _smooth((sole_r - minf(sole_l, sole_r)) / 0.06)
	_pose(THIGH_L, Basis.from_euler(Vector3(ax_l, 0.0, az_l)))
	_pose(SHIN_L, Basis(Vector3.RIGHT, -kn_l))
	_pose(FOOT_L, Basis(Vector3.RIGHT, -(ax_l - kn_l) * lerpf(0.35, 1.0, w_l * grounded) * (1.0 - d * 0.7) - 0.25 * (1.0 - w_l) * grounded * a))
	_pose(THIGH_R, Basis.from_euler(Vector3(ax_r, 0.0, az_r)))
	_pose(SHIN_R, Basis(Vector3.RIGHT, -kn_r))
	_pose(FOOT_R, Basis(Vector3.RIGHT, -(ax_r - kn_r) * lerpf(0.35, 1.0, w_r * grounded) * (1.0 - d * 0.7) - 0.25 * (1.0 - w_r) * grounded * a))

	# ------------------------------------------------------------------ pelvis and torso
	var bob := -absf(sin(phase)) * 0.012 * a
	_pose(HIPS, Basis.from_euler(Vector3(0.0, -twist * 0.7, -roll * 0.5)), Vector3(0.0, sink + bob + breathe * 0.2 - 0.12 * d, recoil * 0.012))
	var tp := aim_pitch * 0.55 + lean + breathe + recoil * 0.05 - flinch * 0.22 + extra_torso.x
	_pose(TORSO, Basis.from_euler(Vector3(tp + 0.2 * d, twist * 1.7 + extra_torso.y, roll + extra_torso.z)))
	# the head follows the aim: it takes the part of the pitch the torso does not, and keeps looking level while the torso leans and bobs
	var hp := aim_pitch * 0.55 - lean * 0.8 - breathe * 0.5 + flinch * 0.3 - 0.25 * d - sin(phase * 2.0) * 0.02 * a
	_pose(HEAD, Basis.from_euler(Vector3(hp, head_yaw - twist * 1.0, -roll * 0.6)))

	# ------------------------------------------------------------------ rifle: ready / low ready / sprint carry, recoil and the reload tilt
	var low := (1.0 - ready) * (1.0 - sprint)
	var carry := sprint
	var rp := LOW_READY_PITCH * low + SPRINT_PITCH * carry
	var rr := 0.0
	var ry := -0.12 * low - 0.35 * carry
	var rpos := Vector3(0.0, -0.05 * low - 0.1 * carry, 0.04 * low + 0.06 * carry)
	var bounce := sin(phase * 2.0) * 0.012 * a
	rpos.y += bounce * (1.0 + carry)
	rp += sin(phase) * 0.03 * a * (1.0 - ready * 0.7)
	var tw := 0.0
	if reload >= 0.0:
		tw = _smooth(reload / 0.14) * (1.0 - _smooth((reload - 0.8) / 0.2))
		rp += -0.22 * tw
		rr += 0.38 * tw
	rp += recoil * 0.07 + aim_pitch * 0.45 * ready
	rpos.z += recoil * 0.055
	rpos.y += recoil * 0.008
	rp += 0.5 * d
	var rb := Basis.from_euler(Vector3(rp, ry, rr))
	if d > 0.0:
		rb = Basis.from_euler(Vector3(-0.95, 0.15, 0.4)).slerp(rb, 1.0 - d) if d < 1.0 else Basis.from_euler(Vector3(-0.95, 0.15, 0.4))
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
			var hang: Vector3 = _sh[k] + Vector3(-0.09 if left else 0.09, -0.58, 0.12)
			target = target.lerp(hang, d)
		_solve_arm(k, target)


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
