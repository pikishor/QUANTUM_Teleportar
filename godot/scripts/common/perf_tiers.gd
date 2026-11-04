class_name PerfTiers
extends Node
## Everything that scales the render cost with the graphics tier and is not owned by the world or the atmosphere (composed by main.gd, one node):
##   * the viewport's mesh LOD threshold (every imported model ships meshoptimizer LODs, `meshes/generate_lods` in the .import files; the renderer picks the LOD from the
##     screen-space error in pixels, so a bigger threshold = fewer triangles in the camera AND in the shadow passes): LOW 5 px, MED 3 px, HIGH 1.5 px;
##   * anisotropic filtering of the model textures (LOW 2x, MED 4x, HIGH 8x) and a texture mip bias on LOW (reads the 1K level of the 2K atlases);
##   * the distances of the LOD hooks the enemies, the vehicles and the characters use (shadows, small parts, animation rate), as static helpers: `shadow_range()`, `part_range()`.
## It reacts to Game.quality_changed and applies the current tier when it enters the tree. It never touches msaa_3d / scaling_3d_scale (the world owns them).
## The Compatibility renderer draws more calls per object than the Mobile one: `compat()` and `cap_scale()` let the pools (enemies, cars) spawn fewer there.

const LOD_THRESHOLD := [5.0, 3.0, 1.5]
const MIP_BIAS := [1.0, 0.0, -0.25]
const ANISO := [Viewport.ANISOTROPY_2X, Viewport.ANISOTROPY_4X, Viewport.ANISOTROPY_8X]
const SURFACE_TAPS := [0, 1, 2]       ## surface texture taps per tier (assets/shaders/surface_tex.gdshaderinc): LOW none (procedural look), MED one albedo+normal pair, HIGH two pairs + the decal mask
const SURFACE_MIP_BIAS := [0.0, 0.0, -0.3]   ## extra mip bias of the surface taps (on top of the viewport's `MIP_BIAS`), sharper on HIGH
const SHADOW_RANGE := 25.0            ## HIGH: characters and cars cast no shadow beyond this camera distance (metres)
const SHADOW_RANGES := [0.0, 16.0, 25.0]   ## per tier: MED drops the shadow of anything beyond 16 m (a far trooper shadow is a few pixels), LOW has no shadows
const PART_RANGE := 45.0              ## small parts (drone fins, car wheels) are hidden beyond this
const MODEL_RANGE := 130.0            ## an enemy model is hidden entirely beyond this (its marks stop at 90 m)
const LIGHT_RANGE := [14.0, 26.0, 40.0]   ## the lights a model carries (a trooper's fill and rim, a car's underglow) are on only this close to the camera, per tier
const COMPAT_CAP_SCALE := 0.75        ## the Compatibility renderer spawns this share of the pooled enemies and cars

var tier := -1


func _ready() -> void:
	Game.quality_changed.connect(apply)
	apply(Game.quality)


func apply(level: int) -> void:
	tier = clampi(level, 0, 2)
	MaterialsV2.set_tier(tier)
	var vp := get_viewport()
	if vp == null:
		return
	vp.mesh_lod_threshold = float(LOD_THRESHOLD[tier])
	vp.anisotropic_filtering_level = ANISO[tier] as Viewport.AnisotropicFiltering
	vp.texture_mipmap_bias = float(MIP_BIAS[tier]) if not (tier == 0 and TextureBudget.halved_count > 0) else 0.0      # LOW with half-size atlases already reads the 1K level


static func compat() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


## A pool cap for the running renderer: Mobile as given, Compatibility 75 % (at least 2).
static func cap_scale(n: int) -> int:
	return n if not compat() else maxi(2, int(floor(float(n) * COMPAT_CAP_SCALE)))


static func surface_taps(level: int) -> int:
	return int(SURFACE_TAPS[clampi(level, 0, 2)])


static func surface_mip_bias(level: int) -> float:
	return float(SURFACE_MIP_BIAS[clampi(level, 0, 2)])


## Camera distance within which a model's own lights are on (see DynamicFill.trim_lights).
static func light_range(level: int) -> float:
	return float(LIGHT_RANGE[clampi(level, 0, 2)])


## Camera distance beyond which dynamic things cast no shadow (the tier's shadow distance is shorter or equal on MED: 55 m).
static func shadow_range() -> float:
	return float(SHADOW_RANGES[clampi(Game.quality, 0, 2)])
