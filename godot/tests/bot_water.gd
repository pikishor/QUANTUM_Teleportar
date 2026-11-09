extends RefCounted
## Look-dev bot for the water in the REAL game (tools/bot.sh res://tests/bot_water.gd OUT EVERY COUNT; QUALITY=0|1|2, BOT_RES=2400x1080).
## env: WATER_VIEWS  semicolon list, one per shot slot: "px,py,pz,tx,ty,tz" = free camera at p looking at t (hero parked under it),
##                   "hero:x,y,z[,yaw[,move]]" = the REAL hero placed there (y < 0 drops him into the water), the real game camera; move=1 holds forward
##      WATER_HOUR   hour of day (default 14), WATER_WEATHER clear|rain (default clear), WATER_FRAMES frames per view (default 24)
var _views: Array[String] = []
var _i := 0
var _f := 0
var _cam: Camera3D = null


func _init() -> void:
	for s in OS.get_environment("WATER_VIEWS").split(";", false):
		_views.append(s.strip_edges())


func step(_t: float, _d: float) -> bool:
	var p := Game.player as Player
	if p == null:
		return false
	var wait := int(OS.get_environment("WATER_FRAMES")) if OS.get_environment("WATER_FRAMES") != "" else 24
	if _f == 2:
		Game.state = &"play"
		p.max_hp = 1.0e6
		p.hp = p.max_hp
		if Game.enemies != null:
			(Game.enemies as EnemyManager).clear()
		if Encounters.current != null:
			Encounters.current.enabled = false
		var city := Game.world as City
		var hour := float(OS.get_environment("WATER_HOUR")) if OS.get_environment("WATER_HOUR") != "" else 14.0
		if city != null and city.day_night != null:
			city.day_night.frozen = true
			city.day_night.set_hour(hour)
		var wx := OS.get_environment("WATER_WEATHER")
		var weather := get_weather()
		if weather != null:
			weather.set_state(&"rain" if wx == "rain" else &"clear", true)
	if _f >= 3 and _i < _views.size():
		_apply(p, _views[_i], _f - 3)
	_f += 1
	if _f >= 3 + wait:
		_f = 3
		_i += 1
		Input.action_release(&"move_forward")
	return _i >= _views.size()


func get_weather() -> Node:
	var w := Game.world.get_node_or_null("../Atmosphere") if Game.world != null else null
	for n in Game.world.get_tree().root.find_children("*", "Weather", true, false) if Game.world != null else []:
		return n
	return w


func _apply(p: Player, v: String, k: int) -> void:
	if v.begins_with("hero:"):
		var a := v.substr(5).split(",")
		if k == 0:
			p.global_position = Vector3(float(a[0]), float(a[1]), float(a[2]))
			p.velocity = Vector3.ZERO
			if a.size() > 3:
				p.camera_rig.yaw = float(a[3])
			if _cam != null:
				_cam.current = false
			if a.size() > 4 and int(a[4]) == 1:
				Input.action_press(&"move_forward")
		return
	var a := v.split(",")
	if _cam == null:
		_cam = Camera3D.new()
		_cam.far = 9000.0
		_cam.near = 0.3
		_cam.fov = 70.0
		p.get_tree().root.add_child(_cam)
	var pos := Vector3(float(a[0]), float(a[1]), float(a[2]))
	_cam.global_position = pos
	_cam.look_at(Vector3(float(a[3]), float(a[4]), float(a[5])), Vector3.UP)
	_cam.current = true
	p.global_position = Vector3(pos.x, 0.0, pos.z)
