extends RefCounted
## Visual bot of the characters module: the articulated hero and operative in the real city, seen with a free look-dev camera (3-4 m and 10-25 m) and with the
## game camera. Look at the pictures: silhouette and value separation at night, the poses (idle, sprint, strafing, firing, reload, hit flinch, death).
##   tools/bot.sh res://tests/bot_characters.gd <out_prefix> 45 10   (every 45 frames, 10 pictures: phases 0-9; writes <out_prefix>_000.png ...)
##   RENDERER=compat tools/bot.sh ...                                  (OpenGL Compatibility renderer)
##   BOT_PHASES=0,5 tools/bot.sh ... 45 2                              (only these phases, in this order; the count must match)
##   BOT_ZOOM=0.6 pulls the free camera closer (default 1).   BOT_QUALITY=0..2 (default 2).
## Phases: 0 hero idle 3/4 front  1 hero sprint (side)  2 hero firing  3 hero reload  4 game camera, operatives at 4 / 12 / 25 m  5 operative close-up
##   6 operative firing at 12 m  7 hero hit and flinch  8 hero death  9 operative death (3 m)
##   10 game camera: flanker 7 m, brute 11 m, shield 16 m, sniper 24 m (the silhouette / emissive-tell check, no HUD rings)  11 close-up of the four specialists at 3-5 m

const Fixture := preload("res://tests/player_fixture.gd")

const TIME_SCALE := 0.3
const NAMES: Array[String] = ["hero_idle", "hero_sprint", "hero_fire", "hero_reload", "game_cam", "op_closeup", "op_fire", "hero_hit", "hero_dead", "op_dead", "spec_game", "spec_close"]

var _every := 45
var _count := 10
var _phase := -1
var _setup_done := false
var _p: Player
var _mgr: EnemyManager
var _order: Array[int] = []
var _group: Array[Drone] = []
var _cam: Camera3D
var _cam_off := Vector3(1.6, 0.4, -3.2)            ## camera offset from the target, in the player's yaw frame (x right, z back)
var _cam_target := 1.0                              ## 0 hero, 1 first enemy of the group


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
	_mgr = Game.enemies as EnemyManager
	Engine.time_scale = TIME_SCALE
	_p.max_hp = 1.0e6
	_mgr.patrol_groups().clear()
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 400.0
	_p.get_tree().root.add_child(_cam)
	for n in _p.get_tree().root.find_children("*", "Stability", true, false):         # it would put the game camera back every frame
		n.set_process(false)
	for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):      # software rendering is slow: keep the tier the bot asks for
		(n as AutoQuality).enabled = false
	Game.set_quality(int(OS.get_environment("BOT_QUALITY")) if OS.get_environment("BOT_QUALITY") != "" else 2)


func _reset_player() -> void:
	Fixture.release_inputs()
	Game.state = &"play"
	_p.invuln = 0.0
	_p.hp = _p.max_hp
	_p.energy = _p.max_energy
	_p.weapon.reset()
	if _p.is_dead():
		Game.do_respawn()
	_p.teleport_to(Game.SPAWN)
	_p.camera_rig.reset_view(-PI * 0.5, -0.05)
	_p.yaw = -PI * 0.5
	Game.heat = 0.0


func _stage(offsets: Array, types: Array, aware: bool) -> void:
	_mgr.clear()
	_group.clear()
	for i in offsets.size():
		var d := _mgr.spawn(types[i], Game.SPAWN + (offsets[i] as Vector3), aware)
		if d != null:
			_group.append(d)


## Freeze the staged enemies where they stand, facing the hero (a still picture of the silhouettes and tells; TestMode.freeze is cleared by every other phase).
func _freeze_facing() -> void:
	TestMode.freeze = true
	for d in _group:
		if is_instance_valid(d):
			d.yaw = PI * 0.5
			d.rotation.y = d.yaw


func _enter(phase: int) -> void:
	Fixture.release_inputs()
	TestMode.freeze = false
	_mgr.clear()
	match phase:
		0:
			_reset_player()
			_cam_off = Vector3(1.7, 0.5, -3.4)
		1:
			_reset_player()
			_cam_off = Vector3(3.6, 0.4, 0.8)
			Input.action_press(&"move_forward")
			Input.action_press(&"sprint")
		2:
			_reset_player()
			_cam_off = Vector3(2.4, 0.3, -2.8)
		3:
			_reset_player()
			_cam_off = Vector3(2.4, 0.3, -2.8)
			_p.weapon.ammo = 3
			Input.action_press(&"reload")
		4:
			_reset_player()
			_p.camera_rig.camera.make_current()
			_stage([Vector3(4.0, 0.0, 0.8), Vector3(12.0, 0.0, -2.5), Vector3(25.0, 0.0, 3.0)], [&"operative", &"operative", &"operative"], false)
		5:
			_reset_player()
			_stage([Vector3(6.0, 0.0, 0.0)], [&"operative"], false)
			_cam_target = 1.0
			_cam_off = Vector3(-1.7, 0.4, -3.4)           ## from the enemy's front: the player stands behind it
		6:
			_reset_player()
			_stage([Vector3(12.0, 0.0, 0.0)], [&"operative"], true)
			_cam_target = 1.0
			_cam_off = Vector3(-3.0, 0.5, -3.0)
		7:
			_reset_player()
			_cam_off = Vector3(1.8, 0.4, -3.0)
		8:
			_reset_player()
			_cam_off = Vector3(2.6, 0.9, -3.2)
		10:
			_reset_player()
			_p.camera_rig.camera.make_current()
			_stage([Vector3(7.0, 0.0, 1.2), Vector3(11.0, 0.0, -2.8), Vector3(16.0, 0.0, 2.5), Vector3(24.0, 0.0, -1.0)], [&"flanker", &"brute", &"shield", &"sniper"], false)
			_freeze_facing()
		11:
			_reset_player()
			_stage([Vector3(7.5, 0.0, -2.0), Vector3(7.5, 0.0, -0.7), Vector3(7.5, 0.0, 0.8), Vector3(7.5, 0.0, 2.3)], [&"flanker", &"sniper", &"brute", &"shield"], false)
			_freeze_facing()
		9:
			_reset_player()
			_stage([Vector3(3.5, 0.0, 0.0)], [&"operative"], false)
			_cam_target = 1.0
			_cam_off = Vector3(-2.4, 0.6, -2.4)
	if phase != 4 and phase != 10:
		_cam.make_current()


func _place_cam(phase: int) -> void:
	if phase == 4 or phase == 10:
		return
	var tgt := _p.global_position
	var yaw := _p.yaw
	if phase == 11:                                              # the specialists stand in a row 6 m ahead: look at the row's centre from the front
		_cam.global_position = Game.SPAWN + Vector3(3.2, 1.6, 0.2)
		_cam.look_at(Game.SPAWN + Vector3(7.5, 1.2, 0.2), Vector3.UP)
		return
	if phase >= 5 and phase != 7 and phase != 8 and not _group.is_empty() and is_instance_valid(_group[0]):
		tgt = _group[0].global_position
		yaw = _group[0].yaw
	var f := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var r := Vector3(-f.z, 0.0, f.x)
	var zoom := float(OS.get_environment("BOT_ZOOM")) if OS.get_environment("BOT_ZOOM") != "" else 1.0       # < 1 = closer
	var pos := tgt + Vector3(0.0, 1.15, 0.0) + r * _cam_off.x * zoom + Vector3(0.0, _cam_off.y * zoom, 0.0) - f * _cam_off.z * zoom
	_cam.global_position = pos
	_cam.look_at(tgt + Vector3(0.0, 1.05, 0.0), Vector3.UP)


func _run(phase: int, k: int) -> void:
	match phase:
		2:
			Input.action_press(&"fire")
		3:
			if k == 2:
				Input.action_release(&"reload")
		7:
			if k == 6:
				_p.damage(20.0, _p.global_position + Vector3(2.0, 1.0, -3.0))
		8:
			if k == 4:
				_p.damage(1.0e7, _p.global_position + Vector3(2.0, 1.0, -3.0))
		9:
			if k == 4 and not _group.is_empty() and is_instance_valid(_group[0]):
				_group[0].damage(500.0, true)
	_place_cam(phase)


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.enemies == null:
		return false
	if not _setup_done:
		_setup()
	var f: int = Dev.get(&"_frame")
	var slot := (f - 1) / _every
	var phase := _order[slot % _order.size()] if not _order.is_empty() else slot
	var k := ((f - 1) % _every) + 1
	if slot != _phase:
		_phase = slot
		_enter(phase)
		print("BOT phase %d %s (frame %d)" % [phase, NAMES[phase % NAMES.size()], f])
	_run(phase, k)
	if k == _every - 1 and OS.get_environment("BOT_STATS") != "":
		print("BOT phase %d: draw calls %d, primitives %d" % [phase, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	if f >= _every * _count:
		Fixture.release_inputs()
		return true
	return false
