extends RefCounted
## w1242-street probe: does a near-traffic bus stop at a bus stop and leave?
const TIMEOUT_SECONDS := 200
const Lib := preload("res://tests/w120_reach_lib.gd")

func run(h: Node) -> void:
	var L := Lib.new()
	await L.start(h)
	var nt := NearTraffic.instance
	nt.enabled = true
	nt.count = 4
	nt.reset()
	var st: Array = StreetLife.bus_stops.duplicate()
	st.sort_custom(func(a, b): return a.distance_to(Game.SPAWN) < b.distance_to(Game.SPAWN))
	for si in 3:
		var sp: Vector3 = st[si]
		# which road: the stop stands 11.8 m from a road centre line
		var ax := 0
		var road_c := 0.0
		for k in CityLayout.N + 1:
			var c := CityLayout.road_center(k)
			if absf(absf(sp.z - c) - 11.8) < 0.2:
				ax = 0
				road_c = c
			elif absf(absf(sp.x - c) - 11.8) < 0.2:
				ax = 1
				road_c = c
		var lat := sp.z if ax == 0 else sp.x
		var su := sp.x if ax == 0 else sp.z
		var dir := 1
		for dd in [1, -1]:
			var line := road_c + VehicleSpecs.lane_offset(ax, dd, CityLayout.LANE)
			if absf(lat - line) < StreetLife.BUS_SIDE:
				dir = dd
		var line2 := road_c + VehicleSpecs.lane_offset(ax, dir, CityLayout.LANE)
		await L.tp(sp + Vector3(0, 0.3, 0) + (Vector3(0, 0, signf(sp.z - road_c)) if ax == 0 else Vector3(signf(sp.x - road_c), 0, 0)) * -0.0, 0.0)
		nt.reset()
		var d0 := StreetLife.bus_dwells
		var l0 := StreetLife.bus_leaves
		nt.place(0, ax, dir, line2, su - float(dir) * 45.0, NearTraffic.BUS_KIND, 11.0, 0, 1.0)
		var stood := 0.0
		var min_d := 999.0
		for t in 20 * 10:
			await L.secs(0.1)
			var bp := nt.car_position(0)
			var dist := Vector2(bp.x - sp.x, bp.z - sp.z).length()
			min_d = minf(min_d, dist)
			if nt.bus_at_stop() >= 0:
				stood += 0.1
		print("BUS stop ", si, " ", sp.snapped(Vector3.ONE * 0.1), " ax ", ax, " dir ", dir, " line ", line2, " dwells ", StreetLife.bus_dwells - d0, " leaves ", StreetLife.bus_leaves - l0, " stood ", snappedf(stood, 0.1), " min dist ", snappedf(min_d, 0.1), " alive ", nt._alive[0])
	await L.finish()
