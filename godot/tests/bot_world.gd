extends RefCounted
## Visual bot for the world module: flies a Camera3D along a cinematic path (street level, wet road and facade close-ups,
## a rooftop, high overviews) and lets Dev save a screenshot every N frames (tools/bot.sh does that):
##   tools/bot.sh res://tests/bot_world.gd /tmp/world 20 10
## One shot per screenshot: shot k is taken at the end of its short dolly move, so every picture is deterministic.
## Optional user args (after --): --cam=x,y,z,tx,ty,tz[,fov];... (fixed poses, one per shot), --fov=70, --quality=0..2, --wet=0..1, --rain=0..1,
## --hide=Family,Family (hide families and their mirrored copies), --stats (print visible / shadow / total draw calls and primitives for every shot: `visible` is the camera pass, the number the budgets in
## BUDGETS.md talk about; the engine's global total adds the shadow cascades), --shots=a,b,c (only these shot names).
## tools/bot.sh does not forward user args: run the main scene yourself with `-- --bot=res://tests/bot_world.gd --shot-seq=PREFIX --every=N --count=M --stats ...`.

var _cam: Camera3D
var _frame := 0
var _args := {}
var _every := 30
var _count := 12
var _shots: Array = []       # [name, from_pos, from_look, to_pos, to_look, fov]
var _ready_frames := 0
var _quality := -1
var _setup_done := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_every = maxi(1, int(_args.get("every", "30")))
	if _args.has("count"):
		_count = maxi(1, int(_args["count"]))


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _world() -> Node3D:
	return Game.world


func _build_shots() -> void:
	_shots.clear()
	var w: City = Game.world as City
	var lots: Array = w.layout.lots if w != null else []
	var tall: CityLayout.Lot = null
	var mid: CityLayout.Lot = null
	var screen: CityLayout.Lot = null
	var best_d := 1.0e9
	var best_m := 1.0e9
	var best_s := 1.0e9
	for b in w.building_data:
		var lot: CityLayout.Lot = b.lot
		var d := Vector2(lot.cx, lot.cz).length()
		if lot.h >= 88.0 and d < best_d:
			best_d = d
			tall = lot
		var dm := Vector2(lot.cx + 50.0, lot.cz - 20.0).length()
		if lot.h >= 44.0 and lot.h < 80.0 and dm < best_m and lot.cz > -100.0:
			best_m = dm
			mid = lot
		if (b.flags & 8) != 0 and d < best_s:
			best_s = d
			screen = lot
	# 0: third-person street view from behind the spawn, eye height of a chase camera
	_shots.append(["third_person", Vector3(-38, 2.8, 6), Vector3(14, 1.6, 1), Vector3(-30, 2.8, 6), Vector3(24, 1.6, 1), 68.0])
	# 1: street level along the avenue from the spawn
	_shots.append(["street_eye", Vector3(-46, 1.75, 3.5), Vector3(120, 5.0, 2.0), Vector3(-28, 1.75, 3.5), Vector3(140, 6.0, 1.0), 72.0])
	# 2: low over the wet road, lamps and neon in the reflection
	_shots.append(["wet_road", Vector3(-30, 0.55, 5.5), Vector3(150, 3.0, 0.0), Vector3(-10, 0.55, 5.5), Vector3(170, 4.0, 0.0), 70.0])
	# 3: a facade close up from the sidewalk
	if mid != null:
		var base := Vector3(mid.cx, 0.0, mid.rect.end.y + 4.0)
		_shots.append(["facade", base + Vector3(mid.w * 0.35, 1.7, 5.0), Vector3(mid.cx, mid.h * 0.30, mid.rect.end.y),
				base + Vector3(mid.w * 0.15, 1.7, 5.0), Vector3(mid.cx - 2.0, mid.h * 0.42, mid.rect.end.y), 68.0])
	else:
		_shots.append(["facade", Vector3(0, 1.7, 20), Vector3(0, 25, 40), Vector3(4, 1.7, 20), Vector3(0, 30, 40), 68.0])
	# 4: a junction seen from a crosswalk, looking diagonally into the grid
	_shots.append(["junction", Vector3(-9.5, 1.7, -12.5), Vector3(70, 7.0, -70), Vector3(-7.5, 1.7, -12.5), Vector3(80, 9.0, -80), 74.0])
	# 5: steam vent on the avenue
	_shots.append(["steam", Vector3(190, 1.8, -2.5), Vector3(207, 1.2, -6.4), Vector3(196, 2.4, -3.0), Vector3(214, 3.0, -7.0), 56.0])
	# 6: the LED facade screen
	if screen != null:
		var sp := Vector3(screen.cx, 2.2, screen.rect.end.y + 26.0)
		_shots.append(["led_screen", sp, Vector3(screen.cx, screen.h * 0.4, screen.rect.end.y), sp + Vector3(6, 0.5, -6), Vector3(screen.cx, screen.h * 0.42, screen.rect.end.y), 60.0])
	# 7: down a long street, a crane move
	_shots.append(["crane", Vector3(-150, 14, 6), Vector3(100, 8, 0), Vector3(-120, 22, 6), Vector3(120, 10, 0), 62.0])
	# 8: rooftop of a landmark tower
	if tall != null:
		var rp := Vector3(tall.cx, tall.h + 1.8, tall.cz)
		_shots.append(["rooftop", rp + Vector3(-6, 0, 6), rp + Vector3(80, -30, -90), rp + Vector3(-4, 0, 4), rp + Vector3(90, -34, -70), 78.0])
		# 9: from the same roof towards the moon
		var md := w._env.moon_dir
		_shots.append(["moon", rp + Vector3(0, 0.5, 0), rp + md * 100.0 + Vector3(0, -6, 0), rp + Vector3(0, 0.5, 0), rp + md * 100.0 + Vector3(-5, -2, 0), 62.0])
	else:
		_shots.append(["rooftop", Vector3(0, 90, 0), Vector3(80, 60, -90), Vector3(2, 90, 0), Vector3(90, 56, -70), 78.0])
	# 10: high overview of the whole grid
	_shots.append(["overview", Vector3(-60, 255, 430), Vector3(0, 10, 0), Vector3(-20, 250, 410), Vector3(0, 10, 0), 62.0])
	# 11: skyline from the outer ring road, low, looking at the towers
	_shots.append(["skyline", Vector3(-330, 4.0, 300), Vector3(0, 55, -40), Vector3(-330, 4.0, 270), Vector3(10, 60, -50), 60.0])
	if _args.has("shots"):
		var wanted: PackedStringArray = String(_args["shots"]).split(",")
		var kept: Array = []
		for s in _shots:
			if s[0] in wanted:
				kept.append(s)
		_shots = kept
	if _args.has("cam"):
		# one or more fixed poses: --cam="x,y,z,tx,ty,tz[,fov];x,y,z,tx,ty,tz"
		_shots = []
		for pose: String in String(_args["cam"]).split(";"):
			var v: PackedStringArray = pose.split(",")
			if v.size() >= 6:
				var p := Vector3(float(v[0]), float(v[1]), float(v[2]))
				var l := Vector3(float(v[3]), float(v[4]), float(v[5]))
				var fov := float(v[6]) if v.size() >= 7 else float(_args.get("fov", "70"))
				_shots.append(["cam%d" % _shots.size(), p, l, p, l, fov])


func _setup() -> void:
	_setup_done = true
	_build_shots()
	var tree := _tree()
	_cam = Camera3D.new()
	_cam.name = "WorldBotCamera"
	_cam.far = 4000.0
	_cam.near = 0.1
	tree.root.add_child(_cam)
	_cam.make_current()
	_free_the_camera(tree)
	if Game.world != null and _args.has("quality") and Game.world.has_method("set_quality"):
		Game.world.set_quality(int(_args["quality"]))
	if _args.has("wet"):
		RenderingServer.global_shader_parameter_set(&"wetness", float(_args["wet"]))
	if _args.has("rain"):
		RenderingServer.global_shader_parameter_set(&"rain", float(_args["rain"]))


## The stability watchdog hands the view back to the gameplay camera once a second and the HUD, the hero and the post layers sit in front of the
## world: a world bot (run through main.tscn) stops the watchdog and hides the HUD and the hero (--keep_hud keeps them).
func _free_the_camera(tree: SceneTree) -> void:
	for n in tree.root.find_children("*", "Node", true, false):
		var sc: Script = n.get_script()
		if sc == null:
			continue
		var path: String = sc.resource_path
		if path.ends_with("/stability.gd"):
			n.process_mode = Node.PROCESS_MODE_DISABLED
		elif n is CanvasLayer and path.contains("/scripts/ui/") and not _args.has("keep_hud"):
			(n as CanvasLayer).visible = false
	if is_instance_valid(Game.player) and not _args.has("keep_hud"):
		(Game.player as Node3D).visible = false


func step(_t: float, _delta: float) -> bool:
	if Game.world == null:
		return false
	if not _setup_done:
		_setup()
	_frame += 1
	if _args.has("hide") and _frame == _every * int(_args.get("hide_from", "0")) + 1:
		# --hide=AmbientTraffic,FacadeKit[,..] [--hide_from=k]: hide those families (real and mirrored copies) from shot k on: A/B draw-call numbers in one run
		for nm: String in String(_args["hide"]).split(","):
			for n in _tree().root.find_children(nm + "*", "MultiMeshInstance3D", true, false):
				(n as Node3D).visible = false
	var shot_i := clampi(int(ceil(float(_frame) / float(_every))) - 1, 0, _shots.size() - 1)
	var f := float((_frame - 1) % _every + 1) / float(_every)
	f = f * f * (3.0 - 2.0 * f) if _every > 1 else 1.0
	var s: Array = _shots[shot_i % _shots.size()]
	if not _cam.current:
		_cam.make_current()
	_cam.fov = s[5]
	var pos: Vector3 = (s[1] as Vector3).lerp(s[3], f)
	var look: Vector3 = (s[2] as Vector3).lerp(s[4], f)
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	Game.camera = _cam
	if _args.has("stats") and _frame % _every == 0:
		# visible = what the camera pass draws (the budget number); shadow = the moon shadow cascades; total = both (what the engine reports globally)
		var vp := (Game.world as Node).get_viewport().get_viewport_rid()
		var info := RenderingServer
		print("BOT shot ", shot_i, " ", s[0],
				" visible: draws=", info.viewport_get_render_info(vp, info.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, info.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
				" prims=", info.viewport_get_render_info(vp, info.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, info.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
				" objs=", info.viewport_get_render_info(vp, info.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, info.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
				" | shadow: draws=", info.viewport_get_render_info(vp, info.VIEWPORT_RENDER_INFO_TYPE_SHADOW, info.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
				" prims=", info.viewport_get_render_info(vp, info.VIEWPORT_RENDER_INFO_TYPE_SHADOW, info.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
				" | total: draws=", info.get_rendering_info(info.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				" prims=", info.get_rendering_info(info.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	return _frame >= _every * _count
