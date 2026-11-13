extends RefCounted
## TEMPORARY probe (landscape builder). Delete before finishing.
func run(host: Node) -> void:
	var t0 := Time.get_ticks_msec()
	TerrainHeight.warm()
	print("WARM total ", Time.get_ticks_msec() - t0, " ms")
	for f in LandscapeSites.falls():
		print("FALL ", f["name"], " pool ", f["pool"], " drop ", snappedf(float(f["drop"]), 0.1), " base_y ", snappedf(float(f["base_y"]), 0.1))
	for s in LandscapeSites.strips():
		print("STRIP ", s["name"], " c ", s["c"], " u ", s["u"], " y ", snappedf(float(s["y"]), 0.1))
	print("PROBE done")
