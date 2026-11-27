extends RefCounted
func run(_h: Node) -> void:
	Bridges.ensure()
	RoadLanes.ensure()
	var b := Bridges.by_id(&"mountain_track_4")
	print("bridge road=", b["road"], " kind=", b["kind"])
	for ri in RoadLanes.roads.size():
		var r: Dictionary = RoadLanes.roads[ri]
		var pts: PackedVector2Array = r["pts"]
		var prof: PackedFloat32Array = r["prof"]
		for k in pts.size():
			if pts[k].distance_to(Vector2(1635.7, -1468.9)) < 12.0:
				print("road %d %s kind=%s pt %s y=%.2f deck=%.2f" % [ri, r["name"], r["kind"], pts[k], prof[k], Bridges.deck_y(pts[k].x, pts[k].y, prof[k] + 2.0)])
	TestLib.check(true, "dump")
