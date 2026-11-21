extends RefCounted
## Wave 117 probe (not a test): why has a wall no ledge above (SnakeZip.edge_above says INF)? Run: tools/test.sh tests/dev_w117_spots.gd
const TIMEOUT_SECONDS := 140


func run(host: Node) -> void:
	Sfx.muted = true
	Game.force_touch = true
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 20)
	Game.state = &"play"
	var p := Game.player as Player
	var sn := p.snake
	(Game.enemies as EnemyManager).clear()
	for yaw: float in [0.785, 2.356, 3.142, 3.927, 4.712]:
		sn.cancel()
		p.teleport_to(Vector3(-30.0, 0.0, 4.0))
		p.camera_rig.reset_view(yaw, 0.2)
		p.yaw = yaw
		await TestLib.frames(host, 40)
		var z := sn.zip_target
		if z.is_empty():
			continue
		var n: Vector3 = z["normal"]
		var into := -Vector3(n.x, 0.0, n.z).normalized()
		var feet: Vector3 = z["dest"]
		var h := 0.6
		var why := "top of scan"
		while h <= 60.0:
			var at := feet + Vector3(0.0, h, 0.0)
			var o := sn.zip._ray(p, at - Vector3(0.0, 1.0, 0.0), at + Vector3(0.0, 0.4, 0.0))
			if not o.is_empty():
				why = "overhead at h %.1f: %s  hit y %.1f" % [h, str((o["collider"] as Node).get_path()).right(50), (o["position"] as Vector3).y]
				break
			if sn.zip._ray(p, at, at + into * 2.4).is_empty():
				why = "wall ends at h %.1f" % h
				for depth in [1.1, 1.7, 0.75, 2.5, 4.0]:
					var col: Vector3 = at + into * float(depth)
					var top := sn.zip._ray(p, col, col + Vector3.DOWN * 2.6)
					why += "  depth %.1f: %s" % [depth, "none" if top.is_empty() else "y %.1f n.y %.2f" % [(top["position"] as Vector3).y, (top["normal"] as Vector3).y]]
				break
			h += 1.2
		print("SPOT yaw ", yaw, " dest ", feet.snapped(Vector3(0.1, 0.1, 0.1)), " normal ", n.snapped(Vector3(0.01, 0.01, 0.01)), " -> ", why)
	main.queue_free()
	await TestLib.frames(host, 2)
