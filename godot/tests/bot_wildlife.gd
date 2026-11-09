extends RefCounted
## Look-dev bot for the wildlife (wave 107) in the REAL game: tools/bot.sh res://tests/bot_wildlife.gd OUT EVERY COUNT   (EVERY = frames per view, COUNT = views)
##   QUALITY=0|1|2 picks the tier, BOT_RES=2400x1080 the resolution.
## env OUT_VIEWS  semicolon list, one per shot slot:  "x,z,yaw,species:n[,species:n ...][,front=22][,dist=6][,lift=0]"
##        the real hero on the ground at (x, z) looking along yaw (radians, 0 = -Z north), the groups spawned `front` metres ahead of him (fanned out), the real game camera `dist` behind him
##   OUT_HOUR (default 12), OUT_HUD=0 hides the HUD layer, OUT_FLEE=1 fires a shot into the air after the first settle (the animals run)
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
		if OS.get_environment("OUT_HUD") == "0":
			_hud = Game.get_tree().root.find_child("Hud", true, false) as CanvasItem
			if _hud != null:
				_hud.visible = false
	if _f >= 3 and _i < _views.size():
		_apply(p, _views[_i], (_f - 3) % maxi(wait, 1))
		if (_f - 3) % maxi(wait, 1) == wait - 1 and city_w() != null:
			print("WILDLIFE shot ", _i, " ", city_w().stats())
	_f += 1
	if _f >= 3 and (_f - 3) % maxi(wait, 1) == 0 and _f > 3:
		_i += 1
	return _i >= _views.size()


func city_w() -> WildlifeWorld:
	var c := Game.world as City
	return c.wildlife as WildlifeWorld if c != null else null


func _apply(p: Player, v: String, k: int) -> void:
	var city := Game.world as City
	if v == "cont":                                      # a later look at the same scene: nothing is placed again
		return
	if v == "scare":                                     # a shot is fired: everything near reacts
		if k == 0 and city.wildlife != null:
			(city.wildlife as WildlifeWorld).scare_all(p.global_position, 80.0)
		return
	var parts := v.split(",")
	var x := float(parts[0])
	var z := float(parts[1])
	var yaw := float(parts[2])
	var front := 22.0
	var dist := -1.0
	var lift := 0.0
	var groups: Array = []
	for i in range(3, parts.size()):
		var s := parts[i]
		if s.begins_with("front="):
			front = float(s.substr(6))
		elif s.begins_with("dist="):
			dist = float(s.substr(5))
		elif s.begins_with("lift="):
			lift = float(s.substr(5))
		elif ":" in s:
			groups.append(s)
	if k == 0:
		var pos := Vector3(x, TerrainHeight.height_at(x, z) + 0.8, z)
		p.camera_rig.cine_clear()
		p.global_position = pos
		p.velocity = Vector3.ZERO
		p.camera_rig.yaw = yaw
		if city.terrain != null:
			city.terrain.settle(pos)
		if city.vegetation != null:
			city.vegetation.settle(pos)
		if city.sites != null and city.sites.has_method(&"settle"):
			city.sites.call(&"settle", pos)
		p.teleport_to(pos)
		p.camera_rig.yaw = yaw
		if dist > 0.0 and "distance" in p.camera_rig:
			p.camera_rig.set("distance", dist)
		var w := city.wildlife as WildlifeWorld
		if w != null:
			w.force_active = true
			w.clear()
			w._hero = pos
			w._hero2 = Vector2(pos.x, pos.z)
			var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var side := Vector3(fwd.z, 0.0, -fwd.x)
			var n_groups := groups.size()
			for gi in n_groups:
				var gs := String(groups[gi]).split(":")
				var id := StringName(gs[0])
				var n := int(gs[1])
				var fan := (float(gi) - float(n_groups - 1) * 0.5) * 11.0
				var at := pos + fwd * (front + float(gi) * 3.0) + side * fan
				at.y = TerrainHeight.height_at(at.x, at.z)
				if AnimalSpecies.cls_of(id) == AnimalSpecies.AIR:
					at.y += lift
				w.spawn_group(id, at, n)
			print("WILDLIFE ", v, " -> ", w.stats())
			if OS.get_environment("OUT_FLEE") == "1":
				w.scare_all(pos + fwd * 4.0, 60.0)
