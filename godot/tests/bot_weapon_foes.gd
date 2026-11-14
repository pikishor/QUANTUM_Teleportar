extends RefCounted
## Look-dev bot of the weapon kit on ENEMIES (wave 114): the real game, the real camera, ONE armed roster enemy per picture a few metres ahead of the hero (so the weapon the enemy holds reads at phone size).
##   WF_IDS=merc_rifle,merc_shotgun,... WF_FRONT=6.5 WF_SIDE=0.0 BOT_RES=1600x720 ENGINE_ARGS="--fixed-fps 12" QUALITY=0|1 tools/bot.sh res://tests/bot_weapon_foes.gd /tmp/out/f 24 8
## WF_AGGRO=0|1 (default 1: the enemy shoots at the hero), WF_HUD=0 hides the HUD layer. EVERY (frames per enemy) and COUNT (enemies) come from the bot.sh arguments;
## the hero is on the EASTFIELD runway (flat) and invulnerable. Prints the weapon id each enemy carries.
var _ids: Array[String] = []
var _i := 0
var _f := 0
var _hud: Node = null


func _init() -> void:
	for s in OS.get_environment("WF_IDS").split(",", false):
		_ids.append(s.strip_edges())


func step(_t: float, _d: float) -> bool:
	var p := Game.player as Player
	if p == null:
		return false
	var wait: int = int(Dev.get(&"_args").get("every", "24")) if Dev.get(&"_args") is Dictionary else 24
	wait = maxi(wait, 2)
	if _f == 2:
		Game.state = &"play"
		p.max_hp = 1.0e6
		p.hp = p.max_hp
		if Game.enemies != null:
			(Game.enemies as EnemyManager).clear()
		if Encounters.current != null:
			Encounters.current.enabled = false
		var city := Game.world as City
		if city != null and city.day_night != null:
			city.day_night.frozen = true
			city.day_night.set_hour(12.0)
		if OS.get_environment("WF_HUD") == "0":
			_hud = Game.get_tree().root.find_child("Hud", true, false)
			if _hud != null and "visible" in _hud:
				_hud.set("visible", false)
	if _f >= 3 and _i < _ids.size():
		_apply(p, _ids[_i], (_f - 3) % wait)
	_f += 1
	if _f >= 3 and (_f - 3) % wait == 0 and _f > 3:
		_i += 1
	return _i >= _ids.size()


func _apply(p: Player, id: String, k: int) -> void:
	if k != 0:
		return
	var city := Game.world as City
	var w := AlienWorld.instance
	if city == null or w == null:
		return
	var front := float(OS.get_environment("WF_FRONT")) if OS.get_environment("WF_FRONT") != "" else 6.5
	var side_m := float(OS.get_environment("WF_SIDE")) if OS.get_environment("WF_SIDE") != "" else 0.0
	var x := 830.0
	var z := 1255.0
	var yaw := -PI * 0.5                                                   # looking east along the runway
	var pos := Vector3(x, TerrainHeight.height_at(x, z) + 0.8, z)
	p.camera_rig.cine_clear()
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.camera_rig.yaw = yaw
	if city.terrain != null:
		city.terrain.settle(pos)
	p.teleport_to(pos)
	p.camera_rig.yaw = yaw
	w.force_active = true
	w.ambient_enabled = false
	w.clear_all()
	w.sites.clear()
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	var at := pos + fwd * front + side * side_m
	at.y = TerrainHeight.height_at(at.x, at.z)
	var aggro := OS.get_environment("WF_AGGRO") != "0"
	var made := w.spawn_group(StringName(id), at, 1, &"", 0.2, aggro)
	for c in made:
		var rf := c as RosterFoe
		var wid := &""
		if rf != null:
			wid = FoeLooks.weapon_of(rf.id)
		print("WEAPON_FOE ", id, " weapon ", wid, " spawned ", made.size())
