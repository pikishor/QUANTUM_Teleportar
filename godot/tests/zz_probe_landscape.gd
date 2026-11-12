extends RefCounted
## TEMPORARY probe (landscape builder). Delete before finishing.
func run(host: Node) -> void:
	TerrainHeight.warm()
	for f in LandscapeSites.falls():
		var dd: Vector2 = f["dir"]
		var pc: Vector2 = f["pool"]
		var lip: Vector2 = f["lip"]
		var base: Vector2 = f["base"]
		print("FALL ", f["name"], " pool ", pc, " dir ", dd, " lip ", lip, " base ", base, " drop ", snappedf(f["drop"], 0.1), " pool_y ", snappedf(f["pool_y"], 0.01), " lip_y ", snappedf(f["lip_y"], 0.01), " base_y ", snappedf(f["base_y"], 0.01), " width ", f["width"], " pool_r ", f["pool_r"])
		for lz: float in [30.0, 60.0, 110.0, 160.0]:
			var cp: Vector2 = pc + dd * lz
			print("   cam at lz ", lz, " ground ", snappedf(TerrainHeight.height_at(cp.x, cp.y), 0.1), " pool_y+14 ", snappedf(f["pool_y"] + 14.0, 0.1))
		var d_lip := 1.0e9
		var nearest_idx := -1
		var i := 0
		for p in WaterLayout.paths:
			var pos: PackedVector2Array = p["pos"]
			for q in pos:
				var d := q.distance_to(lip)
				if d < d_lip:
					d_lip = d
					nearest_idx = i
			i += 1
		print("   nearest river path ", nearest_idx, " at ", snappedf(d_lip, 0.1), " m from the lip; water at lip ", WaterLayout.surface_at(lip.x, lip.y), " at base ", WaterLayout.surface_at(base.x, base.y), " at pool ", WaterLayout.surface_at(pc.x, pc.y))
		var up: PackedVector2Array = f["up"]
		print("   up ", up[0], " .. ", up[up.size() - 1], " n=", up.size(), " out n=", (f["out"] as PackedVector2Array).size())
	print("PROBE done")
