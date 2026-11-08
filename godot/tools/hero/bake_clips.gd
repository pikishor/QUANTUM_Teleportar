extends SceneTree
## Godot side of tools/hero/clips.sh: reads the JSON written by build_clips.py and saves res://assets/anim/hero_clips.res (a HeroClipData resource, binary, packed arrays).
##   godot --headless --path . --script tools/hero/bake_clips.gd -- <in.json>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var src: String = args[0] if args.size() > 0 else "/tmp/hero_clips.json"
	var txt := FileAccess.get_file_as_string(src)
	var j: Variant = JSON.parse_string(txt)
	if typeof(j) != TYPE_DICTIONARY:
		push_error("bad json " + src)
		quit(1)
		return
	var d: Dictionary = j
	var clips: Dictionary = d["clips"]
	for k: String in clips:
		var c: Dictionary = clips[k]
		c["q"] = PackedFloat32Array(c["q"])
		c["hips"] = PackedFloat32Array(c["hips"])
	var res := HeroClipData.new()
	res.data = d
	var err := ResourceSaver.save(res, "res://assets/anim/hero_clips.res")
	print("saved hero_clips.res err=", err, " clips=", clips.keys())
	quit(0 if err == OK else 1)
