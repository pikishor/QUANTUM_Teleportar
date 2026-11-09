class_name Weather
extends Node
## Weather state machine (F6): clear, overcast, drizzle, rain, storm, fog. A child of the Atmosphere (created in its _ready).
## It only picks targets for the existing hooks: Atmosphere.set_weather(rain, wetness) (rain streaks, wet ground, the Sfx beds, wind and thunder
## all follow the rain value), the world Environment's fog density and a lightning flash (a short exposure kick, storm only).
## Gameplay reads static helpers: sight_mult() (enemy awareness range), snipe_mult() (sniper range), flash (0..1).
## The cycle timers run only while Game.state == &"play". set_state() (TEST MENU) overrides immediately; the saved state is Progress's [weather] key.

const STATES: Array[StringName] = [&"clear", &"overcast", &"drizzle", &"rain", &"storm", &"fog"]
## rain, wetness, fog (multiplier of the base density), sight (enemy awareness multiplier), snipe (sniper range multiplier), dwell (seconds, min/max)
const PRESETS := {
	&"clear": {"rain": 0.0, "wet": 0.25, "fog": 1.0, "sight": 1.0, "snipe": 1.0, "dwell": Vector2(90, 180)},
	&"overcast": {"rain": 0.0, "wet": 0.4, "fog": 1.3, "sight": 1.0, "snipe": 1.0, "dwell": Vector2(60, 120)},
	&"drizzle": {"rain": 0.35, "wet": 0.6, "fog": 1.4, "sight": 0.95, "snipe": 1.0, "dwell": Vector2(60, 120)},
	&"rain": {"rain": 0.7, "wet": 0.85, "fog": 1.6, "sight": 0.88, "snipe": 0.95, "dwell": Vector2(60, 150)},
	&"storm": {"rain": 1.0, "wet": 1.0, "fog": 2.0, "sight": 0.8, "snipe": 0.85, "dwell": Vector2(40, 80)},
	&"fog": {"rain": 0.0, "wet": 0.5, "fog": 4.0, "sight": 0.9, "snipe": 0.6, "dwell": Vector2(60, 120)},
}
## Next-state choices per state (cycle).
const NEXT := {
	&"clear": [&"overcast", &"fog"], &"overcast": [&"drizzle", &"clear", &"fog"], &"drizzle": [&"rain", &"overcast"],
	&"rain": [&"storm", &"drizzle", &"overcast"], &"storm": [&"rain"], &"fog": [&"overcast", &"clear"],
}

static var current: StringName = &"rain"       ## the state in force (the game starts in the Atmosphere's steady rain)
static var flash := 0.0                         ## 0..1 lightning flash level
static var cycle_enabled := true

var atmosphere: Atmosphere
var fog_mult := 1.0                             ## eased fog multiplier
var strikes := 0                                ## lightning strikes so far (tests wait on this counter)
var _dwell := 60.0
var _strike_in := 6.0
var _env: Environment
var _base_fog := -1.0
var _base_exposure := 1.0


static func sight_mult() -> float:
	return float(PRESETS[current]["sight"])


static func snipe_mult() -> float:
	return float(PRESETS[current]["snipe"])


static func classify(rain: float) -> StringName:
	return &"clear" if rain < 0.08 else (&"drizzle" if rain < 0.55 else (&"rain" if rain < 0.9 else &"storm"))


func _ready() -> void:
	atmosphere = get_parent() as Atmosphere
	if pending != &"":
		current = pending
		pending = &""
	set_state(current, true)


## Saved state to apply when the node is created after load_file().
## Own generator: the weather must not shift the global random sequence (world layout, traffic) that the rest of the game and the perf probe depend on.
var _rng := RandomNumberGenerator.new()


static var pending: StringName = &""


func set_state(s: StringName, instant := false) -> void:
	if not PRESETS.has(s):
		return
	current = s
	var p: Dictionary = PRESETS[s]
	var d: Vector2 = p["dwell"]
	_dwell = _rng.randf_range(d.x, d.y)
	_strike_in = _rng.randf_range(4.0, 10.0)
	if atmosphere:
		atmosphere.set_weather(float(p["rain"]), float(p["wet"]), instant)
	if instant:
		fog_mult = float(p["fog"])
		_apply_env()


func _process(delta: float) -> void:
	var p: Dictionary = PRESETS[current]
	var target := float(p["fog"])
	if fog_mult != target:
		fog_mult = target if absf(fog_mult - target) < 0.005 else lerpf(fog_mult, target, 1.0 - exp(-delta / 4.0))
	if Game.state != &"play":
		_apply_env()
		return
	if cycle_enabled:
		_dwell -= delta
		if _dwell <= 0.0:
			var opts: Array = NEXT[current]
			set_state(opts[_rng.randi() % opts.size()])
	if current == &"storm":
		_strike_in -= delta
		if _strike_in <= 0.0:
			strike()
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 4.0)
	_apply_env()


## One lightning flash (storm; also callable by tests).
func strike() -> void:
	strikes += 1
	flash = 1.0
	_strike_in = _rng.randf_range(5.0, 16.0)


func _apply_env() -> void:
	if _env == null:
		var vp := get_viewport()
		_env = vp.world_3d.environment if vp and vp.world_3d else null
		if _env == null:
			return
		_base_fog = _env.fog_density
		_base_exposure = _env.tonemap_exposure
	_env.fog_density = _base_fog * fog_mult * lerpf(1.0, 0.3, TerrainWorld.fog_zone) * (1.0 + MountainWeather.fog_boost)      # thinner haze in the outskirts so the mountains read, thicker inside the cloud deck of the mountains
	var base: float = _env.get_meta(&"base_exposure", _base_exposure)
	_env.tonemap_exposure = base * (1.0 + (0.0 if UiSettings.s_reduce_flash else 0.7) * flash)
