extends RefCounted
## Dev helper (not a test): lists every road of TerrainRoads with its length, end points, steepest grade and bridge samples. tools/test.sh tests/dev_roads_list.gd


func run(_host: Node) -> void:
	TerrainHeight.warm()
	var roads := TerrainRoads.roads()
	for i in roads.size():
		var r: Dictionary = roads[i]
		var pts: PackedVector2Array = r["pos"]
		var prof: PackedFloat32Array = r["prof"]
		var steep := 0.0
		for k in range(1, pts.size()):
			var g := absf(prof[k] - prof[k - 1]) / maxf(pts[k].distance_to(pts[k - 1]), 0.1)
			steep = maxf(steep, g)
		var bridge := 0
		for k in pts.size():
			if TerrainRoads.in_span(pts[k].x, pts[k].y):
				bridge += 1
		print("ROAD %d %s kind=%s len=%d n=%d w=%.1f from=(%d,%d) to=(%d,%d) y0=%.0f y1=%.0f maxgrade=%.3f bridge_samples=%d" % [i, r["name"], r["kind"], int(r["len"]), pts.size(), float(r["w"]), pts[0].x, pts[0].y, pts[pts.size() - 1].x, pts[pts.size() - 1].y, prof[0], prof[prof.size() - 1], steep, bridge])
