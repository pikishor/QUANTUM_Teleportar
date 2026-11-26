extends RefCounted
## WAVE 126 look bot (w126-planes): the hero placed at views of the hangars, the army shelters and the PLANE LINE; one shot each (the hero placed by code only).
##   PL_OUT=<dir> PL_TAG=q0 QUALITY=0 BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=900 tools/bot.sh res://tests/bot_w126_planes.gd /tmp/x 100000 1
var _started := false
var _done := false
var p: Player
var out := ""
var tag := ""


func step(_t: float, _dt: float) -> bool:
	if _started:
		return _done
	var tree := Engine.get_main_loop() as SceneTree
	if tree.get_first_node_in_group(&"hud") == null or not is_instance_valid(Game.player):
		return false
	_started = true
	_run(tree)
	return false


func _pf(n: int) -> void:
	for i in n:
		await (Engine.get_main_loop() as SceneTree).physics_frame


func _shot(name: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, name, tag])


## Hero at local `at` (airport frame), looking at local `look`, then wait for the spawns and the door.
func _view(name: String, at: Vector3, look: Vector3, pitch := -0.12) -> void:
	var w := Airport.to_world(at)
	var lw := Airport.to_world(look)
	var d := lw - w
	var yaw := atan2(-d.x, -d.z)
	p.teleport_to(w + Vector3(0.0, 0.3, 0.0))
	p.yaw = yaw
	p.camera_rig.reset_view(yaw, pitch)
	(Game.vehicles as VehicleManager)._spawn_t = 0.0
	await _pf(420)
	await _shot(name)


func _run(_tree: SceneTree) -> void:
	out = OS.get_environment("PL_OUT")
	tag = OS.get_environment("PL_TAG")
	DirAccess.make_dir_recursive_absolute(out)
	p = Game.player as Player
	Game.state = &"play"
	TestMode.god = true
	await _pf(30)
	await _view("hangar_a_out", Vector3(1190.0, 0.0, -940.0), Vector3(1136.0, 4.0, -940.0))
	await _view("hangar_a_in", Vector3(1156.0, 0.0, -934.0), Vector3(1132.0, 1.0, -944.0))
	await _view("shelter_out", Vector3(1360.0, 0.0, -732.0), Vector3(1360.0, 3.0, -775.0))
	await _view("line_n", Vector3(1290.0, 0.0, -880.0), Vector3(1307.0, 3.0, -800.0))
	await _view("line_s", Vector3(1290.0, 0.0, -520.0), Vector3(1307.0, 3.0, -420.0))
	await _view("line_m", Vector3(1288.0, 0.0, -700.0), Vector3(1307.0, 3.0, -620.0))
	_done = true
