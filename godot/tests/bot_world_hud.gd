extends RefCounted
## Look-dev bot for the big-world HUD (tools/bot.sh res://tests/bot_world_hud.gd OUT 20 3, BOT_RES=2400x1080, BOT_USER_ARGS="--touch"):
## env WH_SCENE = foot (hero in the outskirts, wanted, hurt) | car | boat | tank | heli | plane | map | mapworld ; WH_AT="x,z" start position.
var _f := 0
var _veh: Vehicle = null
var _ms: MapScreen = null
var _veh_done := false
var _wp_done := false
var _hurt_done := false


func step(_t: float, _d: float) -> bool:
	var p := Game.player as Player
	if p == null:
		return false
	var scene := OS.get_environment("WH_SCENE") if OS.get_environment("WH_SCENE") != "" else "foot"
	var hud := Game.get_tree().root.find_child("Hud", true, false) as Hud
	_f += 1
	if _f == 2:
		Game.state = &"play"
		var at := OS.get_environment("WH_AT").split(",") if OS.get_environment("WH_AT") != "" else PackedStringArray(["1350", "10"])
		var x := float(at[0])
		var z := float(at[1])
		p.teleport_to(Vector3(x, TerrainHeight.height_at(x, z) + 1.0, z))
		if hud != null:
			hud.touch.controls_on = true
	if _f < 20 or not TerrainMap.ready:
		return false
	if not _veh_done and scene in ["car", "boat", "tank", "heli", "plane"]:
		var kind := {"car": &"sport", "boat": &"boat", "tank": &"tank", "heli": &"heli", "plane": &"plane"}[scene] as StringName
		var vm := Game.vehicles as VehicleManager
		_veh_done = true
		_veh = vm.spawn_parked(kind, p.global_position + Vector3(0, 0.5, 0), 0.0)
		vm.enter(_veh)
	if not _wp_done and not scene.begins_with("map") and OS.get_environment("WH_WP") != "" and hud != null:
		_wp_done = true
		var ms0 := MapScreen.new()
		ms0.name = "MapScreen"
		hud.touch.add_child(ms0)
		var w0 := OS.get_environment("WH_WP").split(",")
		ms0.set_waypoint(Vector3(float(w0[0]), 0.0, float(w0[1])))
	if _f == 22 or (_f > 22 and not _hurt_done):
		_hurt_done = true
		Game.heat = 2.6
		p.set(&"hp", 46.0)
		p.set(&"last_hurt_time", PlayerUtil.now())
		Game.say("+30 INTEGRITY", 2.0)
	if _f >= 30 and hud != null and hud.feed.visible_lines(PlayerUtil.now()).size() < 2:                # keep the feeds alive for the shots
		var now := PlayerUtil.now()
		hud.feed.push(HudFeed.KILL, "DOWN  HIVELING", now)
		hud.feed.push(HudFeed.KILL, "DOWN  SKITTER", now)
		hud.feed.push(HudFeed.PICKUP, "+6 CARBINE", now)
		hud.feed.push(HudFeed.WRECK, "WRECKED  TAXI", now)
		p.set(&"hp", 31.0)
	if scene.begins_with("map") and _ms == null and _f > 24 and hud != null:
		_ms = hud.touch.get_node_or_null("MapScreen") as MapScreen
		if _ms == null:
			hud.touch.open_map()
			_ms = hud.touch.get_node_or_null("MapScreen") as MapScreen
		else:
			_ms.open()
		if _ms != null:
			if OS.get_environment("WH_WP") != "":
				var w := OS.get_environment("WH_WP").split(",")
				_ms.set_waypoint(Vector3(float(w[0]), 0.0, float(w[1])))
			_ms.discover(p.global_position)
			if scene == "mapworld":
				_ms.set_world_mode(true)
	return _f > 90
