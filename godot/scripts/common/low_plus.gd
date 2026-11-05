class_name LowPlus
extends RefCounted
## LOW+, the graphics tier below LOW for phones that cannot hold 30 FPS (Game.low_plus with Game.quality == 0; Game.set_low_plus / set_tier_index switch it).
## What it changes, one place for the numbers (every consumer asks `LowPlus.on()` and uses the share):
##   render      3D scale 0.55 with plain bilinear (no FSR pass at native resolution), no shadows, no MSAA, no reflection, no bloom / fog / tonemap adjustments, material v2 and the
##               quantum surface layer off, the lean facade shader (building_far) for every building;
##   population  enemies, cars, crowd, traffic, flocks, particles and explosion slots at a share of their LOW numbers;
##   interface   the HUD, the touch layer and the minimap redraw at HUD_HZ instead of every frame.
## The governor (AutoQuality) steps LOW -> LOW+ after GOVERNOR_FOR seconds below 30 FPS; a touchscreen with a weak GPU (`weak_gpu`) starts on LOW+ until the player chooses.

const SCALE_3D := 0.55
const ENEMY_SHARE := 0.6               ## LOW cap 5 -> 3
const CAR_SHARE := 0.67                ## LOW cap 3 -> 2
const CROWD_SHARE := 0.5
const TRAFFIC_SHARE := 0.45
const FAUNA_SHARE := 0.5
const FX_SHARE := 0.5                  ## particle counts and explosion slots on top of LOW's own 0.5
const RAIN_SHARE := 0.5
const HUD_HZ := 12.0                   ## HUD / touch layer redraws per second on LOW+ (every 3rd frame at 30 FPS)
const HUD_HZ_LOW := 20.0              ## on LOW (every 2nd frame at 30 FPS, every frame below 20 FPS)
const GOVERNOR_FOR := 5.0              ## seconds under 30 FPS on LOW before the governor steps to LOW+
const WEAK_GPU := ["mali-t", "mali-g31", "mali-g51", "mali-g52", "mali-g57", "mali-400", "mali-450", "adreno (tm) 3", "adreno (tm) 4", "adreno (tm) 5", "adreno (tm) 60", "adreno (tm) 61", "adreno (tm) 62",
		"adreno 3", "adreno 4", "adreno 5", "adreno 60", "adreno 61", "adreno 62", "powervr", "sgx", "videocore", "vivante", "intel(r) hd graphics 4", "apple a8", "apple a9"]


static var throttle := true             ## false = every frame at every tier (the CPU probe's "before" numbers; nothing else sets it)


## Seconds between two redraws of the minimap: 1/15 normally, 1/10 on LOW, 1/7.5 on LOW+.
static func minimap_interval() -> float:
	if Game.quality >= 1 or not throttle:
		return 1.0 / 15.0
	return 1.0 / (7.5 if on() else 10.0)


## LOW+ runs the physics at half rate with at most two catch-up ticks per frame (the player and the camera interpolate between ticks): on a phone below 30 FPS the default 60 Hz
## meant 3-5 physics ticks of every enemy, car and the hero per rendered frame, and a slow frame made the next one slower still.
const PHYSICS_HZ := 30
const PHYSICS_STEPS := 2


static var _physics_lp := false         ## true while apply_physics() has the LOW+ rate in force: leaving LOW+ restores the project rate, any other call leaves the engine alone (tests set their own tick rate)


static func apply_physics() -> void:
	var lp := on()
	if lp:
		Engine.physics_ticks_per_second = PHYSICS_HZ
		Engine.max_physics_steps_per_frame = PHYSICS_STEPS
	elif _physics_lp:
		Engine.physics_ticks_per_second = int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
		Engine.max_physics_steps_per_frame = int(ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame", 8))
	_physics_lp = lp


static func on() -> bool:
	return Game.low_plus and Game.quality == 0


## `n` scaled by `share` while LOW+ is on (at least `min_n`), `n` otherwise.
static func scaled(n: int, share: float, min_n := 1) -> int:
	return maxi(min_n, roundi(float(n) * share)) if on() else n


static func scale_f(x: float, share: float) -> float:
	return x * share if on() else x


## Seconds between two redraws of the HUD and the touch layer: 0 = every frame (MED and HIGH), 1/20 on LOW, 1/12 on LOW+.
static func hud_interval() -> float:
	if Game.quality >= 1 or not throttle:
		return 0.0
	return 1.0 / (HUD_HZ if on() else HUD_HZ_LOW)


## True for GPUs that cannot hold 30 FPS with the LOW tier's shaders (old Mali / Adreno / PowerVR / Vivante): matched on the adapter name, lower case.
static func weak_gpu(adapter: String) -> bool:
	var a := adapter.to_lower()
	for k: String in WEAK_GPU:
		if a.contains(k):
			return true
	return false


## The first-launch tier index (Game.tier_index) of a touchscreen: 0 LOW+ on a weak GPU or a software renderer, 1 LOW otherwise (the saved choice always wins, see AutoQuality.wants_low_default).
static func device_default(adapter: String) -> int:
	var a := adapter.to_lower()
	return 0 if (weak_gpu(a) or a.contains("llvmpipe") or a.contains("swiftshader")) else 1
