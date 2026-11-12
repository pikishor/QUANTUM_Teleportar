extends RefCounted
## TEMPORARY probe (landscape builder). Delete before finishing.
func run(host: Node) -> void:
	TerrainHeight.warm()
	for r in TerrainRoads.roads():
		var pos: PackedVector2Array = r["pos"]
		var hi := -1.0e9
		var hip := 0
		for i in pos.size():
			var h := TerrainHeight.height_at(pos[i].x, pos[i].y)
			if h > hi:
				hi = h
				hip = i
		print("ROAD ", r["name"], " n ", pos.size(), " len ", snappedf(pos.size() * TerrainRoads.STEP, 1.0), " highest ", snappedf(hi, 0.1), " at s ", snappedf(hip * TerrainRoads.STEP, 1.0), " pos ", pos[hip])
	# the highest ground on a coarse grid
	var best := -1.0e9
	var bp := Vector2.ZERO
	for x in range(-2300, 2301, 100):
		for z in range(-2300, 2301, 100):
			var h := TerrainHeight.height_at(float(x), float(z))
			if h > best:
				best = h
				bp = Vector2(x, z)
	print("PEAK ", snappedf(best, 0.1), " at ", bp)
	for p in [Vector2(-536, -2234), Vector2(1863, -1489), Vector2(-98, -2200)]:
		print("SITE-ish height ", p, " ", snappedf(TerrainHeight.height_at(p.x, p.y), 0.1))
	print("PROBE done")
