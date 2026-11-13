extends RefCounted
## TEMPORARY probe (landscape builder). Delete before finishing.
## Global screening for waterfall candidates: steep faces with a plateau above and a bench below, base below 190 m, away from roads and sites.
func run(host: Node) -> void:
	TerrainHeight.warm()
	var t0 := Time.get_ticks_msec()
	var cands: Array = []
	var step := 36.0
	var half := TerrainHeight.WORLD_HALF - 200.0
	var n := int(half / step)
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var p := Vector2(float(i), float(j)) * step
			if TerrainHeight.city_distance(p.x, p.y) < 150.0:
				continue
			var h0 := TerrainHeight.height_pre(p.x, p.y)
			if h0 < 20.0 or h0 > 330.0:
				continue
			var g := Vector2((TerrainHeight.height_pre(p.x + 6.0, p.y) - TerrainHeight.height_pre(p.x - 6.0, p.y)) / 12.0, (TerrainHeight.height_pre(p.x, p.y + 6.0) - TerrainHeight.height_pre(p.x, p.y - 6.0)) / 12.0)
			if g.length() < 0.9:
				continue
			var dir := (-g).normalized()
			var prof := LandscapeSites._profile(p, dir)
			var run := LandscapeSites._run(prof)
			var top: int = run[0]
			var bot: int = run[1]
			var drop := prof[top] - prof[bot]
			if drop < 18.0 or drop > 110.0 or (bot - top) * 2.0 > 70.0:
				continue
			var base := p + dir * (-30.0 + 2.0 * float(bot))
			var rd := TerrainRoads.nearest(base.x, base.y)
			var rdl := float(rd[0])
			cands.append({"p": p, "drop": drop, "base_y": prof[bot], "road": rdl, "dir": dir})
	print("SCREEN candidates ", cands.size(), " in ", Time.get_ticks_msec() - t0, " ms")
	# bucket by 300 m cells, keep the best of each
	var best := {}
	for c in cands:
		var key := Vector2i(int(floor((c["p"] as Vector2).x / 300.0)), int(floor((c["p"] as Vector2).y / 300.0)))
		var sc := float(c["drop"]) * (1.0 + 0.6 * maxf(0.0, 1.0 - float(c["road"]) / 700.0)) * (1.0 if float(c["base_y"]) < 190.0 else 0.2)
		if not best.has(key) or sc > float((best[key] as Dictionary)["sc"]):
			var d: Dictionary = (c as Dictionary).duplicate()
			d["sc"] = sc
			best[key] = d
	var arr: Array = best.values()
	arr.sort_custom(func(a, b): return float(a["sc"]) > float(b["sc"]))
	for k in mini(arr.size(), 45):
		var d: Dictionary = arr[k]
		print("CAND p=(%d,%d) drop %.0f base_y %.0f road %.0f score %.0f" % [int((d["p"] as Vector2).x), int((d["p"] as Vector2).y), float(d["drop"]), float(d["base_y"]), float(d["road"]), float(d["sc"])])
	print("current falls:")
	for f in LandscapeSites.falls():
		print("FALL ", f["name"], " pool ", f["pool"], " drop ", snappedf(float(f["drop"]), 0.1), " base_y ", snappedf(float(f["base_y"]), 0.1))
	print("PROBE done")
