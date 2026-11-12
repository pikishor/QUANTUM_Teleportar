extends RefCounted
## Look-dev bot for the landscape (trees, undergrowth, shores, waterfalls, mountains, anchors) in the REAL game: tools/bot.sh res://tests/bot_landscape.gd OUT EVERY COUNT
##   QUALITY=0|1|2 picks the tier, BOT_RES=2400x1080 the phone aspect, BOT_USER_ARGS="--touch" draws the phone HUD (default: HUD hidden).
## env: LS_VIEWS  semicolon list, one per shot slot (EVERY = frames per view, COUNT = views):
##        "hero:x,z,yaw[,dist]"                the real hero on the ground at (x, z), the real game camera looking along yaw (radians, 0 = -Z north), optional camera distance
##        "road:NAME,s[,yaw_off[,dist]]"       the real hero at s metres along the named road, the real game camera looking along the road (yaw_off added)
##        "cam:px,ph,pz,tx,th,tz"              a free camera at (px, ground+ph, pz) looking at (tx, ground+th, tz)
##        "abs:px,py,pz,tx,ty,tz"              a free camera at absolute coordinates
##      LS_HOUR (default 12), LS_WEATHER clear|rain|snow (default clear), LS_HUD=1 keeps the HUD
var _views: Array[String] = []
var _i := 0
var _f := 0
var _hud: CanvasItem = null
var _wait := 20


func _init() -> void:
	for s in OS.get_environment("LS_VIEWS").split(";", false):
		_views.append(s.strip_edges())


func step(_t: float, _d: float) -> bool:
	var p := Game.player as Player
	if p == null:
		return false
	_wait = int(Dev.get(&"_args").get("every", "20")) if Dev.get(&"_args") is Dictionary else 20
	if _f == 2:
		Game.state = &"play"
		p.max_hp = 1.0e6
		p.hp = p.max_hp
		if Game.enemies != null:
			(Game.enemies as EnemyManager).clear()
		if Encounters.current != null:
			Encounters.current.enabled = false
		var city := Game.world as City
		if city != null and city.terrain != null and OS.get_environment("LS_DEBUG") == "1":
			var tm: ShaderMaterial = city.terrain._mat
			print("LS_DEBUG tex_k=", tm.get_shader_parameter(&"tex_k"), " layers=", tm.get_shader_parameter(&"layers"), " detail=", tm.get_shader_parameter(&"detail"), " quality=", Game.quality)
		var hour := float(OS.get_environment("LS_HOUR")) if OS.get_environment("LS_HOUR") != "" else 12.0
		if city != null and city.day_night != null:
			city.day_night.frozen = true
			city.day_night.set_hour(hour)
		for n in Game.world.get_tree().root.find_children("*", "Weather", true, false):
			var wx := OS.get_environment("LS_WEATHER")
			(n as Weather).set_state(StringName(wx) if wx in ["rain", "snow"] else &"clear", true)
		if OS.get_environment("LS_HUD") != "1":
			_hud = Game.get_tree().root.find_child("Hud", true, false) as CanvasItem
			if _hud != null:
				_hud.visible = false
	if _f >= 3 and _i < _views.size():
		_apply(p, _views[_i], (_f - 3) % maxi(_wait, 1))
	_f += 1
	if _f >= 3 and (_f - 3) % maxi(_wait, 1) == 0 and _f > 3:
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
	var ls = city.get_node_or_null("Landscape")
	if ls != null and ls.has_method(&"settle"):
		ls.call(&"settle", pos)


func _free_cam(p: Player, pos: Vector3, tgt: Vector3, k: int, fov := 70.0) -> void:
	if k == 0:
		p.global_position = Vector3(pos.x, TerrainHeight.height_at(pos.x, pos.z) + 1.0, pos.z)
		p.velocity = Vector3.ZERO
		_settle(pos)
	p.camera_rig.cine_set(Transform3D(Basis.IDENTITY, pos).looking_at(tgt, Vector3.UP), fov)


func _road_point(name: String, s: float) -> Array:
	for r: Dictionary in TerrainRoads.roads():
		if String(r["name"]) == name:
			var pos: PackedVector2Array = r["pos"]
			var i := clampi(int(s / TerrainRoads.STEP), 0, pos.size() - 2)
			var a := pos[i]
			var b := pos[i + 1]
			var d := (b - a).normalized()
			return [a, d]
	return []


func _apply(p: Player, v: String, k: int) -> void:
	if v.begins_with("abs:"):
		var a := v.substr(4).split(",")
		_free_cam(p, Vector3(float(a[0]), float(a[1]), float(a[2])), Vector3(float(a[3]), float(a[4]), float(a[5])), k)
		return
	if v.begins_with("cam:"):
		var a2 := v.substr(4).split(",")
		var pos := Vector3(float(a2[0]), 0.0, float(a2[2]))
		pos.y = TerrainHeight.height_at(pos.x, pos.z) + float(a2[1])
		var tgt := Vector3(float(a2[3]), 0.0, float(a2[5]))
		tgt.y = TerrainHeight.height_at(tgt.x, tgt.z) + float(a2[4])
		_free_cam(p, pos, tgt, k)
		return
	var x := 0.0
	var z := 0.0
	var yaw := 0.0
	var dist := -1.0
	if v.begins_with("road:"):
		var a4 := v.substr(5).split(",")
		var rp := _road_point(a4[0], float(a4[1]))
		if rp.is_empty():
			return
		var q: Vector2 = rp[0]
		var d: Vector2 = rp[1]
		x = q.x
		z = q.y
		yaw = atan2(-d.x, -d.y) + (float(a4[2]) if a4.size() > 2 else 0.0)
		dist = float(a4[3]) if a4.size() > 3 else -1.0
	elif v.begins_with("hero:"):
		var a5 := v.substr(5).split(",")
		x = float(a5[0])
		z = float(a5[1])
		yaw = float(a5[2]) if a5.size() > 2 else 0.0
		dist = float(a5[3]) if a5.size() > 3 else -1.0
	else:
		return
	if k == 0:
		var pos3 := Vector3(x, TerrainHeight.height_at(x, z) + 0.8, z)
		p.camera_rig.cine_clear()
		p.global_position = pos3
		p.velocity = Vector3.ZERO
		p.camera_rig.yaw = yaw
		_settle(pos3)
		p.teleport_to(pos3)
		p.camera_rig.yaw = yaw
		if dist > 0.0 and "distance" in p.camera_rig:
			p.camera_rig.set("distance", dist)
