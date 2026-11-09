extends RefCounted
## Dev helper (not a test): prints road profiles. tools/test.sh tests/dev_road_probe.gd


func run(_host: Node) -> void:
	TerrainHeight.warm()
	for r in TerrainRoads.roads():
		var pts: PackedVector2Array = r["pos"]
		var prof: PackedFloat32Array = r["prof"]
		print(r["name"], " n ", pts.size(), " len ", int(r["len"]))
		var line := ""
		for i in range(0, pts.size(), 12):
			var nat := TerrainBase.height(pts[i].x, pts[i].y)
			var ws := WaterLayout.surface_at(pts[i].x, pts[i].y)
			line += "%d:(%d,%d) nat %.0f prof %.0f%s | " % [i, pts[i].x, pts[i].y, nat, prof[i], (" W%.0f" % ws) if ws > -1.0e8 else ""]
			if (i / 12) % 3 == 2:
				print(line)
				line = ""
		print(line)
