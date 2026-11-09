extends RefCounted
## Look-dev bot for the world map (tools/bot.sh res://tests/bot_terrain_map.gd OUT 25 3, BOT_RES=2400x1080): the hero at the DESERT ROAD gate, the map screen at the usual zoom, then WORLD.
## Waits for the TerrainMap picture (worker thread). env: MAP_AT="x,z" hero position (default 1150,10)
var _f := 0
var _ms: MapScreen = null
var _phase := 0
var _wait := 0


func step(_t: float, _d: float) -> bool:
	var p := Game.player as Player
	if p == null:
		return false
	_f += 1
	if _f == 2:
		Game.state = &"play"
		var at := OS.get_environment("MAP_AT").split(",") if OS.get_environment("MAP_AT") != "" else PackedStringArray(["1150", "10"])
		p.teleport_to(Vector3(float(at[0]), TerrainHeight.height_at(float(at[0]), float(at[1])) + 1.0, float(at[1])))
	if _f < 20 or not TerrainMap.ready:
		return false
	if _ms == null:
		var hud := get_hud(p)
		_ms = hud.get_node_or_null("MapScreen") as MapScreen if hud != null else null
		if _ms == null:
			return false
		_ms.discover(p.global_position)
		_ms.open()
		_wait = 0
		return false
	_wait += 1
	if _wait == 12 and _phase == 0:
		_phase = 1
		_ms.set_world_mode(true)
		_wait = 0
	if _wait == 12 and _phase == 1:
		_phase = 2
		_ms.pan(Vector2(900.0, -300.0))
		_ms.zoom_by(2.2, _ms._rect.get_center())
		_wait = 0
	return _phase == 2 and _wait >= 14


func get_hud(p: Player) -> Node:
	for n in p.get_tree().get_nodes_in_group(&"hud"):
		var t = n.get("touch")
		if t != null:
			return t
	return null
