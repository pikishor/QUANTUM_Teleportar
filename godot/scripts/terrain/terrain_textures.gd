class_name TerrainTextures
extends RefCounted
## The seven scanned terrain layers (Poly Haven CC0, tools/materials/pack_terrain_textures.py -> assets/textures/terrain_<layer>.webp, 1024 px, VRAM compressed with mipmaps) as ONE
## Texture2DArray for assets/shaders/terrain.gdshader. Tier scaling: HIGH uploads the 1024 px layers (about 9.3 MB), MED and LOW the 512 px level of each (the top mip is cut off the
## compressed data, no re-encode: about 2.3 MB). Null when the data cannot be read (headless, a GPU-only format): the shader then paints flat biome colours (`flat_colors`).
## `estimate_bytes(tier)` is the GPU memory the tier uses (texture-memory gate).

const LAYERS: Array[String] = ["grass", "forest", "desert", "beach", "rock", "snow", "dirt"]
const PATH := "res://assets/textures/terrain_%s.webp"
## sRGB look-alikes of the layers, used when the array is unavailable
const FLAT: Array[Color] = [Color(0.32, 0.4, 0.2), Color(0.17, 0.27, 0.13), Color(0.62, 0.45, 0.26), Color(0.7, 0.64, 0.5), Color(0.45, 0.42, 0.4), Color(0.9, 0.92, 0.96), Color(0.4, 0.33, 0.25)]
static var _cache := {}


static func available() -> bool:
	for l in LAYERS:
		if not ResourceLoader.exists(PATH % l):
			return false
	return true


static func flat_colors() -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in FLAT:
		var lin := c.srgb_to_linear()
		out.append(Vector3(lin.r, lin.g, lin.b))
	return out


## The array for the tier, cached per size; null when the layers are missing or unreadable.
static func array(tier: int) -> Texture2DArray:
	var half := tier < 2
	var key := 1 if half else 2
	if _cache.has(key):
		return _cache[key]
	if not available():
		_cache[key] = null
		return null
	var images: Array[Image] = []
	for l in LAYERS:
		var t := load(PATH % l) as Texture2D
		var img: Image = null if t == null else t.get_image()
		if img == null or img.is_empty():
			_cache[key] = null
			return null
		if half and img.get_width() >= 1024 and img.get_mipmap_count() > 1:
			img = Image.create_from_data(img.get_width() / 2, img.get_height() / 2, true, img.get_format(), img.get_data().slice(img.get_mipmap_offset(1)))
		elif half and img.get_width() >= 1024:
			img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_LANCZOS)
			img.generate_mipmaps()
		if not img.has_mipmaps() and not img.is_compressed():
			img.generate_mipmaps()
		images.append(img)
	var arr := Texture2DArray.new()
	if arr.create_from_images(images) != OK:
		_cache[key] = null
		return null
	_cache[key] = arr
	return arr


## Estimated GPU bytes for the tier (4x4 block formats are 1 byte per texel, +1/3 for mipmaps).
static func estimate_bytes(tier: int) -> int:
	if not available():
		return 0
	var px := 1024.0 * 1024.0 if tier >= 2 else 512.0 * 512.0
	return int(px * 4.0 / 3.0) * LAYERS.size()


static func prune(tier: int) -> void:
	var keep := 2 if tier >= 2 else 1
	for k in _cache.keys():
		if int(k) != keep:
			_cache.erase(k)
