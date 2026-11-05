class_name MaterialLib
extends RefCounted
## Per surface kind (asphalt, concrete, metal, brick, tile): scanned set (tools/materials/import_scanned.py -> assets/textures/scanned_<kind>_*.png)
## when present, else the current procedural material (null here: callers keep their own shader look). LOW tier loads the _half files.

const KINDS: Array[String] = ["asphalt", "concrete", "metal", "brick", "tile"]
const DIR := "res://assets/textures/scanned_%s_%s%s.png"
const SHADER := "res://assets/shaders/scanned_surface.gdshader"
const Districts := preload("res://scripts/world/city_districts.gd")
static var _cache := {}


static func path(kind: String, part: String, tier: int) -> String:
	return DIR % [kind, part, "_half" if tier == 0 else ""]


## True when albedo, normal and ORM of the kind all exist for the tier.
static func has_scanned(kind: String, tier: int = 2) -> bool:
	if not KINDS.has(kind):
		return false
	for part in ["albedo", "normal", "orm"]:
		if not ResourceLoader.exists(path(kind, part, tier)):
			return false
	return true


## ShaderMaterial with the scanned set, or null when none was imported (caller then uses its procedural material).
static func scanned(kind: String, tier: int = 2) -> ShaderMaterial:
	var key := "%s|%d" % [kind, 0 if tier == 0 else 1]
	if _cache.has(key):
		return _cache[key]
	var m: ShaderMaterial = null
	if has_scanned(kind, tier) and ResourceLoader.exists(SHADER):
		m = ShaderMaterial.new()
		m.shader = load(SHADER)
		m.set_shader_parameter(&"alb", load(path(kind, "albedo", tier)))
		m.set_shader_parameter(&"nrm", load(path(kind, "normal", tier)))
		m.set_shader_parameter(&"orm", load(path(kind, "orm", tier)))
		m.set_shader_parameter(&"metal_k", 1.0 if kind == "metal" else 0.0)
	_cache[key] = m
	return m


## Tier change: forget the scanned materials of the other size (LOW uses the _half files, MED / HIGH the full ones); nothing is cached for a kind that was never imported.
static func prune(tier: int) -> void:
	var keep := "|0" if tier == 0 else "|1"
	for key: String in _cache.keys():
		if not key.ends_with(keep):
			_cache.erase(key)


## Scanned material when present, else `fallback` (the procedural one).
static func get_material(kind: String, tier: int, fallback: Material) -> Material:
	var m := scanned(kind, tier)
	return m if m != null else fallback


## Which scanned kinds feed which texture slots of the city shaders (slot key as in SurfaceTextures: srf_<slot>_a / srf_<slot>_n).
const SLOTS := {"road": "asphalt", "walk": "concrete", "brick": "brick", "wall": "concrete", "metal": "metal"}


## Wires scanned sets into a city material (ground, sidewalks, facades) through the sampler slots its shader already has: no extra draw, no extra tap.
## Per slot: scanned albedo + normal when the kind was imported, else the slot is left alone (the procedural / SurfaceTextures look). LOW (tier 0) is untouched
## (the shaders skip the taps there). Returns the number of slots replaced.
static func apply_to(mat: ShaderMaterial, slots: Array, tier: int) -> int:
	if mat == null or tier <= 0:
		return 0
	var n := 0
	for slot in slots:
		var kind: String = SLOTS.get(slot, "")
		if kind == "" or not has_scanned(kind, tier):
			continue
		mat.set_shader_parameter("srf_%s_a" % slot, load(path(kind, "albedo", tier)))
		mat.set_shader_parameter("srf_%s_n" % slot, load(path(kind, "normal", tier)))
		if slot == "walk":
			mat.set_shader_parameter(&"srf_walkv", 0.0)          # the scanned slab replaces the district sidewalk array
		n += 1
	return n


## Phase-seam colour per district for a scanned material (same accent the ground and facades use).
static func seam_color(district: int) -> Color:
	return Districts.palette(district)["accent2"]
