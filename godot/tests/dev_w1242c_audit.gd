extends RefCounted
## w1242-critic: static audit of the StreetDetail placements (shop sign vs awning, billboards on their roof, ground props on the ground).
const TIMEOUT_SECONDS := 200
const Lib := preload("res://tests/w120_reach_lib.gd")
func run(h: Node) -> void:
	var L := Lib.new()
	await L.start(h)
	await L.f(5)
	var sd := StreetDetail.instance
	if not sd.built:
		sd.build()
	var city = Game.world
	var aw := {}
	for pl: Dictionary in sd.placements:
		if int(pl["kind"]) == StreetDetail.AWNING:
			aw[int(pl["door"])] = pl
	var clip := 0
	var signs := 0
	for pl: Dictionary in sd.placements:
		if int(pl["kind"]) == StreetDetail.SHOP_SIGN:
			signs += 1
			if aw.has(int(pl["door"])):
				var a: Dictionary = aw[int(pl["door"])]
				var n: Vector3 = pl["n"]
				var t := Vector3(-n.z, 0, n.x)
				var off: float = absf(((pl["pos"] as Vector3) - (a["pos"] as Vector3)).dot(t))
				if off < 1.9 + 0.05:
					clip += 1
	print("AUDIT shop signs ", signs, " inside an awning ", clip)
	var bb := 0
	var floating := 0
	var buried := 0
	for pl: Dictionary in sd.placements:
		if int(pl["kind"]) != StreetDetail.BILLBOARD:
			continue
		bb += 1
		var p: Vector3 = pl["pos"]
		var yaw: float = pl["yaw"]
		var bs := Basis(Vector3.UP, yaw)
		var worst := 0.0
		for lp: Vector3 in [Vector3(-2.2, 0, -0.2), Vector3(2.2, 0, -0.2), Vector3(-2.2, 0, -1.4), Vector3(2.2, 0, -1.4)]:
			var w := p + bs * lp
			var gh: float = city.ground_height(w.x, w.z, p.y + 30.0)
			worst = maxf(worst, absf(gh - p.y))
			if gh > p.y + 0.3:
				buried += 1
		if worst > 0.3:
			floating += 1
			print("AUDIT billboard ", p.snapped(Vector3.ONE * 0.1), " off its roof by ", snappedf(worst, 0.1))
	print("AUDIT billboards ", bb, " not on their roof ", floating, " leg in wall ", buried)
	await L.finish()
