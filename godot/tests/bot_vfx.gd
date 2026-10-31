extends RefCounted
## Visual bot of the explosion VFX: a street explosion at three moments of its life, a wrecked burning car, a quantum collapse, a very close blast
## (no whiteout), a drone death, and the player's muzzle flash and impacts on the ground and on a facade. Look at the pictures.
##   tools/bot.sh res://tests/bot_vfx.gd <out_prefix> 60 9         (every 60 frames, 9 pictures; RENDERER=compat for the OpenGL renderer)
##   BOT_PHASES=0,1,2 tools/bot.sh ... 60 3                          (only these phases; the count must match)
## Phases: 0 blast 0.15 s old  1 blast 0.5 s  2 blast 1.3 s (smoke)  3 wrecked car, 1 s  4 wrecked car, 4 s  5 quantum collapse  6 blast 3 m away  7 drone death
##   8 player firing at the street  9 player firing at a facade. The game runs in slow motion so one frame covers about 6 ms of game time.

const Fixture := preload("res://tests/player_fixture.gd")
const TIME_SCALE := 0.3
const NAMES: Array[String] = ["blast_early", "blast_mid", "blast_late", "wreck_1s", "wreck_4s", "quantum", "blast_close", "drone_death", "fire_street", "fire_facade"]

var _every := 60
var _count := 9
var _phase := -1
var _setup_done := false
var _p: Player
var _order: Array[int] = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			if kv[0] == "every":
				_every = maxi(30, int(kv[1]))
			elif kv[0] == "count":
				_count = maxi(1, int(kv[1]))
	for part in OS.get_environment("BOT_PHASES").split(",", false):
		_order.append(int(part))


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	Engine.time_scale = TIME_SCALE
	_p.max_hp = 1.0e6
	if Game.enemies != null:
		Game.enemies.patrol_groups().clear()
		Game.enemies.clear()


func _reset_player() -> void:
	Fixture.release_inputs()
	Game.state = &"play"
	_p.invuln = 0.0
	_p.hp = _p.max_hp
	_p.teleport_to(Game.SPAWN)
	_p.camera_rig.reset_view(-PI * 0.5, -0.1)
	_p.yaw = -PI * 0.5
	FX.reset()


## Game seconds the effect of each phase has run when its picture is taken. Frames last a varying time under software rendering, so the trigger frame
## is derived from the measured frame time (`_dt`, an exponential average).
const AGE: Array[float] = [0.2, 0.6, 1.4, 1.0, 4.0, 0.2, 0.3, 0.25]
var _dt := 0.1


func _trigger_frame(phase: int) -> int:
	if phase >= AGE.size():
		return 3
	return maxi(8, _every - 1 - roundi(AGE[phase] / maxf(_dt, 0.005)))


func _fire_blast(phase: int) -> void:
	var at := Game.SPAWN + Vector3(14.0, 1.0, 0.0)
	match phase:
		0, 1, 2:
			Game.explode(at, 7.0, {"player_dmg": 0.0, "enemy_dmg": 0.0, "car_dmg": 0.0})
		3, 4:
			Game.explode(Game.SPAWN + Vector3(13.0, 1.0, 1.0), 9.0, {"player_dmg": 0.0, "enemy_dmg": 0.0, "car_dmg": 0.0})
		5:
			Game.explode(Game.SPAWN + Vector3(10.0, 1.0, 0.0), 9.0, {"player_dmg": 0.0, "enemy_dmg": 0.0, "car_dmg": 0.0, "color": Color(0.4, 1.0, 0.93)})
		6:
			Game.explode(Game.SPAWN + Vector3(3.0, 1.0, 0.5), 7.0, {"player_dmg": 0.0, "enemy_dmg": 0.0, "car_dmg": 0.0})
		7:
			var c := Color(1.0, 0.24, 0.37)
			var pos := Game.SPAWN + Vector3(9.0, 1.6, 0.0)
			FX.burst(pos, c, 30, 9.0, 0.8, 10.0)
			FX.blast(pos, 2.5, c, 0.35)


func step(_t: float, delta: float) -> bool:
	if Game.player == null:
		return false
	if not _setup_done:
		_setup()
	var f: int = Dev.get(&"_frame")
	_dt = lerpf(_dt, delta, 0.15)
	var slot := (f - 1) / _every
	var phase := _order[slot % _order.size()] if not _order.is_empty() else slot
	var k := ((f - 1) % _every) + 1
	if slot != _phase:
		_phase = slot
		_reset_player()
		print("BOT phase %d %s (frame %d)" % [phase, NAMES[phase % NAMES.size()], f])
	if k == 2 and OS.get_environment("BOT_DEBUG") != "":
		print("DBG dt %.4f trigger %d" % [_dt, _trigger_frame(phase)])
	if phase <= 7 and k == _trigger_frame(phase):
		_fire_blast(phase)
	if phase == 8:
		_p.camera_rig.aim_at(Game.SPAWN + Vector3(9.0, 0.0, -0.5))
		if k > 5:
			Input.action_press(&"fire")
	elif phase == 9:
		_p.camera_rig.aim_at(Game.SPAWN + Vector3(10.0, 1.8, 12.0))
		if k > 5:
			Input.action_press(&"fire")
	if k == _every - 1 and OS.get_environment("BOT_STATS") != "":
		print("BOT phase %d: draw calls %d, primitives %d, live blasts %d" % [phase, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), FX.explosions.active_count()] + " ages " + str(FX.explosions.slots.filter(func(sl): return sl.active).map(func(sl): return snappedf(sl.age, 0.01))))
	if k == _every - 1 and OS.get_environment("BOT_DEBUG") != "":
		for sl in FX.explosions.slots:
			if sl.active:
				print("DBG slot age %.2f fire vis %s intree %s pos %s scale %s cam %s ground vis %s puff0 %s" % [sl.age, sl.fire.visible, sl.fire.is_visible_in_tree(), sl.fire.global_position, sl.fire.scale, Game.camera.global_position, sl.ground.visible, sl.puffs[0].visible])
	if f >= _every * _count:
		Fixture.release_inputs()
		return true
	return false
