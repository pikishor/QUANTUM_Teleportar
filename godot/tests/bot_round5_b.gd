extends RefCounted
## Render bot of the round 5 presentation fixes: the camera next to a bus / a car, a health pickup beside the lens, and the lamp cones at MED, from the real game camera with the touch HUD.
##   R5_OUT=<dir> BOT_RES=2400x1080 QUALITY=1 BOT_USER_ARGS=--touch BOT_FASTEXIT=1 tools/bot.sh res://tests/bot_round5_b.gd /tmp/x 100000 1
## Frames: <dir>/<nn>_<name>.png

var _out := ""
var _i := 0
var _wait := 0
var _hud: Hud
var _p: Player
var _stage := 0
var _poses: Array = [&"bus_back", &"car_side", &"pickup", &"lamps", &"lamps2"]
var _bus: Vehicle
var _car: Vehicle


func _init() -> void:
	_out = OS.get_environment("R5_OUT")


func step(_t: float, _dt: float) -> bool:
	if _hud == null:
		var tree := Engine.get_main_loop() as SceneTree
		_hud = tree.get_first_node_in_group(&"hud") as Hud
		_p = Game.player as Player
		if _hud == null or _p == null or not (Game.missions is Missions):
			return false
		for n in tree.root.find_children("*", "AutoQuality", true, false):
			(n as AutoQuality).enabled = false
		DirAccess.make_dir_recursive_absolute(_out)
		_hud.touch.controls_on = true
		(Game.enemies as EnemyManager).clear()
		var enc := Encounters.current
		if enc != null:
			enc.enabled = false
		_p.invuln = 1.0e6
		_begin()
		return false
	if _wait > 0:
		_wait -= 1
		return false
	_hud.get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [_out, _i, _poses[_i]])
	print("R5 shot ", _poses[_i])
	_i += 1
	if _i >= _poses.size():
		_hud.get_tree().quit()
		return true
	_begin()
	return false


func _begin() -> void:
	Game.state = &"play"
	var vm := Game.vehicles as VehicleManager
	var spot := Vector3(-30.0, 0.0, 4.0 - 60.0 * float(mini(_i, 2)))
	_p.teleport_to(spot)
	_p.camera_rig.reset_view(0.0, 0.0)
	_wait = 40
	match _poses[_i]:
		&"bus_back":
			var g := _p.global_position
			var back := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, _p.camera_rig.yaw)
			_bus = vm.spawn_parked(&"bus", Vector3(g.x, 0.0, g.z) + back * 3.0, _p.camera_rig.yaw + PI * 0.5)
		&"car_side":
			var g2 := _p.global_position
			var back2 := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, _p.camera_rig.yaw)
			_car = vm.spawn_parked(&"sedan", Vector3(g2.x, 0.0, g2.z) + back2 * 2.2, _p.camera_rig.yaw)
		&"pickup":
			var m := Game.missions as Missions
			var g3 := _p.global_position
			var back3 := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, _p.camera_rig.yaw)
			m.drop(&"health", g3 + back3 * 2.6 + Vector3(1.0, 0.0, 0.0))
		&"lamps":
			(Game.missions as Missions).clear_pickups()
			_p.teleport_to(Vector3(0.0, 0.0, 30.0))
			_p.camera_rig.reset_view(0.4, 0.0)
		&"lamps2":
			_p.teleport_to(Vector3(40.0, 0.0, -30.0))
			_p.camera_rig.reset_view(-0.9, 0.05)
