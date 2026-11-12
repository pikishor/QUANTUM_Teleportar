class_name LandClimate
extends Node
## Wind of the landscape (wave 112): publishes the global shader parameter `wind` (xy = unit direction on the ground, z = strength 0..1.6, w = clock) every frame from the weather,
## so trees, grass, turbines and windsocks all sway the same way and harder in rain and storms. A child of the VegetationWorld (one per game); other systems read `LandClimate.vec()`
## (direction x, strength, direction z) and `LandClimate.strength()`.
## Strength per weather state (Weather.current): clear 0.30, overcast 0.42, drizzle 0.55, rain 0.80, storm 1.45, fog 0.12; a slow noise adds +- 0.15 and the direction drifts around a
## prevailing westerly. The value is eased, never jumps. `LandClimate.override(strength, dir_deg)` pins it (tests, look-dev bots; pass -1 to release).

const PARAM := &"wind"
const BASE := {&"clear": 0.30, &"overcast": 0.42, &"drizzle": 0.55, &"rain": 0.80, &"storm": 1.45, &"fog": 0.12}

static var _declared := false
static var _now := Vector4(0.8, 0.6, 0.3, 0.0)         ## direction x, z (unit), strength, clock
static var _pin := -1.0
static var _pin_dir := 0.0
var _t := 0.0
var _smooth := 0.3


## Declare the global (once per process). Shaders that read `wind` must not compile before this has run: LandKit calls it first.
static func ensure() -> void:
	if _declared:
		return
	_declared = true
	RenderingServer.global_shader_parameter_add(PARAM, RenderingServer.GLOBAL_VAR_TYPE_VEC4, _now)


static func vec() -> Vector3:
	return Vector3(_now.x, _now.z, _now.y)


static func strength() -> float:
	return _now.z


static func direction() -> Vector2:
	return Vector2(_now.x, _now.y)


static func override(strength_v: float, dir_deg := 0.0) -> void:
	_pin = strength_v
	_pin_dir = dir_deg


static func target_strength() -> float:
	var st: StringName = Weather.current
	var base: float = float(BASE.get(st, 0.3))
	var atm := Game.atmosphere as Atmosphere
	if is_instance_valid(atm):
		base = maxf(base, 0.3 + 0.5 * atm.rain_now)           # a rain value set by hand (test menu) counts as well as a weather state
	return base


func _ready() -> void:
	ensure()
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	var tgt := target_strength()
	var dir_a := 3.3 + 0.55 * sin(_t * 0.021) + 0.25 * sin(_t * 0.057 + 1.3)          # about west-south-west, drifting
	if _pin >= 0.0:
		tgt = _pin
		dir_a = deg_to_rad(_pin_dir)
	else:
		tgt = clampf(tgt + 0.15 * sin(_t * 0.13) * (0.5 + 0.5 * sin(_t * 0.031)), 0.05, 1.6)
	_smooth = move_toward(_smooth, tgt, delta * 0.25)
	_now = Vector4(cos(dir_a), sin(dir_a), _smooth, fposmod(_t, 600.0))
	RenderingServer.global_shader_parameter_set(PARAM, _now)
