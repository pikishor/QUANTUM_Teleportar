extends RefCounted
func run(_host: Node) -> void:
	var t0 := Time.get_ticks_msec()
	TerrainHeight.warm()
	var t1 := Time.get_ticks_msec()
	OutskirtsSites.ensure()
	var t2 := Time.get_ticks_msec()
	for s in SettlementData.towns():
		SettlementData.plan_of(s)
	var t3 := Time.get_ticks_msec()
	var n := 0
	for s in SettlementData.towns():
		var pl := SettlementData.plan_of(s)
		var ts := Time.get_ticks_msec()
		var out := SettlementKit.build(pl, Rect2(), false)
		n += 1
		print("KIT %s whole-town build %d ms tris %d" % [s["id"], Time.get_ticks_msec() - ts, (out["mesh"] as SettlementMesh).tris()])
	print("COLD warm=%d ms, sites=%d ms, plans=%d ms" % [t1 - t0, t2 - t1, t3 - t2])
