extends RefCounted
## TEMPORARY probe (landscape builder). Delete before finishing.
func run(host: Node) -> void:
	var t0 := Time.get_ticks_msec()
	TerrainHeight.warm()
	print("WARM ms ", Time.get_ticks_msec() - t0)
	for s in LandscapeSites.strips():
		print("STRIP ", s["name"], " c ", s["c"], " u ", s["u"], " y ", snappedf(s["y"], 0.1))
		var c: Vector2 = s["c"]
		var u: Vector2 = s["u"]
		var line := ""
		for k in 13:
			var a := (float(k) / 12.0 - 0.5) * 520.0
			line += "%.1f " % TerrainHeight.height_at(c.x + u.x * a, c.y + u.y * a)
		print("   profile along: ", line)
	print("FLAT ", LandscapeSites.debug_flat)
