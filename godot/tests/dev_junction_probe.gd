extends RefCounted
## Dev helper (not a test): a branch road against its parent: lateral distance and profile difference sample by sample, and the bridge spans of both. tools/test.sh tests/dev_junction_probe.gd (JP_CHILD, JP_PARENT)
const TIMEOUT_SECONDS := 100


func run(_host: Node) -> void:
	TerrainHeight.warm()
	Bridges.ensure()
	var child := OS.get_environment("JP_CHILD") if OS.get_environment("JP_CHILD") != "" else "SUMMIT ROAD"
	var parent := OS.get_environment("JP_PARENT") if OS.get_environment("JP_PARENT") != "" else "PASS ROAD"
	var rc: Dictionary = {}
	var rp: Dictionary = {}
	for r: Dictionary in TerrainRoads.roads():
		if String(r["name"]) == child:
			rc = r
		if String(r["name"]) == parent:
			rp = r
	var pc: PackedVector2Array = rc["pos"]
	var pp: PackedVector2Array = rp["pos"]
	print("JUNC child spans %s (n=%d), parent spans %s (n=%d)" % [str(rc["spans"]), pc.size(), str(rp["spans"]), pp.size()])
	for i in mini(40, pc.size()):
		var bd := 1.0e9
		var bj := -1
		for j in pp.size():
			var d := pp[j].distance_to(pc[i])
			if d < bd:
				bd = d
				bj = j
		print("JUNC child %2d (%.0f, %.0f) prof %.2f | nearest parent sample %d at %.1f m prof %.2f diff %.2f | deck_y@child hint %.1f -> %s" % [i, pc[i].x, pc[i].y, (rc["prof"] as PackedFloat32Array)[i], bj, bd, (rp["prof"] as PackedFloat32Array)[bj], (rc["prof"] as PackedFloat32Array)[i] - (rp["prof"] as PackedFloat32Array)[bj], (rc["prof"] as PackedFloat32Array)[i], str(Bridges.deck_y(pc[i].x, pc[i].y, (rc["prof"] as PackedFloat32Array)[i]))])
	for b: Dictionary in Bridges.list:
		if String(b["road"]) in [child, parent]:
			var pts: PackedVector3Array = b["pts"]
			print("JUNC bridge %s road %s %d pts from (%.0f, %.1f, %.0f) to (%.0f, %.1f, %.0f) len %.0f" % [b["id"], b["road"], pts.size(), pts[0].x, pts[0].y, pts[0].z, pts[pts.size() - 1].x, pts[pts.size() - 1].y, pts[pts.size() - 1].z, float(b["len"])])
