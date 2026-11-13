extends RefCounted
## Dev helper: prints where the ground has a step of more than 6 m over 4 m along z = PROBE_Z from PROBE_X0 to PROBE_X1
func run(_host: Node) -> void:
	TerrainHeight.warm()
	var z := float(OS.get_environment("PROBE_Z")) if OS.get_environment("PROBE_Z") != "" else -300.0
	var x0 := float(OS.get_environment("PROBE_X0")) if OS.get_environment("PROBE_X0") != "" else -2500.0
	var x1 := float(OS.get_environment("PROBE_X1")) if OS.get_environment("PROBE_X1") != "" else 2500.0
	var x := x0
	var worst := 0.0
	while x < x1:
		var h0 := TerrainHeight.height_at(x, z)
		var h1 := TerrainHeight.height_at(x + 4.0, z)
		if absf(h1 - h0) > 4.0:
			print("STEP at x=%.0f: %.1f -> %.1f (%.1f)" % [x, h0, h1, h1 - h0])
		worst = maxf(worst, absf(h1 - h0))
		x += 25.0
	print("worst ", worst)
