extends RefCounted
## Look-dev bot for the towns of the outskirts in the REAL game: tools/bot.sh res://tests/bot_towns.gd OUT EVERY COUNT   (EVERY = frames per view, COUNT = views)
##   QUALITY=0|1|2 picks the tier, BOT_RES=2400x1080 the phone resolution, BOT_USER_ARGS="--touch" draws the phone HUD.
## env: OUT_VIEWS  semicolon list, one per shot slot (the TOWN frame: x across, z along the main street, y up from the pad):
##        "t:id,lx,ly,lz,tx,ty,tz[,fov]"     a free camera at (lx, ly, lz) looking at (tx, ty, tz)
##        "w:id,lx,lz[,yaw_off[,dist]]"      the real hero standing at (lx, lz) on the ground, the real game camera looking along the street (+z) turned by yaw_off radians, camera distance dist
##      OUT_HOUR (default 12), OUT_WEATHER clear|rain|snow (default clear), OUT_HUD=0 hides the HUD layer
var _views: Array[String] = []
var _i := 0
var _f := 0
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
		if (_f - 3) % maxi(wait, 1) == maxi(wait, 1) - 1:                         # the last frame of a view: what the renderer drew
			var sw := (Game.world as City).towns as SettlementWorld
			var st: Dictionary = sw.stats() if sw != null else {"chunks": 0, "tris": 0}
			print("TOWNSTAT %s draws=%d prims=%d chunks=%d folk=%d tris_near=%d" % [_views[_i].get_slice(",", 0), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), int(st["chunks"]), sw.folk.active_count() if sw != null else 0, int(st["tris"])])
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
	if city.towns != null and city.towns.has_method(&"settle"):
		city.towns.call(&"settle", pos)


func _apply(p: Player, v: String, k: int) -> void:
	if v.begins_with("t:"):
		var a := v.substr(2).split(",")
		var st := OutskirtsSites.by_id(StringName(a[0]))
		if st.is_empty():
			return
		var cpos := SettlementData.to_world(st, float(a[1]), float(a[3]), float(a[2]))
		var tpos := SettlementData.to_world(st, float(a[4]), float(a[6]), float(a[5]))
		if k == 0:
			var hp := SettlementData.to_world(st, 0.0, -float(st["len"]) - 10.0, 1.0)
			p.global_position = Vector3(hp.x, TerrainHeight.height_at(hp.x, hp.z) + 1.0, hp.z)
			p.velocity = Vector3.ZERO
			_settle(cpos)
		p.camera_rig.cine_set(Transform3D(Basis.IDENTITY, cpos).looking_at(tpos, Vector3.UP), float(a[7]) if a.size() > 7 else 68.0)
		return
	if v.begins_with("f:"):                                       # "f:id,k[,dist]": the hero stands dist metres in front of the k-th person of the town, looking at them
		var a3 := v.substr(2).split(",")
		var mine: Array[Dictionary] = []
		for e in SettlementFolk.entries():
			if String(e["town"]) == a3[0]:
				mine.append(e)
		if mine.is_empty() or k != 0:
			return
		var e0: Dictionary = mine[clampi(int(a3[1]), 0, mine.size() - 1)]
		var fc: Vector2 = e0["face"]
		var dd := float(a3[2]) if a3.size() > 2 else 4.5
		var hp := e0["pos"] as Vector3
		var pos2 := Vector3(hp.x + fc.x * dd, hp.y + 0.8, hp.z + fc.y * dd)
		p.camera_rig.cine_clear()
		p.global_position = pos2
		p.velocity = Vector3.ZERO
		p.camera_rig.yaw = atan2(fc.x, fc.y)
		_settle(pos2)
		p.teleport_to(pos2)
		p.camera_rig.yaw = atan2(fc.x, fc.y)
		if "distance" in p.camera_rig:
			p.camera_rig.set("distance", 3.2)
		return
	if v.begins_with("w:"):
		var a2 := v.substr(2).split(",")
		var st2 := OutskirtsSites.by_id(StringName(a2[0]))
		if st2.is_empty():
			return
		if k == 0:
			var cs: Array = SettlementData.plan_of(st2).street_at(float(a2[2]))
			var w := SettlementData.to_world(st2, (cs[0] as Vector2).x + float(a2[1]), float(a2[2]))
			var pos := Vector3(w.x, TerrainHeight.height_at(w.x, w.z) + 0.8, w.z)
			var yaw := float(st2["yaw"]) + PI + (float(a2[3]) if a2.size() > 3 else 0.0)
			p.camera_rig.cine_clear()
			p.global_position = pos
			p.velocity = Vector3.ZERO
			p.camera_rig.yaw = yaw
			_settle(pos)
			p.teleport_to(pos)
			p.camera_rig.yaw = yaw
			if a2.size() > 4 and "distance" in p.camera_rig:
				p.camera_rig.set("distance", float(a2[4]))
