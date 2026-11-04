class_name PostFx2
extends RefCounted
## Lighting and post FX, second pass ("quantum realism"). Pure tables and helpers, no nodes:
##  - district_grade(pos): LUT-like colour grade (gain / lift / saturation) blended between the four districts, applied by post_film.gdshader (MED/HIGH)
##    and, on LOW (no post pass), as an Environment adjustment saturation only.
##  - apply_env(): filmic tone-mapping white point, bloom threshold and SSAO by time of day and tier (called by DayNight.apply).
##  - SHADOW: sun shadow quality per tier.  - shaft_amount(): fake light shafts (screen space, post shader).  - pulse(): ability film kick.
## Switchable (TEST / DEMO menus: POST LOOK) so shots can be compared with and without.

const DISTRICT_NAMES: Array[StringName] = [&"market", &"foundry", &"slums", &"towers"]   ## same order as Sfx.DISTRICTS
## gain multiplies the highlights, lift adds in the shadows, sat scales colour. Subtle by design: the film grade in AtmospherePost.DEFAULTS stays the base.
const GRADES := {
	&"market": {"gain": Vector3(1.05, 1.0, 0.92), "lift": Vector3(0.006, 0.002, -0.004), "sat": 1.08},
	&"foundry": {"gain": Vector3(1.06, 0.97, 0.88), "lift": Vector3(0.010, 0.000, -0.006), "sat": 0.92},
	&"slums": {"gain": Vector3(0.96, 1.03, 0.97), "lift": Vector3(-0.004, 0.008, 0.004), "sat": 0.82},
	&"towers": {"gain": Vector3(0.95, 1.0, 1.08), "lift": Vector3(-0.004, 0.004, 0.012), "sat": 1.02},
}
const NEUTRAL := {"gain": Vector3.ONE, "lift": Vector3.ZERO, "sat": 1.0}
const BLEND_WIDTH := 24.0                  ## metres either side of a district border over which grades cross-fade

## Sun shadows per tier (0 LOW, 1 MED, 2 HIGH): enabled, max distance, blur, normal bias, opacity.
const SHADOW: Array[Dictionary] = [
	{"on": false, "dist": 55.0, "blur": 1.0, "nbias": 1.2, "opacity": 1.0},
	{"on": true, "dist": 55.0, "blur": 1.0, "nbias": 1.1, "opacity": 0.9},
	{"on": true, "dist": 130.0, "blur": 1.6, "nbias": 1.2, "opacity": 0.95},
]
const TONE_WHITE_DAY := 4.6                ## filmic shoulder: earlier roll-off by day so bright facades do not clip,
const TONE_WHITE_NIGHT := 6.4              ## later at night so neon keeps its colour
const GLOW_THR_DAY := 1.15                 ## bloom starts higher by day (white walls), at the base value at night
const PULSE_DECAY := 2.2                   ## 1/s: how fast the ability film kick fades
const PULSE_CA := 0.0030
const PULSE_GRAIN := 0.03

static var enabled := true                 ## TEST / DEMO switch


static func set_enabled(on: bool) -> void:
	enabled = on


## Blend weights (market, foundry, slums, towers) for a world position: the quadrants of Sfx.district_at, cross-faded near the borders.
static func district_weights(pos: Vector3) -> PackedFloat32Array:
	var east := smoothstep(-BLEND_WIDTH, BLEND_WIDTH, pos.x)
	var south := smoothstep(-BLEND_WIDTH, BLEND_WIDTH, pos.z)
	return PackedFloat32Array([(1.0 - east) * (1.0 - south), east * (1.0 - south), (1.0 - east) * south, east * south])


## {"gain": Vector3, "lift": Vector3, "sat": float} at a position. pos == null / disabled: neutral.
static func district_grade(pos: Variant) -> Dictionary:
	if not enabled or not (pos is Vector3):
		return NEUTRAL.duplicate()
	var w := district_weights(pos as Vector3)
	var gain := Vector3.ZERO
	var lift := Vector3.ZERO
	var sat := 0.0
	for i in 4:
		var g: Dictionary = GRADES[DISTRICT_NAMES[i]]
		gain += (g["gain"] as Vector3) * w[i]
		lift += (g["lift"] as Vector3) * w[i]
		sat += float(g["sat"]) * w[i]
	return {"gain": gain, "lift": lift, "sat": sat}


## 0..1 strength of the fake light shafts: sunlit hours and dusk, thinner in rain, faint moon shafts at night.
static func shaft_amount(night: float, twilight: float, rain: float) -> float:
	if not enabled:
		return 0.0
	var day := 1.0 - clampf(night, 0.0, 1.0)
	var a := 0.25 + 0.55 * day + 0.35 * clampf(twilight, 0.0, 1.0) * day
	return clampf(a * (1.0 - 0.7 * clampf(rain, 0.0, 1.0)), 0.0, 1.0) * 0.8


## Shaft steps per tier (post shader loop count): LOW has no post pass, MED 4, HIGH 8.
static func shaft_steps(tier: int) -> int:
	return [0, 4, 8][clampi(tier, 0, 2)]


## Tone-mapping white point and bloom threshold for a night amount 0..1.
static func tone_white(night: float) -> float:
	return lerpf(TONE_WHITE_DAY, TONE_WHITE_NIGHT, clampf(night, 0.0, 1.0)) if enabled else 6.0


static func glow_threshold(base: float, night: float) -> float:
	return lerpf(GLOW_THR_DAY, base, clampf(night, 0.0, 1.0)) if enabled else base


## True where screen-space AO exists: only the Forward+ renderer has it; MED uses half resolution and fewer samples.
static func ao_supported() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


static func apply_env(e: Environment, night: float, tier: int) -> void:
	if e == null:
		return
	var base_thr: float = e.get_meta(&"glow_thr_base", e.glow_hdr_threshold)
	e.set_meta(&"glow_thr_base", base_thr)
	e.tonemap_white = tone_white(night)
	e.glow_hdr_threshold = glow_threshold(base_thr, night)
	var ao := enabled and tier >= 1 and ao_supported()
	e.ssao_enabled = ao
	if ao:
		e.ssao_radius = 1.4 if tier == 1 else 1.8
		e.ssao_intensity = 1.6 if tier == 1 else 2.0
		e.ssao_power = 1.5
		e.ssao_detail = 0.0 if tier == 1 else 0.5
		e.ssao_light_affect = 0.25
		e.ssao_ao_channel_affect = 0.0


static func apply_shadow(sun: DirectionalLight3D, tier: int) -> void:
	var s: Dictionary = SHADOW[clampi(tier, 0, 2)]
	sun.shadow_enabled = s["on"]
	sun.directional_shadow_max_distance = s["dist"]
	sun.shadow_blur = s["blur"]
	sun.shadow_normal_bias = s["nbias"]
	sun.shadow_opacity = s["opacity"]


## Screen position (UV, z = 1 when the sun is in front of the camera) of a light direction (towards the light).
static func sun_screen(cam: Camera3D, to_light: Vector3) -> Vector3:
	if cam == null or not cam.is_inside_tree():
		return Vector3(0.5, 0.0, 0.0)
	if cam.global_transform.basis.z.dot(to_light) > -0.05:     # camera looks along -Z: the sun is behind the view
		return Vector3(0.5, 0.0, 0.0)
	var vp := cam.get_viewport().get_visible_rect().size
	var p := cam.unproject_position(cam.global_position + to_light * 500.0)
	return Vector3(p.x / maxf(vp.x, 1.0), p.y / maxf(vp.y, 1.0), 1.0)


## Ability film kick: call on QUANTUM TELEPORT, ENTANGLE, COLLAPSE and the quantum verbs. Harmless without an Atmosphere.
static func pulse(strength := 1.0) -> void:
	if enabled and is_instance_valid(Game.atmosphere) and Game.atmosphere.has_method(&"ability_pulse"):
		Game.atmosphere.call(&"ability_pulse", strength)
