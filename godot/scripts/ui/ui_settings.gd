class_name UiSettings
extends RefCounted
## Player settings and the best score, persisted with ConfigFile (user://settings.cfg by default; tests pass a temp path).

const DEFAULT_PATH := "user://settings.cfg"

var path: String
var quality := -1            ## graphics tier 0..2, -1 = never chosen (keep the default / --quality)
var post := true             ## post-process (grain, vignette, grade)
var muted := false
var best := 0


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
	best = maxi(int(cf.get_value("progress", "best", 0)), 0)


func save() -> bool:
	var cf := ConfigFile.new()
	cf.set_value("graphics", "quality", quality)
	cf.set_value("graphics", "post", post)
	cf.set_value("audio", "muted", muted)
	cf.set_value("progress", "best", best)
	return cf.save(path) == OK
