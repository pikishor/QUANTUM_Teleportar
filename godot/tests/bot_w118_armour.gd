extends RefCounted
## WAVE 118 look bot of THE ARMOUR YARD, the helipads and their map icons: the real game at phone aspect, the phone HUD, REAL FINGERS only (tests/w116_fingers.gd). One PNG per moment in W118_OUT.
##   W118_OUT=<dir> W118_PARTS=places,map,enter BOT_RES=1200x540 BOT_USER_ARGS=--touch ENGINE_ARGS="--fixed-fps 30" QUALITY=0 BOT_TIMEOUT=580 tools/bot.sh res://tests/bot_w118_armour.gd /tmp/x 100000 1
##   W118_SPOTS="x,z,yaw;x,z,yaw" replaces the spots of the `places` part.
const Fingers := preload("res://tests/w116_fingers.gd")
var _started := false
var _done := false
var tree: SceneTree
var root: Window
var fg: Fingers
var p: Player
var vm: VehicleManager
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


func until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("W118 shot ", name, " pos ", p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), " veh ", p.vehicle, " buttons ", fg.tc.visible_ids())


func tp(pos: Vector3, yaw := -PI * 0.5, pitch := -0.05) -> void:
	fg.up_all()
	await frames(2)
	p.snake.cancel()
	p.snake.reset()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await frames(45)


func tap(pos: Vector2) -> void:
	fg.down(7, pos)
	await frames(3)
	fg.up(7)
	await frames(3)


func tap_action(act: StringName) -> bool:
	var at := fg.button(act)
	if at == Vector2.INF:
		print("W118 no button ", act)
		return false
	await tap(at)
	return true


func _run() -> void:
	root = tree.root
	out = OS.get_environment("W118_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
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
	TestMode.god = true
	CrateReveal._quiet = 0
	var city := Game.world as City
	if city != null and city.day_night != null:
		city.day_night.frozen = true
		city.day_night.set_hour(13.0)
	var at := Game.atmosphere as Atmosphere
	if at != null and at.weather != null:
		at.weather.set_process(false)
		at.set_weather(0.0, 0.3, true)
	await frames(30)
	print("W118 setup touch ", Game.force_touch, " controls ", fg.tc != null and fg.tc.controls_on, " quality ", Game.quality)
	var parts := OS.get_environment("W118_PARTS")
	for part in (parts if parts != "" else "places,map").split(",", false):
		await call("_part_" + part)
	print("W118 DONE")
	_done = true


func _part_places() -> void:
	var spots := OS.get_environment("W118_SPOTS")
	if spots == "":
		spots = "-300,120,1.57;-320,40,3.14;122,25,1.57;105,50,0"
	var i := 0
	for s in spots.split(";", false):
		var a := s.split(",")
		await tp(Vector3(float(a[0]), 0.3, float(a[1])), float(a[2]))
		await frames(60)
		await shot("place_%d" % i)
		i += 1


func _part_map() -> void:
	await tp(Game.SPAWN + Vector3(0, 0.3, 0))
	await shot("map_0_hud")
	var mm := fg.tc._minimap_rect()
	await tap(mm.get_center())
	await frames(30)
	await shot("map_1_open")
	var ms := root.find_child("MapScreen", true, false) as MapScreen
	if ms != null and MapScreen.up:
		var z := ms.find_child("Zoom", true, false) as Button
		await tap(z.get_global_rect().get_center())
		await frames(20)
		await shot("map_2_zoom")
		var c := ms.find_child("Close", true, false) as Button
		await tap(c.get_global_rect().get_center())
	await frames(10)


func _part_call() -> void:
	await tp(Game.SPAWN + Vector3(0, 0.3, 0))
	if not fg.tc.more_open:
		await tap_action(&"more")
	await frames(6)
	await shot("call_0_more")
	await tap_action(&"garage_call")
	await frames(8)
	await shot("call_1_list")
	if CallIn.is_open():
		var b := CallIn.instance.find_child("Call_Tank", true, false) as Button
		await tap(b.get_global_rect().get_center())
		await frames(20)
		await shot("call_2_tank")
	if fg.tc.more_open:
		await tap_action(&"more")


func _part_enter() -> void:
	var yard := ArmourSites.YARD
	await tp(Vector3(yard.x - 8.0, 0.3, yard.z - 13.5), PI)
	await frames(60)
	await shot("enter_0_yard")
	fg.stick(Vector2(0, -1))
	await until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 240)
	fg.stick(Vector2.ZERO)
	await frames(4)
	await shot("enter_1_at_tank")
	await tap_action(&"interact")
	await frames(30)
	await shot("enter_2_in_tank")
	fg.stick(Vector2(0, -1))
	await frames(90)
	fg.press(6, &"fire")
	await frames(8)
	await shot("enter_3_fire")
	fg.up(6)
	fg.stick(Vector2.ZERO)
	await frames(60)
	await tap_action(&"interact")
	await frames(20)
	var pad := ArmourSites.PAD_EAST
	await tp(Vector3(pad.x + 2.6, 0.3, pad.z - 11.0), PI)
	await frames(60)
	fg.stick(Vector2(0, -1))
	await until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 240)
	fg.stick(Vector2.ZERO)
	await frames(4)
	await tap_action(&"interact")
	await frames(20)
	await shot("enter_4_in_heli")
	fg.press(1, &"jump")
	await frames(120)
	await shot("enter_5_heli_up")
	fg.up(1)
	await frames(10)


## Draw-call cost of the minimap's armour badges and of the places at the spawn: the same frame with the icons on and off (not the perf gate: one number for the builder).
func _part_cost() -> void:
	await tp(Game.SPAWN + Vector3(0, 0.3, 0))
	await frames(60)
	var vp := root.get_viewport()
	var on: Dictionary = PerfProbe.snapshot(vp)
	var mm := root.find_children("*", "Minimap", true, false)[0] as Minimap
	print("W118 cost ON  total_draws %d draws %d nodes %d armour_drawn %d sites built %d" % [on["total_draws"], on["draws"], on["nodes"], mm.armour_drawn, ArmourSites.instance.built_count()])
	ArmourSites.icons_on = false
	await frames(40)
	var off: Dictionary = PerfProbe.snapshot(vp)
	print("W118 cost OFF total_draws %d draws %d nodes %d armour_drawn %d" % [off["total_draws"], off["draws"], off["nodes"], mm.armour_drawn])
	ArmourSites.icons_on = true
	await frames(40)
	var on2: Dictionary = PerfProbe.snapshot(vp)
	print("W118 cost ON2 total_draws %d draws %d armour_drawn %d" % [on2["total_draws"], on2["draws"], mm.armour_drawn])
