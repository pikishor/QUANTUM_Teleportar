extends RefCounted
## Dev helper of the wave 112 LOOK critic (not a test): lists the bridges (id, kind, road, start, end), the points of a few roads and the towns. tools/test.sh tests/dev_critic_probe.gd


func run(_host: Node) -> void:
	TerrainHeight.warm()
	Bridges.ensure()
	for b: Dictionary in Bridges.list:
		var pts: PackedVector3Array = b["pts"]
		print("BRIDGE %s kind=%s road=%s len=%d a=(%d,%d,%.1f) b=(%d,%d,%.1f)" % [b["id"], b["kind"], b.get("road", "?"), int(b["len"]), pts[0].x, pts[0].z, pts[0].y,
				pts[pts.size() - 1].x, pts[pts.size() - 1].z, pts[pts.size() - 1].y])
	for r: Dictionary in TerrainRoads.roads():
		var pos: PackedVector2Array = r["pos"]
		for s in [0.0, 400.0, 800.0, 1250.0, 2000.0]:
			var i := clampi(int(s / TerrainRoads.STEP), 0, pos.size() - 1)
			print("ROADPT %s s=%d (%d,%d) h=%.1f" % [r["name"], int(s), pos[i].x, pos[i].y, TerrainHeight.height_at(pos[i].x, pos[i].y)])
	for t in SettlementData.towns():
		var sp: Vector3 = t["pos"]
		print("TOWN %s %s pos=(%d,%d) yaw=%.2f" % [t["id"], t["style"], sp.x, sp.z, float(t["yaw"])])
	print("STEP ", TerrainRoads.STEP)
