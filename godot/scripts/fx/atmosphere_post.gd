extends CanvasLayer
## The full-screen post-process of the Atmosphere: a CanvasLayer drawn above the 3D picture and below every HUD layer, holding one
## ColorRect whose shader (assets/shaders/post_film.gdshader) reads hint_screen_texture. It owns the *tunable values* of every
## effect (`set_param`) and applies the quality-tier masks on top, so a LOW phone pays only for grade + vignette + grain.
## Works in the Mobile renderer and in Compatibility (canvas shaders and the screen texture exist in both).

const SHADER := preload("res://assets/shaders/post_film.gdshader")
## Below the default canvas (0) and the HUD (1): the picture is graded first, interface elements stay crisp and ungraded.
const LAYER := -1

## The art direction: designer values at full quality. Every key is a uniform of post_film.gdshader.
const DEFAULTS := {
	&"exposure": 1.04,
	&"black_crush": 0.008,
	&"lift": Vector3(-0.014, 0.011, 0.013),
	&"mid_gamma": Vector3(1.0, 1.0, 1.0),
	&"gain": Vector3(1.05, 1.0, 0.915),
	&"contrast": 0.16,
	&"saturation": 0.96,
	&"vignette_amount": 0.55,
	&"vignette_start": 0.45,
	&"ca_amount": 0.0012,
	&"grain_amount": 0.042,
	&"grain_size": 1.25,
	&"grain_fps": 24.0,
	&"sharpen_amount": 0.35,
	&"haze_amount": 0.8,
	&"lens_amount": 0.6,
	&"overlay_amount": 0.8,
}

## Per quality tier (0 LOW, 1 MED, 2 HIGH): the fraction of an effect that exists. 0 = the shader branch is skipped entirely.
const TIER_MASK: Array[Dictionary] = [
	{&"ca_amount": 0.0, &"sharpen_amount": 0.0, &"haze_amount": 0.0, &"lens_amount": 0.0, &"overlay_amount": 0.0, &"grain_size": 1.5},
	{&"ca_amount": 1.0, &"sharpen_amount": 0.0, &"haze_amount": 1.0, &"lens_amount": 0.0, &"overlay_amount": 0.55, &"grain_size": 1.15},
	{&"ca_amount": 1.0, &"sharpen_amount": 1.0, &"haze_amount": 1.0, &"lens_amount": 1.0, &"overlay_amount": 1.0, &"grain_size": 1.0},
]

## Feedback caps (hurt and death): chromatic aberration adds at most this much on top of the film value (MED and HIGH only), and the picture never
## loses more than this fraction of its colour. Both come back to the film look by themselves (the Atmosphere eases them).
const FB_CA_MAX := 0.004
const FB_SAT_LOSS_MAX := 0.35

var tier := 1
var rect: ColorRect
var mat: ShaderMaterial
var _base: Dictionary = DEFAULTS.duplicate()
var _rain := 0.0
var _slant := 0.0
var _fb_ca := 0.0
var _fb_sat := 1.0


func _ready() -> void:
	layer = LAYER
	rect = ColorRect.new()
	rect.name = "Screen"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.focus_mode = Control.FOCUS_NONE
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	rect.material = mat
	add_child(rect)
	_push_all()


## Set the designer value of one effect (a uniform name of post_film.gdshader, for example &"grain_amount"). The quality tier
## still masks it, so a LOW phone never pays for an effect even when a settings screen asks for it.
func set_param(param: StringName, value: Variant) -> void:
	if not DEFAULTS.has(param):
		push_warning("AtmospherePost: unknown parameter '%s'" % param)
		return
	_base[param] = value
	_push(param)


func get_param(param: StringName) -> Variant:
	return _base.get(param)


## The value the shader really receives (designer value x tier mask).
func effective(param: StringName) -> Variant:
	var v: Variant = _base.get(param)
	if v is float:
		var m: Dictionary = TIER_MASK[tier]
		var out := float(v) * float(m[param]) if m.has(param) else float(v)
		if param == &"ca_amount" and tier > 0:
			out += _fb_ca
		elif param == &"saturation":
			out *= _fb_sat
		return out
	return v


## Hurt / death feedback on top of the designer values: `ca` extra chromatic aberration (0..FB_CA_MAX), `sat` colour kept (1 = all, never below 1 - FB_SAT_LOSS_MAX).
func set_feedback(ca: float, sat: float) -> void:
	ca = clampf(ca, 0.0, FB_CA_MAX)
	sat = clampf(sat, 1.0 - FB_SAT_LOSS_MAX, 1.0)
	if ca == _fb_ca and sat == _fb_sat or (is_equal_approx(ca, _fb_ca) and is_equal_approx(sat, _fb_sat) and ca > 0.0 and sat < 1.0):
		return           # near-equal values skip the push, but the exact rest state (0, 1) is always written
	_fb_ca = ca
	_fb_sat = sat
	_push(&"ca_amount")
	_push(&"saturation")


func feedback() -> Vector2:
	return Vector2(_fb_ca, _fb_sat)


func set_quality(level: int) -> void:
	tier = clampi(level, 0, 2)
	_push_all()


## 0..1, the smoothed global rain: lens droplets, haze and the rain curtain scale with it.
func set_rain(rain: float) -> void:
	if absf(rain - _rain) < 0.002 and not (rain == 0.0 and _rain != 0.0):
		return
	_rain = rain
	if mat:
		mat.set_shader_parameter(&"rain_amount", _rain)


## Screen-space lean of the distant rain streaks (positive: they move right as they fall).
func set_slant(slant: float) -> void:
	if absf(slant - _slant) < 0.004:
		return
	_slant = slant
	if mat:
		mat.set_shader_parameter(&"wind_slant", _slant)


func _push_all() -> void:
	if mat == null:
		return
	for param: StringName in DEFAULTS:
		_push(param)
	mat.set_shader_parameter(&"rain_amount", _rain)
	mat.set_shader_parameter(&"wind_slant", _slant)


func _push(param: StringName) -> void:
	if mat:
		mat.set_shader_parameter(param, effective(param))
