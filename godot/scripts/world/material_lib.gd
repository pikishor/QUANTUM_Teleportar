class_name MaterialLib
extends RefCounted
## Per surface kind (asphalt, concrete, metal, brick, tile): scanned set (tools/materials/import_scanned.py -> assets/textures/scanned_<kind>_*.png)
## when present, else the current procedural material (null here: callers keep their own shader look). LOW tier loads the _half files.

const KINDS: Array[String] = ["asphalt", "concrete", "metal", "brick", "tile"]
const DIR := "res://assets/textures/scanned_%s_%s%s.png"
const SHADER := "res://assets/shaders/scanned_surface.gdshader"
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


## Scanned material when present, else `fallback` (the procedural one).
static func get_material(kind: String, tier: int, fallback: Material) -> Material:
	var m := scanned(kind, tier)
	return m if m != null else fallback
