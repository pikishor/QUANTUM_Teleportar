extends RefCounted
## WAVE 128 look bot (w128-anim): the hero seated in vehicles (and the casts), shot from a close 3/4 view and from the game's own chase camera. Set-up by code (frames only).
##   AN_OUT=<dir> AN_TAG=q0 AN_KINDS=h_scout,p_glider QUALITY=0 BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=900 tools/bot.sh res://tests/bot_w128_anim.gd /tmp/x 100000 1
var _started := false
var _done := false
var p: Player
var vm: VehicleManager
var out := ""
var tag := ""
var cam: Camera3D


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
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, name, tag])


func _run(tree: SceneTree) -> void:
	out = OS.get_environment("AN_OUT")
	tag = OS.get_environment("AN_TAG")
	DirAccess.make_dir_recursive_absolute(out)
	for q in tree.root.find_children("*", "AutoQuality", true, false):
		(q as AutoQuality).enabled = false
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	Game.state = &"play"
	TestMode.god = true
	await _pf(30)
	var kinds := OS.get_environment("AN_KINDS").split(",", false)
	if kinds.is_empty():
		kinds = PackedStringArray(["h_scout", "h_attack", "p_glider", "p_fighter", "p_cub", "p_biplane", "p_jumbo", "t_heavy", "quad", "jetski"])
	cam = Camera3D.new()
	tree.root.add_child(cam)
	var at := Airport.to_world(Vector3(1250.0, 0.0, -640.0))
	p.teleport_to(at + Vector3(-30.0, 0.5, 0.0))
	await _pf(60)
	for k in kinds:
		vm._release_farthest(at)
		vm._release_farthest(at)
		var v := vm.spawn_parked(StringName(k), at, 0.3)
		if v == null:
			print("AN no %s" % k)
			continue
		await _pf(4)
		vm.enter(v)
		await _pf(40)
		var s: Dictionary = p.body.seat_info
		var head: Vector3 = s.get("head", Vector3(0.0, 1.6, 0.0))
		var node: Node3D = v.visual.model if String(s.get("node", "")) == "" else v.visual.model.get_node(String(s["node"]))
		var rg := p.body.rig
		var hw := rg.model.global_transform * rg.head_now()
		print("AN %s head %s seat-head %s body %s vis %s" % [k, hw, node.global_transform * head, p.body.global_position, p.body.visible])
		var big := float(v.spec["len"]) > 12.0
		for view in [["side", Vector3(-2.2, 0.5, -1.4)], ["back", Vector3(1.2, 1.2, 2.6)]]:
			var off: Vector3 = view[1]
			if big:
				off *= 1.6
			var eye := hw + node.global_transform.basis * off
			p.camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
			Game.camera.global_position = eye
			Game.camera.look_at(hw - Vector3(0.0, 0.25, 0.0), Vector3.UP)
			await _pf(3)
			await _shot("seat_%s_%s" % [k, view[0]])
		p.camera_rig.process_mode = Node.PROCESS_MODE_INHERIT
		await _pf(10)
		await _shot("chase_%s" % k)
		vm.exit_vehicle()
		await _pf(4)
		vm._release(v)
	if OS.get_environment("AN_CASTS") == "1":
		p.teleport_to(at + Vector3(-30.0, 0.5, 0.0))
		await _pf(60)
		var hw := p.global_position + Vector3(0.0, 1.5, 0.0)
		for id: StringName in [&"blink", &"superposition", &"entangle", &"collapse", &"shield"]:
			for ph in [["wind", 6], ["release", 18]]:
				p.body.cast.start(id)
				await _pf(int(ph[1]))
				p.camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
				var f := Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))
				var r := Vector3(cos(p.yaw), 0.0, -sin(p.yaw))
				Game.camera.global_position = hw + f * 2.6 - r * 1.4 + Vector3(0.0, 0.2, 0.0)
				Game.camera.look_at(hw - Vector3(0.0, 0.35, 0.0), Vector3.UP)
				get_tree_paused_safe()
				await _shot("cast_%s_%s" % [id, ph[0]])
				p.camera_rig.process_mode = Node.PROCESS_MODE_INHERIT
				await _pf(50)
	_done = true
	tree.quit()


func get_tree_paused_safe() -> void:
	pass
