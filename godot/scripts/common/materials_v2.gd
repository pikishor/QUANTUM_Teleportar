class_name MaterialsV2
extends RefCounted
## Materials v2 strength (shader-only surface realism: macro variation, road decals, triplanar wear, edge dirt, glass reflection, sign flicker).
## The shaders read the global `mv2_amount` (assets/shaders/material_v2.gdshaderinc). No texture is involved, so texture memory is unchanged.
## Registered by Game._ready, set per tier by PerfTiers.apply. LOW keeps the cheap half of the look, HIGH the full one.

const PARAM := &"mv2_amount"
const AMOUNT := [0.5, 0.85, 1.0]      ## per quality tier LOW / MED / HIGH
const SHADERS := ["ground", "ground_lite", "building", "building_mirror", "building_far", "building_far_mirror", "prop", "prop_mirror", "prop_kit"]

static var amount := 1.0
static var registered := false
static var enabled := true            ## TEST / DEMO menu switch for before / after comparison (off = the shaders' v1 look)


static func register() -> void:
	if registered:
		return
	registered = true
	if "--mv2=0" in OS.get_cmdline_user_args():       # look-dev: tools runs can shoot the v1 look for before / after comparisons
		enabled = false
	RenderingServer.global_shader_parameter_add(PARAM, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, effective())


static func amount_for(tier: int) -> float:
	return float(AMOUNT[clampi(tier, 0, AMOUNT.size() - 1)])


static func set_tier(tier: int) -> void:
	amount = 0.0 if (tier == 0 and LowPlus.on()) else amount_for(tier)      # LOW+: the shaders skip the whole v2 block
	_push()


static func set_enabled(on: bool) -> void:
	enabled = on
	_push()


static func effective() -> float:
	return amount if enabled else 0.0


static func _push() -> void:
	if registered:
		RenderingServer.global_shader_parameter_set(PARAM, effective())


## CPU mirror of mv2_flicker in the include (same terms, used by tests and any non-shader emitter): a multiplier around 1.0 that never goes below 0.4.
static func flicker(seed_v: float, t: float, amt: float = 1.0) -> float:
	var hum := 1.0 - 0.06 * (0.5 + 0.5 * sin(t * 6.8 + seed_v * 31.0)) * (0.5 + 0.5 * sin(t * 47.0 + seed_v * 7.0))
	var sag := 1.0 - 0.28 * smoothstep(0.88, 1.0, sin(t * 0.37 + seed_v * 50.0))
	return lerpf(1.0, hum * sag, clampf(amt, 0.0, 1.0))
