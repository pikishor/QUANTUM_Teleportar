class_name UiSettings
extends RefCounted
## Player settings and the best score, persisted with ConfigFile (user://settings.cfg by default; tests pass a temp path).

const DEFAULT_PATH := "user://settings.cfg"

var path: String
var quality := -1            ## graphics tier 0..2, -1 = never chosen (keep the default / --quality)
var post := true             ## post-process (grain, vignette, grade)
var muted := false
var volumes := {}            ## per-bus volume 0..1 {"Master", "SFX", "Music", "Ambient", "Voice"}; missing = full
var best := 0
var cutscenes := true        ## cutscenes (intro, chapter, boss beats) on / off
var test_mode := false        ## test (hack) menu available in a release build too (debug builds always have it)
var aim_assist := true       ## soft aim assist (look slowdown + magnetism near enemies; off for the Pulse Lance)
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
var subtitles := true        ## radio subtitle plate
var freeze_time := false     ## day/night cycle frozen at the current hour
var cb_safe := false         ## colour-blind safe markers (blue / orange / white instead of red / green / magenta)

const SENS_MIN := 0.3
const SENS_MAX := 2.0
const HUD_MIN := 0.8
const HUD_MAX := 1.2
const BTN_MIN := 0.8
const BTN_MAX := 1.4
const FPS_CHOICES: Array[int] = [30, 60, 90, 120, 0]

## Live values read by the consumers (touch controls, camera rig, UiUtil, story view); `publish()` copies the saved choices here.
static var s_look_x := 1.0
static var s_look_y := 1.0
static var s_ads := 1.0
static var s_hud_scale := 1.0
static var s_left_hand := false
static var s_button_size := 1.0
static var s_vibration := true
static var s_subtitles := true
static var s_cb_safe := false
static var s_freeze_time := false


func _init(p := DEFAULT_PATH) -> void:
	path = p
	load_file()


func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	quality = clampi(int(cf.get_value("graphics", "quality", -1)), -1, 2)
	post = bool(cf.get_value("graphics", "post", true))
	muted = bool(cf.get_value("audio", "muted", false))
	var vols = cf.get_value("audio", "volumes", {})
	volumes = (vols as Dictionary).duplicate() if vols is Dictionary else {}
	best = maxi(int(cf.get_value("progress", "best", 0)), 0)
	cutscenes = bool(cf.get_value("graphics", "cutscenes", true))
	intro_seen = bool(cf.get_value("progress", "intro_seen", false))
	test_mode = bool(cf.get_value("debug", "test_mode", false))
	aim_assist = bool(cf.get_value("gameplay", "aim_assist", true))
	auto_fire = bool(cf.get_value("gameplay", "auto_fire", false))
	look_x = clampf(float(cf.get_value("controls", "look_x", 1.0)), SENS_MIN, SENS_MAX)
	look_y = clampf(float(cf.get_value("controls", "look_y", 1.0)), SENS_MIN, SENS_MAX)
	ads_sens = clampf(float(cf.get_value("controls", "ads_sens", 1.0)), SENS_MIN, SENS_MAX)
	hud_scale = clampf(float(cf.get_value("ui", "hud_scale", 1.0)), HUD_MIN, HUD_MAX)
	left_hand = bool(cf.get_value("ui", "left_hand", false))
	button_size = clampf(float(cf.get_value("ui", "button_size", 1.0)), BTN_MIN, BTN_MAX)
	var cap := int(cf.get_value("graphics", "fps_cap", 60))
	fps_cap = cap if FPS_CHOICES.has(cap) else 60
	vibration = bool(cf.get_value("controls", "vibration", true))
	subtitles = bool(cf.get_value("ui", "subtitles", true))
	cb_safe = bool(cf.get_value("ui", "cb_safe", false))
	freeze_time = bool(cf.get_value("gameplay", "freeze_time", false))


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
	s_subtitles = subtitles
	s_cb_safe = cb_safe
	s_freeze_time = freeze_time
	if engine:
		AimAssist.enabled = aim_assist
		AimAssist.auto_fire = auto_fire
		Engine.max_fps = fps_cap


## A short haptic tick when vibration is on (handhelds only).
static func buzz(ms := 30) -> void:
	if s_vibration and DisplayServer.is_touchscreen_available():
		Input.vibrate_handheld(ms)


func save() -> bool:
	var cf := ConfigFile.new()
	cf.set_value("graphics", "quality", quality)
	cf.set_value("graphics", "post", post)
	cf.set_value("audio", "muted", muted)
	cf.set_value("audio", "volumes", volumes)
	cf.set_value("progress", "best", best)
	cf.set_value("graphics", "cutscenes", cutscenes)
	cf.set_value("progress", "intro_seen", intro_seen)
	cf.set_value("debug", "test_mode", test_mode)
	cf.set_value("gameplay", "aim_assist", aim_assist)
	cf.set_value("gameplay", "auto_fire", auto_fire)
	cf.set_value("controls", "look_x", look_x)
	cf.set_value("controls", "look_y", look_y)
	cf.set_value("controls", "ads_sens", ads_sens)
	cf.set_value("ui", "hud_scale", hud_scale)
	cf.set_value("ui", "left_hand", left_hand)
	cf.set_value("ui", "button_size", button_size)
	cf.set_value("graphics", "fps_cap", fps_cap)
	cf.set_value("controls", "vibration", vibration)
	cf.set_value("ui", "subtitles", subtitles)
	cf.set_value("ui", "cb_safe", cb_safe)
	cf.set_value("gameplay", "freeze_time", freeze_time)
	return cf.save(path) == OK
