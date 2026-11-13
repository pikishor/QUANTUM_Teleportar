extends RefCounted
## Dev helper: per road, the steepest profile step and the worst difference between the finished ground and the profile
func run(_host: Node) -> void:
	TerrainHeight.warm()
	for r in TerrainRoads.roads():
		var pts: PackedVector2Array = r["pos"]
		var prof: PackedFloat32Array = r["prof"]
		var wg := 0.0
		var wgi := 0
		var wo := 0.0
		var woi := 0
		for i in range(1, pts.size()):
			var g := absf(prof[i] - prof[i - 1]) / maxf(pts[i].distance_to(pts[i - 1]), 1.0)
			if g > wg:
				wg = g
				wgi = i
		for i in range(0, pts.size(), 7):
			var h := TerrainHeight.height_at(pts[i].x, pts[i].y)
			if TerrainHeight.depth_at(pts[i].x, pts[i].y) < 0.05 and not TerrainRoads.in_span(pts[i].x, pts[i].y):
				var o := absf(h - prof[i])
				if o > wo:
					wo = o
					woi = i
		print("%s: worst grade %.3f at (%.0f, %.0f) | worst bench off %.2f at (%.0f, %.0f)" % [r["name"], wg, pts[wgi].x, pts[wgi].y, wo, pts[woi].x, pts[woi].y])
