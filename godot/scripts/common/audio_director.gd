class_name AudioDirector
extends RefCounted
## AUDIO v3 data and rules, all static and pure so the tests can drive them without a scene. `Sfx` asks this class for what to do; it holds no state.
##   - music director v2: per-stem dB offsets from the weather, the hour, the heat, the chapter and the boss phase (`stem_targets`), the stealth music state from the
##     enemies' alert levels (`stealth_state`), the boss-theme boost of the last phase;
##   - engine variants per vehicle kind (`engine_for`), footstep surface per place (`footstep_surface`), ability sounds (`VERB_SOUNDS`);
##   - `shows`: the radio schedule lives in RadioShows.
## Stem order is Sfx.STEMS: pad, pulse, bass, perc, lead. Offsets never lift a stem above 0 dB and never wake a stem that the base state keeps off.

const OFF_DB := -60.0
const SNEAK_RANGE := 24.0            ## an unaware enemy this close makes the music hold its breath (state `sneak`)
const SUSPECT_RANGE := 45.0          ## a suspicious or searching enemy this close makes it `suspect`
const LEVEL_UNAWARE := 0             ## mirrors Stealth.Level
const LEVEL_SUSPICIOUS := 1
const LEVEL_SEARCHING := 2
const LEVEL_ALERTED := 3

const WEATHER := {
	&"clear": [0.0, 0.0, 0.0, 0.0, 0.0],
	&"drizzle": [1.0, -0.5, 0.0, 0.0, -2.0],
	&"rain": [2.0, -1.5, 0.0, -1.0, -4.0],
	&"storm": [3.0, -2.0, 1.0, 0.0, -8.0],
}
const NIGHT := [1.0, -2.0, 0.0, -1.0, -3.0]
const DAWN := [1.0, -1.0, -1.0, 0.0, 0.0]
const DUSK := [0.0, 1.0, 0.0, 0.0, -1.0]
const BOSS_PHASE_1 := [0.0, 0.0, 0.0, -4.0, -4.0]       ## the fight opens restrained, phase 2 is the full theme, phase 3 lifts the boss layer
const BOSS_LAYER_BOOST := {1: -3.0, 2: 0.0, 3: 3.0}      ## dB on top of Sfx.LAYER_DB[boss]
const CHAPTERS := 12                                      ## the sequel arc ends here; the music keeps its last colour afterwards

## Ability sounds: the three newest quantum verbs (PHASE SHIELD, TIME SLIP, ARC) and the hero verbs (SLAM, WARP GRAB, throw, wall-run). id -> [sound, dB, duck kind or ""]
const VERB_SOUNDS := {
	&"shield": [&"verb_shield", -4.0, &"ability"],
	&"slip": [&"verb_slip", -4.0, &"ability"],
	&"arc": [&"verb_arc", -5.0, &"ability"],
	&"slam": [&"verb_slam", -3.0, &"explosion"],
	&"grab": [&"verb_grab", -6.0, &"ability"],
	&"throw": [&"verb_throw", -5.0, &""],
	&"wallrun": [&"verb_wallrun", -10.0, &""],
}

## Engine families. kind -> [variant, pitch multiplier, dB]. The base family (empty variant) is the sedan-like car loop pair.
const ENGINES := {
	&"bike": [&"bike", 1.0, 0.0], &"qbike": [&"hover", 1.25, -2.0],
	&"hover": [&"hover", 1.0, 0.0], &"skiff": [&"hover", 0.9, -1.0], &"rover": [&"hover", 0.7, 0.0],
	&"truck": [&"heavy", 1.0, 1.0], &"bus": [&"heavy", 1.15, 0.0], &"van": [&"heavy", 1.3, -1.0], &"ambulance": [&"heavy", 1.25, -1.0],
	&"heli": [&"heavy", 0.62, 2.0], &"plane": [&"bike", 0.75, 1.0], &"boat": [&"heavy", 0.95, 0.0], &"tank": [&"heavy", 0.5, 3.0], &"armoured": [&"heavy", 1.05, 0.0],
	&"quad": [&"bike", 1.1, 0.0], &"scooter": [&"bike", 1.45, -2.0], &"hoverbike": [&"hover", 1.2, -1.0],
	&"sport": [&"", 1.14, 0.0], &"interceptor": [&"", 1.1, 0.0], &"suv": [&"", 0.9, 0.0], &"taxi": [&"", 1.0, 0.0], &"wagon": [&"", 0.95, 0.0], &"sedan": [&"", 1.0, 0.0],
}
const ENGINE_VARIANTS: Array[StringName] = [&"bike", &"hover", &"heavy"]

## Interiors with a soft floor (the rest ring like tile).
const CARPET_ROOMS: Array[StringName] = [&"bar", &"club", &"lobby", &"apartment", &"clinic", &"med_bay"]


static func _zero() -> Array:
	return [0.0, 0.0, 0.0, 0.0, 0.0]


static func weather_mods(weather: StringName) -> Array:
	return WEATHER.get(weather, WEATHER[&"clear"])


## hour < 0 = no clock = no change.
static func hour_mods(hour: float) -> Array:
	if hour < 0.0:
		return _zero()
	var h := fposmod(hour, 24.0)
	if h >= 20.0 or h < 5.0:
		return NIGHT
	if h < 8.0:
		return DAWN
	if h >= 17.0:
		return DUSK
	return _zero()


## The street heats the score up before the state flips: explore / driving grow bass and perc toward heat 3, alert grows perc and pulse toward heat 3.
static func heat_mods(state: StringName, heat: float) -> Array:
	var m := _zero()
	match state:
		&"explore", &"driving", &"sneak":
			var t := clampf(heat / 1.0, 0.0, 1.0)
			m[2] = 3.0 * t
			m[3] = 2.0 * t
		&"alert", &"suspect":
			var t2 := clampf((heat - 1.0) / 2.0, 0.0, 1.0)
			m[1] = 2.0 * t2
			m[3] = 4.0 * t2
	return m


static func chapter_mods(chapter: int) -> Array:
	var c := clampf(float(maxi(chapter, 0)) / float(CHAPTERS - 1), 0.0, 1.0)
	return [0.0, 2.0 * c, 2.0 * c, 1.0 * c, 0.0]


static func boss_mods(phase: int) -> Array:
	return BOSS_PHASE_1 if phase == 1 else _zero()


static func boss_layer_boost(phase: int) -> float:
	return float(BOSS_LAYER_BOOST.get(clampi(phase, 1, 3), 0.0))


## Final stem levels (dB) for `base` (one row of Sfx.MUSIC_STATES). ctx: weather, hour, heat, chapter, boss_phase (0 = none).
static func stem_targets(base: Array, state: StringName, ctx: Dictionary) -> PackedFloat32Array:
	var w := weather_mods(StringName(ctx.get("weather", &"clear")))
	var h := hour_mods(float(ctx.get("hour", -1.0)))
	var he := heat_mods(state, float(ctx.get("heat", 0.0)))
	var ch := chapter_mods(int(ctx.get("chapter", 0)))
	var bp := int(ctx.get("boss_phase", 0))
	var bm := boss_mods(bp) if (state == &"boss" and bp > 0) else _zero()
	var calm := state in [&"explore", &"driving", &"sneak", &"suspect", &"alert", &"menu"]
	var out := PackedFloat32Array()
	out.resize(5)
	for i in 5:
		var b := float(base[i])
		if b <= -50.0 or state in [&"death", &"win"]:
			out[i] = b
			continue
		var d: float = float(bm[i])
		if calm:
			d += float(w[i]) + float(h[i]) + float(he[i]) + float(ch[i])
		out[i] = clampf(b + d, -50.0, 0.0)
	return out


## The stealth music state for the strongest awareness around (level -1 = no enemy considered). &"" = nothing to say, the normal rules decide.
static func stealth_state(level: int, nearest_unaware: float, nearest_suspicious: float) -> StringName:
	if level >= LEVEL_ALERTED:
		return &"alert"
	if level >= LEVEL_SUSPICIOUS and nearest_suspicious <= SUSPECT_RANGE:
		return &"suspect"
	if level >= LEVEL_UNAWARE and nearest_unaware <= SNEAK_RANGE:
		return &"sneak"
	return &""


## [loop family variant, pitch multiplier, dB] for a vehicle kind.
static func engine_for(kind: StringName) -> Array:
	return ENGINES.get(kind, [&"", 1.0, 0.0])


static func engine_loops(variant: StringName) -> Array[StringName]:
	if variant == &"":
		return [&"engine_low", &"engine_high"]
	return [StringName("engine_%s_low" % variant), StringName("engine_%s_high" % variant)]


## What the feet hear. indoors: the listener stands in an interior (room = its type); y: the world height; climbing: a stair or ledge.
static func footstep_surface(y: float, climbing: bool, indoors: bool, room: StringName) -> StringName:
	if indoors:
		return &"carpet" if room in CARPET_ROOMS else &"tile"
	if y > 0.5:
		return &"roof"
	if climbing or y > 0.12:
		return &"stairs"
	return &"asphalt"
