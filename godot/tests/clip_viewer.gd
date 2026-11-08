extends "res://tests/loco_viewer.gd"
## Look-dev of the captured clips: the hero (live Player) pinned to frames of a clip (HeroClips.force), side camera sheets. One sheet per clip: <out>/clip_<name>.png.
##   tools/clip_view.sh OUT_DIR [WxH]      env CLIPS=jump_start,jump_loop  CLIP_FRAMES=14  CLIP_SECS=<clip duration>

func run(h: Node) -> void:
	host = h
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] == "out":
			out = kv[1]
	DirAccess.make_dir_recursive_absolute(out)
	await e.setup(host)
	p = e.p
	_make_floor_grid()
	_side = SubViewport.new()
	_side.size = Vector2i(tile.x, tile.y)
	_side.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_side_cam = Camera3D.new()
	_side_cam.fov = 40.0
	_side.add_child(_side_cam)
	host.add_child(_side)
	_side_cam.make_current()
	var names := (OS.get_environment("CLIPS") if OS.get_environment("CLIPS") != "" else "jump_start,jump_loop,jump_land,crouch_idle,crouch_walk,idle,ready").split(",", false)
	var n := int(OS.get_environment("CLIP_FRAMES")) if OS.get_environment("CLIP_FRAMES") != "" else 14
	await e.prep(Vector3(0.0, 0.0, -30.0), -PI * 0.5, -0.1, 20)
	for nm in names:
		var c: Dictionary = (HeroClips.data()["clips"] as Dictionary).get(nm, {})
		if c.is_empty():
			continue
		var dur := float(c["dur"])
		var sides: Array[Image] = []
		for i in n:
			p.body.clips.force = [nm, dur * float(i) / float(n)]
			for k in 3:
				await RenderingServer.frame_post_draw
			sides.append(await _grab_side())
		_sheet(sides, "%s/clip_%s.png" % [out, nm], 7)
		print("CLIP ", nm, " ", dur)
	p.body.clips.force = []
	await e.teardown()
