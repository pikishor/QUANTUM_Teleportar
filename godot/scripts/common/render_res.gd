class_name RenderRes
extends RefCounted
## Render resolution (Options 'RESOLUTION': BALANCED / HIGH / NATIVE). Only the 3D scene is scaled (Viewport.scaling_3d_scale); the HUD is drawn in CanvasLayers at
## full window resolution, so it stays crisp. Mobile (and Forward+) upscale with FSR 1.0 (SCALING_3D_MODE_FSR); Compatibility has no FSR, it uses the bilinear mode.
## At scale 1.0 the mode is bilinear (no upscale pass at all). Effective mode = governor override > the player's saved choice > the tier default (LOW 0, MED 1, HIGH 2).
## AutoQuality lowers the effective mode one step (never saved) before it drops a tier; a tier change clears that override.

const NAMES := ["BALANCED", "HIGH", "NATIVE"]
const SCALES := [0.67, 0.85, 1.0]

static var user_mode := -1        ## saved choice, -1 = follow the tier
static var gov_mode := -1         ## governor override for the current tier, -1 = none


static func tier_mode(tier: int) -> int:
	return clampi(tier, 0, 2)


static func mode(tier: int = Game.quality) -> int:
	if gov_mode >= 0:
		return gov_mode
	return user_mode if user_mode >= 0 else tier_mode(tier)


static func scale_for(m: int) -> float:
	return float(SCALES[clampi(m, 0, 2)])


static func scale(tier: int = Game.quality) -> float:
	return scale_for(mode(tier))


static func mode_name(m: int) -> String:
	return NAMES[clampi(m, 0, 2)]


static func fsr_supported() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"


static func apply(vp: Viewport, tier: int = Game.quality) -> void:
	if vp == null:
		return
	var s := scale(tier)
	vp.scaling_3d_scale = s
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if (s < 0.999 and fsr_supported()) else Viewport.SCALING_3D_MODE_BILINEAR
	if s < 0.999:
		vp.fsr_sharpness = 0.5


static func _vp() -> Viewport:
	if is_instance_valid(Game.world) and Game.world.is_inside_tree():
		return Game.world.get_viewport()
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root if tree != null else null


## The player picked a mode (or -1 = follow the tier): clears the governor override and applies live. Returns the effective mode.
static func set_user(m: int) -> int:
	user_mode = clampi(m, -1, 2)
	gov_mode = -1
	apply(_vp())
	return mode()


## Options button: cycles BALANCED -> HIGH -> NATIVE from the effective mode.
static func next_mode() -> int:
	return (mode() + 1) % 3


## Governor step: lowers the effective mode by one when it is above BALANCED. Returns true when it did.
static func governor_lower() -> bool:
	var m := mode()
	if m <= 0:
		return false
	gov_mode = m - 1
	apply(_vp())
	return true


static func on_tier_changed() -> void:
	gov_mode = -1


static func label() -> String:
	return "%s %d%%" % [mode_name(mode()), roundi(scale() * 100.0)]
