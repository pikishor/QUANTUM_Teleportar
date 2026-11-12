extends RefCounted
## TEMPORARY probe (landscape builder): shoreline positions. Delete before finishing.
func run(host: Node) -> void:
	TerrainHeight.warm()
	for z in [-900, -300, 0, 300, 700, 1100, 1500, 1900]:
		var x := -1000.0
		var prev := TerrainHeight.height_at(x, z)
		var found := false
		while x > -2990.0:
			x -= 10.0
			var h := TerrainHeight.height_at(x, z)
			if h < -1.5 and prev >= -1.5:
				print("z=%d west shore at x=%.0f (h %.1f -> %.1f) coast_dist=%.0f" % [z, x, prev, h, TerrainHeight.coast_distance(x, z)])
				found = true
				break
			prev = h
		if not found:
			print("z=%d no west shore" % z)
	for x in [-600, 0, 600, 1200, 1800, 2400]:
		var z := 1100.0
		var prev := TerrainHeight.height_at(x, z)
		var found := false
		while z < 2990.0:
			z += 10.0
			var h := TerrainHeight.height_at(x, z)
			if h < -1.5 and prev >= -1.5:
				print("x=%d south shore at z=%.0f" % [x, z])
				found = true
				break
			prev = h
		if not found:
			print("x=%d no south shore" % x)
