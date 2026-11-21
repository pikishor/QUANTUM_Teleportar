extends RefCounted
## WAVE 117 CRITIC STRIPS: one phone session, fingers only (InputEventScreenTouch through Input.parse_input_event). Title -> play by a finger, then one scene, one PNG every CRB_EVERY frames.
##   CRB_SCENE=hold|jump|wall|ziproof|zipwall|fly|noanchor CRB_OUT=<dir> BOT_RES=1200x540 BOT_USER_ARGS="--touch" ENGINE_ARGS="--fixed-fps 30" BOT_TIMEOUT=600 QUALITY=0 tools/bot.sh res://tests/bot_w117_critic.gd /tmp/x 100000 1
## CRB_STREET=0|1|2 picks the street of the hold scene. CRB_OLD=1 switches the critic's fixes off (the frames before).
const Fingers := preload("res://tests/w116_fingers.gd")
const STREETS: Array = [[Vector3(-30.0, 0.0, 4.0), -PI * 0.5], [Vector3(-30.0, 0.0, 4.0), PI * 0.5], [Vector3(240.1, 0.0, -305.0), 0.0]]
var _started := false
var _done := false
var root: Window
var tree: SceneTree
var fg: Fingers
var hud: Node
var out := ""
var p: Player
var sn: SnakeTraversal
var n := 0
var every := 6


func step(_t: float, _dt: float) -> bool:
	if _started:
		return _done
	tree = Engine.get_main_loop() as SceneTree
	if tree.get_first_node_in_group(&"hud") == null or not is_instance_valid(Game.player):
		return false
	_started = true
	_run()
	return false


func frames(k: int) -> void:
	for i in k:
		await tree.process_frame


func menu_btn(id: StringName) -> Vector2:
	hud.call(&"_ensure_layout")
	for b: Dictionary in hud.get("buttons"):
		if b["id"] == id:
			return (b["rect"] as Rect2).get_center()
	return Vector2.INF


func tap_at(pos: Vector2, finger := 5) -> void:
	fg.down(finger, pos)
	await frames(3)
	fg.up(finger)
	await frames(3)


func tap(action: StringName, finger: int, hold := 3) -> void:
	if fg.press(finger, action):
		await frames(hold)
		fg.up(finger)


func shot(tag: String) -> void:
	n += 1
	print("CRB %02d %s mode %s/%s/%s ang %.2f rope %.1f v %.1f (vy %.1f) y %.1f label %s" % [n, tag, sn.mode_name(), sn.swing.phase, sn.zip.phase, sn.swing.rope_angle, sn.swing.rope, p.velocity.length(), p.velocity.y, p.global_position.y, fg.button_label(&"snake")])
	if out == "":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, tag])


## `k` frames, a picture every `every`.
func roll(k: int, tag: String) -> void:
	for i in k:
		await frames(1)
		if i % every == every - 1:
			await shot(tag)


func tp(pos: Vector3, yaw: float, pitch: float) -> void:
	fg.up_all()
	await frames(2)
	sn.cancel()
	sn.reset()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	await frames(40)


func _run() -> void:
	root = tree.root
	out = OS.get_environment("CRB_OUT")
	if out != "":
		DirAccess.make_dir_recursive_absolute(out)
	if OS.get_environment("CRB_EVERY") != "":
		every = maxi(1, int(OS.get_environment("CRB_EVERY")))
	for q in root.find_children("*", "AutoQuality", true, false):
		(q as AutoQuality).enabled = false
	Game.force_touch = true
	CrateReveal._quiet = 0
	Sfx.muted = true
	if OS.get_environment("CRB_OLD") == "1" and ClassDB.class_exists(&"Object"):
		_old()
	hud = tree.get_first_node_in_group(&"hud")
	fg = Fingers.new(root)
	await frames(20)
	var start_id: StringName = &"deploy" if menu_btn(&"deploy") != Vector2.INF else &"continue"
	print("CRB state at start ", Game.state, " menu button ", menu_btn(start_id))
	if Game.state != &"play" and menu_btn(start_id) != Vector2.INF:
		await tap_at(menu_btn(start_id))
	var t0 := Time.get_ticks_msec()
	while Game.state != &"play" and Time.get_ticks_msec() - t0 < 30000:
		await frames(5)
		if Game.state == &"cutscene":
			await tap_at(fg.vp() * 0.5)
	p = Game.player as Player
	sn = p.snake
	fg = Fingers.new(root)
	p.max_hp = 1.0e6
	p.hp = 1.0e6
	TestMode.god = true
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	var scene := OS.get_environment("CRB_SCENE")
	var st: Array = STREETS[int(OS.get_environment("CRB_STREET"))] if OS.get_environment("CRB_STREET") != "" else STREETS[0]
	match scene:
		"hold":
			await tp(st[0], st[1], 0.2)
			await tap(&"jump", 2)
			await frames(5)
			fg.press(1, &"snake")
			await roll(int(OS.get_environment("CRB_FRAMES")) if OS.get_environment("CRB_FRAMES") != "" else 300, "hold")
			fg.up_all()
			await roll(110, "letgo")
		"jump":
			await tp(st[0], st[1], 0.2)
			await tap(&"jump", 2)
			await frames(5)
			fg.press(1, &"snake")
			every = 3
			for i in 200:
				await frames(1)
				if i % 6 == 5:
					await shot("swing")
				if sn.swing.is_hanging() and sn.swing.rope_angle > 0.1:
					break
			fg.press(2, &"jump")
			await frames(2)
			await shot("jumped")
			fg.up(2)
			await roll(60, "after")
			fg.up_all()
			await roll(30, "after")
		"wall":
			await tp(st[0], 0.0, 0.35)
			await tap(&"jump", 2)
			await frames(5)
			fg.press(1, &"snake")
			await roll(150, "wall")
			fg.up_all()
			await roll(30, "after")
		"ziproof", "zipwall":
			await tp(Vector3(240.1, 0.0, -305.0), PI * 0.5, 0.5 if scene == "ziproof" else 0.2)
			await frames(20)
			await shot("before")
			every = 2
			fg.press(1, &"snake")
			await frames(3)
			fg.up(1)
			await roll(100 if scene == "zipwall" else 50, "zip")
			every = 10
			await roll(30, "after")
		"fly":
			await tp(st[0], st[1], 0.2)
			await shot("ground")
			await tap(&"jump", 2)
			await frames(8)
			await shot("air")
			await tap(&"fly", 4)
			every = 10
			await roll(20, "takeoff")
			fg.stick(Vector2(0.0, -1.0))
			await roll(80, "fly")
			fg.stick(Vector2.ZERO)
			await tap(&"fly", 4)
			every = 8
			await roll(150, "land")
		"noanchor":
			await tp(Vector3(1200.0, 0.0, 0.0), 0.0, 0.05)
			await shot("ground")
			await tap(&"jump", 2)
			await frames(6)
			fg.press(1, &"snake")
			every = 5
			await roll(60, "held")
			fg.up_all()
			await roll(40, "after")
	fg.up_all()
	print("CRB END")
	_done = true
	tree.quit()


## The critic's fixes off (the wave 117 builders' state), for the frames before.
func _old() -> void:
	for pair: Array in [["SwingMotion", "critic_fix"], ["SnakeZip", "critic_fix"]]:
		pass
