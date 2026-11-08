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
## file stems of the four layers of the district sidewalk array (district id order)
const WALK_LAYERS: Array[String] = ["walk_market", "walk_foundry", "sidewalk", "walk_towers"]
## Scanned (Poly Haven, CC0) sets from tools/materials/pack_world_materials.py, packed in the same slot format (assets/textures/world_<name>_a.webp / _n.webp, 1024 px at every tier).
## They replace the procedural set of the slot when ALL their files exist; a missing file keeps the procedural one (nothing else changes).
const WORLD := "res://assets/textures/world_%s.webp"
const WORLD_SLOTS := {"brick": "brick", "wall": "wall", "metal": "metal", "corr": "corr"}
const ROAD_LAYERS: Array[String] = ["road_market", "road_foundry", "road_slums", "road_towers"]
const WALK_SCAN_LAYERS: Array[String] = ["walk_market", "walk_foundry", "walk_slums", "walk_towers"]
static var _cache := {}


## True when the scanned pair (or pairs) of a world name list exist.
static func has_world(names: Array) -> bool:
	for n: String in names:
		if not ResourceLoader.exists(WORLD % (n + "_a")) or not ResourceLoader.exists(WORLD % (n + "_n")):
			return false
	return true


## True when the slot (brick, wall, metal, corr) is served by a scanned set.
static func scanned_slot(slot: String) -> bool:
	return WORLD_SLOTS.has(slot) and OS.get_environment("QT_SCANNED") != "0" and has_world([WORLD_SLOTS[slot]])


static func scanned_roads() -> bool:
	return OS.get_environment("QT_SCANNED") != "0" and has_world(ROAD_LAYERS)


static func scanned_walks() -> bool:
	return OS.get_environment("QT_SCANNED") != "0" and has_world(WALK_SCAN_LAYERS)


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
	var path := (WORLD % file.trim_prefix("world:")) if file.begins_with("world:") else (DIR % file)
	if not ResourceLoader.exists(path):
		return null
	var t := load(path) as Texture2D
	if t != null and half and not file.begins_with("world:"):
		t = TextureBudget._halved(t)          # returns the texture itself when the data cannot be read (headless)
	_cache[key] = t
	return t


## District sidewalk variants as ONE texture array (layer = district id: 0 market hex flagstones, 1 foundry tread plate, 2 slums = the plain sidewalk set, 3 towers polished slabs),
## `kind` "albedo" or "normal". HIGH uploads the 2048 px layers, MED the 1024 px level of each (the top mip is cut off the compressed data, no re-encode), LOW loads nothing.
## Null when the data cannot be read (headless, a GPU-only format): the shader then keeps its single sidewalk set (`srf_walkv` = 0).
static func walk_array(kind: String, tier: int) -> Texture2DArray:
	if scanned_walks():
		return _layer_array("walkv", WALK_SCAN_LAYERS, kind, tier, true)
	return _layer_array("walkv", WALK_LAYERS, kind, tier, false)


## The four district roads (market clean asphalt, foundry pit-lane, slums cracked and patched, towers worn) as one texture array, `kind` "albedo" or "normal"; null when the scanned set is missing.
static func road_array(kind: String, tier: int) -> Texture2DArray:
	if not scanned_roads():
		return null
	return _layer_array("roadv", ROAD_LAYERS, kind, tier, true)


static func _layer_array(tag: String, stems: Array[String], kind: String, tier: int, scanned: bool) -> Texture2DArray:
	var low := tier == 0 and scanned and kind == "albedo" and OS.get_environment("QT_SCANNED") != "0"       # LOW: the scanned ALBEDO layers at 512 px (one tap in the lite shaders)
	if taps(tier) == 0 and not low:
		return null
	var half := tier == 1
	var key := "%s%s_%s|%d" % [tag, "_scan" if scanned else "", kind, 0 if low else (1 if half else 2)]
	if _cache.has(key):
		return _cache[key]
	var images: Array[Image] = []
	for stem in stems:
		var path := (WORLD % ("%s_%s" % [stem, "a" if kind == "albedo" else "n"])) if scanned else (DIR % ("%s_%s" % [stem, kind]))
		if not ResourceLoader.exists(path):
			_cache[key] = null
			return null
		var t := load(path) as Texture2D
		var img: Image = null if t == null else t.get_image()
		if img == null or img.is_empty() or img.get_mipmap_count() < 1:
			_cache[key] = null
			return null
		if (half and img.get_width() >= 2048) or (low and img.get_width() >= 1024):
			img = Image.create_from_data(img.get_width() / 2, img.get_height() / 2, img.get_mipmap_count() > 1, img.get_format(), img.get_data().slice(img.get_mipmap_offset(1)))
		images.append(img)
	var arr := Texture2DArray.new()
	if arr.create_from_images(images) != OK:
		_cache[key] = null
		return null
	_cache[key] = arr
	return arr


## Interior sampler uniforms of assets/shaders/interior_surface.gdshader -> scanned file stems (one tap each, every tier: the interior is a single draw call).
const INTERIOR := {"scan_plaster": "i_plaster", "scan_brick": "i_brick", "scan_tile": "i_tile", "scan_check": "i_check", "scan_concrete": "i_concrete", "scan_wood": "i_wood"}


static func scanned_interiors() -> bool:
	if OS.get_environment("QT_SCANNED") == "0":
		return false
	for stem: String in INTERIOR.values():
		if not ResourceLoader.exists(WORLD % (stem + "_a")):
			return false
	return true


## Bind the scanned interior floors and walls to an interior_surface material; without the files (or QT_SCANNED=0) `scan_k` is 0 and the shader keeps its procedural look. Returns true when bound.
static func apply_interior(mat: ShaderMaterial, tier: int) -> bool:
	var ok := scanned_interiors()
	if ok:
		for u: String in INTERIOR:
			var key := "i|" + u
			if not _cache.has(key):
				_cache[key] = load(WORLD % (INTERIOR[u] + "_a")) as Texture2D
			mat.set_shader_parameter(StringName(u), _cache[key])
	mat.set_shader_parameter(&"scan_k", 1.0 if ok else 0.0)
	mat.set_shader_parameter(&"scan_bias", 0.0 if tier >= 1 else 0.5)
	return ok


## Drop the cached textures the tier does not use (LOW none, MED the half-size ones, HIGH the full-size ones); the materials were re-bound by `apply` already, so they are freed.
static func prune(tier: int) -> int:
	var n := 0
	for key: String in _cache.keys():
		if key == "sign_atlas":
			continue
		var keep := (tier == 1 and key.ends_with("|1")) or (tier >= 2 and key.ends_with("|2"))
		if taps(tier) == 0:
			keep = tier == 0 and key.ends_with("|0")            # LOW keeps only its 512 px scanned albedo layers
		if not keep:
			_cache.erase(key)
			n += 1
	return n


## The neon-text glyph atlas (tools/textures/gen_signage.py), cached; null when the file is missing.
static func sign_atlas() -> Texture2D:
	if not _cache.has("sign_atlas"):
		_cache["sign_atlas"] = load("res://assets/textures/signage_atlas.png") if ResourceLoader.exists("res://assets/textures/signage_atlas.png") else null
	return _cache["sign_atlas"]


## LOW: a scanned albedo file ("brick_a", "wall_a") at half size (512 px), null when missing or QT_SCANNED=0. Cached.
static func low_tex(stem: String) -> Texture2D:
	var key := "lo|" + stem + "|0"
	if _cache.has(key):
		return _cache[key]
	var t: Texture2D = null
	if OS.get_environment("QT_SCANNED") != "0" and ResourceLoader.exists(WORLD % stem):
		t = TextureBudget._halved(load(WORLD % stem) as Texture2D)
	_cache[key] = t
	return t


## LOW tier: the lite ground and the facade shader get ONE albedo-modulator tap of the scanned sets (`srf_lo`); everything else stays procedural.
static func _apply_low(mat: ShaderMaterial, keys: Array) -> void:
	var lo := 0.0
	for k: String in keys:
		if k == "roadv":
			var ra := road_array("albedo", 0)
			mat.set_shader_parameter(&"srf_roadv_a", ra)
			lo = maxf(lo, 1.0 if ra != null else 0.0)
		elif k == "walkv":
			var wa := walk_array("albedo", 0) if scanned_walks() else null
			mat.set_shader_parameter(&"srf_walkv_a", wa)
		elif scanned_slot(k) and (k == "brick" or k == "wall"):
			var t := low_tex("%s_a" % WORLD_SLOTS[k])
			mat.set_shader_parameter("srf_%s_a" % k, t)
			lo = maxf(lo, 1.0 if t != null else 0.0)
	mat.set_shader_parameter(&"srf_lo", lo)


## Bind the sets `keys` (SETS keys, plus "decal", "trim" and "sign") to `mat` for the tier; LOW clears them and switches the taps off.
static func apply(mat: ShaderMaterial, keys: Array, tier: int) -> void:
	var n_taps := taps(tier)
	mat.set_shader_parameter(&"srf_k", 1.0 if n_taps >= 1 else 0.0)
	mat.set_shader_parameter(&"srf_hi", 1.0 if n_taps >= 2 else 0.0)
	mat.set_shader_parameter(&"srf_bias", PerfTiers.surface_mip_bias(tier))
	mat.set_shader_parameter(&"srf_lo", 0.0)
	for k: String in keys:
		if k == "sign":
			mat.set_shader_parameter(&"sign_atlas", sign_atlas())        # the neon-text distance atlas (18 KB, lossless, every tier: it IS the signage)
		elif k == "walkv":
			# the district sidewalks: the array when it can be built (then the plain sidewalk pair stays unloaded), else the single sidewalk set
			var wa := walk_array("albedo", tier)
			var wn := walk_array("normal", tier)
			var ok := wa != null and wn != null
			mat.set_shader_parameter(&"srf_walkv_a", wa if ok else null)
			mat.set_shader_parameter(&"srf_walkv_n", wn if ok else null)
			mat.set_shader_parameter(&"srf_walkv", 1.0 if ok else 0.0)
			mat.set_shader_parameter(&"srf_walk_a", null if ok else tex("sidewalk_albedo", tier))
			mat.set_shader_parameter(&"srf_walk_n", null if ok else tex("sidewalk_normal", tier))
		elif k == "roadv":
			var ra := road_array("albedo", tier)
			var rn := road_array("normal", tier)
			var rok := ra != null and rn != null
			mat.set_shader_parameter(&"srf_roadv_a", ra if rok else null)
			mat.set_shader_parameter(&"srf_roadv_n", rn if rok else null)
			mat.set_shader_parameter(&"srf_roadv", 1.0 if rok else 0.0)
			mat.set_shader_parameter(&"srf_road_a", null if rok else tex("asphalt_albedo", tier))
			mat.set_shader_parameter(&"srf_road_n", null if rok else tex("asphalt_normal", tier))
		elif k == "decal":
			mat.set_shader_parameter(&"srf_decal", tex("decals", tier) if n_taps >= 2 else null)        # the decal mask is a HIGH tap
		elif k == "trim":
			mat.set_shader_parameter(&"srf_trim_a", tex("trim_albedo", tier))
			mat.set_shader_parameter(&"srf_trim_n", tex("trim_normal", tier))
		elif scanned_slot(k):
			mat.set_shader_parameter("srf_%s_a" % k, tex("world:%s_a" % WORLD_SLOTS[k], tier))
			mat.set_shader_parameter("srf_%s_n" % k, tex("world:%s_n" % WORLD_SLOTS[k], tier))
		else:
			var stem: String = SETS[k]
			mat.set_shader_parameter("srf_%s_a" % k, tex(stem + "_albedo", tier))
			mat.set_shader_parameter("srf_%s_n" % k, tex(stem + "_normal", tier))

	if tier == 0:
		_apply_low(mat, keys)                  # after the loop: it cleared every full-size set (LOW holds only the 512 px scanned albedo layers)


## Estimated GPU bytes of everything the tier would load (4x4 block formats are 1 byte per texel, +1/3 for mipmaps; half size on MED for the 2K procedural files). The scanned sets
## replace the procedural slot they serve (1024 px at every tier). LOW stays 0 here: its scanned albedo layers are counted by `estimate_low_bytes`.
static func estimate_bytes(tier: int) -> int:
	if taps(tier) == 0:
		return 0
	var files: Array[String] = []
	var scan_roads := scanned_roads()
	var scan_walks := scanned_walks()
	for f in ["asphalt_albedo", "asphalt_normal"]:
		if not scan_roads:
			files.append(DIR % f)
	if scan_roads:
		for st in ROAD_LAYERS:
			files.append_array([WORLD % (st + "_a"), WORLD % (st + "_n")])
	for st in (WALK_SCAN_LAYERS if scan_walks else ["walk_market", "walk_foundry", "walk_towers", "sidewalk"]):
		for suffix in (["a", "n"] if scan_walks else ["albedo", "normal"]):
			files.append((WORLD % ("%s_%s" % [st, suffix])) if scan_walks else (DIR % ("%s_%s" % [st, suffix])))
	for slot in ["brick", "wall", "metal", "corr"]:
		if scanned_slot(slot):
			files.append_array([WORLD % (WORLD_SLOTS[slot] + "_a"), WORLD % (WORLD_SLOTS[slot] + "_n")])
		else:
			files.append_array([DIR % (SETS[slot] + "_albedo"), DIR % (SETS[slot] + "_normal")])
	files.append_array([DIR % "roof_tar_albedo", DIR % "roof_tar_normal", DIR % "trim_albedo", DIR % "trim_normal"])
	if tier >= 2:
		files.append(DIR % "decals")
	var total := 0
	for path in files:
		var t := load(path) as Texture2D
		if t == null:
			continue
		var px := float(t.get_width() * t.get_height())
		if tier == 1 and t.get_width() >= 2048:
			px *= 0.25
		total += int(px * 4.0 / 3.0)
	return total


## LOW: the 512 px scanned albedo layers (road + sidewalk arrays) and the two facade albedos that the lite shaders tap once.
static func estimate_low_bytes() -> int:
	if not scanned_roads():
		return 0
	var layers := ROAD_LAYERS.size() + (WALK_SCAN_LAYERS.size() if scanned_walks() else 0) + (2 if scanned_slot("brick") and scanned_slot("wall") else 0)
	return int(float(layers) * 512.0 * 512.0 * 4.0 / 3.0)
