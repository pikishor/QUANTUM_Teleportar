extends RefCounted
## WAVE 127 look bot (w127-tanks): a LINEUP of the twenty new military ground vehicles on EASTFIELD's runway (four per shot, three-quarter view) and the places where they wait
## (ARMY BASE, VEHICLE DEPOT, the three road CHECKPOINTS). The hero and the lineup are placed by code only (a look bot, not a check).
##   TK_OUT=<dir> TK_TAG=q0 TK_ONLY=lineup|places QUALITY=0 BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=1200 tools/bot.sh res://tests/bot_w127_tanks.gd /tmp/x 100000 1
var _started := false
var _done := false
var p: Player
var vm: VehicleManager
var out := ""
var tag := ""


func step(_t: float, _dt: float) -> bool:
	if _started:
		return _done
	var tree := Engine.get_main_loop() as SceneTree
	if tree.get_first_node_in_group(&"hud") == null or not is_instance_valid(Game.player):
		return false
	_started = true
	_run(tree)
	return false


func _pf(n: int) -> void:
	for i in n:
		await (Engine.get_main_loop() as SceneTree).physics_frame


func _shot(name: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, name, tag])


func _look(w: Vector3, lw: Vector3, pitch: float) -> void:
	var d := lw - w
	var yaw := atan2(-d.x, -d.z)
	p.teleport_to(w + Vector3(0.0, 0.3, 0.0))
	p.yaw = yaw
	p.camera_rig.reset_view(yaw, pitch)


func _place(name: String, at: Vector3, look: Vector3, pitch := -0.15, wait := 420) -> void:
	_look(at, look, pitch)
	vm._spawn_t = 0.0
	await _pf(wait)
	await _shot(name)


func _run(_tree: SceneTree) -> void:
	out = OS.get_environment("TK_OUT")
	tag = OS.get_environment("TK_TAG")
	var only := OS.get_environment("TK_ONLY")
	DirAccess.make_dir_recursive_absolute(out)
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	Game.state = &"play"
	TestMode.god = true
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	await _pf(30)
	DemoMenu.set_time(float(OS.get_environment("TK_HOUR")) if OS.get_environment("TK_HOUR") != "" else 13.0)
	TestMode.set_weather("CLEAR")
	if only == "" or only == "lineup":
		# the lineup on the runway: kinds in table order, 16 m apart along the runway axis, nose to the camera side (east, local +x)
		var n := TankRoster.NEW.size()
		for g in range(int(OS.get_environment("TK_FROM")) if OS.get_environment("TK_FROM") != "" else 0, n, 2):
			vm._reset_all()
			await _pf(4)
			var mid := Vector3(1255.0, 0.0, -800.0)
			for j in 2:
				if g + j >= n:
					break
				var k: StringName = TankRoster.NEW[g + j]
				var lp := mid + Vector3(0.0, 0.0, (float(j) - 0.5) * 13.0)
				var w := Airport.to_world(lp)
				w.y = TerrainHeight.height_at(w.x, w.z)
				vm._fixed_n += 1
				var v := vm.spawn_parked(k, w, Airport.heading_world(-PI * 0.4))
				if v != null:
					v.set_meta(&"called", true)
					v.set_meta(&"hold", true)
					v.update_lod(0.0)
				vm._count_fixed()
			var cam := Airport.to_world(mid + Vector3(15.0, 0.0, 6.0))
			_look(cam, Airport.to_world(mid + Vector3(0.0, 1.5, 0.0)), -0.12)
			p.visible = false                                                          # (a look bot: the hero would stand in front of the lineup)
			await _pf(90)
			await _shot("lineup_%d" % (g / 2))
		vm._reset_all()
		await _pf(4)
	p.visible = true
	if only == "base":
		var b2 := Airport.to_world(TankRoster.BASE_LOCAL + Vector3(0.0, 0.0, 40.0))
		await _place("army_base", Airport.to_world(Vector3(1340.0, 0.0, -722.0)), b2 + Vector3(0.0, 1.0, 0.0), -0.12)
	if only == "" or only == "places":
		var base := Airport.to_world(TankRoster.BASE_LOCAL + Vector3(0.0, 0.0, 40.0))
		await _place("army_base", Airport.to_world(Vector3(1340.0, 0.0, -722.0)), base + Vector3(0.0, 1.0, 0.0), -0.12)
		var dep := TankRoster.DEPOT + Vector3(TankRoster.DEPOT_DX * 3.0, Harbour.QUAY_Y, 0.0)
		await _place("depot", dep + Vector3(-10.0, 0.0, -34.0), dep + Vector3(0.0, 1.0, 0.0))
		for s: Dictionary in TankRoster.sites():
			if String(s["id"]).begins_with("checkpoint"):
				var c: Vector3 = s["pos"]
				var dir := Vector3.FORWARD
				for cp: Dictionary in TankRoster.CHECKPOINTS:
					if cp["id"] == s["id"]:
						var spot := TankRoster.road_spot(String(cp["road"]), float(cp["at"]))
						var d2: Vector2 = spot["dir"]
						dir = Vector3(d2.x, 0.0, d2.y)
				await _place(String(s["id"]), c - dir * 30.0 + Vector3(dir.z, 0.0, -dir.x) * 8.0, c + Vector3(0.0, 1.0, 0.0))
	_done = true
