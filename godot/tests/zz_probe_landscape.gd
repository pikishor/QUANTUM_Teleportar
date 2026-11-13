extends RefCounted
## TEMPORARY probe (landscape builder). Delete before finishing.
func run(host: Node) -> void:
	TerrainHeight.warm()
	var peaks: Array = []
	var step := 90.0
	for j in range(-48, 49):
		for i in range(-48, 49):
			var x := float(i) * step
			var z := float(j) * step
			var h := TerrainHeight.height_at(x, z)
			if h > 250.0:
				peaks.append({"x": x, "z": z, "h": h})
	peaks.sort_custom(func(a, b): return float(a["h"]) > float(b["h"]))
	print("HIGH points ", peaks.size())
	var shown: Array = []
	for p in peaks:
		var ok := true
		for q in shown:
			if Vector2(float(p["x"]) - float(q["x"]), float(p["z"]) - float(q["z"])).length() < 700.0:
				ok = false
		if ok:
			shown.append(p)
		if shown.size() >= 10:
			break
	for p in shown:
		print("PEAK x=%d z=%d h=%.0f" % [int(p["x"]), int(p["z"]), float(p["h"])])
	print("PROBE done")
