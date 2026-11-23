extends RefCounted
## w120-reach: data survey (no play): ground height and water along the world edge and over a grid. Run: tools/test.sh tests/dev_w120_survey.gd
func run(_h: Node) -> void:
	TerrainHeight.warm()
	var e := CityLayout.PLAY_HALF
	var land := 0
	var n := 0
	var worst := -999.0
	for side in 4:
		for i in 90:
			var t := -e + 2.0 * e * float(i) / 89.0
			var q: Vector2 = [Vector2(e, t), Vector2(-e, t), Vector2(t, e), Vector2(t, -e)][side]
			var hh := TerrainHeight.height_at(q.x, q.y)
			n += 1
			if hh > TerrainHeight.SEA_LEVEL + 0.3:
				land += 1
				if hh > worst:
					worst = hh
				if land < 40: print("EDGE LAND ", q, " h=", snappedf(hh, 0.1))
	print("EDGE: %d of %d edge samples are land, highest %.1f" % [land, n, worst])
	var hi := -999.0
	var hp := Vector2.ZERO
	for i in 60:
		for j in 60:
			var x := -4400.0 + 8800.0 * i / 59.0
			var z := -4400.0 + 8800.0 * j / 59.0
			var hh := TerrainHeight.height_at(x, z)
			if hh > hi:
				hi = hh; hp = Vector2(x, z)
	print("PEAK ", hp, " ", hi, " slope ", TerrainHeight.slope_at(hp.x, hp.y))
	var steep := 0
	var landn := 0
	var steep_pts := []
	for i in 200:
		for j in 200:
			var x := -4400.0 + 8800.0 * i / 199.0
			var z := -4400.0 + 8800.0 * j / 199.0
			if TerrainHeight.height_at(x, z) < TerrainHeight.SEA_LEVEL + 0.3 or TerrainHeight.city_distance(x, z) < 0.0:
				continue
			landn += 1
			var s := TerrainHeight.slope_at(x, z)
			if s > 1.19:
				steep += 1
				if steep_pts.size() < 12: steep_pts.append(Vector3(x, TerrainHeight.height_at(x, z), z))
	print("STEEP >50deg: %d of %d land samples" % [steep, landn], " ", steep_pts)
	TestLib.check(true, "survey")
