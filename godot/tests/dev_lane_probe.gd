extends RefCounted
## Dev helper (not a test): every place where the finished ground in a lane (+-3 m of a highway centre line, the centre of a track) is more than 0.45 m off the road profile. tools/test.sh tests/dev_lane_probe.gd
const TIMEOUT_SECONDS := 100


func run(_host: Node) -> void:
	TerrainHeight.warm()
	Bridges.ensure()
	var total := 0
	for road: Dictionary in TerrainRoads.roads():
		var pos: PackedVector2Array = road["pos"]
		var prof: PackedFloat32Array = road["prof"]
		var hw := String(road["kind"]) == "highway"
		var run_start := -1
		var worst := 0.0
		var bad := 0
		for i in range(1, pos.size() - 1):
			var d := (pos[i + 1] - pos[i - 1]).normalized()
			var side := Vector2(-d.y, d.x)
			var dev := 0.0
			for off: float in ([-3.0, 0.0, 3.0] if hw else [0.0]):
				var q := pos[i] + side * off
				if TerrainRoads.in_span(q.x, q.y):
					continue
				dev = maxf(dev, absf(TerrainHeight.height_at(q.x, q.y) - prof[i]))
			if dev > 0.45:
				bad += 1
				worst = maxf(worst, dev)
				if run_start < 0:
					run_start = i
					print("LANE %-16s sample %3d (%.0f, %.0f) deviates %.2f m" % [road["name"], i, pos[i].x, pos[i].y, dev])
			else:
				run_start = -1
		total += bad
		print("LANE %-16s %d of %d samples off the profile by > 0.45 m (worst %.2f m)" % [road["name"], bad, pos.size(), worst])
	print("LANE total %d" % total)
