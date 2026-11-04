class_name DayNight
extends Node
## Time of day (F5): one 12-minute cycle (CYCLE seconds = 24 game hours). It moves the single directional light (moon at night, sun by day),
## recolours the sky / fog / ambient, drives the global shader parameter `night` (0 day .. 1 night) that building windows and the baked lamp pools read,
## and nudges traffic and crowd density by the hour. No extra lights, no extra draws; LOW updates once a second.
## Freeze: UiSettings.s_freeze_time (settings) or `frozen`. The clock only advances while Game.state is play.

const CYCLE := 720.0
const START_HOUR := 21.0
const NIGHT_PARAM := &"night"
const SKY_DAY := {"zenith": Color(0.10, 0.24, 0.52), "mid": Color(0.30, 0.46, 0.72), "horizon": Color(0.60, 0.70, 0.80)}
const SKY_DUSK := Color(0.95, 0.52, 0.30)
const SUN_COLOR := Color(1.0, 0.90, 0.74)
const FOG_DAY := Color(0.52, 0.62, 0.72)

var hour := START_HOUR
var frozen := false
var env_owner: RefCounted                   ## the city's CityEnv (sun, sky_mat, env)
var ambient: Node                           ## the living city, gets set_density()
var tier := 1
var density := 1.0
var night := 1.0                            ## last applied night_amount
var _acc := 99.0
var _night_base := {}
var _fog_night := Color.BLACK
var _amb_night := 1.6
var _glow_base := 1.0
var mood := Color.WHITE                     ## last applied window mood (tint rgb, lit share a)
var _density_applied := -1.0


## 0 (full day) .. 1 (full night) for an hour 0..24: dusk 17:30-19:30, dawn 4:30-6:30.
static func night_amount(h: float) -> float:
	h = fposmod(h, 24.0)
	var dawn := smoothstep(4.5, 6.5, h)
	var dusk := smoothstep(17.5, 19.5, h)
	return clampf(1.0 - dawn + dusk, 0.0, 1.0)


## 0..1, how close to sunrise / sunset (warm horizon).
static func twilight(h: float) -> float:
	h = fposmod(h, 24.0)
	return maxf(1.0 - absf(h - 6.0) / 1.6, maxf(1.0 - absf(h - 18.5) / 1.6, 0.0))


## Traffic and crowd multiplier by hour: rush hours busiest, small hours quietest (0.7 .. 1.12).
static func density_for(h: float) -> float:
	h = fposmod(h, 24.0)
	var rush := maxf(1.0 - absf(h - 8.5) / 2.0, maxf(1.0 - absf(h - 17.5) / 2.0, 0.0))
	var deep := maxf(1.0 - absf(h - 3.0) / 3.0, 0.0)
	return 1.0 + 0.12 * rush - 0.3 * deep         # exactly 1.0 at START_HOUR


## Unit vector towards the light (sun in the day, moon at night): rises in the east at 6, sets at 18, the moon the other way round.
static func light_dir(h: float) -> Vector3:
	h = fposmod(h, 24.0)
	var a := (fposmod(h - 6.0, 12.0) / 12.0) * PI
	return Vector3(cos(a) * 0.8, maxf(sin(a), 0.0) * 0.95 + 0.12, -0.55).normalized()


## Cloud overcast 0..1 per weather state (cloud deck density and sun dimming).
const OVERCAST := {&"clear": 0.0, &"overcast": 0.8, &"drizzle": 0.85, &"rain": 0.95, &"storm": 1.0, &"fog": 0.7}


## Sky look for an hour, weather state and tier: the values written to sky.gdshader (testable without a renderer).
static func sky_look(h: float, weather: StringName, level: int) -> Dictionary:
	var n := night_amount(h)
	var oc: float = OVERCAST.get(weather, 0.0)
	return {"day": 1.0 - n, "overcast": oc, "twilight_amount": twilight(h),
		"aurora_amount": n * (1.0 - oc) * (0.0 if level == 0 else 1.0) if n > 0.6 else 0.0,
		"planet_amount": smoothstep(0.7, 1.0, n) * (1.0 - oc * 0.8),
		"skyline_amount": 1.0, "lod": 0.0 if level == 0 else 1.0,
		"cloud_cover": clampf(lerpf(0.5, 0.78, n) + oc * 0.3, 0.0, 0.95),
		"star_amount": 0.55 * smoothstep(0.55, 1.0, n) * (1.0 - oc * 0.85)}


## Tone-mapper exposure for an hour and weather: nearly constant (0.94 by day .. 1.0 at night, a touch more under heavy overcast), so day, dusk,
## night and weather all land in one exposure band. DayNight.apply() writes it as the Environment meta `base_exposure`, which Weather scales for lightning.
static func exposure_for(h: float, weather: StringName) -> float:
	var n := night_amount(h)
	var oc: float = OVERCAST.get(weather, 0.0)
	return lerpf(0.94, 1.0, n) * (1.0 + 0.05 * oc)


static func clock_text(h: float) -> String:
	h = fposmod(h, 24.0)
	return "%02d:%02d" % [int(h), int((h - floorf(h)) * 60.0)]


var _exposure_base := 1.0


func setup(owner_env: RefCounted, level: int) -> void:
	env_owner = owner_env
	tier = level
	_night_base = {"zenith_color": Color(0.003, 0.008, 0.018), "mid_color": Color(0.045, 0.062, 0.100), "horizon_color": Color(0.20, 0.27, 0.34),
		"star_amount": 0.55, "moon_color": Color(0.70, 0.82, 1.0)}      # the defaults of sky.gdshader
	var e := env_owner.get("env") as Environment
	_fog_night = e.fog_light_color
	_amb_night = e.ambient_light_energy
	_glow_base = e.glow_strength
	_exposure_base = e.tonemap_exposure
	_acc = 99.0
	apply()


func set_tier(level: int) -> void:
	tier = level


func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	apply()


func _process(delta: float) -> void:
	if env_owner == null:
		return
	var freeze := frozen or UiSettings.s_freeze_time
	if not freeze and Game.is_playing():
		hour = fposmod(hour + delta * 24.0 / CYCLE, 24.0)
	_acc += delta
	if _acc >= (1.0 if tier == 0 else 0.25):
		_acc = 0.0
		apply()


func apply() -> void:
	if env_owner == null:
		return
	var n := night_amount(hour)
	var tw := twilight(hour)
	var sky := env_owner.get("sky_mat") as ShaderMaterial
	var e := env_owner.get("env") as Environment
	var sun := env_owner.get("sun") as DirectionalLight3D
	night = n
	RenderingServer.global_shader_parameter_set(NIGHT_PARAM, n)
	mood = LightingPolish.window_mood(hour)
	RenderingServer.global_shader_parameter_set(LightingPolish.MOOD_PARAM, Vector4(mood.r, mood.g, mood.b, mood.a))
	e.glow_strength = _glow_base * LightingPolish.glow_for(n, tier)
	PostFx2.apply_env(e, n, tier)                      # filmic white point, bloom threshold and AO by time of day
	var d := light_dir(hour)
	sun.transform = Transform3D(Basis.looking_at(-d, Vector3.UP), Vector3.ZERO)
	var warm := SUN_COLOR.lerp(SKY_DUSK, tw)
	sun.light_color = warm.lerp(Color(0.58, 0.72, 1.0), n)
	sun.light_energy = lerpf(1.35, 0.9, n) * (1.0 - 0.35 * tw * (1.0 - n))
	sky.set_shader_parameter(&"moon_dir", d)
	sky.set_shader_parameter(&"moon_color", warm.lerp(_night_base["moon_color"], n))
	sky.set_shader_parameter(&"moon_radius", lerpf(0.06, 0.045, n))
	var look := sky_look(hour, Weather.current, tier)
	for k in look:
		sky.set_shader_parameter(StringName(k), look[k])
	sky.set_shader_parameter(&"sun_dir", d)
	sky.set_shader_parameter(&"sun_color", warm)
	for pair in [["zenith_color", "zenith"], ["mid_color", "mid"], ["horizon_color", "horizon"]]:
		var c: Color = (SKY_DAY[pair[1]] as Color).lerp(_night_base[pair[0]], n)
		if pair[0] != "zenith_color":
			c = c.lerp(SKY_DUSK, tw * 0.45 * (1.0 - absf(n - 0.5) * 0.6))
		sky.set_shader_parameter(StringName(pair[0]), c)
	var fogc := FOG_DAY.lerp(_fog_night, n).lerp(SKY_DUSK * 0.6, tw * 0.3)
	var oc: float = look["overcast"]
	var grey := fogc.get_luminance()
	e.fog_light_color = fogc.lerp(Color(grey, grey, grey * 1.04), oc * 0.45)
	e.fog_sky_affect = lerpf(0.2, 0.5, oc)
	e.ambient_light_energy = lerpf(_amb_night * 0.85, _amb_night, n)
	e.set_meta(&"base_exposure", exposure_for(hour, Weather.current) * _exposure_base)
	density = density_for(hour)
	if ambient != null and absf(density - _density_applied) > 0.02 and ambient.has_method(&"set_density"):
		_density_applied = density
		ambient.call(&"set_density", density)
