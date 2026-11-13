extends RefCounted
## Dev helper (not a test): rail samples near a point: mode, bed height against the nearest road surface (clearance of a viaduct over a road). tools/test.sh tests/dev_rail_probe.gd (RP_X, RP_Z, RP_R)
const TIMEOUT_SECONDS := 100


func run(_host: Node) -> void:
	TerrainHeight.warm()
	RailNet.ensure()
	var x := float(OS.get_environment("RP_X")) if OS.get_environment("RP_X") != "" else 242.0
	var z := float(OS.get_environment("RP_Z")) if OS.get_environment("RP_Z") != "" else -1341.0
	var r := float(OS.get_environment("RP_R")) if OS.get_environment("RP_R") != "" else 40.0
	var modes := ["GROUND", "VIADUCT", "TUNNEL", "CUTTING", "?", "?"]
	for rt: Dictionary in RailNet.routes():
		var pts: PackedVector2Array = rt["pos"]
		var ys: PackedFloat32Array = rt["y"]
		var mode: PackedByteArray = rt["mode"]
		for i in pts.size():
			if pts[i].distance_to(Vector2(x, z)) < r:
				var nr := TerrainRoads.nearest(pts[i].x, pts[i].y)
				print("RAILPROBE route %s sample %d (%.0f, %.0f) y %.2f mode %d (%s) nearest road %s at %.1f m road_y %.2f clearance %.2f ground %.2f" % [str(rt.get("id", "?")), i, pts[i].x, pts[i].y, ys[i], mode[i], modes[mini(mode[i], 5)], str(nr[1]), float(nr[0]), float(nr[2]), ys[i] - float(nr[2]), TerrainHeight.height_at(pts[i].x, pts[i].y)])
