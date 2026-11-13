extends RefCounted
## Dev helper: profile samples of road PROBE_ROAD around index PROBE_I (+-6)
func run(_host: Node) -> void:
	TerrainHeight.warm()
	var nm := OS.get_environment("PROBE_ROAD")
	for r in TerrainRoads.roads():
		if String(r["name"]) != nm:
			continue
		var pts: PackedVector2Array = r["pos"]
		var prof: PackedFloat32Array = r["prof"]
		var wg := 0.0
		var wi := 1
		for i in range(1, pts.size()):
			var g := absf(prof[i] - prof[i - 1]) / maxf(pts[i].distance_to(pts[i - 1]), 1.0)
			if g > wg:
				wg = g
				wi = i
		for i in range(maxi(wi - 6, 0), mini(wi + 7, pts.size())):
			var si := OutskirtsSites.inside(pts[i].x, pts[i].y, 200.0)
			print("i%d (%.0f,%.0f) prof %.2f ground %.2f step %.2f m/%.1f m site %d" % [i, pts[i].x, pts[i].y, prof[i], TerrainHeight.height_at(pts[i].x, pts[i].y), prof[i] - prof[maxi(i - 1, 0)], pts[i].distance_to(pts[maxi(i - 1, 0)]), si])
