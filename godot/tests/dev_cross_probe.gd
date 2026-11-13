extends RefCounted
## Dev helper (not a test): the ground across a road (lateral offsets -9..+9 m) at road samples: height against the road profile. tools/test.sh tests/dev_cross_probe.gd (CP_ROAD, CP_S0, CP_S1)
const TIMEOUT_SECONDS := 100


func run(_host: Node) -> void:
	TerrainHeight.warm()
	var rn := OS.get_environment("CP_ROAD") if OS.get_environment("CP_ROAD") != "" else "DESERT ROAD"
	var s0 := float(OS.get_environment("CP_S0")) if OS.get_environment("CP_S0") != "" else 1170.0
	var s1 := float(OS.get_environment("CP_S1")) if OS.get_environment("CP_S1") != "" else 1210.0
	for road: Dictionary in TerrainRoads.roads():
		if String(road["name"]) != rn:
			continue
		var pos: PackedVector2Array = road["pos"]
		var prof: PackedFloat32Array = road["prof"]
		var i := int(s0 / TerrainRoads.STEP)
		while i <= int(s1 / TerrainRoads.STEP) and i < pos.size() - 1:
			var d := (pos[i + 1] - pos[i - 1]).normalized()
			var side := Vector2(-d.y, d.x)
			var line := ""
			for off: float in [-9.0, -6.0, -3.0, 0.0, 3.0, 6.0, 9.0]:
				var q := pos[i] + side * off
				line += " %+.0f:%+.2f" % [off, TerrainHeight.height_at(q.x, q.y) - prof[i]]
			print("CROSS %s sample %d (%.0f, %.0f) prof %.2f | height - profile at lateral offsets:%s" % [rn, i, pos[i].x, pos[i].y, prof[i], line])
			i += 1
