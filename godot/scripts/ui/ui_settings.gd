class_name UiSettings
extends RefCounted
## Player settings and the best score, persisted with ConfigFile (user://settings.cfg by default; tests pass a temp path).

const DEFAULT_PATH := "user://settings.cfg"

var path: String
var quality := -1            ## graphics tier 0..2, -1 = never chosen (keep the default / --quality)
var low_plus := false        ## LOW+ chosen (quality is 0 then): the tier below LOW
var post := true             ## post-process (grain, vignette, grade)
var muted := false
var volumes := {}            ## per-bus volume 0..1 {"Master", "SFX", "Music", "Ambient", "Voice"}; missing = full
var best := 0
var cutscenes := true        ## cutscenes (intro, chapter, boss beats) on / off
var test_mode := false        ## test (hack) menu available in a release build too (debug builds always have it)
var aim_assist := true       ## soft aim assist (look slowdown + magnetism near enemies; off for the Pulse Lance)
var civilians := true        ## the people in the street can be hurt and killed (a quantum dissolve, no gore); off = they only run and shots pass through them (Game.civilian_casualties)
var auto_fire := false       ## hold the trigger automatically while the crosshair is on an enemy
var intro_seen := false      ## the intro plays once, at the first DEPLOY
var look_x := 1.0            ## look sensitivity multipliers (touch drag and mouse), SENS_MIN..SENS_MAX
var look_y := 1.0
var ads_sens := 1.0          ## extra look multiplier at full ADS
var hud_scale := 1.0         ## HUD / touch UI scale, HUD_MIN..HUD_MAX
var left_hand := false       ## touch layout mirrored: stick on the right, buttons on the left
var button_size := 1.0       ## touch button size multiplier, BTN_MIN..BTN_MAX
var fps_cap := 60            ## one of FPS_CHOICES (0 = uncapped)
var vibration := true
var haptic_level := 1        ## haptic intensity 0 light, 1 normal, 2 strong (HAPTIC_NAMES)
var key_binds := {}          ## keyboard overrides: action name -> physical keycode (ControlMap)
var pad_binds := ControlMap.default_pad()   ## controller layout: slot -> action (ControlMap)
var subtitles := true        ## radio subtitle plate
var freeze_time := false     ## day/night cycle frozen at the current hour
var language := "en"         ## Tr.LANGS
var text_scale := 1.0        ## Tr.SCALES (1.0 / 1.25 / 1.5)
var cb_variant := 0          ## colour-safe palette when cb_safe: 0 deutan/protan (blue / orange), 1 tritan (red / teal)
var reduce_flash := false    ## no lightning exposure pulse, no full-screen quantum flash
var reduce_motion := false   ## no screen shake, no slow motion
var sub_size := 1.0          ## subtitle text multiplier (Tr.SCALES)
var sub_bg := 1              ## subtitle plate opacity step 0 soft, 1 normal, 2 solid
var chatter := 1             ## story chatter: 0 off (urgent lines only), 1 low (story beats, short), 2 full
var res_mode := -1          ## render resolution RenderRes 0 balanced .. 2 native, -1 = follow the graphics tier
var difficulty := 1         ## Difficulty.NAMES index (default NORMAL)
var cb_safe := false         ## colour-blind safe markers (blue / orange / white instead of red / green / magenta)

const SENS_MIN := 0.3
const SENS_MAX := 2.0
const HUD_MIN := 0.8
const HUD_MAX := 1.2
const BTN_MIN := 0.8
const BTN_MAX := 1.4
const FPS_CHOICES: Array[int] = [30, 60, 90, 120, 0]
const HAPTIC_NAMES: Array[String] = ["LIGHT", "NORMAL", "STRONG"]
const HAPTIC_SCALE: Array[float] = [0.5, 1.0, 1.6]
const REDUCED_MS := 60           ## longest buzz under reduce-motion

## Live values read by the consumers (touch controls, camera rig, UiUtil, story view); `publish()` copies the saved choices here.
static var s_look_x := 1.0
static var s_look_y := 1.0
static var s_ads := 1.0
static var s_hud_scale := 1.0
static var s_left_hand := false
static var s_button_size := 1.0
static var s_vibration := true
static var s_haptic := 1
static var buzzed := 0                     ## buzzes issued (tests)
static var last_plan := {}                 ## the last buzz plan (tests)
static var s_subtitles := true
static var s_cb_safe := false
static var s_freeze_time := false
static var s_cb_variant := 0
static var s_reduce_flash := false
static var s_reduce_motion := false
static var s_sub_size := 1.0
static var s_sub_bg := 1
static var s_chatter := 1
const CHATTER_NAMES: Array[String] = ["OFF", "LOW", "FULL"]
static var s_opt_page := 0                 ## options screen page (0 main, 1 accessibility); UI state only, never saved


func _init(p := DEFAULT_PATH) -> void:
	path = p
	load_file()


static func _f(v: Variant, d := 1.0) -> float:
	return float(v) if (v is float and is_finite(v)) or v is int else d


static func _b(v: Variant, d := false) -> bool:
	return bool(v) if v is bool or v is int else d


func load_file() -> void:
	var cf := Progress._read(path)
	if cf == null:
		return
	quality = clampi(Progress._num(cf.get_value("graphics", "quality", -1)), -1, 2)
	low_plus = quality == 0 and _b(cf.get_value("graphics", "low_plus", false))
	post = _b(cf.get_value("graphics", "post", true))
	muted = _b(cf.get_value("audio", "muted", false))
	var vols = cf.get_value("audio", "volumes", {})
	volumes = (vols as Dictionary).duplicate() if vols is Dictionary else {}
	best = maxi(Progress._num(cf.get_value("progress", "best", 0)), 0)
	cutscenes = _b(cf.get_value("graphics", "cutscenes", true))
	intro_seen = _b(cf.get_value("progress", "intro_seen", false))
	test_mode = _b(cf.get_value("debug", "test_mode", false))
	aim_assist = _b(cf.get_value("gameplay", "aim_assist", true))
	auto_fire = _b(cf.get_value("gameplay", "auto_fire", false))
	civilians = _b(cf.get_value("gameplay", "civilians", true))
	res_mode = clampi(Progress._num(cf.get_value("graphics", "res_mode", -1), -1), -1, 2)
	difficulty = Difficulty.clamp_mode(Progress._num(cf.get_value("gameplay", "difficulty", 1), 1))
	look_x = clampf(_f(cf.get_value("controls", "look_x", 1.0)), SENS_MIN, SENS_MAX)
	look_y = clampf(_f(cf.get_value("controls", "look_y", 1.0)), SENS_MIN, SENS_MAX)
	ads_sens = clampf(_f(cf.get_value("controls", "ads_sens", 1.0)), SENS_MIN, SENS_MAX)
	hud_scale = clampf(_f(cf.get_value("ui", "hud_scale", 1.0)), HUD_MIN, HUD_MAX)
	left_hand = _b(cf.get_value("ui", "left_hand", false))
	button_size = clampf(_f(cf.get_value("ui", "button_size", 1.0)), BTN_MIN, BTN_MAX)
	var cap := Progress._num(cf.get_value("graphics", "fps_cap", 60), 60)
	fps_cap = cap if FPS_CHOICES.has(cap) else 60
	vibration = _b(cf.get_value("controls", "vibration", true))
	haptic_level = clampi(Progress._num(cf.get_value("controls", "haptic_level", 1), 1), 0, 2)
	key_binds = ControlMap.sanitize_keys(cf.get_value("controls", "key_binds", {}))
	pad_binds = ControlMap.sanitize_pad(cf.get_value("controls", "pad_binds", {}))
	subtitles = _b(cf.get_value("ui", "subtitles", true))
	cb_safe = _b(cf.get_value("ui", "cb_safe", false))
	freeze_time = _b(cf.get_value("gameplay", "freeze_time", false))
	var lg = cf.get_value("ui", "language", "en")
	language = lg if lg is String and Tr.LANGS.has(lg) else "en"
	var ts := clampf(_f(cf.get_value("ui", "text_scale", 1.0)), 1.0, 1.5)
	text_scale = ts if Tr.SCALES.any(func(x): return is_equal_approx(x, ts)) else 1.0
	cb_variant = clampi(Progress._num(cf.get_value("ui", "cb_variant", 0)), 0, 1)
	reduce_flash = _b(cf.get_value("ui", "reduce_flash", false))
	reduce_motion = _b(cf.get_value("ui", "reduce_motion", false))
	var ss := clampf(_f(cf.get_value("ui", "sub_size", 1.0)), 1.0, 1.5)
	sub_size = ss if Tr.SCALES.any(func(x): return is_equal_approx(x, ss)) else 1.0
	sub_bg = clampi(Progress._num(cf.get_value("ui", "sub_bg", 1), 1), 0, 2)
	chatter = clampi(Progress._num(cf.get_value("ui", "chatter", 1), 1), 0, 2)


## Next FPS cap in FPS_CHOICES (wraps).
func next_fps_cap() -> int:
	return FPS_CHOICES[(maxi(FPS_CHOICES.find(fps_cap), 0) + 1) % FPS_CHOICES.size()]


## Copies the choices to the static mirrors and the engine (FPS cap, aim assist, auto-fire). `engine` false skips the engine calls (tests).
func publish(engine := true) -> void:
	s_look_x = look_x
	s_look_y = look_y
	s_ads = ads_sens
	s_hud_scale = hud_scale
	s_left_hand = left_hand
	s_button_size = button_size
	s_vibration = vibration
	s_haptic = haptic_level
	ControlMap.pad_binds = pad_binds.duplicate()
	s_subtitles = subtitles
	s_cb_safe = cb_safe
	s_freeze_time = freeze_time
	s_cb_variant = cb_variant
	s_reduce_flash = reduce_flash
	s_reduce_motion = reduce_motion
	s_sub_size = sub_size
	s_sub_bg = sub_bg
	s_chatter = chatter
	RenderRes.user_mode = res_mode
	Difficulty.set_mode(difficulty)
	Tr.set_lang(language)
	Tr.text_scale = text_scale
	Game.civilian_casualties = civilians
	if engine:
		AimAssist.enabled = aim_assist
		AimAssist.auto_fire = auto_fire
		Engine.max_fps = fps_cap
		ControlMap.apply_keys(key_binds)


## What a buzz of `ms` does with the settings applied: {ms, amp 0..1, weak, strong}; empty when vibration is off. The intensity level scales the length and the strength;
## reduce-motion keeps haptics but caps them (short, at most 40 % strength) and drops the continuous engine rumble (ControllerInput).
static func haptic_plan(ms: int) -> Dictionary:
	if not s_vibration or ms <= 0:
		return {}
	var k := HAPTIC_SCALE[clampi(s_haptic, 0, 2)]
	var amp := clampf(float(ms) / 120.0 * k, 0.15, 1.0)
	var dur := clampf(float(ms) * k, 10.0, 400.0)
	if s_reduce_motion:
		amp = minf(amp, 0.4)
		dur = minf(dur, float(REDUCED_MS))
	return {"ms": int(dur), "amp": amp, "weak": amp * 0.6, "strong": amp}


## A haptic tick when vibration is on: the controller rumbles when one is in use, else the handheld vibrates (touchscreens).
static func buzz(ms := 30) -> void:
	var plan := haptic_plan(ms)
	if plan.is_empty():
		return
	buzzed += 1
	last_plan = plan
	if ControllerInput.device >= 0:
		Input.start_joy_vibration(ControllerInput.device, float(plan["weak"]), float(plan["strong"]), float(plan["ms"]) / 1000.0)
	elif DisplayServer.is_touchscreen_available():
		Input.vibrate_handheld(int(plan["ms"]), float(plan["amp"]))


func save() -> bool:
	var cf := ConfigFile.new()
	cf.set_value("graphics", "quality", quality)
	cf.set_value("graphics", "low_plus", low_plus and quality == 0)
	cf.set_value("graphics", "post", post)
	cf.set_value("audio", "muted", muted)
	cf.set_value("audio", "volumes", volumes)
	cf.set_value("progress", "best", best)
	cf.set_value("graphics", "cutscenes", cutscenes)
	cf.set_value("progress", "intro_seen", intro_seen)
	cf.set_value("debug", "test_mode", test_mode)
	cf.set_value("gameplay", "aim_assist", aim_assist)
	cf.set_value("gameplay", "auto_fire", auto_fire)
	cf.set_value("gameplay", "civilians", civilians)
	cf.set_value("gameplay", "difficulty", difficulty)
	cf.set_value("controls", "look_x", look_x)
	cf.set_value("controls", "look_y", look_y)
	cf.set_value("controls", "ads_sens", ads_sens)
	cf.set_value("ui", "hud_scale", hud_scale)
	cf.set_value("ui", "left_hand", left_hand)
	cf.set_value("ui", "button_size", button_size)
	cf.set_value("graphics", "fps_cap", fps_cap)
	cf.set_value("graphics", "res_mode", res_mode)
	cf.set_value("controls", "vibration", vibration)
	cf.set_value("controls", "haptic_level", haptic_level)
	cf.set_value("controls", "key_binds", key_binds)
	cf.set_value("controls", "pad_binds", pad_binds)
	cf.set_value("ui", "subtitles", subtitles)
	cf.set_value("ui", "cb_safe", cb_safe)
	cf.set_value("gameplay", "freeze_time", freeze_time)
	cf.set_value("ui", "language", language)
	cf.set_value("ui", "text_scale", text_scale)
	cf.set_value("ui", "cb_variant", cb_variant)
	cf.set_value("ui", "reduce_flash", reduce_flash)
	cf.set_value("ui", "reduce_motion", reduce_motion)
	cf.set_value("ui", "sub_size", sub_size)
	cf.set_value("ui", "sub_bg", sub_bg)
	cf.set_value("ui", "chatter", chatter)
	return cf.save(path) == OK
