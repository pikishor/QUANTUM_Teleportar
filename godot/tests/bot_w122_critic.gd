extends RefCounted
## w122-critic look bot: the real game, phone HUD, Game.force_touch, reward cards on. Start spots by teleport (setup); every walk in is the left thumb on the stick, every turn the right thumb.
## Per building: outside view of the door, walk in by stick, inside view, inside view back toward the street windows. Shops: front, walk in, inside, look out, BUY by finger.
##   W122_OUT=<dir> BOT_RES=1200x540 BOT_USER_ARGS=--touch ENGINE_ARGS="--fixed-fps 30" QUALITY=1 BOT_TIMEOUT=900 tools/bot.sh res://tests/bot_w122_critic.gd /tmp/x 100000 1
const Fingers := preload("res://tests/w116_fingers.gd")
var _started := false
var _done := false
var tree: SceneTree
var p: Player
var fg: Fingers
var out := ""


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


func shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png("%s/%s.png" % [out, nm])
	print("CRIT shot ", nm, " pos ", p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), " fps ", Engine.get_frames_per_second(), " tower ", TowerFloors.open_lot, " shop ", ShopFronts.open_lot, " ctx ", fg.button_label(&"interact"))


func place(pos: Vector3, look_at: Vector3, pitch := -0.08) -> void:
	fg.up_all()
	var yaw := atan2(-(look_at.x - pos.x), -(look_at.z - pos.z))
	p.teleport_to(pos)
	p.velocity = Vector3.ZERO
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	await frames(45)


func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func go(q: Vector3, limit_frames: int, arrive := 0.7) -> bool:
	var pushing := false
	for i in limit_frames:
		var gp := p.global_position
		if flat(gp, q) < arrive:
			break
		var d := q - gp
		var err := wrapf(atan2(-d.x, -d.z) - p.camera_rig.yaw, -PI, PI)
		if absf(err) > 0.3:
			if pushing:
				fg.stick(Vector2.ZERO)
				pushing = false
			fg.look(-err * 160.0, 0.0, 4)
			await frames(2)
			continue
		if not pushing:
			fg.stick(Vector2(0.0, -0.7))
			pushing = true
		await frames(1)
	fg.stick(Vector2.ZERO)
	await frames(3)
	return flat(p.global_position, q) < arrive


func turn_to(q: Vector3) -> void:
	for i in 6:
		var d := q - p.global_position
		var err := wrapf(atan2(-d.x, -d.z) - p.camera_rig.yaw, -PI, PI)
		if absf(err) < 0.1:
			break
		fg.look(-err * 160.0, 0.0, 4)
		await frames(3)
	await frames(20)


func _run() -> void:
	out = OS.get_environment("W122_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	Game.force_touch = true
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	fg = Fingers.new(tree.root)
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	var city = Game.world
	if city.get(&"day_night") != null:
		city.day_night.set_hour(float(OS.get_environment("CRIT_HOUR")) if OS.get_environment("CRIT_HOUR") != "" else 17.0)
	var tf := TowerFloors.instance
	var only := OS.get_environment("CRIT_ONLY")
	var seen := {}
	var picks := [[&"office", Game.SPAWN], [&"apartment", Game.SPAWN], [&"hotel", Game.SPAWN], [&"house", Game.SPAWN], [&"house", Game.SPAWN + Vector3(150, 0, 80)], [&"office", Game.SPAWN + Vector3(-160, 0, -120)]]
	var bi := 0
	for pk in picks:
		bi += 1
		if only != "" and not only.contains("b"):
			break
		var kind: StringName = pk[0]
		var tw := tf.nearest(pk[1], 0.0 if kind == &"house" else TowerFloors.MIN_H, kind)
		if tw.is_empty():
			print("CRIT no ", kind)
			continue
		var li: int = (tw["lot"] as CityLayout.Lot).index
		if seen.has(li):
			print("CRIT dup ", kind)
		seen[li] = true
		var lot: CityLayout.Lot = tw["lot"]
		print("CRIT building %d %s lot %d size %.0fx%.0fx%.0f" % [bi, kind, li, lot.w, lot.d, lot.h])
		var outside := TowerFloors.door_pos(tw, 7.0)
		await place(outside, TowerFloors.door_pos(tw, -3.0) + Vector3(0, 2, 0), 0.05)
		await shot("b%d_%s_a_out" % [bi, kind])
		var ok := await go(TowerFloors.door_pos(tw, -3.0), 400)
		print("CRIT walk in ", kind, " ok ", ok, " inside ", TowerFloors.inside(p.global_position))
		await turn_to(TowerFloors.door_pos(tw, -12.0))
		await shot("b%d_%s_b_in" % [bi, kind])
		await turn_to(TowerFloors.door_pos(tw, 10.0) + Vector3(0, 2, 0))
		await shot("b%d_%s_c_back" % [bi, kind])
		var iu := TowerFloors.inner_u(tw)
		var lv := TowerFloors.levels_of(lot)
		if lv.size() > 1:
			await place(TowerFloors.at(tw, iu * 0.5, TowerFloors.SHAFT_W + 1.4, lv[1] + 0.05), TowerFloors.at(tw, iu * 0.5, TowerFloors.inner_v(tw), lv[1] + 1.0), -0.1)
			await shot("b%d_%s_d_floor1" % [bi, kind])
	var sf := ShopFronts.instance
	var n_shop := 0
	if sf != null and (only == "" or only.contains("s")):
		for kind: StringName in [&"food", &"clothes", &"guns", &"motors"]:
			var s: Dictionary = sf.nearest_of(kind, Game.SPAWN)
			if s.is_empty():
				print("CRIT no shop ", kind)
				continue
			n_shop += 1
			var n: Vector3 = s["normal"]
			var w: Vector3 = s["wall"]
			await place(w + n * 7.0 + (s["along"] as Vector3) * 2.0, w + Vector3(0, 1.5, 0), -0.02)
			await shot("s%d_%s_a_front" % [n_shop, kind])
			var ok1 := await go(w + n * 1.0, 300)
			var ok2 := await go(w - n * 1.4, 200)
			var ok3 := await go(sf.buy_spot(), 300, 0.5)
			print("CRIT shop walk ", kind, " ", ok1, ok2, ok3, " ctx ", fg.button_label(&"interact"))
			await turn_to(w - n * 6.0)
			await shot("s%d_%s_b_in" % [n_shop, kind])
			await turn_to(w + n * 8.0 + Vector3(0, 1.4, 0))
			await shot("s%d_%s_c_out" % [n_shop, kind])
			await turn_to(sf.buy_spot() - n * 3.0)
			if fg.button_label(&"interact") == "BUY":
				var c0 := (Game.progress as Progress).credits
				(Game.progress as Progress).credits = 20000
				var bp := fg.button(&"interact")
				fg.down(8, bp)
				await frames(3)
				fg.up(8)
				await frames(20)
				await shot("s%d_%s_d_buy" % [n_shop, kind])
				var vs := InteriorGameplay.instance.vendor_screen
				if vs.is_open:
					for i in vs.rows.size():
						if vs.rows[i]["state"] == "buy":
							fg.down(8, vs.rects[i].get_center())
							await frames(3)
							fg.up(8)
							await frames(20)
							print("CRIT bought ", vs.rows[i]["id"], " credits ", (Game.progress as Progress).credits)
							break
					await shot("s%d_%s_e_bought" % [n_shop, kind])
					fg.down(8, vs.close_rect.get_center())
					await frames(3)
					fg.up(8)
					await frames(10)
				print("CRIT vendor open after close ", vs.is_open, " c0 ", c0)
	_done = true
