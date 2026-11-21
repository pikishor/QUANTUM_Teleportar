extends RefCounted
## Wave 117 probe (not a test): what the swing anchor search sees along the avenue, old scoring against new. Run: tools/test.sh tests/dev_w117_anchors.gd
const TIMEOUT_SECONDS := 100
func run(host: Node) -> void:
	Sfx.muted = true
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 20)
	Game.state = &"play"
	var p := Game.player as Player
	var sn := p.snake
	TrafficField.bare_street()
	TestMode.god = true
	sn.anchors.debug = true
	for x in [180.0, 220.0, 250.0, 280.0, 310.0, 340.0]:
		for y in [6.0, 14.0]:
			p.teleport_to(Vector3(x, y, 4.0))
			p.camera_rig.reset_view(-PI * 0.5, 0.2)
			p.velocity = Vector3(15.0, 0.0, 0.0)
			await TestLib.frames(host, 30)
			p.global_position = Vector3(x, y, 4.0)
			p.velocity = Vector3(15.0, 0.0, 0.0)
			for old in [true, false]:
				SnakeSwing.old_motion = old
				var hit := sn.anchors.find_swing(p, Vector3(1, 0, 0), Vector3(1, 0.2, 0).normalized(), SnakePower.range_m(), true)
				var lines := []
				for c in sn.anchors.cands:
					var pos: Vector3 = c["pos"]
					lines.append("y%.1f p%.1f (%+.0f,%+.0f,%+.0f) s %s" % [c["yaw"], c["pitch"], pos.x - x, pos.y - y, pos.z - 4.0, ("%.1f" % c["score"]) if c["score"] > -INF else "-"])
				print("PROBE x %.0f y %.0f %s: pick %s stats %s" % [x, y, "old" if old else "new", (hit.get("pos", Vector3.ZERO) as Vector3 - Vector3(x, y, 4.0)).snapped(Vector3.ONE) if not hit.is_empty() else "NONE", sn.anchors.stats])
				if not old:
					print("    ", lines)
	SnakeSwing.old_motion = false
	main.queue_free()
