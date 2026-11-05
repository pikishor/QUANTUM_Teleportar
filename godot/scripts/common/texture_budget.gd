class_name TextureBudget
extends RefCounted
## LOW-tier texture memory. The imported model atlases are 2048 px (ASTC / BPTC with mipmaps, about 5.6 MB each, several per character, car and drone); the LOW tier
## already sampled their 1024 px level (mip bias), so the top level was dead weight in GPU memory. `halve_models()` replaces every model texture of 1024 px or more by its
## own second mip level (compressed data, no re-encode: the image is read back, the first level is cut off, the rest uploaded as a new texture) in the SHARED materials of
## the model scenes, so the full-size textures are freed. Run it BEFORE the models are instantiated (main.gd), only on the LOW tier; the textures stay at half size
## until the next launch. Skips quietly when the texture data cannot be read (headless, a GPU-only format).

const MODELS: Array[String] = ["player", "operative", "drone_heavy", "drone_sentinel", "drone_striker", "car_sedan", "car_sport", "car_suv", "car_taxi", "car_wagon", "car_van", "car_truck", "bike_street", "car_hover", "car_vael_patrol", "core_gem", "pickup_energy", "pickup_health"]
const MIN_SIDE := 1024

static var halved_count := 0
static var low_active := false                  ## set by halve_models() (the LOW tier): HeroCharacter halves its own textures through halve_texture()
static var saved_bytes := 0
static var _half_cache := {}                    ## original path -> its half-size copy (one per file, shared by the model scenes and every instance copy of their materials)
static var _half_path := {}                     ## instance id of a half-size copy -> the path of the full-size file
static var _low_orig: Array = []                ## [material, slot, original resource path] of every halved model texture, so a switch to MED / HIGH can reload the full-size file


## Halve every large model texture. Returns the number of textures replaced.
static func halve_models() -> int:
	low_active = true
	if DisplayServer.get_name() == "headless":
		return 0
	var n := 0
	for model_name in MODELS:
		var path := "res://assets/models/%s.glb" % model_name
		if not ResourceLoader.exists(path):
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		var inst := scene.instantiate()
		for node in inst.find_children("*", "MeshInstance3D", true, false):
			var mesh := (node as MeshInstance3D).mesh
			if mesh == null:
				continue
			for i in mesh.get_surface_count():
				var mat := mesh.surface_get_material(i) as BaseMaterial3D
				if mat == null:
					continue
				for slot in BaseMaterial3D.TEXTURE_MAX:
					var tex := mat.get_texture(slot as BaseMaterial3D.TextureParam)
					if tex == null:
						continue
					if tex.resource_path == "":
						continue                # already a halved copy (no file behind it)
					var half: Texture2D = _low_tex(tex)
					if half != null:
						_low_orig.append([mat, slot, tex.resource_path])
						mat.set_texture(slot as BaseMaterial3D.TextureParam, half)
						n += 1
		inst.free()
	halved_count += n
	retarget_tree()
	return n


## The half-size copy of a model texture file (cached per file), null when the texture is not a file under assets/textures or cannot be halved.
static func _low_tex(tex: Texture2D) -> Texture2D:
	var p := tex.resource_path if tex != null else ""
	if not p.begins_with("res://assets/textures/"):
		return null
	if not _half_cache.has(p):
		var h := _halved(tex)
		_half_cache[p] = h if h != tex else null
		if h != tex:
			_half_path[h.get_instance_id()] = p
	return _half_cache[p]


## Every material in the running scene tree that is a COPY of a model material (cars paint, drones, the hero shader) holds its own texture references, so the shared-material swaps above
## do not reach them: bring their textures to the current state (half size on LOW, the full files otherwise, the 2K twins on HIGH, the 1K files otherwise).
static func retarget_tree() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return 0
	var n := 0
	var seen := {}
	var stack: Array = [tree.root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if not node is GeometryInstance3D:
			continue
		var gi := node as GeometryInstance3D
		var mats: Array = []
		if gi.material_override != null:
			mats.append(gi.material_override)
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
			var mesh := (gi as MeshInstance3D).mesh
			for i in mesh.get_surface_count():
				mats.append(gi.get_surface_override_material(i))
				mats.append(mesh.surface_get_material(i))
		for m: Material in mats:
			if m == null or seen.has(m):
				continue
			seen[m] = true
			n += _retarget_material(m)
	return n


static func _retarget_material(m: Material) -> int:
	var n := 0
	if m is BaseMaterial3D:
		var bm := m as BaseMaterial3D
		for slot in BaseMaterial3D.TEXTURE_MAX:
			var t := bm.get_texture(slot as BaseMaterial3D.TextureParam)
			if t == null:
				continue
			var r := _retarget_texture(t, true)
			if r != null:
				bm.set_texture(slot as BaseMaterial3D.TextureParam, r)
				n += 1
	elif m is ShaderMaterial and (m as ShaderMaterial).shader != null and (m as ShaderMaterial).shader.resource_path == HeroCharacter.SHADER:
		var sm := m as ShaderMaterial
		for u in sm.shader.get_shader_uniform_list():
			var v: Variant = sm.get_shader_parameter(u["name"])
			if not v is Texture2D:
				continue
			var t := v as Texture2D
			var r := _retarget_texture(t, false)
			if r != null:
				sm.set_shader_parameter(u["name"], r)
				n += 1
	return n


## The texture `t` should be replaced by for the current tier state, or null when it is right already.
static func _retarget_texture(t: Texture2D, twins: bool) -> Texture2D:
	var out: Texture2D = null
	if low_active:
		out = _low_tex(t)
	elif _half_path.has(t.get_instance_id()):
		out = load(_half_path[t.get_instance_id()]) as Texture2D
	if twins:
		var base: Texture2D = out if out != null else t
		var p := base.resource_path
		if high_active:
			var p2 := high_path(p) if p != "" else ""
			if p2 != "":
				out = load(p2) as Texture2D
		elif p.contains("_2k."):
			var p1 := p.replace("_2k.", ".")
			if ResourceLoader.exists(p1):
				out = load(p1) as Texture2D
	return out if out != t else null


## Leaving the LOW tier: reload the full-size model textures into the shared materials (the half-size copies are freed once nothing else uses them).
static func restore_models() -> int:
	var n := 0
	for e: Array in _low_orig:
		var mat := e[0] as BaseMaterial3D
		var tex := load(e[2]) as Texture2D if ResourceLoader.exists(e[2]) else null
		if mat != null and tex != null:
			mat.set_texture(e[1] as BaseMaterial3D.TextureParam, tex)
			n += 1
	_low_orig.clear()
	low_active = false
	retarget_tree()
	_half_cache.clear()
	_half_path.clear()
	return n


## Public wrapper: the half-size copy of a large texture (the texture itself when its data cannot be read, e.g. headless).
static func halve_texture(tex: Texture2D) -> Texture2D:
	return _halved(tex)


static func _halved(tex: Texture2D) -> Texture2D:
	if tex.get_width() < MIN_SIDE or tex.get_height() < MIN_SIDE:
		return tex
	var img := tex.get_image()
	if img == null or img.is_empty() or img.get_mipmap_count() < 1:
		return tex
	var fmt := img.get_format()
	var data := img.get_data().slice(img.get_mipmap_offset(1))
	var out := Image.create_from_data(img.get_width() / 2, img.get_height() / 2, img.get_mipmap_count() > 1, fmt, data)
	if out == null or out.is_empty():
		return tex
	saved_bytes += img.get_mipmap_offset(1)
	return ImageTexture.create_from_image(out)


## HIGH tier only: full-resolution (2K) ORM / emission maps for the hero and the starter car (sedan). Every other asset keeps its 1K import, so LOW and MED never load these
## files (they are separate `*_2k` imports, loaded only here). Replaces the textures in the SHARED materials of the model scenes, before the models are instantiated.
const HIGH_MODELS: Array[String] = ["player", "car_sedan"]
static var high_count := 0
static var high_active := false
static var _held: Array[PackedScene] = []
static var _high_orig: Array = []               ## [material, slot, 1K file path] of every texture upgrade_high replaced        ## keeps the upgraded scenes (and their shared materials) cached, otherwise the changes are lost when the scene is freed


## "res://assets/textures/x_orm.jpg" -> its 2K twin path (or "" when there is none).
static func high_path(path: String) -> String:
	var stem := path.get_basename()
	if not (stem.ends_with("_orm") or stem.ends_with("_emit")):
		return ""
	var p2 := "%s_2k.%s" % [stem, path.get_extension()]
	return p2 if ResourceLoader.exists(p2) else ""


static func upgrade_high() -> int:
	high_active = true
	var n := 0
	for model_name in HIGH_MODELS:
		var path := "res://assets/models/%s.glb" % model_name
		if not ResourceLoader.exists(path):
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		_held.append(scene)
		var inst := scene.instantiate()
		for node in inst.find_children("*", "MeshInstance3D", true, false):
			var mesh := (node as MeshInstance3D).mesh
			if mesh == null:
				continue
			for i in mesh.get_surface_count():
				var mat := mesh.surface_get_material(i) as BaseMaterial3D
				if mat == null:
					continue
				for slot in [BaseMaterial3D.TEXTURE_ORM, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION, BaseMaterial3D.TEXTURE_EMISSION]:
					var tex := mat.get_texture(slot)
					if tex == null or tex.resource_path == "":
						continue
					var p2 := high_path(tex.resource_path)
					if p2 == "":
						continue
					var t2 := load(p2) as Texture2D
					if t2 != null and t2 != tex:
						_high_orig.append([mat, slot, tex.resource_path])
						mat.set_texture(slot, t2)
						n += 1
		inst.free()
	high_count += n
	retarget_tree()
	return n


## Leaving the HIGH tier: put the 1K maps back into the shared materials and let go of the cached scenes, so the 2K twins are freed.
static func downgrade_high() -> int:
	var n := 0
	for e: Array in _high_orig:
		var mat := e[0] as BaseMaterial3D
		var tex := load(e[2]) as Texture2D if ResourceLoader.exists(e[2]) else null
		if mat != null and tex != null:
			mat.set_texture(e[1] as int, tex)
			n += 1
	_high_orig.clear()
	_held.clear()
	high_active = false
	retarget_tree()
	return n


## Runtime tier change (PerfTiers, after the world applied the tier): load or release what the new tier needs, then drop the surface caches the tier no longer uses.
## LOW = half-size model atlases, MED = the 1K imports, HIGH = those plus the 2K twins. Idempotent: it acts on the actual state.
static func set_tier(level: int) -> void:
	if level <= 0:
		if high_active:
			downgrade_high()
		if not low_active:
			halve_models()
	else:
		if low_active:
			restore_models()
		if level >= 2 and not high_active:
			upgrade_high()
		elif level < 2 and high_active:
			downgrade_high()
	SurfaceTextures.prune(level)
	MaterialLib.prune(level)
