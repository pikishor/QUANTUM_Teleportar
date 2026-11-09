extends SceneTree
## Converts the Quaternius animal packs (CC0, art_sources/open_animals/SOURCE.md) into lean, game-ready scenes: assets/models/animals/<species>.scn
##   - the FBX is imported by Godot itself (4.6 reads FBX natively), no Blender needed
##   - ALL surfaces are merged into ONE surface (one draw call per animal) with the material colours baked into COLOR (species tint applied there), so the game's own
##     `animal.gdshader` (vertex colour, wind-free, dissolve for the quantum-dust death) is the only material
##   - the rig and the clips are kept: AnimationPlayer with the loop clips `idle`, `walk`, `run`, `fly` / `swim` (the quadruped skeleton family of the farm pack shares bone names, so
##     the horse and cow clips also drive the sheep, llama, pig and zebra; position and scale tracks are dropped so a clip made for one body never stretches another)
##   - horns / antlers are generated geometry bound to the Head bone
##   - scaled to metres (`length` is the nose-to-tail length) and turned to face -Z (Godot forward), feet on y = 0
## Run (see convert_animals.sh): godot --headless --path <scratch project holding res://raw/*.fbx> -s convert_animals.gd -- <output dir>

const ANIMS_FROM_HORSE := ["idle", "walk", "run"]
## species -> {src, length (m), yaw (deg about Y to face -Z), tint (material name or surface index -> Color), horns, donor (clip source), clips {game clip -> source clip name}}
const SPECIES := {
	"horse": {"src": "horse", "length": 2.3, "flip": 180.0, "tint": {}, "clips": {"idle": "Idle", "walk": "Walk", "run": "Run", "dead": "Death"}},
	"deer": {"src": "horse", "length": 1.75, "flip": 180.0, "tint": {0: Color(0.52, 0.35, 0.20), 1: Color(0.26, 0.17, 0.10)}, "horns": "antlers", "clips": {"idle": "Idle", "walk": "Walk", "run": "Run", "dead": "Death"}},
	"zebra": {"src": "zebra", "length": 2.2, "flip": 180.0, "tint": {}, "clips": {"idle": "Idle", "walk": "Walk", "run": "Run", "dead": "Death"}},
	"cow": {"src": "cow", "length": 2.3, "flip": 180.0, "tint": {}, "clips": {"idle": "Idle", "walk": "Walk", "run": "Run", "dead": "Death"}},
	"sheep": {"src": "sheep", "length": 1.3, "flip": 180.0, "tint": {}, "donor": "cow", "clips": {"idle": "Idle", "walk": "Walk", "run": "Run"}},
	"goat": {"src": "llama", "length": 1.25, "flip": 180.0, "tint": {"Brown": Color(0.62, 0.55, 0.45), "White": Color(0.9, 0.88, 0.82), "Grey": Color(0.3, 0.28, 0.26)}, "horns": "goat", "donor": "horse", "clips": {"idle": "Idle", "walk": "Walk", "run": "Run"}},
	"boar": {"src": "pig", "length": 1.45, "flip": 180.0, "tint": {0: Color(0.30, 0.22, 0.17), 1: Color(0.22, 0.16, 0.12)}, "tusks": true, "donor": "cow", "clips": {"idle": "Idle", "walk": "Walk", "run": "Run"}},
	"wolf": {"src": "wolf", "length": 1.45, "flip": 180.0, "tint": {"Wolf": Color(0.50, 0.50, 0.53)}, "clips": {"idle": "Idle", "walk": "Walking"}},
	"coyote": {"src": "wolf", "length": 1.1, "flip": 180.0, "tint": {"Wolf": Color(0.66, 0.52, 0.34)}, "clips": {"idle": "Idle", "walk": "Walking"}},
	"fox": {"src": "red_fox", "length": 0.95, "flip": 180.0, "tint": {}, "clips": {"walk": "ArmatureAction"}},
	"songbird": {"src": "bird", "length": 0.22, "flip": 180.0, "tint": {0: Color(0.42, 0.32, 0.22), 1: Color(0.85, 0.7, 0.3)}, "clips": {"fly": "ArmatureAction"}},
	"seagull": {"src": "bird", "length": 0.55, "flip": 180.0, "tint": {0: Color(0.93, 0.94, 0.95), 1: Color(0.95, 0.65, 0.15)}, "clips": {"fly": "ArmatureAction"}},
	"eagle": {"src": "bird", "length": 0.95, "flip": 180.0, "tint": {0: Color(0.30, 0.20, 0.12), 1: Color(0.95, 0.78, 0.2)}, "clips": {"fly": "ArmatureAction"}},
	"fish": {"src": "fish", "length": 0.45, "flip": 180.0, "tint": {0: Color(0.72, 0.78, 0.80)}, "clips": {"swim": "ArmatureAction"}},
	"shark": {"src": "fish", "length": 3.2, "flip": 180.0, "tint": {0: Color(0.40, 0.46, 0.52)}, "fin": true, "clips": {"swim": "ArmatureAction"}},
	"dolphin": {"src": "whale", "length": 2.5, "flip": 180.0, "tint": {0: Color(0.52, 0.60, 0.68), 1: Color(0.86, 0.9, 0.93)}, "clips": {"swim": "ArmatureAction"}},
	"whale": {"src": "whale", "length": 11.0, "flip": 180.0, "tint": {0: Color(0.28, 0.34, 0.42), 1: Color(0.8, 0.84, 0.88)}, "clips": {"swim": "ArmatureAction"}},
}


var root_holder: Node


func _init() -> void:
	root_holder = Node.new()
	get_root().add_child(root_holder)
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "res://out"
	var only: Array = (args[1] as String).split(",") if args.size() > 1 else []
	DirAccess.make_dir_recursive_absolute(out_dir)
	for id: String in SPECIES:
		if not only.is_empty() and not only.has(id):
			continue
		var def: Dictionary = SPECIES[id]
		var err := _convert(id, def, out_dir)
		print("%s: %s" % [id, "ok" if err == OK else "ERROR %d" % err])
	quit()


func _load(src: String) -> Node3D:
	return (load("res://raw/%s.fbx" % src) as PackedScene).instantiate() as Node3D


func _convert(id: String, def: Dictionary, out_dir: String) -> int:
	var root := _load(def["src"])
	for n in root.find_children("*", "Light3D", true, false) + root.find_children("*", "Camera3D", true, false):
		n.get_parent().remove_child(n)
		n.free()
	var skel: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var mi: MeshInstance3D = skel.find_children("*", "MeshInstance3D", true, false)[0]
	var src_mesh: ArrayMesh = mi.mesh as ArrayMesh
	var to_root: Transform3D = _xform_to(root, mi)
	# ---- merge the surfaces with baked colours, in root space ----
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var bones := PackedInt32Array()
	var wts := PackedFloat32Array()
	var idx := PackedInt32Array()
	var tint: Dictionary = def["tint"]
	for s in src_mesh.get_surface_count():
		var arr := src_mesh.surface_get_arrays(s)
		var mat := src_mesh.surface_get_material(s) as BaseMaterial3D
		var col := mat.albedo_color if mat != null else Color(0.7, 0.7, 0.7)
		var mname := mat.resource_name if mat != null else ""
		if tint.has(mname):
			col = tint[mname]
		elif tint.has(s):
			col = tint[s]
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nv: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var b: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var base := verts.size()
		var per := b.size() / v.size()
		for i in v.size():
			verts.append(v[i])
			norms.append(nv[i])
			cols.append(col)
		for i in v.size():
			for k in 4:
				bones.append(b[i * per + k] if k < per else 0)
				wts.append(w[i * per + k] if k < per else 0.0)
		for i in ind:
			idx.append(base + i)
	# renormalise the weights (4 influences)
	for i in verts.size():
		var sum := wts[i * 4] + wts[i * 4 + 1] + wts[i * 4 + 2] + wts[i * 4 + 3]
		if sum > 0.0001:
			for k in 4:
				wts[i * 4 + k] /= sum
	# ---- horns, tusks and the shark fin (bound to a bone) ----
	if def.get("horns", "") != "":
		_add_horns(def["horns"], mi.skin, verts, norms, cols, bones, wts, idx, to_root)
	# ---- the new mesh (vertex space unchanged: it still matches the skin) ----
	var am := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = wts
	arrays[Mesh.ARRAY_INDEX] = idx
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = am
	mi.skin = mi.skin.duplicate() as Skin                   # a resource that still points into the FBX would be saved as an external reference
	# ---- scale, face -Z, feet on y = 0 : done on the model node so the rig keeps its own units. The size comes from the POSED skeleton (bone origins), not from the bind-pose
	# vertices (the packs are exported with armature rotations and scales that make the raw bounds meaningless) ----
	var wrapper := Node3D.new()
	wrapper.name = id
	var model := root
	model.name = "Model"
	model.scene_file_path = ""                              # the imported scene's children become plain nodes of this scene
	wrapper.add_child(model)
	root_holder.add_child(wrapper)
	var ap0: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var first := _first_clip(ap0, def)
	ap0.play(first)
	ap0.advance(0.01)
	var to_model := _xform_to(model, skel)
	var lo := Vector3(1.0e9, 1.0e9, 1.0e9)
	var hi := Vector3(-1.0e9, -1.0e9, -1.0e9)
	for i in skel.get_bone_count():
		var p: Vector3 = to_model * skel.get_bone_global_pose(i).origin
		lo = lo.min(p)
		hi = hi.max(p)
	var ext := hi - lo
	var yaw := 0.0 if ext.z >= ext.x else PI * 0.5
	var along := maxf(ext.x, ext.z)
	var k: float = float(def["length"]) / (maxf(along, 0.0001) * float(def.get("bone_pad", 1.12)))
	yaw += deg_to_rad(float(def.get("flip", 0.0)))
	var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(k, k, k))
	var c := (lo + hi) * 0.5
	var off := -(basis * Vector3(c.x, lo.y, c.z))
	model.transform = Transform3D(basis, off)
	model.owner = wrapper
	_own(model, wrapper)
	print("   bones extent=%s yaw=%.0f k=%.4f" % [str(ext), rad_to_deg(yaw), k])
	# ---- clips ----
	var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var lib := AnimationLibrary.new()
	var donor_name: String = def.get("donor", "")
	var donor_ap: AnimationPlayer = null
	var donor_root: Node3D = null
	if donor_name != "":
		donor_root = _load(donor_name)
		donor_ap = donor_root.find_children("*", "AnimationPlayer", true, false)[0]
	for game_clip: String in def["clips"]:
		var want: String = def["clips"][game_clip]
		var anim := _find_clip(donor_ap if donor_ap != null else ap, want)
		if anim == null:
			continue
		anim = anim.duplicate() as Animation
		anim.loop_mode = Animation.LOOP_NONE if game_clip == "dead" else Animation.LOOP_LINEAR
		if donor_ap != null:
			_strip_tracks(anim, skel)
		lib.add_animation(game_clip, anim)
	for old in ap.get_animation_library_list():
		ap.remove_animation_library(old)
	ap.add_animation_library("", lib)
	ap.stop()
	var scene := PackedScene.new()
	scene.pack(wrapper)
	var path := "%s/%s.scn" % [out_dir, id]
	var err := ResourceSaver.save(scene, path, ResourceSaver.FLAG_COMPRESS)
	print("   %s tris=%d verts=%d clips=%s" % [path, idx.size() / 3, verts.size(), str(lib.get_animation_list())])
	if donor_root != null:
		donor_root.free()
	wrapper.free()
	return err


func _own(n: Node, owner_node: Node) -> void:
	for ch in n.get_children():
		ch.owner = owner_node
		_own(ch, owner_node)


func _first_clip(ap: AnimationPlayer, def: Dictionary) -> StringName:
	for want: String in ["Idle", "Walk", "Walking", "ArmatureAction"]:
		var a := _find_clip(ap, want)
		if a != null:
			for n in ap.get_animation_list():
				if ap.get_animation(n) == a:
					return n
	return ap.get_animation_list()[0]


func _find_clip(ap: AnimationPlayer, want: String) -> Animation:
	for a in ap.get_animation_list():
		var s := String(a)
		if s == want or s.ends_with("|" + want):
			return ap.get_animation(a)
	return null


## Keeps rotation tracks of the bones the target skeleton has; drops position / scale tracks (made for another body) and tracks of missing bones.
func _strip_tracks(anim: Animation, skel: Skeleton3D) -> void:
	for t in range(anim.get_track_count() - 1, -1, -1):
		var p := String(anim.track_get_path(t))
		var bone := p.get_slice(":", 1)
		var typ := anim.track_get_type(t)
		if typ != Animation.TYPE_ROTATION_3D or skel.find_bone(bone) < 0:
			anim.remove_track(t)


func _xform_to(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _bounds(verts: PackedVector3Array, t: Transform3D) -> AABB:
	var bb := AABB(t * verts[0], Vector3.ZERO)
	for v in verts:
		bb = bb.expand(t * v)
	return bb


func _head_bone(skel: Skeleton3D) -> int:
	return skel.find_bone("Head")


func _add_horns(kind: String, skin: Skin, verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, bones: PackedInt32Array, wts: PackedFloat32Array, idx: PackedInt32Array, to_root: Transform3D) -> void:
	# The packs are exported with a rotated armature, so the body axes in vertex space are found, not assumed: UP is the world up seen from vertex space, the body runs along the
	# axis with the longest extent, and the end whose dominant bone is the Head or the Neck is the face. The skull is 11 % of the length at that end.
	var up := (to_root.basis.inverse() * Vector3.UP).normalized()
	var bb := _bounds(verts, Transform3D.IDENTITY)
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var long_i := 0
	for i in 3:
		if bb.size[i] > bb.size[long_i] and absf(axes[i].dot(up)) < 0.9:
			long_i = i
	var fwd := Vector3.ZERO
	var head := -1
	var skull := PackedVector3Array()
	var lo := 1.0e9
	var hi := -1.0e9
	for v in verts:
		lo = minf(lo, v[long_i])
		hi = maxf(hi, v[long_i])
	for sg in [1.0, -1.0]:
		var cand := PackedVector3Array()
		var weight_of := {}
		for i in verts.size():
			var near: bool = verts[i][long_i] > hi - (hi - lo) * 0.11 if sg > 0.0 else verts[i][long_i] < lo + (hi - lo) * 0.11
			if near:
				cand.append(verts[i])
				for k in 4:
					weight_of[bones[i * 4 + k]] = float(weight_of.get(bones[i * 4 + k], 0.0)) + wts[i * 4 + k]
		var best := -1.0
		var bone := -1
		for bi in weight_of:
			if float(weight_of[bi]) > best:
				best = float(weight_of[bi])
				bone = int(bi)
		var nm := String(skin.get_bind_name(bone)) if bone >= 0 and bone < skin.get_bind_count() else ""
		print("   end %+d on axis %d: verts=%d dominant bone=%s" % [int(sg), long_i, cand.size(), nm])
		if nm.begins_with("Head") or nm.begins_with("Neck"):
			skull = cand
			head = bone
			fwd = axes[long_i] * sg
			break
	if skull.size() < 4:
		return
	var side := fwd.cross(up).normalized()
	var f_lo := 1.0e9
	var f_hi := -1.0e9
	var u_hi := -1.0e9
	var s_lo := 1.0e9
	var s_hi := -1.0e9
	for v in skull:
		f_lo = minf(f_lo, v.dot(fwd))
		f_hi = maxf(f_hi, v.dot(fwd))
		u_hi = maxf(u_hi, v.dot(up))
		s_lo = minf(s_lo, v.dot(side))
		s_hi = maxf(s_hi, v.dot(side))
	var sc := (f_hi - f_lo) * 0.9
	var s_mid := (s_lo + s_hi) * 0.5
	var half := (s_hi - s_lo) * 0.5
	print("   skull f=%.4f..%.4f up=%.4f side=%.4f sc=%.4f" % [f_lo, f_hi, u_hi, half, sc])
	for sx in [-1.0, 1.0]:
		var base: Vector3 = fwd * (f_lo + (f_hi - f_lo) * 0.25) + up * (u_hi - sc * 0.12) + side * (s_mid + sx * half * 0.55)
		if kind == "antlers":
			var col := Color(0.80, 0.74, 0.60)
			_stick(verts, norms, cols, bones, wts, idx, head, base, up * 1.0 - fwd * 0.2 + side * sx * 0.3, sc * 1.9, sc * 0.075, col, 3)
			_stick(verts, norms, cols, bones, wts, idx, head, base + up * sc * 0.95 - fwd * sc * 0.15, up * 0.6 + fwd * 0.8 + side * sx * 0.2, sc * 1.0, sc * 0.05, col, 3)
			_stick(verts, norms, cols, bones, wts, idx, head, base + up * sc * 1.4, up * 1.0 - fwd * 0.5 + side * sx * 0.8, sc * 0.9, sc * 0.05, col, 3)
			_stick(verts, norms, cols, bones, wts, idx, head, base + up * sc * 0.5, up * 0.7 + fwd * 0.3 + side * sx * 0.9, sc * 0.8, sc * 0.05, col, 3)
		else:
			_stick(verts, norms, cols, bones, wts, idx, head, base, up * 1.0 - fwd * 0.9 + side * sx * 0.25, sc * 1.7, sc * 0.14, Color(0.20, 0.18, 0.16), 4)


## A thin tapering prism from `base` along `dir`, `len` long, `thick` wide at the base, `sides` sides, bound to bone `bone`.
func _stick(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, bones: PackedInt32Array, wts: PackedFloat32Array, idx: PackedInt32Array, bone: int, base: Vector3, dir: Vector3, len: float, thick: float, col: Color, sides: int) -> void:
	var d := dir.normalized()
	var up := Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT
	var a := d.cross(up).normalized()
	var b := d.cross(a).normalized()
	var v0 := verts.size()
	for ring in 2:
		var p := base + d * (len * float(ring))
		var r := thick * (1.0 - 0.85 * float(ring))
		for s in sides:
			var ang := TAU * float(s) / float(sides)
			var off := (a * cos(ang) + b * sin(ang))
			verts.append(p + off * r)
			norms.append(off)
			cols.append(col)
			bones.append_array([bone, 0, 0, 0])
			wts.append_array([1.0, 0.0, 0.0, 0.0])
	for s in sides:
		var n := (s + 1) % sides
		idx.append_array([v0 + s, v0 + sides + s, v0 + n, v0 + n, v0 + sides + s, v0 + sides + n])
