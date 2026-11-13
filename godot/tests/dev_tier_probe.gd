extends RefCounted
func run(host: Node) -> void:
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	var city := Game.world as City
	var tw := city.towns as SettlementWorld
	var s := OutskirtsSites.by_id(&"harrow_field")
	tw.settle(s["pos"])
	for q in 3:
		city.set_quality(q)
		var root := tw.town_root(&"harrow_field")
		var vals := []
		for c in root.get_children():
			var mi := c.get_node_or_null("Mesh") as MeshInstance3D
			if mi != null:
				vals.append(mi.visibility_range_end)
		print("TIER ", q, " tw.quality=", tw.quality, " city.quality=", city.quality, " ranges=", vals)
	for r in TerrainRoads.roads():
		var pts: PackedVector2Array = r["pos"]
		print("ROAD ", r["name"], " n=", pts.size(), " first=", pts[0], " last=", pts[pts.size() - 1], " keys=", r.keys())
		break
	for r in TerrainRoads.roads():
		var pts2: PackedVector2Array = r["pos"]
		print("ROAD %s first=(%.0f, %.0f) len0=%.0f last=(%.0f, %.0f)" % [r["name"], pts2[0].x, pts2[0].y, pts2[0].length(), pts2[pts2.size() - 1].x, pts2[pts2.size() - 1].y])
