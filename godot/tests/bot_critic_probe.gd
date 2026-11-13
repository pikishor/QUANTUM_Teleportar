extends RefCounted
## Look-dev bot of the wave 112 LOOK critic: finds out WHICH node draws a visual defect by hiding groups of nodes one shot at a time (the beach at 19:00, the real camera).
##   CRIT_HIDE  semicolon list, one per shot: "" (nothing) or a comma list of node paths below /root/Runner/Main (for example "Atmosphere,World/Towns")
##   CRIT_AT    "x,z,yaw" the hero (default the west beach z = -300)   CRIT_HOUR (default 19)
var _f := 0
var _shot := 0
var _hides: Array[String] = []
var _wait := 14


func _init() -> void:
	for s in OS.get_environment("CRIT_HIDE").split(";", true):
		_hides.append(s.strip_edges())


func step(_t: float, _d: float) -> bool:
	var p := Game.player as Player
	if p == null:
		return false
	_wait = int(Dev.get(&"_args").get("every", "14")) if Dev.get(&"_args") is Dictionary else 14
	var city := Game.world as City
	if _f == 2:
		Game.state = &"play"
		p.max_hp = 1.0e6
		p.hp = p.max_hp
		(Game.enemies as EnemyManager).clear()
		if Encounters.current != null:
			Encounters.current.enabled = false
		city.day_night.frozen = true
		city.day_night.set_hour(float(OS.get_environment("CRIT_HOUR")) if OS.get_environment("CRIT_HOUR") != "" else 19.0)
		for n in Game.get_tree().root.find_children("*", "Weather", true, false):
			(n as Weather).set_state(&"clear", true)
		var at := OS.get_environment("CRIT_AT").split(",") if OS.get_environment("CRIT_AT") != "" else PackedStringArray()
		var x := float(at[0]) if at.size() >= 2 else -3241.0
		var z := float(at[1]) if at.size() >= 2 else -300.0
		var yaw := float(at[2]) if at.size() >= 3 else PI * 0.5
		var pos := Vector3(x, TerrainHeight.height_at(x, z) + 0.8, z)
		p.camera_rig.cine_clear()
		p.global_position = pos
		p.velocity = Vector3.ZERO
		if city.terrain != null:
			city.terrain.settle(pos)
		if city.vegetation != null:
			city.vegetation.settle(pos)
		p.teleport_to(pos)
		p.camera_rig.yaw = yaw
		var hud := Game.get_tree().root.find_child("Hud", true, false) as CanvasLayer
		if hud != null:
			hud.visible = false
	if _f >= 3 and _shot < _hides.size() and (_f - 3) % _wait == 0:
		var root := Game.get_tree().root.get_node_or_null("Runner/Main")
		for path in _hides[_shot].split(",", false):
			var nd := root.get_node_or_null(path.strip_edges()) if root != null else null
			if nd != null and "visible" in nd:
				nd.set("visible", false)
				print("CRITPROBE shot %d hides %s" % [_shot, path])
			else:
				print("CRITPROBE shot %d: no node %s" % [_shot, path])
		_shot += 1
	_f += 1
	return _shot >= _hides.size() and (_f - 3) % _wait == _wait - 1
