extends RefCounted
## Look-dev bot for the traffic (cars in the street, on the highways, parked along the kerbs) in the REAL game camera: tools/bot.sh res://tests/bot_traffic.gd OUT EVERY COUNT
##   QUALITY=0|1|2 picks the tier, BOT_RES=2400x1080 the phone resolution, BOT_USER_ARGS="--touch" draws the phone HUD.
## env: OUT_VIEWS  semicolon list, one per shot slot:
##        "street:x,z,yaw[,dist]"            the hero on the city street at (x, z), the game camera looking along yaw (radians, 0 = -Z north), optional camera distance
##        "road:i,s,yaw_off[,dist]"          the hero beside road i (TerrainRoads index: 0 PASS ROAD, 1 DESERT ROAD, 2 COAST ROAD, 3 FOREST ROAD ...) at `s` metres from its start, looking along the road + yaw_off
##        "site:id[,yaw_off[,dist]]"         the hero at an outskirts site (village, farm ...)
##      OUT_HOUR (default 12), OUT_WARM (seconds of traffic simulated before the first shot of each view, default 14), OUT_HUD=0 hides the HUD layer.
var _views: Array[String] = []
var _i := 0
var _f := 0
var _hud: CanvasItem = null
var _warmed := -1


func _init() -> void:
	for s in OS.get_environment("OUT_VIEWS").split(";", false):
		_views.append(s.strip_edges())


func step(_t: float, _d: float) -> bool:
	var p := Game.player as Player
	if p == null:
		return false
	var wait: int = int(Dev.get(&"_args").get("every", "20")) if Dev.get(&"_args") is Dictionary else 20
	if _f == 2:
		Game.state = &"play"
		p.max_hp = 1.0e6
		p.hp = p.max_hp
		if Game.enemies != null:
			(Game.enemies as EnemyManager).clear()
		if Encounters.current != null:
			Encounters.current.enabled = false
		var city := Game.world as City
		var hour := float(OS.get_environment("OUT_HOUR")) if OS.get_environment("OUT_HOUR") != "" else 12.0
		if city != null and city.day_night != null:
			city.day_night.frozen = true
			city.day_night.set_hour(hour)
		if OS.get_environment("OUT_HUD") == "0":
			_hud = Game.get_tree().root.find_child("Hud", true, false) as CanvasItem
			if _hud != null:
				_hud.visible = false
	if _f >= 3 and _i < _views.size():
		_apply(p, _views[_i], (_f - 3) % maxi(wait, 1))
	_f += 1
	if _f >= 3 and (_f - 3) % maxi(wait, 1) == 0 and _f > 3:
		_i += 1
	return _i >= _views.size()


func _settle(pos: Vector3) -> void:
	var city := Game.world as City
	if city == null:
		return
	if city.terrain != null:
		city.terrain.settle(pos)
	if city.vegetation != null:
		city.vegetation.settle(pos)
	if city.sites != null and city.sites.has_method(&"settle"):
		city.sites.call(&"settle", pos)


## Runs the traffic of the ambient city for `secs` game seconds around `pos` (the real game does this in _process; a software-GL bot renders at 2-5 fps).
func _warm(pos: Vector3, secs: float) -> void:
	var city := Game.world as City
	if city == null or city.ambient == null:
		return
	var amb: Node = city.ambient
	var n := int(secs / 0.1)
	var road: Object = amb.get(&"road_traffic")                           # null on the commit before the road traffic existed
	var parked: Object = amb.get(&"parked")
	for k in n:
		(amb.get(&"near_traffic") as NearTraffic).step(0.1, pos)
		if road != null:
			road.call(&"set_time", float(k) * 0.1)
			road.call(&"step", 0.1, pos)
		if parked != null:
			parked.call(&"step", 0.1, pos)
		var mgr := Game.vehicles as VehicleManager
		if mgr != null and k % 5 == 0:
			mgr._stream()
	if road != null and OS.get_environment("OUT_WAIT_CAR") != "0" and (absf(pos.x) > TerrainHeight.CITY_HALF - 100.0 or absf(pos.z) > TerrainHeight.CITY_HALF - 100.0):
		# a highway frame: run on until a road car is 14 - 46 m ahead of the camera (the traffic is sparse, a frame at a random moment often shows an empty road)
		var yaw: float = (Game.player as Player).camera_rig.yaw
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		for k in 600:
			var found := false
			for i in 64:
				if road != null and bool(road.call(&"car_alive", i)):
					var q: Vector3 = road.call(&"car_position", i)
					var d := Vector2(q.x - pos.x, q.z - pos.z)
					if d.length() > 14.0 and d.length() < 46.0 and d.normalized().dot(fwd) > 0.75:
						found = true
						break
			if found:
				break
			(amb.get(&"near_traffic") as NearTraffic).step(0.1, pos)
			road.call(&"step", 0.1, pos)
			if parked != null:
				parked.call(&"step", 0.1, pos)


func _apply(p: Player, v: String, k: int) -> void:
	var x := 0.0
	var z := 0.0
	var y := 0.0
	var yaw := 0.0
	var dist := -1.0
	if v.begins_with("street:"):
		var a := v.substr(7).split(",")
		x = float(a[0])
		z = float(a[1])
		yaw = float(a[2]) if a.size() > 2 else 0.0
		dist = float(a[3]) if a.size() > 3 else -1.0
	elif v.begins_with("road:"):
		var a2 := v.substr(5).split(",")
		var rd: Dictionary = TerrainRoads.roads()[int(a2[0])]
		var pts: PackedVector2Array = rd["pos"]
		var want := float(a2[1])
		var acc := 0.0
		var si := 0
		while si < pts.size() - 2 and acc + pts[si].distance_to(pts[si + 1]) < want:
			acc += pts[si].distance_to(pts[si + 1])
			si += 1
		var seg := (pts[si + 1] - pts[si])
		var tg := seg.normalized()
		var base_pt := pts[si] + tg * (want - acc)
		var right := Vector2(-tg.y, tg.x)
		x = base_pt.x + right.x * 9.0                              # on the verge, 9 m from the centre line
		z = base_pt.y + right.y * 9.0
		yaw = atan2(-tg.x, -tg.y) + (float(a2[2]) if a2.size() > 2 else 0.0)
		dist = float(a2[3]) if a2.size() > 3 else -1.0
	elif v.begins_with("site:"):
		var a3 := v.substr(5).split(",")
		var st := OutskirtsSites.by_id(StringName(a3[0]))
		if st.is_empty():
			return
		var front := OutskirtsSites.to_world(st, Vector3(0.0, 0.0, -30.0))
		x = front.x
		z = front.z
		yaw = float(st["yaw"]) + PI + (float(a3[1]) if a3.size() > 1 else 0.0)
		dist = float(a3[2]) if a3.size() > 2 else -1.0
	else:
		return
	if k == 0:
		var inside := absf(x) < TerrainHeight.CITY_HALF and absf(z) < TerrainHeight.CITY_HALF
		y = 0.0 if inside else TerrainHeight.height_at(x, z)
		var pos := Vector3(x, y + 0.8, z)
		p.camera_rig.cine_clear()
		p.global_position = pos
		p.velocity = Vector3.ZERO
		p.camera_rig.yaw = yaw
		_settle(pos)
		p.teleport_to(pos)
		p.camera_rig.yaw = yaw
		if dist > 0.0 and "distance" in p.camera_rig:
			p.camera_rig.set("distance", dist)
		var warm := float(OS.get_environment("OUT_WARM")) if OS.get_environment("OUT_WARM") != "" else 14.0
		_warm(pos, warm)
	if k == 2:
		var city2 := Game.world as City
		if city2 != null and city2.ambient != null:
			var nt := city2.ambient.get(&"near_traffic") as NearTraffic
			var rt: Object = city2.ambient.get(&"road_traffic")
			var pk: Object = city2.ambient.get(&"parked")
			print("TRAFFIC_BOT view '%s': near cars %d, road cars %s, parked cars %s, hero at (%.0f, %.0f)" % [v, nt.alive_count(), str(rt.call(&"alive_count")) if rt != null else "-", str(pk.call(&"alive_count")) if pk != null else "-", p.global_position.x, p.global_position.z])
