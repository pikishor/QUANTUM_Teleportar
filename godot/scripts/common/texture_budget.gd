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


## Halve every large model texture. Returns the number of textures replaced.
static func halve_models() -> int:
	low_active = true
	if DisplayServer.get_name() == "headless":
		return 0
	var done := {}
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
					if not done.has(tex):
						done[tex] = _halved(tex)
					var half: Texture2D = done[tex]
					if half != null and half != tex:
						mat.set_texture(slot as BaseMaterial3D.TextureParam, half)
						n += 1
		inst.free()
	halved_count += n
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
static var _held: Array[PackedScene] = []        ## keeps the upgraded scenes (and their shared materials) cached, otherwise the changes are lost when the scene is freed


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
						mat.set_texture(slot, t2)
						n += 1
		inst.free()
	high_count += n
	return n
