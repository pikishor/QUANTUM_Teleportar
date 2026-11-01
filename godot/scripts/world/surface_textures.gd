class_name SurfaceTextures
extends RefCounted
## Tier-scaled PBR surface sets (tools/textures/gen_surfaces.py -> assets/textures/surface_*.png, VRAM compressed with mipmaps, see ARCHITECTURE.md "Surfaces").
## LOW loads nothing (the shaders keep their procedural look, `srf_k` = 0), MED loads the sets at half size (the 2K ones lose their top mip level: compressed data,
## no re-encode, `TextureBudget._halved`), HIGH loads them in full and the shaders add the second scale and the decal mask. Textures are cached per name and size.
## `apply(material, sets, tier)` sets the samplers named `srf_<key>` plus `srf_k`, `srf_hi`, `srf_bias` (tier numbers come from `PerfTiers`).

const DIR := "res://assets/textures/surface_%s.png"
## key -> [file stem, albedo suffix, normal suffix] (decals and trim have their own naming)
const SETS := {
	"road": "asphalt", "walk": "sidewalk", "brick": "brick", "wall": "concrete", "roof": "roof_tar", "metal": "painted_metal", "corr": "corrugated",
}
static var _cache := {}


## Texture taps for the tier (PerfTiers.surface_taps); the environment variable QT_SURFACES=0 switches them off for before / after captures.
static func taps(tier: int) -> int:
	return 0 if OS.get_environment("QT_SURFACES") == "0" else PerfTiers.surface_taps(tier)


## The texture for `file` ("asphalt_albedo", "decals", ...) at the tier's size, null when LOW or when the file is missing.
static func tex(file: String, tier: int) -> Texture2D:
	if taps(tier) == 0:
		return null
	var half := tier == 1
	var key := "%s|%d" % [file, 1 if half else 2]
	if _cache.has(key):
		return _cache[key]
	var path := DIR % file
	if not ResourceLoader.exists(path):
		return null
	var t := load(path) as Texture2D
	if t != null and half:
		t = TextureBudget._halved(t)          # returns the texture itself when the data cannot be read (headless)
	_cache[key] = t
	return t


## The neon-text glyph atlas (tools/textures/gen_signage.py), cached; null when the file is missing.
static func sign_atlas() -> Texture2D:
	if not _cache.has("sign_atlas"):
		_cache["sign_atlas"] = load("res://assets/textures/signage_atlas.png") if ResourceLoader.exists("res://assets/textures/signage_atlas.png") else null
	return _cache["sign_atlas"]


## Bind the sets `keys` (SETS keys, plus "decal", "trim" and "sign") to `mat` for the tier; LOW clears them and switches the taps off.
static func apply(mat: ShaderMaterial, keys: Array, tier: int) -> void:
	var n_taps := taps(tier)
	mat.set_shader_parameter(&"srf_k", 1.0 if n_taps >= 1 else 0.0)
	mat.set_shader_parameter(&"srf_hi", 1.0 if n_taps >= 2 else 0.0)
	mat.set_shader_parameter(&"srf_bias", PerfTiers.surface_mip_bias(tier))
	for k: String in keys:
		if k == "sign":
			mat.set_shader_parameter(&"sign_atlas", sign_atlas())        # the neon-text distance atlas (18 KB, lossless, every tier: it IS the signage)
		elif k == "decal":
			mat.set_shader_parameter(&"srf_decal", tex("decals", tier) if n_taps >= 2 else null)        # the decal mask is a HIGH tap
		elif k == "trim":
			mat.set_shader_parameter(&"srf_trim_a", tex("trim_albedo", tier))
			mat.set_shader_parameter(&"srf_trim_n", tex("trim_normal", tier))
		else:
			var stem: String = SETS[k]
			mat.set_shader_parameter("srf_%s_a" % k, tex(stem + "_albedo", tier))
			mat.set_shader_parameter("srf_%s_n" % k, tex(stem + "_normal", tier))


## Estimated GPU bytes of everything the tier would load (4x4 block formats are 1 byte per texel, +1/3 for mipmaps; half size on MED).
static func estimate_bytes(tier: int) -> int:
	if taps(tier) == 0:
		return 0
	var total := 0
	for f in ["asphalt_albedo", "asphalt_normal", "sidewalk_albedo", "sidewalk_normal", "brick_albedo", "brick_normal", "concrete_albedo", "concrete_normal",
			"roof_tar_albedo", "roof_tar_normal", "painted_metal_albedo", "painted_metal_normal", "corrugated_albedo", "corrugated_normal", "trim_albedo", "trim_normal", "decals"]:
		var t := load(DIR % f) as Texture2D
		if t == null:
			continue
		if f == "decals" and tier < 2:
			continue
		var px := float(t.get_width() * t.get_height())
		if tier == 1 and t.get_width() >= 2048:
			px *= 0.25
		total += int(px * 4.0 / 3.0)
	return total
