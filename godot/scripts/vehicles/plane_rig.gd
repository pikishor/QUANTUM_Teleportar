class_name PlaneRig
extends RefCounted
## WAVE 129 (w129-machanim): the MOVING PARTS of a procedural aeroplane (PlaneModels): ailerons, flaps, elevators, rudders on their hinge lines, landing gear legs that fold
## away and the doors that close over them. They are cut out of the near body (PlaneModels._geom, rig mode) and built into the "Detail" mesh as a SKINNED mesh: one bone per part
## (bone 0 = the fixed detail: struts, pods, sensors), so the whole set still draws as the one Detail draw call it was. Each live plane owns a small Skeleton3D ("Rig") whose bone
## rotations MachAnim.plane writes from the stick, the lever and the gear state. The far body (Body_LOD1) keeps every surface fixed and closed.
##   part(rig, name, kind, builder, pivot, axis, sign)   PlaneModels._geom registers a part (axis oriented so that a positive angle = trailing edge down / right, gear folded)
##   skinned(det, rig) -> ArrayMesh                     the Detail mesh: det on bone 0, every part on its own bone (one surface per material)
##   skin(rig) -> Skin                                  the binds (shared by every plane of the kind)
##   make_skeleton(rig) -> Skeleton3D                   the per-plane skeleton ("Rig"), at rest
##   pose(skel, rig, d)                                 sets the bones: d = {aileron, elevator, rudder, flap (rad), gear (0 down .. 1 up), door (0 closed .. 1 open)}
## Hinge axes: a part turns about its hinge line, oriented so that a POSITIVE angle moves the trailing edge against the panel's up vector (wing: down; fin, whose up is +X: left).
## Kinds: &"aileron" (side -1 / 1: opposite), &"flap", &"elevator", &"rudder", &"ruddervator" (side), &"elevon" (side), &"gear" (fold rad), &"door" (open rad).

const AILERON := 0.32
const ELEVATOR := 0.3
const RUDDER := 0.35
const FLAP := 0.55
const GEAR_FOLD := 1.62
const DOOR_OPEN := 1.45


static func part(rig: Array, name: String, kind: StringName, b: RefCounted, pivot: Vector3, axis: Vector3, sgn := 1.0, fold := 0.0) -> void:
	rig.append({"name": name, "kind": kind, "b": b, "pivot": pivot, "axis": axis.normalized(), "sign": sgn, "fold": fold})


## Detail as one skinned mesh: every surface (material) of the fixed detail and of each part merged, bone index per vertex.
static func skinned(det: RefCounted, rig: Array) -> ArrayMesh:
	var by_mat := {}                                            # material name -> [verts, normals, bones, weights, material]
	var order: Array[String] = []
	var srcs: Array = [[det, 0]]
	for i in rig.size():
		srcs.append([rig[i]["b"], i + 1])
	for e: Array in srcs:
		var b: PlaneModels = e[0]
		if b == null or b._empty():
			continue
		var m: ArrayMesh = b._finish()
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			var key := mat.resource_name if mat != null else "?"
			if not by_mat.has(key):
				by_mat[key] = [PackedVector3Array(), PackedVector3Array(), PackedInt32Array(), PackedFloat32Array(), mat]
				order.append(key)
			var arr := m.surface_get_arrays(s)
			var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var slot: Array = by_mat[key]
			var pv: PackedVector3Array = slot[0]                  # packed arrays are values: append to a copy and store it back
			pv.append_array(vv)
			slot[0] = pv
			var pn: PackedVector3Array = slot[1]
			pn.append_array(nn)
			slot[1] = pn
			var bones := PackedInt32Array()
			var wts := PackedFloat32Array()
			bones.resize(vv.size() * 4)
			wts.resize(vv.size() * 4)
			for k in vv.size():
				bones[k * 4] = int(e[1])
				wts[k * 4] = 1.0
			var pb: PackedInt32Array = slot[2]
			pb.append_array(bones)
			slot[2] = pb
			var pw: PackedFloat32Array = slot[3]
			pw.append_array(wts)
			slot[3] = pw
	var out := ArrayMesh.new()
	for key in order:
		var slot: Array = by_mat[key]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = slot[0]
		arr[Mesh.ARRAY_NORMAL] = slot[1]
		arr[Mesh.ARRAY_BONES] = slot[2]
		arr[Mesh.ARRAY_WEIGHTS] = slot[3]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, slot[4])
	return out


static func skin(rig: Array) -> Skin:
	var sk := Skin.new()
	sk.add_bind(0, Transform3D.IDENTITY)
	for i in rig.size():
		sk.add_bind(i + 1, Transform3D(Basis.IDENTITY, rig[i]["pivot"] as Vector3).affine_inverse())
	return sk


static func make_skeleton(rig: Array) -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Rig"
	sk.add_bone("root")
	for i in rig.size():
		var b := sk.add_bone(String(rig[i]["name"]))
		sk.set_bone_parent(b, 0)
		sk.set_bone_rest(b, Transform3D(Basis.IDENTITY, rig[i]["pivot"] as Vector3))
		sk.set_bone_pose_position(b, rig[i]["pivot"] as Vector3)
	return sk


## The angle (rad) of one part for the deflections `d`.
static func angle_of(p: Dictionary, d: Dictionary) -> float:
	var sgn := float(p["sign"])
	match StringName(p["kind"]):
		&"aileron":
			return float(d.get("aileron", 0.0)) * sgn
		&"elevon":
			return float(d.get("aileron", 0.0)) * sgn - float(d.get("elevator", 0.0))
		&"flap":
			return float(d.get("flap", 0.0))
		&"elevator":
			return -float(d.get("elevator", 0.0))
		&"ruddervator":                                     # the panel's "up" points outward and down: a positive angle lifts its trailing edge
			return float(d.get("elevator", 0.0)) + float(d.get("rudder", 0.0)) * sgn * 0.6
		&"rudder":                                          # the fin's "up" is +X: a positive angle swings the trailing edge left
			return -float(d.get("rudder", 0.0))
		&"gear":
			return float(p["fold"]) * float(d.get("gear", 0.0))
		&"door":
			return float(p["fold"]) * float(d.get("door", 1.0))
	return 0.0


static func pose(skel: Skeleton3D, rig: Array, d: Dictionary) -> void:
	for i in rig.size():
		var p: Dictionary = rig[i]
		skel.set_bone_pose_rotation(i + 1, Quaternion(p["axis"] as Vector3, angle_of(p, d)))
