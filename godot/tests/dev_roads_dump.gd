extends RefCounted
## Dev helper (not a test): prints every road of TerrainRoads (name, kind, length, a sample every ROADS_STEP metres) and the sites. tools/test.sh tests/dev_roads_dump.gd


func run(_host: Node) -> void:
	TerrainHeight.warm()
	var step := int(OS.get_environment("ROADS_STEP")) if OS.get_environment("ROADS_STEP") != "" else 300
	var only := OS.get_environment("ROADS_ONLY")
	for r in TerrainRoads.roads():
		if only != "" and String(r["name"]) != only:
			continue
		var pts: PackedVector2Array = r["pos"]
		var prof: PackedFloat32Array = r["prof"]
		var acc := 0.0
		var line := "%s (%s, %.0f m, %d spans):" % [r["name"], r["kind"], float(r["len"]), (r["spans"] as Array).size()]
		var next := 0.0
		for i in pts.size():
			if i > 0:
				acc += pts[i].distance_to(pts[i - 1])
			if acc >= next or i == pts.size() - 1:
				line += " s%.0f(%.0f,%.0f h%.0f)" % [acc, pts[i].x, pts[i].y, prof[i]]
				next += float(step)
		print(line)
	for s in OutskirtsSites.list:
		var sp: Vector3 = s["pos"]
		print("SITE %s %s (%.0f, %.0f) y%.1f r%.0f yaw %.2f" % [s["id"], s["kind"], sp.x, sp.z, sp.y, float(s["r"]), float(s["yaw"])])
