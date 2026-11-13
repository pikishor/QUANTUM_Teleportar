extends RefCounted
## Dev helper (not a test): the GPS route (WorldRoute, car mode) from the city hub to every pad and town: found, length against the straight line, how much of it is off the roads. tools/test.sh tests/dev_route_probe.gd
const TIMEOUT_SECONDS := 120


func run(_host: Node) -> void:
	TerrainHeight.warm()
	var hub: Dictionary = RoamData.pad(&"hub")
	var a: Vector3 = hub["pos"]
	for pad: Dictionary in RoamData.pads():
		var b: Vector3 = pad["pos"]
		var t0 := Time.get_ticks_usec()
		var poly := WorldRoute.route(a, b, &"car")
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		var straight := Vector2(a.x - b.x, a.z - b.z).length()
		var len := WorldRoute.length(poly)
		# metres of the route that are not within 14 m of any road (off-road driving)
		var off := 0.0
		for i in range(1, poly.size()):
			var q := poly[i]
			if not WorldRoute.in_city(q) and float(TerrainRoads.nearest(q.x, q.z)[0]) > 14.0:
				off += poly[i].distance_to(poly[i - 1])
		print("ROUTEPROBE hub -> %-14s points %3d length %5.0f m straight %5.0f m ratio %.2f off-road %4.0f m (%.0f ms)" % [pad["id"], poly.size(), len, straight, len / maxf(straight, 1.0), off, ms])
