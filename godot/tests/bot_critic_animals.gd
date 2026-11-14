extends RefCounted
## Look-dev bot of the wave 113 critic (lens LOOK): ANIMALS reacting to a blast, in the real game, from the real camera. The hero stands in a forest clearing (the first forest or plains spot
## the bot finds), a herd of deer and a wolf pack stand 20 m ahead, a table blast goes off 6 m from the herd and frames are saved at fixed seconds after it.
##   AN_OUT=/tmp/x AN_BLAST=gr_frag AN_SPECIES="deer:5,wolf:3" AN_T=0.15,0.7,1.6,3.2 BOT_RES=1200x540 QUALITY=0 ENGINE_ARGS="--fixed-fps 12" tools/bot.sh res://tests/bot_critic_animals.gd /tmp/x/seq 100000 1
## AN_SPOT="x,z,yaw" forces the place. Prints how many animals live, run and are dead at every frame.

var _p: Player
var _w: WildlifeWorld
var _out := ""
var _blast := &"gr_frag"
var _species: Array[String] = []
var _times: Array[float] = []
var _spot := Vector3.ZERO
var _yaw := 0.0
var _phase := 0
var _t := 0.0
var _warm := 0.0
var _k := 0
var _render_on := true
var _fired := false
var _setup_done := false
var _crit: Array = []


func _init() -> void:
	_out = OS.get_environment("AN_OUT")
	if OS.get_environment("AN_BLAST") != "":
		_blast = StringName(OS.get_environment("AN_BLAST"))
	var sp := OS.get_environment("AN_SPECIES")
	for s in (sp if sp != "" else "deer:5,wolf:3").split(",", false):
		_species.append(s)
	var ts := OS.get_environment("AN_T")
	for s in (ts if ts != "" else "0.15,0.7,1.6,3.2").split(",", false):
		_times.append(float(s))


func _find_spot() -> bool:
	var forced := OS.get_environment("AN_SPOT")
	if forced != "":
		var fp := forced.split(",")
		_spot = Vector3(float(fp[0]), 0.0, float(fp[1]))
		_yaw = float(fp[2])
		return true
	var best := Vector3.ZERO
	var best_score := -1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 4000:
		var x := rng.randf_range(-1800.0, 1800.0)
		var z := rng.randf_range(-1800.0, 1800.0)
		var h := TerrainHeight.height_at(x, z)
		var b := TerrainBase.biome_at(x, z, h)
		if b != TerrainBase.FOREST and b != TerrainBase.PLAINS:
			continue
		if h < 6.0 or h > 120.0:
			continue
		var slope := absf(TerrainHeight.height_at(x + 12.0, z) - h) + absf(TerrainHeight.height_at(x, z + 12.0) - h) + absf(TerrainHeight.height_at(x - 25.0, z - 25.0) - h)
		var score := 1.0 / (0.3 + slope) + (0.4 if b == TerrainBase.FOREST else 0.0)
		if score > best_score:
			best_score = score
			best = Vector3(x, h, z)
	if best_score < 0.0:
		return false
	_spot = best
	_yaw = 0.0
	return true


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	var city := Game.world as City
	_w = city.wildlife as WildlifeWorld if city != null else null
	if _w == null:
		print("BOTAN no wildlife world")
		return
	for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	TestMode.god = true
	if city.day_night != null:
		city.day_night.frozen = true
		city.day_night.set_hour(12.0)
	if not _find_spot():
		print("BOTAN no spot")
		return
	DirAccess.make_dir_recursive_absolute(_out)
	print("BOTAN spot ", _spot, " yaw ", _yaw, " biome ", TerrainBase.biome_at(_spot.x, _spot.z, _spot.y))


func _dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _right() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


func _stage() -> void:
	var city := Game.world as City
	var pos := Vector3(_spot.x, TerrainHeight.height_at(_spot.x, _spot.z) + 0.8, _spot.z)
	_p.camera_rig.cine_clear()
	_p.global_position = pos
	_p.velocity = Vector3.ZERO
	_p.camera_rig.yaw = _yaw
	if city.terrain != null:
		city.terrain.settle(pos)
	if city.vegetation != null:
		city.vegetation.settle(pos)
	if city.sites != null and city.sites.has_method(&"settle"):
		city.sites.call(&"settle", pos)
	_p.teleport_to(pos)
	_p.camera_rig.reset_view(_yaw, -0.08)
	_w.force_active = true
	_w.director = false
	_w.clear()
	_w._hero = pos
	_w._hero2 = Vector2(pos.x, pos.z)
	var n_groups := _species.size()
	for gi in n_groups:
		var gs := _species[gi].split(":")
		var id := StringName(gs[0])
		var n := int(gs[1])
		var fan := (float(gi) - float(n_groups - 1) * 0.5) * 12.0
		var at := pos + _dir() * 20.0 + _right() * fan
		at.y = TerrainHeight.height_at(at.x, at.z)
		_w.spawn_group(id, at, n)
	_crit = _w.critters.duplicate()
	print("BOTAN staged ", _crit.size(), " animals ", _species)
	_t = 0.0
	_k = 0
	_fired = false


func _census() -> String:
	var alive := 0
	var moving := 0
	var dead := 0
	var states := {}
	for c in _crit:
		if not is_instance_valid(c):
			dead += 1
			continue
		var cc := c as Critter
		if not cc.alive or cc.dying:
			dead += 1
		else:
			alive += 1
			states[cc.state] = int(states.get(cc.state, 0)) + 1
	return "alive %d dead/gone %d states %s" % [alive, dead, str(states)]


func step(_t_unused: float, delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null:
		return false
	if not _setup_done:
		_setup()
		if _w == null or _spot == Vector3.ZERO:
			return true
	Game.state = &"play"
	_p.invuln = 5.0
	if _warm < 2.5:
		if _warm == 0.0:
			_p.teleport_to(_spot + Vector3(0.0, 1.0, 0.0))
		_warm += delta
		RenderingServer.render_loop_enabled = false
		return false
	if _phase == 0:
		RenderingServer.render_loop_enabled = false
		_render_on = false
		_stage()
		_phase = 1
		return false
	_t += delta
	_p.camera_rig.aim_at(_spot + _dir() * 18.0 + Vector3(0.0, 1.0, 0.0))
	if not _fired and _t >= 1.5:                                                  # the herd has settled and grazes: now the blast, 6 m from its middle on the hero's side
		_fired = true
		_t = 0.0
		var at := _spot + _dir() * 14.0 + Vector3(0.0, 0.3, 0.0)
		var g := TerrainHeight.height_at(at.x, at.z)
		at.y = g + 0.3
		print("BOTAN before ", _census())
		BlastTable.apply(_blast, at, _p, {})
		return false
	if not _fired:
		return false
	if _k < _times.size():
		var due := maxf(_times[_k], delta * 2.0 + 0.01)
		if _t >= due - delta * 2.5 and not _render_on:
			RenderingServer.render_loop_enabled = true
			_render_on = true
		if _t >= due and _render_on:
			var img := _p.get_viewport().get_texture().get_image()
			img.save_png("%s/an_%d.png" % [_out, _k])
			print("BOTAN frame ", _k, " t=", snappedf(_t, 0.01), " ", _census())
			_k += 1
			RenderingServer.render_loop_enabled = false
			_render_on = false
	if _k >= _times.size():
		RenderingServer.render_loop_enabled = true
		print("BOTAN done")
		_p.get_tree().quit()
		return true
	return false
