extends RefCounted
## Look-dev bot for the terrain world (tools/bot.sh res://tests/bot_terrain.gd OUT EVERY COUNT, QUALITY=0|1|2, BOT_RES=2400x1080).
## env: TERR_VIEWS = semicolon list of "px,py,pz,tx,ty,tz" (camera position, look-at target; world metres), one per shot slot;
##      TERR_FRAMES = frames to wait per view (default 12).  A view beginning with "hero:" parks the hero at px,pz and uses the real game camera.
var _views: Array[String] = []
var _i := 0
var _f := 0



func _init() -> void:
	var raw := OS.get_environment("TERR_VIEWS")
	for s in raw.split(";", false):
		_views.append(s.strip_edges())


func step(_t: float, _d: float) -> bool:
	var p := Game.player as Player
	if p == null:
		return false
	var wait := int(OS.get_environment("TERR_FRAMES")) if OS.get_environment("TERR_FRAMES") != "" else 12
	if _f == 2:
		Game.state = &"play"
		if OS.get_environment("TERR_HOUR") != "" and is_instance_valid(Game.world):
			(Game.world as City).day_night.set_hour(float(OS.get_environment("TERR_HOUR")))
		if OS.get_environment("TERR_NORAIN") == "1" and is_instance_valid(Game.atmosphere):
			(Game.atmosphere as Atmosphere).set_weather(0.0, 0.2)
		p.max_hp = 1.0e6
		p.hp = p.max_hp
		if Game.enemies != null:
			(Game.enemies as EnemyManager).clear()
	if _f >= 3 and _i < _views.size():
		_apply(p, _views[_i])
	_f += 1
	if _f >= 3 + wait:
		_f = 3
		_i += 1
	return _i >= _views.size()


func _apply(p: Player, v: String) -> void:
	if v.begins_with("hero:"):
		var a := v.substr(5).split(",")
		var pos := Vector3(float(a[0]), float(a[1]), float(a[2]))
		p.global_position = pos
		p.velocity = Vector3.ZERO
		p.camera_rig.cine_clear()
		if a.size() > 3:
			p.camera_rig.yaw = float(a[3])
		return
	var rel := v.begins_with("r:")
	if rel:
		v = v.substr(2)
	var a := v.split(",")
	var pos := Vector3(float(a[0]), float(a[1]), float(a[2]))
	var tgt := Vector3(float(a[3]), float(a[4]), float(a[5]))
	if rel:                                                  # heights are metres above the ground at each point
		pos.y += TerrainHeight.height_at(pos.x, pos.z)
		tgt.y += TerrainHeight.height_at(tgt.x, tgt.z)
	var xf := Transform3D(Basis.IDENTITY, pos).looking_at(tgt, Vector3.UP)
	p.camera_rig.cine_set(xf, 70.0)
	p.global_position = Vector3(pos.x, TerrainHeight.height_at(pos.x, pos.z) + 1.0 if (rel or absf(pos.x) > 1100.0 or absf(pos.z) > 1100.0) else 0.0, pos.z)
