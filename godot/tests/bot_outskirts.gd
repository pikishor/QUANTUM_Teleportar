extends RefCounted
## Look-dev bot for the outskirts (vegetation, sites, mountain weather) in the REAL game: tools/bot.sh res://tests/bot_outskirts.gd OUT EVERY COUNT   (EVERY = frames per view, COUNT = views)
##   QUALITY=0|1|2 picks the tier, BOT_RES=2400x1080 the resolution, BOT_USER_ARGS="--touch" draws the phone HUD.
## env: OUT_VIEWS  semicolon list, one per shot slot:
##        "hero:x,z,yaw[,dist]"            the real hero on the ground at (x, z), the real game camera looking along yaw (radians; 0 = -Z north), optional camera distance
##        "site:id[,yaw_off[,dist[,h]]]"   the real hero at the site's entrance, the camera looking at the site (yaw_off added to the site's yaw, camera dist metres, height h above ground)
##        "cam:px,ph,pz,tx,th,tz"          a free camera at (px, ground+ph, pz) looking at (tx, ground+th, tz)
##      OUT_HOUR (default 12), OUT_WEATHER clear|rain|snow (default clear), OUT_HUD=0 hides the HUD layer
var _views: Array[String] = []
var _i := 0
var _f := 0
var _cam: Camera3D = null
var _hud: CanvasItem = null


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
		for n in Game.world.get_tree().root.find_children("*", "Weather", true, false):
			var wx := OS.get_environment("OUT_WEATHER")
			(n as Weather).set_state(StringName(wx) if wx in ["rain", "snow"] else &"clear", true)
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


func _apply(p: Player, v: String, k: int) -> void:
	if v.begins_with("incave:"):                         # "incave:i[,yaw]": the real hero in chamber i of the cave (0 = the first), the real game camera
		var a5 := v.substr(7).split(",")
		var city := Game.world as City
		if city == null or city.sites == null:
			return
		if k == 0:
			p.camera_rig.cine_clear()
			(city.sites as OutskirtsWorld).ensure_site(&"cave")
			var cv: CaveSystem = (city.sites as OutskirtsWorld).cave
			if cv != null:
				if not cv.inside():
					cv.enter(p)
				var ch := CaveSystem.CHAMBERS[clampi(int(a5[0]), 0, CaveSystem.CHAMBERS.size() - 1)]
				p.teleport_to(cv.origin() + Vector3(ch.x, 0.6, ch.y - 5.0))
				p.camera_rig.yaw = float(a5[1]) if a5.size() > 1 else PI
		return
	if v.begins_with("sc:"):                             # "sc:id,lx,ly,lz[,tx,ty,tz]": a free camera in the site's local frame (ly above the pad), looking at (tx, ty, tz) (default the pad centre, 4 m up)
		var a4 := v.substr(3).split(",")
		var st := OutskirtsSites.by_id(StringName(a4[0]))
		if st.is_empty():
			return
		var cpos := OutskirtsSites.to_world(st, Vector3(float(a4[1]), float(a4[2]), float(a4[3])))
		var look := Vector3(float(a4[4]), float(a4[5]), float(a4[6])) if a4.size() > 6 else Vector3(0.0, 4.0, 0.0)
		var tpos := OutskirtsSites.to_world(st, look)
		if k == 0:
			var hp := OutskirtsSites.to_world(st, Vector3(0.0, 0.0, -float(st["r"]) - 6.0))
			p.global_position = Vector3(hp.x, TerrainHeight.height_at(hp.x, hp.z) + 1.0, hp.z)
			p.velocity = Vector3.ZERO
			_settle(cpos)
		p.camera_rig.cine_set(Transform3D(Basis.IDENTITY, cpos).looking_at(tpos, Vector3.UP), 68.0)
		return
	if v.begins_with("cam:"):
		var a := v.substr(4).split(",")
		var pos := Vector3(float(a[0]), 0.0, float(a[2]))
		pos.y = TerrainHeight.height_at(pos.x, pos.z) + float(a[1])
		var tgt := Vector3(float(a[3]), 0.0, float(a[5]))
		tgt.y = TerrainHeight.height_at(tgt.x, tgt.z) + float(a[4])
		if k == 0:
			p.global_position = Vector3(pos.x, TerrainHeight.height_at(pos.x, pos.z) + 1.0, pos.z)
			p.velocity = Vector3.ZERO
			_settle(pos)
		p.camera_rig.cine_set(Transform3D(Basis.IDENTITY, pos).looking_at(tgt, Vector3.UP), 70.0)
		return
	var x := 0.0
	var z := 0.0
	var yaw := 0.0
	var dist := -1.0
	var lift := 0.0
	if v.begins_with("hero:"):
		var a2 := v.substr(5).split(",")
		x = float(a2[0])
		z = float(a2[1])
		yaw = float(a2[2]) if a2.size() > 2 else 0.0
		dist = float(a2[3]) if a2.size() > 3 else -1.0
	elif v.begins_with("site:"):
		var a3 := v.substr(5).split(",")
		var s := OutskirtsSites.by_id(StringName(a3[0]))
		if s.is_empty():
			return
		var front := OutskirtsSites.to_world(s, Vector3(0.0, 0.0, -float(a3[2]) if a3.size() > 2 else -28.0))
		x = front.x
		z = front.z
		yaw = float(s["yaw"]) + PI + (float(a3[1]) if a3.size() > 1 else 0.0)
		dist = float(a3[2]) if a3.size() > 2 else -1.0
		lift = float(a3[3]) if a3.size() > 3 else 0.0
	if k == 0:
		p.camera_rig.cine_clear()
	if k == 0:
		var pos := Vector3(x, TerrainHeight.height_at(x, z) + 0.8, z)
		p.camera_rig.cine_clear()
		p.global_position = pos
		p.velocity = Vector3.ZERO
		p.camera_rig.yaw = yaw
		_settle(pos)
		p.teleport_to(pos)
		p.camera_rig.yaw = yaw
		if dist > 0.0 and "distance" in p.camera_rig:
			p.camera_rig.set("distance", dist)
