extends RefCounted
## w121-critic: leaving lot 44 from the lift bay to the street door by the stick; prints the hero's height changes.
const TIMEOUT_SECONDS := 300
const Lib := preload("res://tests/w120_reach_lib.gd")
var L: Lib


func run(h: Node) -> void:
	L = Lib.new()
	await L.start(h)
	L.fast(true)
	var tf := TowerFloors.instance
	var tw := tf.nearest(Game.SPAWN)
	for t in tf.towers:
		if (t["lot"] as CityLayout.Lot).index == int(OS.get_environment("LOT") if OS.get_environment("LOT") != "" else "44"):
			tw = t
	var door := TowerFloors.door_pos(tw, 4.0)
	await L.tp(door, Lib.yaw_to(door, TowerFloors.door_pos(tw, -3.0)))
	await L.secs(0.6)
	var tl := TowerLift.instance
	var st := tl.call_point(0) + (tl.base.basis * Vector3.BACK) * 1.0
	var tgt := TowerFloors.door_pos(tw, 3.0)
	if OS.get_environment("IN") == "1":
		st = door
		tgt = TowerFloors.door_pos(tw, -2.5)
		print("CRIT2 open %d du %.2f" % [TowerFloors.open_lot, TowerFloors.door_u(tw)])
	await L.tp(st, Lib.yaw_to(st, tgt))
	print("CRIT2 from %s uv %s to %s du %.2f iu %.2f" % [st, TowerFloors.uv_of(tw, st), tgt, TowerFloors.door_u(tw), TowerFloors.inner_u(tw)])
	L.fg.stick(Vector2(0, -1))
	var yy := L.p.global_position.y
	for i in 120:
		await L.secs(0.1)
		var gp := L.p.global_position
		var err := wrapf(Lib.yaw_to(gp, tgt) - L.p.camera_rig.yaw, -PI, PI)
		if absf(err) > 0.2:
			L.fg.look(-err * 160.0, 0.0, 3)
		if absf(gp.y - yy) > 0.05 or i % 10 == 0:
			yy = gp.y
			print("CRIT2 t%d y %.2f uv %s trav %d/%d verbs %s floor %s wallrun %s" % [i, yy, TowerFloors.uv_of(tw, gp), L.p.traversal.kind, L.p.traversal.last_kind, L.p.verbs.active(), L.p.is_on_floor(), L.p.wall_running])
		if i % 10 == 5:
			var col := L.p.get_last_slide_collision()
			if col != null:
				print("CRIT2   col %s at %s n %s" % [(col.get_collider() as Node).get_path() if col.get_collider() is Node else "?", col.get_position(), col.get_normal()])
		if Lib.flat(gp, tgt) < 0.8:
			break
	L.fg.stick(Vector2.ZERO)
	print("CRIT2 end ", L.p.global_position)
	await L.finish()
