extends RefCounted
## Dev probe: what the anchor finder sees from a spot. Run: SA_X=.. SA_Y=.. SA_Z=.. SA_YAW=.. tools/test.sh tests/dev_snake_anchors.gd
const TIMEOUT_SECONDS := 100.0
var host: Node


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(hst: Node) -> void:
	host = hst
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	var p := Game.player as Player
	(Game.enemies as EnemyManager).clear()
	Game.state = &"play"
	TestMode.god = true
	var spots := [[-30.0, 0.0, 4.0, -1.5708], [-30.0, 20.0, 4.0, -1.5708], [-30.0, 40.0, 4.0, -1.5708], [100.0, 30.0, -120.0, 0.0], [15.0, 22.0, -60.0, 0.0]]
	if OS.get_environment("SA_X") != "":
		spots = [[float(OS.get_environment("SA_X")), float(OS.get_environment("SA_Y")), float(OS.get_environment("SA_Z")), float(OS.get_environment("SA_YAW"))]]
	var sn := p.snake
	sn.anchors.debug = true
	for sp in spots:
		p.teleport_to(Vector3(sp[0], sp[1], sp[2]))
		p.camera_rig.reset_view(sp[3], 0.3)
		await frames(20)
		var h := Vector3(-sin(sp[3]), 0.0, -cos(sp[3]))
		var aim := PlayerUtil.forward_of(sp[3], 0.3)
		var r := sn.anchors.find_swing(p, h, aim, SnakePower.range_m(), true)
		var nhit := 0
		for c in sn.anchors.cands:
			if (c["score"] as float) > -INF:
				nhit += 1
		print("SA spot (%.0f %.0f %.0f) yaw %.2f reach %.0f: rays %d, scored %d, best %s" % [sp[0], sp[1], sp[2], sp[3], SnakePower.range_m(), sn.anchors.rays, nhit, "none" if r.is_empty() else "%s at %s dist %.1f score %.2f" % [String(r["kind"]), str(r["pos"]), r["dist"], r["score"]]])
		var shown := 0
		for c in sn.anchors.cands:
			if (c["score"] as float) > -INF and shown < 6:
				shown += 1
				print("   cand yaw %.2f pitch %.2f d %.1f pos %s score %.2f" % [c["yaw"], c["pitch"], c["d"], str(c["pos"]), c["score"]])
