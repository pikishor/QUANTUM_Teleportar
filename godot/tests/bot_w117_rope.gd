extends RefCounted
## WAVE 117 look bot of THE ROPE OF SNAKES, the zip and the cues: the real game at phone aspect, the phone HUD, REAL FINGERS only (tests/w116_fingers.gd). One PNG per moment in W117_OUT.
##   W117_OUT=<dir> W117_PARTS=rope,zip,cue,energy BOT_RES=1200x540 BOT_USER_ARGS=--touch ENGINE_ARGS="--fixed-fps 30" QUALITY=0 BOT_TIMEOUT=580 tools/bot.sh res://tests/bot_w117_rope.gd /tmp/x 100000 1
##   W117_OLD=1  the single snake rope of wave 115 and the old zip end (before frames)
const Fingers := preload("res://tests/w116_fingers.gd")
const SPOT := Vector3(-30.0, 0.0, 4.0)
var _started := false
var _done := false
var tree: SceneTree
var root: Window
var fg: Fingers
var p: Player
var sn: SnakeTraversal
var out := ""
var _cam2: Camera3D


func step(_t: float, _dt: float) -> bool:
	if _started:
		return _done
	tree = Engine.get_main_loop() as SceneTree
	if tree.get_first_node_in_group(&"hud") == null or not is_instance_valid(Game.player):
		return false
	_started = true
	_run()
	return false


func frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("W117 shot ", name, " mode ", sn.mode_name(), " pos ", p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), " label ", fg.button_label(&"snake"))


## A frame through a spare camera (a close look at the anchor or at the hand), then back to the chase camera.
func close(name: String, at: Vector3, look: Vector3) -> void:
	if _cam2 == null:
		_cam2 = Camera3D.new()
		_cam2.fov = 50.0
		root.add_child(_cam2)
	_cam2.global_position = at
	_cam2.look_at(look, Vector3.UP)
	_cam2.make_current()
	await frames(1)
	await shot(name)
	p.camera_rig.camera.make_current()


func tp(pos: Vector3, yaw := -PI * 0.5, pitch := 0.05) -> void:
	fg.up_all()
	await frames(2)
	sn.cancel()
	sn.reset()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await frames(15)


func _run() -> void:
	root = tree.root
	out = OS.get_environment("W117_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	p = Game.player as Player
	sn = p.snake
	fg = Fingers.new(root)
	for n in root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Game.missions != null:
		Game.missions.contracts.enabled = false
	if Encounters.current != null:
		Encounters.current.enabled = false
	p.max_hp = 1.0e6
	p.hp = 1.0e6
	TestMode.god = true
	CrateReveal._quiet = 0
	var old := OS.get_environment("W117_OLD") == "1"
	if old:
		SnakeTendril.braided_rope = false
		SnakeZip.wall_end = false
		SnakeFx.cues_on = false
	var city := Game.world as City
	if city != null and city.day_night != null:
		city.day_night.frozen = true
		city.day_night.set_hour(13.0)
	var at := Game.atmosphere as Atmosphere
	if at != null and at.weather != null:
		at.weather.set_process(false)
		at.set_weather(0.0, 0.3, true)
	await frames(30)
	print("W117 setup touch ", Game.force_touch, " controls ", fg.tc != null and fg.tc.controls_on, " quality ", Game.quality, " old ", old)
	var parts := OS.get_environment("W117_PARTS")
	for part in (parts if parts != "" else "rope,zip,cue,energy").split(",", false):
		await call("_part_" + part)
	print("W117 DONE")
	_done = true


func _part_rope() -> void:
	await tp(SPOT)
	fg.press(1, &"jump")
	await frames(3)
	fg.up(1)
	await until(func() -> bool: return p.air_time > 0.25, 40)
	fg.press(2, &"snake")
	var ok := await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.SWING and sn.swing.tendril != null, 30)
	print("W117 rope swing ", ok)
	if not ok:
		fg.up_all()
		return
	var t := sn.swing.tendril
	await frames(2)
	await shot("rope_1_fly_out")
	await until(func() -> bool: return t.is_attached(), 40)
	await frames(5)
	await shot("rope_2_taut")
	var hand := t.origin_pos
	var side := (t.head_pos - hand).normalized().cross(Vector3.UP).normalized()
	var along := (t.head_pos - hand).normalized()
	await close("rope_3_hand_close", hand + along * 2.5 + side * 3.0, hand + along * 2.5)
	hand = t.origin_pos
	along = (t.head_pos - hand).normalized()
	await close("rope_4_bite_close", t.head_pos - along * 0.4 + side * 2.2, t.head_pos - along * 0.6)
	await frames(8)
	await shot("rope_5_swing")
	print("W117 rope braid ", t.braid, " radius ", t.braid_radius, " pitch ", t.braid_pitch, " tension ", t.tension, " len ", t.length(), " instances ", SnakeTendrilPool.current.instances)
	fg.up(2)
	await frames(3)
	hand = t.origin_pos
	await close("rope_6_unwind_close", hand + (t.head_pos - hand).normalized() * 2.5 + side * 3.5, hand + (t.head_pos - hand).normalized() * 2.5)
	await shot("rope_7_let_go")
	await until(func() -> bool: return p.is_on_floor(), 200)


func _part_zip() -> void:
	await tp(Vector3(240.1, 0.0, -305.0), PI * 0.5, 0.2)
	await frames(20)
	await shot("zip_1_marker")
	fg.press(2, &"snake")
	await frames(4)
	fg.up(2)
	await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.ZIP, 30)
	await frames(3)
	await shot("zip_2_pull")
	var n := 0
	while sn.mode == SnakeTraversal.Mode.ZIP and n < 6:
		await frames(9)
		n += 1
		if sn.mode == SnakeTraversal.Mode.ZIP:
			await shot("zip_3_%d_%s" % [n, sn.zip.phase])
	await frames(20)
	await shot("zip_4_end")
	print("W117 zip end mode ", sn.mode_name(), " reason ", sn.zip.end_reason, " floor ", p.is_on_floor(), " y ", p.global_position.y)
	# a tower with no ledge in reach: what the marker says
	SnakeZip.haul_max = 3.0
	await tp(Vector3(240.1, 0.0, -305.0), PI * 0.5, 0.2)
	await frames(20)
	await shot("zip_5_marker_no_ledge")
	SnakeZip.haul_max = 140.0


func _part_cue() -> void:
	await tp(Vector3(1200.0, 0.0, 0.0), 0.0, 0.05)       # far from every building: nothing to bite
	await frames(30)
	fg.press(2, &"snake")
	await frames(4)
	fg.up(2)
	await frames(5)
	await shot("cue_1_no_anchor")
	await frames(40)


func _part_energy() -> void:
	await tp(SPOT, -PI * 0.5, 0.6)
	fg.press(1, &"jump")
	await frames(3)
	fg.up(1)
	await until(func() -> bool: return fg.button(&"fly") != Vector2.INF, 60)
	fg.press(1, &"fly")
	await frames(4)
	fg.up(1)
	await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.FLY, 30)
	var fx := SnakeFx.current
	fg.press(2, &"snake")                    # BOOST burns the energy
	await until(func() -> bool: return fx.energy_warn >= 1 or sn.mode != SnakeTraversal.Mode.FLY, 400)
	await frames(3)
	await shot("energy_1_low")
	await until(func() -> bool: return fx.energy_warn >= 2 or sn.mode != SnakeTraversal.Mode.FLY, 400)
	await frames(3)
	await shot("energy_2_countdown")
	fg.up_all()


## Look fixture (art only, no control is tested here): a rope of snakes between two fixed points, seen close at the bite, in the middle and whole, taut and slack.
func _part_still() -> void:
	await tp(SPOT)
	var a := SPOT + Vector3(-3.0, 1.4, -2.0)
	var b := SPOT + Vector3(-9.0, 9.0, -8.0)
	var along := (b - a).normalized()
	var side := along.cross(Vector3.UP).normalized()
	for ten: float in [0.95, 0.2]:
		var t := SnakeTendril.fire(a, b, {"braid": 3, "travel": 0.15, "tension": ten, "thickness": 0.07, "host": p})
		t.user["keep"] = true
		await until(func() -> bool: return t.is_attached(), 30)
		await frames(12)
		var tag := "taut" if ten > 0.5 else "slack"
		print("W117 still ", tag, " state ", t.state, " len ", t.length(), " radius ", t.braid_radius, " pitch ", t.braid_pitch, " open ", t.braid_open, " instances ", SnakeTendrilPool.current.instances)
		await close("still_%s_1_bite" % tag, b - along * 0.3 + side * 1.9, b - along * 0.5)
		await close("still_%s_1b_bite_from_below" % tag, b - along * 2.4 + side * 0.9 + Vector3(0.0, 0.4, 0.0), b - along * 0.3)
		await close("still_%s_1c_bite_far" % tag, b - along * 1.0 + side * 5.0, b - along * 1.0)
		await close("still_%s_2_middle" % tag, (a + b) * 0.5 + side * 2.2, (a + b) * 0.5)
		await close("still_%s_3_whole" % tag, (a + b) * 0.5 + side * 9.0, (a + b) * 0.5)
		t.retract(0.5)
		await frames(5)
		await close("still_%s_4_unwinding" % tag, (a + b) * 0.5 + side * 9.0, (a + b) * 0.5)
		await until(func() -> bool: return not t.is_alive(), 40)
