extends RefCounted
## WAVE 128 look bot (w128-airlook): the hero placed at views of the HELI LINE, the PLANE LINE and the hangars; one shot each (the hero placed by code only: a look bot, not a check).
##   AL_OUT=<dir> AL_TAG=q1 QUALITY=1 BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=900 tools/bot.sh res://tests/bot_w128_air.gd /tmp/x 100000 1
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


func _view(name: String, at: Vector3, look: Vector3, pitch := -0.12, wait := 360) -> void:
	var w := Airport.to_world(at)
	var lw := Airport.to_world(look)
	var d := lw - w
	var yaw := atan2(-d.x, -d.z)
	p.teleport_to(w + Vector3(0.0, 0.3, 0.0))
	p.yaw = yaw
	p.camera_rig.reset_view(yaw, pitch)
	(Game.vehicles as VehicleManager)._spawn_t = 0.0
	await _pf(wait)
	await _shot(name)


func _run(_tree: SceneTree) -> void:
	out = OS.get_environment("AL_OUT")
	tag = OS.get_environment("AL_TAG")
	DirAccess.make_dir_recursive_absolute(out)
	p = Game.player as Player
	Game.state = &"play"
	TestMode.god = true
	await _pf(30)
	var only := OS.get_environment("AL_ONLY")
	var views := [
		["heli_n", Vector3(1318.0, 0.0, -945.0), Vector3(1334.0, 3.0, -900.0)],
		["heli_m", Vector3(1318.0, 0.0, -760.0), Vector3(1334.0, 3.0, -700.0)],
		["heli_s", Vector3(1318.0, 0.0, -560.0), Vector3(1334.0, 3.0, -500.0)],
		["heli_back", Vector3(1350.0, 0.0, -880.0), Vector3(1334.0, 2.0, -892.0)],
		["plane_n", Vector3(1290.0, 0.0, -880.0), Vector3(1307.0, 3.0, -800.0)],
		["plane_m", Vector3(1288.0, 0.0, -700.0), Vector3(1307.0, 3.0, -620.0)],
		["plane_s", Vector3(1290.0, 0.0, -520.0), Vector3(1307.0, 3.0, -420.0)],
		["hangar_a_in", Vector3(1156.0, 0.0, -934.0), Vector3(1132.0, 1.0, -944.0)],
		["shelter_out", Vector3(1360.0, 0.0, -732.0), Vector3(1360.0, 3.0, -775.0)],
	]
	for v: Array in views:
		if only != "" and not only.split(",").has(String(v[0])):
			continue
		await _view(String(v[0]), v[1], v[2])
	_done = true
