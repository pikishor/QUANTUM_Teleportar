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
	return cf.save(path) == OK
