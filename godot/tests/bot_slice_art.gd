extends RefCounted
## Slice art bot: the market street around the spawn and the three most used interiors (corner store, bar, warehouse), seen from the real game camera.
## Prints draws / primitives per spot and saves one PNG per spot.
##   SLICE_OUT=<dir> [SLICE_SPOTS=a,b] BOT_RES=1200x540 [QUALITY=0|1] tools/bot.sh res://tests/bot_slice_art.gd /tmp/x 1000 1
const SETTLE := 14
## name: [kind, yaw, pitch, dx, dz]  (street: offset from the spawn; interior: type + hero offset in the room)
const SPOTS := {
	&"st_e": [&"street", -1.5708, -0.10, 0.0, 0.0],
	&"st_w": [&"street", 1.5708, -0.10, 0.0, 0.0],
	&"st_n": [&"street", 3.1416, -0.10, 0.0, 0.0],
	&"st_s": [&"street", 0.0, -0.10, 0.0, 0.0],
	&"st_e2": [&"street", -1.5708, -0.10, 30.0, 0.0],
	&"st_w2": [&"street", 1.5708, -0.10, -40.0, 0.0],
	&"st_s2": [&"street", 0.0, -0.10, 0.0, 30.0],
	&"st_n2": [&"street", 3.1416, -0.10, 0.0, -30.0],
	&"sw_a": [&"street", -2.2, -0.05, 9.0, -3.0],
	&"sw_b": [&"street", -0.9, -0.05, 9.0, 3.0],
	&"sw_c": [&"street", 0.6, -0.05, -9.0, 3.0],
	&"sw_d": [&"street", 2.4, -0.05, -9.0, -3.0],
	&"in_store_a": [&"interior", &"bodega", 0.0, 0.0],
	&"in_store_b": [&"interior", &"bodega", 2.4, 1.0],
	&"in_store_c": [&"interior", &"bodega", 4.0, 2.0],
	&"in_bar_a": [&"interior", &"bar", 0.0, 0.0],
	&"in_bar_b": [&"interior", &"bar", 2.4, 1.0],
	&"in_bar_c": [&"interior", &"bar", 4.0, 2.0],
	&"in_wh_a": [&"interior", &"warehouse", 0.0, 0.0],
	&"in_wh_b": [&"interior", &"warehouse", 2.4, 1.0],
	&"in_wh_c": [&"interior", &"warehouse", 4.0, 2.0],
	&"in_apt_a": [&"interior", &"apartment", 0.0, 0.0],
	&"in_apt_b": [&"interior", &"apartment", 2.4, 1.0],
	&"in_apt_c": [&"interior", &"apartment", 4.0, 2.0],
	&"in_cli_a": [&"interior", &"clinic", 0.0, 0.0],
	&"in_cli_b": [&"interior", &"clinic", 2.4, 1.0],
	&"in_cli_c": [&"interior", &"clinic", 4.0, 2.0],
	&"in_lob_a": [&"interior", &"lobby", 0.0, 0.0],
	&"in_off_a": [&"office", &"lobby", 0.0, 0.0],
	&"in_off_b": [&"office", &"lobby", 2.5, 1.0],
	&"in_off_c": [&"office", &"lobby", -2.4, 2.0],
	&"in_wpn_a": [&"interior", &"weapons", 0.0, 0.0],
	&"in_wpn_b": [&"interior", &"weapons", 2.4, 1.0],
	&"in_wpn_c": [&"interior", &"weapons", 4.0, 2.0],
}
var _spots: Array[StringName] = []
var _i := 0
var _wait := 0
var _p: Player
var _out := ""


func _init() -> void:
	_out = OS.get_environment("SLICE_OUT")
	var s := OS.get_environment("SLICE_SPOTS")
	for n in (s.split(",", false) if s != "" else PackedStringArray()):
		_spots.append(StringName(n))
	if _spots.is_empty():
		for k in SPOTS:
			_spots.append(k)


func step(_t: float, _dt: float) -> bool:
	if _p == null:
		_p = Game.player as Player
		if _p == null:
			return false
		for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
			(n as AutoQuality).enabled = false
		for n in _p.get_tree().root.find_children("*", "Stability", true, false):
			n.set_process(false)
		_p.max_hp = 1.0e6
		if OS.get_environment("SLICE_HUD") == "0":
			for n in _p.get_tree().root.find_children("*", "CanvasLayer", true, false):
				var sc: Script = n.get_script()
				if sc != null and sc.resource_path.contains("/scripts/ui/"):
					(n as CanvasLayer).visible = false
		DirAccess.make_dir_recursive_absolute(_out)
		_begin()
	if _i >= _spots.size():
		return true
	if _wait > 0:
		_wait -= 1
		_p.hp = _p.max_hp
		return false
	var img := _p.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, _spots[_i]])
	print("SLICE %s draws %d prims %d" % [_spots[_i], RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	_i += 1
	if _i >= _spots.size():
		print("SLICE_DONE")
		if OS.get_environment("BOT_FASTEXIT") != "":
			OS.kill(OS.get_process_id())
		return true
	_begin()
	return false


func _begin() -> void:
	_wait = SETTLE
	Game.state = &"play"
	if is_instance_valid(Game.enemies):
		TestMode.kill_all_enemies()
	TestMode.set_weather("CLEAR")
	TestMode.set_heat(0.0)
	var sp: Array = SPOTS[_spots[_i]]
	var ig := InteriorGameplay.instance
	if sp[0] == &"street":
		if ig != null and ig.active:
			ig.leave(true)
		var pos: Vector3 = Game.SPAWN + Vector3(float(sp[3]), 0.1, float(sp[4]))
		_p.teleport_to(pos)
		_p.camera_rig.reset_view(float(sp[1]), float(sp[2]))
	else:
		if ig == null:
			return
		if ig.active:
			ig.leave(true)
		var d := ig.doors_of(sp[1], Game.SPAWN)[0]
		_p.teleport_to(d["pos"])
		ig.enter(d, true)
		if sp[0] == &"office":
			# the smallest room of the plan (the job room behind a lobby): the hero stands in its corner looking across it (a) / at its door side (b, c)
			var best := Rect2()
			for r in ig.interior.floor_rects:
				if r.get_area() > 8.0 and (best.get_area() <= 0.0 or r.get_area() < best.get_area()):
					best = r
			var c := best.get_center()
			var corner := best.position + Vector2(0.9, 0.9) if float(sp[2]) >= 0.0 else best.end - Vector2(0.9, 0.9)
			_p.teleport_to(Vector3(corner.x, d["pos"].y, corner.y))
			var look := c - corner
			print("SLICE office rect ", best, " hero ", corner)
			_p.camera_rig.reset_view(atan2(-look.x, -look.y) + (0.0 if float(sp[3]) < 1.5 else 1.2), -0.12)
			return
		# the hero keeps the entry spot; the camera looks around from there (a: the way in, b/c: turned)
		_p.camera_rig.reset_view(float(sp[2]), -0.12)
