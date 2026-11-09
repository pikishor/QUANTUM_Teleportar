extends RefCounted
## Dev helper (not a test): prints the terrain / water layout numbers. tools/test.sh tests/dev_water_probe.gd


func run(_host: Node) -> void:
	var t0 := Time.get_ticks_msec()
	TerrainHeight.warm()
	print("warm ms ", Time.get_ticks_msec() - t0)
	for p in WaterLayout.paths:
		var pos: PackedVector2Array = p["pos"]
		var s: PackedFloat32Array = p["surface"]
		print(p["name"], " pts ", pos.size(), " len ", p["length"], " start ", pos[0], " s0 ", s[0], " end ", pos[pos.size() - 1], " s1 ", s[s.size() - 1])
	for i in WaterLayout.LAKES.size():
		print("lake ", WaterLayout.LAKES[i]["name"], " level ", WaterLayout.lake_level[i])
	t0 = Time.get_ticks_msec()
	var n := 0
	var wet := 0
	var mx := -1e9
	var mn := 1e9
	for ix in 200:
		for iz in 200:
			var x := -3000.0 + ix * 30.0
			var z := -3000.0 + iz * 30.0
			var h := TerrainHeight.height_at(x, z)
			n += 1
			mx = maxf(mx, h)
			mn = minf(mn, h)
			if TerrainHeight.water_level_at(x, z) != TerrainHeight.NO_WATER:
				wet += 1
	print("40000 samples ms ", Time.get_ticks_msec() - t0, " max ", mx, " min ", mn, " wet ", wet)
	for p in [Vector2(0, 0), Vector2(-1400, 0), Vector2(-1700, 0), Vector2(-2200, 0), Vector2(0, 1500), Vector2(0, 2200), Vector2(0, -2000), Vector2(2000, 0), Vector2(1400, -1400)]:
		print(p, " h ", TerrainHeight.height_at(p.x, p.y), " water ", TerrainHeight.water_level_at(p.x, p.y), " coast_d ", TerrainHeight.coast_distance(p.x, p.y))
