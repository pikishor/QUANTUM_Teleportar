extends RefCounted
## w121-lifts probe: what floats in the sea near (4300, 600). Lists geometry instances within 260 m whose AABB sits over the sea, and saves a frame.
var _started := false
var _done := false
var tree: SceneTree

func step(_t: float, _dt: float) -> bool:
	if _started:
		return _done
	tree = Engine.get_main_loop() as SceneTree
	if tree.get_first_node_in_group(&"hud") == null or not is_instance_valid(Game.player):
		return false
	_started = true
	_run()
	return false

func _run() -> void:
	Game.state = &"play"
	var p := Game.player as Player
	var at := Vector3(4300.0, 0.0, 600.0)
	p.teleport_to(at + Vector3(-120, 30, 0))
	for i in 240:
		await tree.process_frame
	p.global_position = at + Vector3(-150, 40, 0)
	p.velocity = Vector3.ZERO
	p.yaw = atan2(-(150.0), 0.0)
	p.camera_rig.reset_view(p.yaw, -0.1)
	for i in 60:
		await tree.process_frame
	p.global_position = at + Vector3(-150, 40, 0)
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(OS.get_environment("OUT") + "/crystal.png")
	_list(tree.root, at)
	_done = true

func _list(n: Node, at: Vector3) -> void:
	if n is GeometryInstance3D and (n as Node3D).is_visible_in_tree():
		var g := n as GeometryInstance3D
		var bb: AABB = g.global_transform * g.get_aabb()
		var c := bb.get_center()
		if Vector2(c.x - at.x, c.z - at.z).length() < 300.0 and bb.size.length() < 400.0:
			var th := TerrainHeight.height_at(c.x, c.z)
			print("GEO ", g.get_path(), " ", g.get_class(), " c=", c.snapped(Vector3.ONE), " size=", bb.size.snapped(Vector3.ONE), " ground=", snappedf(th, 0.1))
	for ch in n.get_children():
		_list(ch, at)
