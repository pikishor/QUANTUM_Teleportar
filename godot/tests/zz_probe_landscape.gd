extends RefCounted
## TEMPORARY probe (landscape builder): looks for cliffs. Delete before finishing.
func run(host: Node) -> void:
	TerrainHeight.warm()
	var step := 24.0
	var best := []
	var x := -2900.0
	var hist := {}
	while x < 2900.0:
		var z := -2900.0
		while z < 2900.0:
			if TerrainHeight.city_distance(x, z) > 60.0:
				var h := TerrainHeight.height_at(x, z)
				if h > 8.0:
					var sl := TerrainHeight.slope_at(x, z)
					var b := int(sl * 4.0)
					hist[b] = int(hist.get(b, 0)) + 1
					if sl > 1.15:
						best.append([sl, x, z, h])
			z += step
		x += step
	var keys := hist.keys()
	keys.sort()
	for k in keys:
		print("slope bin %.2f-%.2f : %d" % [float(k) / 4.0, float(k + 1) / 4.0, hist[k]])
	best.sort_custom(func(a, b): return a[0] > b[0])
	print("cliff candidates ", best.size())
	for i in mini(best.size(), 40):
		var c = best[i]
		print("  slope %.2f at (%.0f, %.0f) h=%.1f" % [c[0], c[1], c[2], c[3]])
