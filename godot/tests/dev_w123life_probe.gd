extends RefCounted
## w123-life probe (not a check): JUMP at a door frame (tower street door, shop glass door) by real fingers; prints the wall-run outcome per lateral offset.
const TIMEOUT_SECONDS := 280
const Lib := preload("res://tests/w120_reach_lib.gd")
var L: Lib


func run(h: Node) -> void:
	h.get_tree().root.size = Vector2i(844, 390)
	L = Lib.new()
	await L.start(h)
	L.fast(true)
	var tf := TowerFloors.instance
	var tw: Dictionary = tf.nearest(Game.SPAWN)
	var n: Vector3 = tw["n"]
	var t: Vector3 = tw["t"]
	var door := TowerFloors.door_pos(tw, 0.0)
	print("W123 tower door ", door, " n ", n, " can_wall_run ", HeroPower.can_wall_run())
	for side in [1.0, -1.0]:
		for ang in [0.0, 0.5, -0.5, 0.9, -0.9]:
			for k in [-1.2, -0.9, -0.6, 0.6, 0.9, 1.2]:
				await _try("tower", door, n * side, t, k, 3.0 if side > 0 else 2.6, ang)
	var sf := ShopFronts.instance
	if sf != null:
		var s := sf.nearest_of(&"food", Game.SPAWN)
		if not s.is_empty():
			for side in [1.0, -1.0]:
				for ang in [0.0, 0.5, -0.5, 0.9, -0.9]:
					for k in [-1.1, -0.8, 0.0, 0.8, 1.1]:
						await _try("shop", s["wall"], (s["normal"] as Vector3) * side, s["along"], k, 3.0 if side > 0 else 2.2, ang)
	await L.finish()


func _try(what: String, door: Vector3, out: Vector3, t: Vector3, k: float, dist: float, ang := 0.0) -> void:
	var start := door + out * dist + t * (k - tan(ang) * dist) + Vector3.UP * 0.2
	await L.tp(start, Lib.yaw_to(start, door + t * k))
	await L.secs(0.4)
	var wr0: int = L.p.verbs.wall_runs
	L.fg.stick(Vector2(0.0, -1.0))
	var ymax := 0.0
	var jumped := false
	var hang := 0.0
	var tt := 0.0
	while tt < 3.5:
		await L.secs(0.05)
		tt += 0.05
		var gp := L.p.global_position
		var dd := (gp - door).dot(out)
		if not jumped and dd < 1.0:
			jumped = true
			await L.press(&"jump")
		ymax = maxf(ymax, gp.y - door.y)
		if gp.y - door.y > 0.8 and absf(L.p.velocity.y) < 0.5 and not L.p.is_on_floor():
			hang += 0.05
	L.fg.stick(Vector2.ZERO)
	await L.secs(0.5)
	var gp := L.p.global_position
	var bad: bool = TowerFloors.blocks(gp + Vector3.UP) or ShopFronts.blocks(gp + Vector3.UP) or Game.world.is_inside_building(gp + Vector3.UP)
	if hang > 0.6 or bad or absf((gp - door).dot(out)) < 0.25:
		print("W123 BAD ang=%.1f bad=%s" % [ang, bad])
	print("W123 %s out=%s k=%.1f ymax=%.2f hang=%.2f wallruns=%d end_d=%.2f end_y=%.2f lat=%.2f floor=%s" % [what, out.snapped(Vector3.ONE), k, ymax, hang, L.p.verbs.wall_runs - wr0, (gp - door).dot(out), gp.y - door.y, (gp - door).dot(t), L.p.is_on_floor()])
