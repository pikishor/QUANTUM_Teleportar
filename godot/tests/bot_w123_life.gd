extends RefCounted
## w123-life look bot: the real game camera at (1) the bench nearest the spawn with somebody sitting on it, (2) the bus stop nearest the spawn with people waiting and a bus at the stop.
##   W123_OUT=<dir> BOT_RES=1200x540 QUALITY=0|1 tools/bot.sh res://tests/bot_w123_life.gd /tmp/x 1000 1
var _p: Player
var _out := ""
var _phase := 0
var _wait := 0


func _init() -> void:
	_out = OS.get_environment("W123_OUT")


func _nearest(list: Array[Vector3]) -> Vector3:
	var best := Vector3.INF
	for b: Vector3 in list:
		if absf(b.x) > CityLayout.HALF - 120.0:
			continue
		if best == Vector3.INF or Vector2(b.x - Game.SPAWN.x, b.z - Game.SPAWN.z).length() < Vector2(best.x - Game.SPAWN.x, best.z - Game.SPAWN.z).length():
			best = b
	return best


func step(_t: float, _dt: float) -> bool:
	if _p == null:
		_p = Game.player as Player
		if _p == null:
			return false
		for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
			(n as AutoQuality).enabled = false
		_p.max_hp = 1.0e6
		DirAccess.make_dir_recursive_absolute(_out)
		Game.state = &"play"
		if is_instance_valid(Game.enemies):
			TestMode.kill_all_enemies()
		TestMode.set_weather("CLEAR")
		(Game.world as City).day_night.set_hour(15.0)
		var b := _nearest(StreetLife.benches)
		var face := signf(b.y)
		_p.teleport_to(Vector3(b.x + 2.5, 0.1, b.z + face * 4.0))
		_p.camera_rig.reset_view(atan2(-(b.x - (b.x + 2.5)), -(b.z - (b.z + face * 4.0))), -0.12)
		_wait = 120
		return false
	if _wait > 0:
		_wait -= 1
		_p.hp = _p.max_hp
		if _phase == 1 and _wait == 200:
			_place_bus()
		return false
	match _phase:
		0:
			_shot("bench")
			var sp := _stop()
			var c := CityLayout.road_center(roundi((sp.z + CityLayout.HALF) / CityLayout.PITCH))
			var side := signf(sp.z - c)
			var eye := Vector3(sp.x + 9.0, 0.1, c - side * 6.0)
			_p.teleport_to(eye)
			_p.camera_rig.reset_view(atan2(-(sp.x - eye.x), -(sp.z - eye.z)), -0.1)
			_phase = 1
			_wait = 260
		1:
			_shot("busstop")
			_phase = 2
			_wait = 200
		2:
			_shot("bus_gone")
			return true
	return false


func _stop() -> Vector3:
	var best := Vector3.INF
	for sp: Vector3 in StreetLife.bus_stops:
		var c := CityLayout.road_center(roundi((sp.z + CityLayout.HALF) / CityLayout.PITCH))
		if absf(absf(sp.z - c) - 11.8) > 0.2 or absf(sp.x) > CityLayout.HALF - 120.0:
			continue
		if best == Vector3.INF or sp.distance_to(Game.SPAWN) < best.distance_to(Game.SPAWN):
			best = sp
	return best


func _place_bus() -> void:
	var nt := NearTraffic.instance
	var sp := _stop()
	var c := CityLayout.road_center(roundi((sp.z + CityLayout.HALF) / CityLayout.PITCH))
	var dir := 1
	var line := c + VehicleSpecs.lane_offset(0, dir, CityLayout.LANE)
	if absf(line - sp.z) > StreetLife.BUS_SIDE:
		dir = -1
		line = c + VehicleSpecs.lane_offset(0, dir, CityLayout.LANE)
	nt.place(0, 0, dir, line, sp.x - dir * 30.0, NearTraffic.BUS_KIND, 10.0, 1)


func _shot(name: String) -> void:
	var img := _p.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])
	print("W123 shot %s: sitting %d waiting %d boarded %d bus_dwells %d" % [name, (Game.world as City).ambient.life.sitting_count(), (Game.world as City).ambient.life.waiting_near(_p.global_position, 30.0), (Game.world as City).ambient.life.boarded, StreetLife.bus_dwells])
