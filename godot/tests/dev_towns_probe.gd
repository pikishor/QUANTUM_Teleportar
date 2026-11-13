extends RefCounted
## Dev helper (not a test): boots the real scene, builds every town around its pad centre and prints the numbers (chunks, triangles, colliders, build time, doors, anchors, helipads, parked slots).
##   tools/test.sh tests/dev_towns_probe.gd


func run(host: Node) -> void:
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	var city := Game.world as City
	print("TOWNS node: ", city.towns, " ", SettlementWorld.instance)
	var sw := SettlementWorld.instance
	if sw == null:
		return
	for s in SettlementData.towns():
		var t0 := Time.get_ticks_msec()
		var pl := SettlementData.plan_of(s)
		var t1 := Time.get_ticks_msec()
		sw.settle(s["pos"])
		var t2 := Time.get_ticks_msec()
		var st := sw.stats()
		print("TOWN %s style=%s houses=%d items=%d failed=%s plan=%d ms settle=%d ms chunks=%d tris=%d colliders=%d far=%s doors=%d anchors=%d helipad=%d parked=%d folk=%d" % [s["id"], s["style"], pl.houses, pl.items.size(), pl.failed, t1 - t0, t2 - t1, sw.chunk_count(s["id"]), st["tris"], st["colliders"], sw.has_far(s["id"]), SettlementData.doors_of(s["id"]).size(), pl.anchors.size(), pl.helipads.size(), pl.parked.size(), pl.folk.size()])
	print("STATS ", sw.stats())
