extends Node
## Command-line dev hooks. Inert unless flags are passed after `--` (see tools/shot.sh and tools/bot.sh):
##   --shot=PATH           save one screenshot after --frames frames (default 20), then quit
##   --shot-seq=PREFIX     save PREFIX_000.png, PREFIX_001.png ... every --every frames (default 30), --count shots (default 5), then quit
##   --bot=res://x.gd      run a bot: the script needs `func step(t: float, delta: float) -> bool` (return true when finished)
## Screenshots need a real renderer (xvfb + software GL); --headless renders nothing.

var _args := {}
var _frame := 0
var _shots := 0
var _bot: RefCounted
var _t := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	set_process(not _args.is_empty())
	if _args.has("bot"):
		var script := load(_args["bot"]) as GDScript
		if script:
			_bot = script.new()
		else:
			push_error("Dev: cannot load bot %s" % _args["bot"])


func _process(delta: float) -> void:
	_frame += 1
	_t += delta
	var finished := false
	if _bot and _bot.has_method("step"):
		finished = _bot.step(_t, delta)
	if _args.has("shot") and _frame >= int(_args.get("frames", "20")):
		await _save(_args["shot"])
		get_tree().quit()
		set_process(false)
		return
	if _args.has("shot-seq"):
		var every := int(_args.get("every", "30"))
		if _frame % every == 0:
			await _save("%s_%03d.png" % [_args["shot-seq"], _shots])
			_shots += 1
			if _shots >= int(_args.get("count", "5")):
				get_tree().quit()
				set_process(false)
				return
	if finished and not _args.has("shot-seq"):
		get_tree().quit()
		set_process(false)


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("Dev: no image (use xvfb + software GL, not --headless)")
		return
	img.save_png(path)
	print("SHOT_SAVED ", path, " ", img.get_size())
