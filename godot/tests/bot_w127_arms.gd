extends RefCounted
## WAVE 127 tank arms (w127-arms): frames to LOOK at, by fingers (tests/w116_fingers.gd) in the real main scene, on the open ground beside SOUTH FARM that tests/test_tank_arms_w127.gd
## uses: the battle tank's HUD (FIRE with its reload ring, the arm, ARMS, SHELL, SMOKE, the turret dial), a target tank, the ATGM seeker LOCKED, the smoke cloud, the howitzer's target
## marker 220 m out, a rocket salvo, an enemy crew firing at the hero, a burning tank, the board's tank cards in the ARMY YARD.
##   ARMS_OUT=<dir> ARMS_TAG=q0 QUALITY=0 BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=900 tools/bot.sh res://tests/bot_w127_arms.gd /tmp/x 100000 1
const Fingers := preload("res://tests/w116_fingers.gd")
const GROUND := Vector3(1490.0, 0.0, 1740.0)
const HDG := PI
var _started := false
var _done := false
var fg: Fingers
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


func _until(c: Callable, n: int) -> bool:
	for i in n:
		if c.call():
			return true
		await (Engine.get_main_loop() as SceneTree).physics_frame
	return c.call()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	(Engine.get_main_loop() as SceneTree).root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, name, tag])
	print("ARMS SHOT %s" % name)


func _tap(action: StringName) -> bool:
	if not fg.press(6, action):
		return false
	await _pf(4)
	fg.up(6)
	await _pf(4)
	return true


func _hold(action: StringName, n: int) -> void:
	if fg.press(2, action):
		await _pf(n)
		fg.up(2)


func _g(at: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, 400.0, at.z), Vector3(at.x, -50.0, at.z), Game.L_WORLD)
	var r := (Engine.get_main_loop() as SceneTree).root.get_world_3d().direct_space_state.intersect_ray(q)
	return r["position"] if not r.is_empty() else Vector3(at.x, TerrainHeight.height_at(at.x, at.z), at.z)


func _fp(along: float, across := 0.0) -> Vector3:
	return _g(GROUND + Vector3(-sin(HDG), 0.0, -cos(HDG)) * along + Vector3(cos(HDG), 0.0, -sin(HDG)) * across)


func _spawn(kind: StringName, at: Vector3, h: float) -> Vehicle:
	vm._fixed_n += 1
	var v := vm.spawn_parked(kind, at, h)
	if v != null:
		v.set_meta(&"hold", true)
		v.set_meta(&"air_target", true)
		v.global_position = _g(at)
	vm._count_fixed()
	return v


func _drop(v: Vehicle) -> void:
	if v == null or not is_instance_valid(v):
		return
	for m: StringName in [&"hold", &"air_target", &"aim_at", &"tank_target"]:
		if v.has_meta(m):
			v.remove_meta(m)
	if v.active and not v.driver_is_player:
		vm._release(v)
	vm._count_fixed()


func _enter(v: Vehicle) -> bool:
	var at := v.global_position + v.forward() * (float(v.spec["len"]) * 0.5 + 8.0)
	p.teleport_to(at + Vector3(0.0, 0.3, 0.0))
	var d := v.global_position - at
	p.yaw = atan2(-d.x, -d.z)
	p.camera_rig.reset_view(p.yaw, -0.1)
	await _pf(10)
	fg.stick(Vector2(0.0, -0.6))
	await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER" and v.edge_distance(p.global_position) < VehicleSpecs.ENTER_REACH - 0.6, 480)
	fg.stick(Vector2.ZERO)
	await _pf(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == v, 90)
	return p.vehicle == v


func _leave() -> void:
	if p.vehicle != null:
		await _tap(&"interact")
		await _pf(20)


## The camera behind the vehicle, looking where it points (the hero's view in a tank).
func _view(v: Vehicle, pitch := -0.08) -> void:
	p.camera_rig.reset_view(v.heading, pitch)
	await _pf(20)


func _run(tree: SceneTree) -> void:
	out = OS.get_environment("ARMS_OUT")
	if out == "":
		out = "/tmp"
	tag = OS.get_environment("ARMS_TAG")
	if tag == "":
		tag = "q%d" % Game.quality
	DirAccess.make_dir_recursive_absolute(out)
	Game.force_touch = true
	CrateReveal._quiet = 0
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	fg = Fingers.new(tree.root)
	TestMode.god = true
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	if is_instance_valid(Game.world) and Game.world.has_method(&"set_hour"):
		Game.world.call(&"set_hour", 11.0)
	TerrainHeight.warm()
	p.teleport_to(_fp(0.0) + Vector3(0.0, 0.5, 0.0))
	await _pf(60)
	# 1. the battle tank's HUD and a target tank 60 m ahead, side on
	var tk := _spawn(&"tank", _fp(0.0), HDG)
	if tk == null or not await _enter(tk):
		print("ARMS tank not boarded")
		_done = true
		tree.quit()
		return
	var tg := _spawn(&"tank", _fp(60.0), HDG + PI * 0.5)
	tg.max_hp = 50000.0
	tg.hp = tg.max_hp
	tk.set_meta(&"aim_at", tg.global_position + Vector3(0.0, 1.2, 0.0))
	await _view(tk)
	await _pf(40)
	await _shot("tank_hud")
	await _hold(&"fire", 8)
	await _pf(6)
	await _shot("tank_fire_reload")
	# 2. the ATGM seeker on a light tank 170 m out
	_drop(tg)
	await _tap(&"arms_next")
	await _tap(&"arms_next")
	var far := _spawn(&"ltank", _fp(170.0, 6.0), HDG)
	far.max_hp = 50000.0
	far.hp = far.max_hp
	tk.set_meta(&"aim_at", far.global_position + Vector3(0.0, 1.0, 0.0))
	await _pf(140)
	await _shot("atgm_locked")
	await _tap(&"aim")
	await _pf(50)
	await _shot("atgm_flight")
	# 3. smoke
	await _tap(&"flare")
	await _pf(70)
	await _shot("smoke")
	_drop(far)
	await _leave()
	_drop(tk)
	await _pf(200)                                                          # the smoke clears
	# 4. the howitzer's marker on armour 220 m out, then the shell, then the salvo
	var art := _spawn(&"artillery", _fp(-20.0), HDG)
	if art != null and await _enter(art):
		var t2 := _spawn(&"apc", _fp(200.0), HDG + 0.6)
		t2.set_meta(&"tank_target", true)
		art.set_meta(&"aim_at", _g(t2.global_position + Vector3(12.0, 0.0, 6.0)))
		await _view(art, -0.02)
		await _pf(60)
		await _shot("artillery_marker")
		await _hold(&"fire", 6)
		await _pf(100)
		await _shot("artillery_hit")
		await _tap(&"arms_next")
		var truck := _spawn(&"truck", _fp(110.0), HDG + PI * 0.5)
		art.set_meta(&"aim_at", truck.global_position + Vector3(0.0, 1.0, 0.0))
		await _pf(30)
		await _tap(&"aim")
		await _pf(26)
		await _shot("salvo")
		_drop(truck)
		_drop(t2)
		await _leave()
		_drop(art)
	# 5. an enemy crew engages the hero's tank; a burning tank
	var tk2 := _spawn(&"tank", _fp(-60.0), HDG)
	if tk2 != null and await _enter(tk2):
		tk2.max_hp = 50000.0
		tk2.hp = tk2.max_hp
		var foe := TankCrews.current.spawn(&"tank", _fp(60.0), HDG + PI, &"mission", {"hp": 5000.0}) if TankCrews.current != null else null
		await _view(tk2)
		var s0 := TankCrews.shots
		await _until(func() -> bool: return TankCrews.shots > s0, 900)
		await _pf(3)
		await _shot("enemy_fires")
		if foe != null:
			foe.hp = 600.0
			foe.max_hp = 2000.0
			_place_face(foe, tk2)
			tk2.set_meta(&"aim_at", foe.global_position + Vector3(0.0, 1.2, 0.0))
			await _pf(60)
			await _hold(&"fire", 8)
			await _pf(30)
			await _shot("enemy_hit")
		await _leave()
	# 6. the board's tank cards in the ARMY YARD
	p.teleport_to(ArmourSites.YARD + Vector3(0.0, 0.3, 14.0))
	await _pf(60)
	var board := MissionBoardScreen.board()
	board.world_offers = true
	board.generate()
	var hud := tree.get_first_node_in_group(&"hud") as Hud
	if hud != null:
		hud.open_board()
		await _pf(10)
		await _shot("board_tank")
		Game.state = &"play"
	_done = true
	tree.quit()


func _place_face(v: Vehicle, other: Vehicle) -> void:
	var d := other.global_position - v.global_position
	v.heading = atan2(d.x, d.z)                                            # its REAR to the hero: the round goes into the engine deck
	v.rotation.y = v.heading
