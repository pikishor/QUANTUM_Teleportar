extends RefCounted
## w1242-critic: the street detail layer's placement defects found in the wave 124 part 2 review (the real main scene, its own city).
##  1. a shop's blade sign never sits inside the awning over the same door (1488 of 1978 blades cut through the awning cloth);
##  3. a street tree's crown is over the follow camera (its underside was 2.25 m up: a green wall filled the phone screen on the sidewalk) and its trunk stops the hero:
##     the left thumb pushes the hero at a trunk by the stick (real finger events) and he never passes through it (he walked through every trunk, news box and bin);
##  2. every rooftop billboard stands on its roof: all four feet on the roof surface (8 of 18 floated 6.2 m over a lower roof step).
## Run: tools/test.sh tests/test_street_w1242c.gd
const TIMEOUT_SECONDS := 200
const Lib := preload("res://tests/w120_reach_lib.gd")
func run(h: Node) -> void:
	var L := Lib.new()
	await L.start(h)
	await L.f(5)
	var sd := StreetDetail.instance
	TestLib.check(sd != null, "the street detail layer exists")
	if sd == null:
		await L.finish()
		return
	if not sd.built:
		sd.build()
	var city = Game.world
	var aw := {}
	for pl: Dictionary in sd.placements:
		if int(pl["kind"]) == StreetDetail.AWNING:
			aw[int(pl["door"])] = pl
	var clip: Array = []
	var signs := 0
	for pl: Dictionary in sd.placements:
		if int(pl["kind"]) != StreetDetail.SHOP_SIGN:
			continue
		signs += 1
		if aw.has(int(pl["door"])):
			var a: Dictionary = aw[int(pl["door"])]
			var n: Vector3 = pl["n"]
			var t := Vector3(-n.z, 0, n.x)
			var off: float = absf(((pl["pos"] as Vector3) - (a["pos"] as Vector3)).dot(t))
			if off < StreetDetail.AWNING_HW + 0.1:                     # the blade (0.08 m thick) inside the awning's width
				clip.append((pl["pos"] as Vector3).snapped(Vector3.ONE * 0.1))
	TestLib.check(signs >= 100 and clip.is_empty(), "no shop blade sign cuts through its awning (%d signs, %d inside the awning: %s)" % [signs, clip.size(), clip.slice(0, 4)])
	var bb := 0
	var bad: Array = []
	for pl: Dictionary in sd.placements:
		if int(pl["kind"]) != StreetDetail.BILLBOARD:
			continue
		bb += 1
		var p: Vector3 = pl["pos"]
		var bs := Basis(Vector3.UP, float(pl["yaw"]))
		for lp: Vector3 in [Vector3(-2.2, 0, -0.2), Vector3(2.2, 0, -0.2), Vector3(-2.2, 0, -1.4), Vector3(2.2, 0, -1.4)]:
			var w := p + bs * lp
			var gh: float = city.ground_height(w.x, w.z, p.y + 30.0)
			if absf(gh - p.y) > 0.3:
				bad.append("%s foot %s roof %.1f" % [p.snapped(Vector3.ONE * 0.1), lp, gh])
				break
	TestLib.check(bb >= 6 and bad.is_empty(), "every rooftop billboard stands on its roof (%d billboards, %d off: %s)" % [bb, bad.size(), bad.slice(0, 4)])
	# 3. trees
	var g := StreetDetail.make_geo(StreetDetail.TREE, 0, "", 0, true)
	var low := 99.0
	for vv: Vector3 in (g["v"] as PackedVector3Array):
		if Vector2(vv.x, vv.z).length() > 0.5 and vv.y > 1.2:
			low = minf(low, vv.y)
	TestLib.check(low >= 3.3, "the street tree crown's underside is over the follow camera (%.2f m, needs 3.3)" % low)
	CrateReveal._quiet = 0
	Game.force_touch = true
	var s0 := Game.SPAWN
	var tree_pl: Dictionary = {}
	var best := 1.0e9
	for pl: Dictionary in sd.placements:
		if int(pl["kind"]) == StreetDetail.TREE:
			var dd := Lib.flat(pl["pos"], s0)
			if dd < best:
				best = dd
				tree_pl = pl
	var tp_: Vector3 = tree_pl["pos"]
	# run along the sidewalk (parallel to the nearest road axis): the kerb side is +-28.75 m from the block centre, so the run is along the other axis
	var bx := -CityLayout.HALF + (floorf((tp_.x + CityLayout.HALF) / CityLayout.PITCH) + 0.5) * CityLayout.PITCH
	var along := Vector3(0, 0, 1) if absf(tp_.x - bx) > 20.0 else Vector3(1, 0, 0)
	var start := tp_ + along * 5.0 + Vector3(0, 0.3, 0)
	var goal := tp_ - along * 4.0
	await L.tp(start, Lib.yaw_to(start, goal))
	sd.update(Vector2(tp_.x, tp_.z), true)
	await L.f(3)
	var closest := 99.0
	L.fg.stick(Vector2(0.0, -1.0))
	for i in int(3.0 * Engine.physics_ticks_per_second):
		await h.get_tree().physics_frame
		closest = minf(closest, Lib.flat(L.p.global_position, tp_))
	L.fg.up_all()
	TestLib.check(sd.solids > 0 and closest > 0.3, "pushed at a street tree by the stick, the hero is stopped by its trunk (closest %.2f m to the trunk axis, %d solid props in the window)" % [closest, sd.solids])
	await L.finish()
