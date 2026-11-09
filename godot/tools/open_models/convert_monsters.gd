extends SceneTree
## Converts the Quaternius Ultimate Monsters rigs (CC0, art_sources/quaternius_ultimate_monsters) into the lean alien creatures of the outskirts: assets/models/aliens/<id>.scn
##   - the glTF is imported by Godot itself, no Blender needed
##   - ALL surfaces become ONE surface (one draw call per creature). The atlas colour is sampled at every vertex into COLOR.rgb (so no texture memory is spent), re-graded to the quantum-
##     realism palette (hue shift, saturation, value, a darkening toward the feet) and the cartoon eyes and teeth (the near-white atlas pixels) become the GLOW MASK in COLOR.a: the game's own
##     `alien.gdshader` turns that mask into bioluminescent eyes, seams and teeth in the species' glow colour
##   - the mesh is simplified with Godot's own meshoptimizer LODs (ImporterMesh.generate_lods): the LOD whose triangle count is nearest to `tris` is kept, unused vertices are dropped
##   - the rig and the clips are kept: AnimationPlayer with idle / walk / run / attack / hit / dead / jump (flyers: idle / fly / attack / hit / dead)
##   - scaled to metres (`fit`: height, length or span of the POSED body) and turned to face -Z (Godot forward), feet (or the belly) on y = 0
## Run (see convert_monsters.sh): godot --headless --path <scratch project holding res://raw/*.gltf and res://raw/atlas.png> -s convert_monsters.gd -- <output dir> [id,id,...]

const BIPED_CLIPS := {"idle": "Idle", "walk": "Walk", "run": "Run", "attack": "Punch", "hit": "HitReact", "dead": "Death", "jump": "Jump"}
const BLOB_CLIPS := {"idle": "Idle", "walk": "Walk", "attack": "Bite_Front", "hit": "HitRecieve", "dead": "Death", "jump": "Jump"}
const FLYER_CLIPS := {"idle": "Flying_Idle", "fly": "Fast_Flying", "attack": "Headbutt", "hit": "HitReact", "dead": "Death", "punch": "Punch"}

## id -> {src (raw file), fit {height|length|span: metres}, tris (target), hue (degrees), sat, val, foot (darkening toward the ground 0..1), glow (Color of eyes, teeth and seams), flip (deg), clips}
const SPECIES := {
	"grunt": {"src": "big_alien", "fit": {"height": 1.9}, "tris": 1700, "hue": 40.0, "sat": 0.70, "val": 0.82, "foot": 0.25, "glow": Color(0.35, 1.0, 0.55), "clips": BIPED_CLIPS},
	"spitter": {"src": "big_bluedemon", "fit": {"height": 1.8}, "tris": 1500, "hue": 130.0, "sat": 0.77, "val": 0.78, "foot": 0.25, "glow": Color(0.75, 1.0, 0.15), "clips": BIPED_CLIPS},
	"brute": {"src": "big_yeti", "fit": {"height": 3.1}, "tris": 1800, "hue": 0.0, "sat": 0.60, "val": 0.88, "foot": 0.3, "glow": Color(0.35, 0.8, 1.0), "clips": BIPED_CLIPS},
	"stalker": {"src": "big_ninja", "fit": {"height": 1.85}, "tris": 1500, "hue": 170.0, "sat": 0.55, "val": 0.95, "foot": 0.1, "glow": Color(1.0, 0.25, 0.4), "clips": BIPED_CLIPS},
	"skitter": {"src": "big_dino", "fit": {"height": 1.25}, "tris": 1300, "hue": -15.0, "sat": 0.75, "val": 0.82, "foot": 0.3, "glow": Color(1.0, 0.62, 0.15), "clips": BIPED_CLIPS},
	"broodmother": {"src": "big_mushroomking", "fit": {"height": 4.4}, "tris": 2600, "hue": 215.0, "sat": 0.7, "val": 0.88, "foot": 0.3, "glow": Color(0.8, 0.4, 1.0), "clips": BIPED_CLIPS},
	"popper": {"src": "blob_greenblob", "fit": {"height": 1.05}, "tris": 900, "hue": -20.0, "sat": 0.9, "val": 0.92, "foot": 0.15, "glow": Color(0.95, 1.0, 0.2), "clips": BLOB_CLIPS},
	"swarmer": {"src": "flying_armabee", "fit": {"span": 1.1}, "tris": 900, "hue": 10.0, "sat": 0.75, "val": 0.9, "foot": 0.0, "glow": Color(1.0, 0.7, 0.1), "clips": FLYER_CLIPS},
	"storm_drake": {"src": "flying_dragon_evolved", "fit": {"span": 7.5}, "tris": 2600, "hue": 190.0, "sat": 0.75, "val": 0.88, "foot": 0.0, "glow": Color(0.45, 0.85, 1.0), "clips": FLYER_CLIPS},
	"warden": {"src": "flying_goleling_evolved", "fit": {"span": 4.6}, "tris": 2300, "hue": 20.0, "sat": 0.55, "val": 0.78, "foot": 0.0, "glow": Color(0.3, 1.0, 0.9), "clips": FLYER_CLIPS},
	"glider": {"src": "flying_squidle", "fit": {"span": 2.4}, "tris": 1400, "hue": 120.0, "sat": 0.7, "val": 0.92, "foot": 0.0, "glow": Color(0.3, 1.0, 0.95), "clips": FLYER_CLIPS},
}

var root_holder: Node
var atlas: Image


func _init() -> void:
	root_holder = Node.new()
	get_root().add_child(root_holder)
	atlas = Image.load_from_file(ProjectSettings.globalize_path("res://raw/atlas.png"))
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "res://out"
	var only: Array = (args[1] as String).split(",") if args.size() > 1 else []
	DirAccess.make_dir_recursive_absolute(out_dir)
	for id: String in SPECIES:
		if not only.is_empty() and not only.has(id):
			continue
		var err := _convert(id, SPECIES[id], out_dir)
		print("%s: %s" % [id, "ok" if err == OK else "ERROR %d" % err])
	quit()


func _sample(uv: Vector2) -> Color:
	var x := int(floorf(fposmod(uv.x, 1.0) * float(atlas.get_width()))) % atlas.get_width()
	var y := int(floorf(fposmod(uv.y, 1.0) * float(atlas.get_height()))) % atlas.get_height()
	return atlas.get_pixel(x, y)


func _grade(c: Color, def: Dictionary) -> Color:
	var hh := c.h + float(def["hue"]) / 360.0
	hh = hh - floorf(hh)
	return Color.from_hsv(hh, clampf(c.s * float(def["sat"]), 0.0, 1.0), clampf(c.v * float(def["val"]), 0.0, 1.0))


func _convert(id: String, def: Dictionary, out_dir: String) -> int:
	var root := (load("res://raw/%s.gltf" % def["src"]) as PackedScene).instantiate() as Node3D
	for n in root.find_children("*", "Light3D", true, false) + root.find_children("*", "Camera3D", true, false):
		n.get_parent().remove_child(n)
		n.free()
	var skel: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var mis := skel.find_children("*", "MeshInstance3D", true, false)
	var mi: MeshInstance3D = mis[0]
	var src_meshes: Array[ArrayMesh] = []
	for m in mis:                                                               # a few rigs (the mushroom king, the blobs) are several meshes on one skin: they are merged
		src_meshes.append((m as MeshInstance3D).mesh as ArrayMesh)
	# ---- merge the surfaces: sampled colour, grade, glow mask ----
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var bones := PackedInt32Array()
	var wts := PackedFloat32Array()
	var idx := PackedInt32Array()
	var glow: Color = def["glow"]
	var surfaces: Array = []
	for sm in src_meshes:
		for s in sm.get_surface_count():
			surfaces.append(sm.surface_get_arrays(s))
	for arr: Array in surfaces:
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nv: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var b: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var base := verts.size()
		var per := b.size() / v.size()
		for i in v.size():
			var raw := _sample(uv[i]) if uv.size() > i else Color(0.6, 0.6, 0.6)
			var eye := raw.v > 0.72 and raw.s < 0.3                         # the near-white eyes and teeth of the pack
			var col := _grade(raw, def)
			var a := 0.0
			if eye:
				col = glow.lerp(Color.WHITE, 0.35)
				a = 1.0
			verts.append(v[i])
			norms.append(nv[i])
			cols.append(Color(col.r, col.g, col.b, a))
			for k in 4:
				bones.append(b[i * per + k] if k < per else 0)
				wts.append(w[i * per + k] if k < per else 0.0)
		for i in ind:
			idx.append(base + i)
	# ---- simplify with meshoptimizer's LODs: keep the one nearest to the triangle target ----
	var arrays0 := []
	arrays0.resize(Mesh.ARRAY_MAX)
	arrays0[Mesh.ARRAY_VERTEX] = verts
	arrays0[Mesh.ARRAY_NORMAL] = norms
	arrays0[Mesh.ARRAY_COLOR] = cols
	arrays0[Mesh.ARRAY_BONES] = bones
	arrays0[Mesh.ARRAY_WEIGHTS] = wts
	arrays0[Mesh.ARRAY_INDEX] = idx
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays0)
	im.generate_lods(25.0, 60.0, [])
	var best_i := PackedInt32Array(idx)
	var best_d := absf(float(idx.size() / 3) - float(def["tris"]))
	for l in im.get_surface_lod_count(0):
		var li := im.get_surface_lod_indices(0, l)
		var d := absf(float(li.size() / 3) - float(def["tris"]))
		if d < best_d:
			best_d = d
			best_i = li
	# drop the unused vertices
	var remap := {}
	var nverts := PackedVector3Array()
	var nnorms := PackedVector3Array()
	var ncols := PackedColorArray()
	var nbones := PackedInt32Array()
	var nwts := PackedFloat32Array()
	var nidx := PackedInt32Array()
	for i in best_i:
		if not remap.has(i):
			remap[i] = nverts.size()
			nverts.append(verts[i])
			nnorms.append(norms[i])
			ncols.append(cols[i])
			for k in 4:
				nbones.append(bones[i * 4 + k])
				nwts.append(wts[i * 4 + k])
		nidx.append(remap[i])
	for i in nverts.size():
		var sum := nwts[i * 4] + nwts[i * 4 + 1] + nwts[i * 4 + 2] + nwts[i * 4 + 3]
		if sum > 0.0001:
			for k in 4:
				nwts[i * 4 + k] /= sum
	# ---- the new mesh (vertex space unchanged: it still matches the skin) ----
	var am := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = nverts
	arrays[Mesh.ARRAY_NORMAL] = nnorms
	arrays[Mesh.ARRAY_COLOR] = ncols
	arrays[Mesh.ARRAY_BONES] = nbones
	arrays[Mesh.ARRAY_WEIGHTS] = nwts
	arrays[Mesh.ARRAY_INDEX] = nidx
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = am
	mi.skin = mi.skin.duplicate() as Skin
	for extra in mis.slice(1):
		extra.get_parent().remove_child(extra)
		extra.free()
	# ---- the foot gradient (darker toward the ground) needs the posed height: measure the posed body first ----
	var wrapper := Node3D.new()
	wrapper.name = id
	var model := root
	model.name = "Model"
	model.scene_file_path = ""
	wrapper.add_child(model)
	root_holder.add_child(wrapper)
	var ap0: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var first := _find_name(ap0, String((def["clips"] as Dictionary).get("idle", (def["clips"] as Dictionary).get("fly", "Idle"))))
	if first != &"":
		ap0.play(first)
		ap0.advance(0.01)
	var to_model := _xform_to(model, skel)
	var lo := Vector3(1.0e9, 1.0e9, 1.0e9)
	var hi := Vector3(-1.0e9, -1.0e9, -1.0e9)
	var bone_of := PackedInt32Array()
	for i in mi.skin.get_bind_count():
		var bi := mi.skin.get_bind_bone(i)
		if bi < 0:
			bi = skel.find_bone(mi.skin.get_bind_name(i))
		bone_of.append(bi)
	var posed := PackedVector3Array()
	for i in nverts.size():
		var acc := Vector3.ZERO
		for k in 4:
			var wk := nwts[i * 4 + k]
			if wk <= 0.0:
				continue
			var bs := nbones[i * 4 + k]
			var gp := skel.get_bone_global_pose(bone_of[bs]) * mi.skin.get_bind_pose(bs)
			acc += wk * (gp * nverts[i])
		var p := to_model * acc
		posed.append(p)
		lo = lo.min(p)
		hi = hi.max(p)
	var ext := hi - lo
	var fit: Dictionary = def["fit"]
	var k := 1.0
	if fit.has("height"):
		k = float(fit["height"]) / maxf(ext.y, 0.0001)
	elif fit.has("length"):
		k = float(fit["length"]) / maxf(maxf(ext.x, ext.z), 0.0001)
	else:
		k = float(fit["span"]) / maxf(maxf(ext.x, ext.z), 0.0001)
	# face -Z: the packs face +Z in glTF space; `flip` turns them (the viewer shows the result)
	var yaw := deg_to_rad(float(def.get("flip", 180.0)))
	var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(k, k, k))
	var c := (lo + hi) * 0.5
	var floor_y := lo.y if float(def.get("foot", 0.0)) > 0.0 or not fit.has("span") else lo.y
	var off := -(basis * Vector3(c.x, floor_y, c.z))
	model.transform = Transform3D(basis, off)
	model.owner = wrapper
	_own(model, wrapper)
	# darken toward the feet now that the height is known (vertex colours stay sRGB values)
	var foot := float(def.get("foot", 0.0))
	if foot > 0.0:
		var cc := PackedColorArray(ncols)
		for i in cc.size():
			var t := clampf((posed[i].y - lo.y) / maxf(ext.y, 0.0001), 0.0, 1.0)
			var d := 1.0 - foot * (1.0 - t)
			cc[i] = Color(cc[i].r * d, cc[i].g * d, cc[i].b * d, cc[i].a)
		arrays[Mesh.ARRAY_COLOR] = cc
		var am2 := ArrayMesh.new()
		am2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mi.mesh = am2
	print("   posed extent=%s k=%.4f tris=%d verts=%d" % [str(ext), k, nidx.size() / 3, nverts.size()])
	# ---- clips ----
	var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var lib := AnimationLibrary.new()
	for game_clip: String in def["clips"]:
		var want: String = def["clips"][game_clip]
		var nm := _find_name(ap, want)
		if nm == &"":
			continue
		var anim := ap.get_animation(nm).duplicate() as Animation
		anim.loop_mode = Animation.LOOP_NONE if (game_clip == "dead" or game_clip == "hit" or game_clip == "attack" or game_clip == "punch" or game_clip == "jump") else Animation.LOOP_LINEAR
		lib.add_animation(game_clip, anim)
	for old in ap.get_animation_library_list():
		ap.remove_animation_library(old)
	ap.add_animation_library("", lib)
	ap.stop()
	var scene := PackedScene.new()
	scene.pack(wrapper)
	var path := "%s/%s.scn" % [out_dir, id]
	var err := ResourceSaver.save(scene, path, ResourceSaver.FLAG_COMPRESS)
	print("   %s clips=%s" % [path, str(lib.get_animation_list())])
	wrapper.free()
	return err


func _own(n: Node, owner_node: Node) -> void:
	for ch in n.get_children():
		ch.owner = owner_node
		_own(ch, owner_node)


func _find_name(ap: AnimationPlayer, want: String) -> StringName:
	for a in ap.get_animation_list():
		var s := String(a)
		if s == want or s.ends_with("|" + want):
			return a
	return &""


func _xform_to(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
