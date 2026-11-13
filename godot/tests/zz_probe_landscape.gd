extends RefCounted
## TEMPORARY probe (landscape builder). Delete before finishing.
func run(host: Node) -> void:
	TerrainHeight.warm()
	print("WORLD_HALF ", TerrainHeight.WORLD_HALF, " SEA ", TerrainHeight.SEA_LEVEL, " BEACH ", TerrainHeight.BEACH, " BEACH_TOP ", TerrainHeight.BEACH_TOP)
	for z in [300.0, -600.0, 1000.0]:
		var line := "z=%d: " % int(z)
		var x := -2100.0
		while x < -1200.0:
			line += "%d:%.1f " % [int(x), TerrainHeight.height_at(x, z)]
			x += 50.0
		print(line)
	for r in TerrainRoads.roads():
		var pos: PackedVector2Array = r["pos"]
		print("ROAD ", r["name"], " n ", pos.size(), " len ", snappedf(pos.size() * TerrainRoads.STEP, 1.0), " start ", pos[0], " end ", pos[pos.size() - 1])
	for f in LandscapeSites.falls():
		print("FALL ", f["name"], " pool ", f["pool"], " lip ", f["lip"], " drop ", snappedf(float(f["drop"]), 0.1), " width ", f["width"], " pool_y ", snappedf(float(f["pool_y"]), 0.1))
	for s in LandscapeSites.strips():
		print("STRIP ", s["name"], " c ", s["c"], " u ", s["u"], " y ", snappedf(float(s["y"]), 0.1))
	var kinds := {}
	for an in AnchorSites.all_anchors():
		var k := String(an["kind"])
		if not kinds.has(k):
			kinds[k] = []
		(kinds[k] as Array).append(Vector2(an["base"].x, an["base"].z))
	for k in kinds.keys():
		print("ANCHOR ", k, " n ", (kinds[k] as Array).size(), " first ", (kinds[k] as Array)[0], " second ", (kinds[k] as Array)[mini(1, (kinds[k] as Array).size() - 1)])
	var i := 0
	for pth in WaterLayout.paths:
		var pos2: PackedVector2Array = pth["pos"]
		print("RIVER ", i, " n ", pos2.size(), " at 20 ", pos2[20], " at 60 ", pos2[mini(60, pos2.size() - 1)], " hw ", (pth["hw"] as PackedFloat32Array)[20])
		i += 1
	for st in OutskirtsSites.list:
		print("SITE ", st["id"], " ", st["pos"])
	print("PROBE done")
