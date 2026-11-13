extends RefCounted
## Dev helper (not a test): the roads with a sample within R metres of a point. tools/test.sh tests/dev_roads_near.gd   (RN_X, RN_Z, RN_R)
const TIMEOUT_SECONDS := 100


func run(_host: Node) -> void:
	TerrainHeight.warm()
	var x := float(OS.get_environment("RN_X")) if OS.get_environment("RN_X") != "" else 1748.5
	var z := float(OS.get_environment("RN_Z")) if OS.get_environment("RN_Z") != "" else 563.2
	var r := float(OS.get_environment("RN_R")) if OS.get_environment("RN_R") != "" else 30.0
	var roads := TerrainRoads.roads()
	for i in roads.size():
		var pos: PackedVector2Array = roads[i]["pos"]
		var best := 1.0e9
		var bk := -1
		for k in pos.size():
			var d := pos[k].distance_to(Vector2(x, z))
			if d < best:
				best = d
				bk = k
		if best < r:
			print("ROADSNEAR %d %s nearest sample %d (s=%d) at (%.0f, %.0f) %.1f m, kind %s" % [i, roads[i]["name"], bk, bk * 10, pos[bk].x, pos[bk].y, best, roads[i]["kind"]])
