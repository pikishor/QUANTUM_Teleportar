extends RefCounted
## Look-dev bot for the outskirts interiors in the REAL game: tools/bot.sh res://tests/bot_country_interiors.gd OUT EVERY COUNT
##   env INT_TYPES  comma list of InteriorCountry types, one per shot slot (the nearest door of that type in any town is used, the real hero and camera inside)
var _types: Array[String] = []
var _i := 0
var _f := 0


func _init() -> void:
	for s in OS.get_environment("INT_TYPES").split(",", false):
		_types.append(s.strip_edges())


func step(_t: float, _d: float) -> bool:
	var ig := InteriorGameplay.instance
	var p := Game.player as Player
	if ig == null or p == null:
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
	if _f >= 3 and _i < _types.size() and (_f - 3) % maxi(wait, 1) == 0:
		if ig.active:
			ig.leave(true)
		var d := ig.doors_of(StringName(_types[_i]), p.global_position)
		print("BOT_INT %s doors=%d nearest=%s" % [_types[_i], d.size(), str(d[0]["name"]) if not d.is_empty() else "-"])
		print("BOT_INT ", ig.test_enter(StringName(_types[_i])))
	_f += 1
	if _f >= 3 and (_f - 3) % maxi(wait, 1) == 0 and _f > 3:
		_i += 1
	return _i >= _types.size()
