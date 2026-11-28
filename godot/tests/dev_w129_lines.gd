extends RefCounted
## Dev probe (w129-airdraws): the footprints (xz boxes of the built models, rotors included) of the PLANE LINE and the HELI LINE at their places, the clearance of every
## wingtip to the runway's east edge and to the nearest helicopter. Headless: tools/test.sh tests/dev_w129_lines.gd
func run(_h: Node) -> void:
	if OS.get_environment("SOLVE") == "2":
		_solve2()
		return
	if OS.get_environment("SOLVE") != "":
		_solve()
		return
	var edge := Airport.RUNWAY_X + Airport.RUNWAY_W * 0.5
	var helis: Array = []
	for pt: Dictionary in HeliRoster.spawn_points():
		var k: StringName = pt["kind"]
		var box := _box(k, Airport.to_local(pt["pos"]), PI * 0.5)
		helis.append([k, box])
	for pt: Dictionary in PlaneRoster.spawn_points():
		if not String(pt["id"]).begins_with("pl_"):
			continue
		var k: StringName = pt["kind"]
		var lp := Airport.to_local(pt["pos"])
		var h := float(PlaneRoster.PLACES[k][1])
		var box := _box(k, lp, h)
		var near := 1.0e9
		var who := ""
		for e: Array in helis:
			var hb: Rect2 = e[1]
			var d := _gap(box, hb)
			if d < near:
				near = d
				who = String(e[0])
		var wb := _wing_band(k)
		print("LINE %-14s z %7.1f  x %6.1f..%6.1f  runway gap %5.1f  heli gap %5.1f (%s)  wing z %.1f..%.1f (model)  len %.1f..%.1f" % [k, lp.z, box.position.x, box.end.x, box.position.x - edge, near, who, wb[0], wb[1], wb[2], wb[3]])


func _solve() -> void:
	var edge := Airport.RUNWAY_X + Airport.RUNWAY_W * 0.5
	var planes: Array = []
	for pt: Dictionary in PlaneRoster.spawn_points():
		if not String(pt["id"]).begins_with("pl_"):
			continue
		var k: StringName = pt["kind"]
		var lp := Airport.to_local(pt["pos"])
		var box := _box(k, lp, float(PlaneRoster.PLACES[k][1]))
		var west := lp.x - box.position.x
		var nx := maxf(lp.x, edge + 12.0 + west)
		var nb := Rect2(box.position + Vector2(nx - lp.x, 0.0), box.size)
		planes.append([k, nx, nb])
		print("SOLVE plane %s x %.1f -> %.1f  (east tip %.1f)" % [k, lp.x, nx, nb.end.x])
	for pt: Dictionary in HeliRoster.spawn_points():
		var k2: StringName = pt["kind"]
		var lp2 := Airport.to_local(pt["pos"])
		var zo := {} if AirDraws.old else {&"h_utility": -968.0, &"h_quantum": -360.0, &"h_void": -330.0, &"h_gull": -300.0, &"h_ultra": -270.0, &"h_naval": -240.0, &"h_coax": -210.0, &"h_tilt": -180.0}
		if zo.has(k2):
			lp2.z = zo[k2]
		var hb := _box(k2, lp2, PI * 0.5)
		var half := (hb.size.x) * 0.5
		var need := lp2.x
		for e: Array in planes:
			var pb: Rect2 = e[2]
			if pb.end.y + 4.0 > hb.position.y and pb.position.y - 4.0 < hb.end.y:
				need = maxf(need, pb.end.x + 5.0 + (lp2.x - hb.position.x))
		var nb2 := Rect2(hb.position + Vector2(need - lp2.x, 0.0), hb.size)
		var clash := ""
		for sh: Dictionary in Hangars.SITES:
			if bool(sh["army"]):
				var sp: Vector2 = sh["pos"]
				var sz: Vector3 = sh["size"]
				var r := Rect2(sp.x - sz.x * 0.5 - 5.0, sp.y - sz.z * 0.5, sz.x + 10.0, sz.z + 30.0)
				if r.intersects(nb2):
					clash += " SHELTER " + String(sh["id"])
		if nb2.end.x > TankRoster.BASE_LOCAL.x - 4.0 and nb2.end.y > TankRoster.BASE_LOCAL.z - 6.0 and nb2.position.y < TankRoster.BASE_LOCAL.z + 13.5 * 9.0:
			clash += " BASE"
		print("SOLVE heli %s z %.1f x %.1f -> %.1f (east %.1f)%s" % [k2, lp2.z, lp2.x, need, nb2.end.x, clash])


func _gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var dz := maxf(maxf(a.position.y - b.end.y, b.position.y - a.end.y), 0.0)
	if dx == 0.0 and dz == 0.0:
		return -minf(minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x), minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y))
	return sqrt(dx * dx + dz * dz)


## xz box (local airport frame) of kind's model at local `at`, local heading `h` (0 = nose north = -z).
func _box(k: StringName, at: Vector3, h: float) -> Rect2:
	var spec: Dictionary = VehicleSpecs.SPECS[k]
	var m: Node3D = VehicleCraftModels.build(String(spec.get("procedural", k)), spec) if spec.has("procedural") else HeliModels.build(String(k), spec)
	var lo := Vector2(1.0e9, 1.0e9)
	var hi := Vector2(-1.0e9, -1.0e9)
	var st: Array = [[m, Transform3D.IDENTITY]]
	while not st.is_empty():
		var e: Array = st.pop_back()
		for c in (e[0] as Node).get_children():
			if not (c is Node3D):
				continue
			var xf: Transform3D = (e[1] as Transform3D) * (c as Node3D).transform
			if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
				var bb := xf * (c as MeshInstance3D).mesh.get_aabb()
				lo = Vector2(minf(lo.x, bb.position.x), minf(lo.y, bb.position.z))
				hi = Vector2(maxf(hi.x, bb.end.x), maxf(hi.y, bb.end.z))
			st.append([c, xf])
	var r := float(spec.get("rotor_r", 0.0))
	lo = Vector2(minf(lo.x, -r), minf(lo.y, -r))
	hi = Vector2(maxf(hi.x, r), maxf(hi.y, r))
	m.free()
	# rotate the box corners by the local heading (Node3D yaw h about +y)
	var b := Basis(Vector3.UP, h)
	var out_lo := Vector2(1.0e9, 1.0e9)
	var out_hi := Vector2(-1.0e9, -1.0e9)
	for q in [Vector3(lo.x, 0, lo.y), Vector3(hi.x, 0, lo.y), Vector3(lo.x, 0, hi.y), Vector3(hi.x, 0, hi.y)]:
		var w: Vector3 = b * q + at
		out_lo = Vector2(minf(out_lo.x, w.x), minf(out_lo.y, w.z))
		out_hi = Vector2(maxf(out_hi.x, w.x), maxf(out_hi.y, w.z))
	return Rect2(out_lo, out_hi - out_lo)


## Model-space z range of everything wider than 4.5 m from the centre line (the wings and the tailplane tips), and the model's z extent: [wz0, wz1, z0, z1].
func _wing_band(k: StringName) -> Array:
	var spec: Dictionary = VehicleSpecs.SPECS[k]
	var m: Node3D = VehicleCraftModels.build(String(spec.get("procedural", k)), spec) if spec.has("procedural") else HeliModels.build(String(k), spec)
	var wz0 := 1.0e9
	var wz1 := -1.0e9
	var z0 := 1.0e9
	var z1 := -1.0e9
	var st: Array = [[m, Transform3D.IDENTITY]]
	while not st.is_empty():
		var e: Array = st.pop_back()
		for c in (e[0] as Node).get_children():
			if not (c is Node3D):
				continue
			var xf: Transform3D = (e[1] as Transform3D) * (c as Node3D).transform
			if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
				var mesh := (c as MeshInstance3D).mesh
				for si in mesh.get_surface_count():
					for v: Vector3 in (mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
						var w := xf * v
						z0 = minf(z0, w.z)
						z1 = maxf(z1, w.z)
						if absf(w.x) > 4.5:
							wz0 = minf(wz0, w.z)
							wz1 = maxf(wz1, w.z)
			st.append([c, xf])
	m.free()
	return [wz0, wz1, z0, z1]


## xz points of the model (every vertex, decimated) at local `at`, heading `h`; a rotor disc adds its rim.
func points(k: StringName, at: Vector3, h: float) -> PackedVector2Array:
	var spec: Dictionary = VehicleSpecs.SPECS[k]
	var m: Node3D = VehicleCraftModels.build(String(spec.get("procedural", k)), spec) if spec.has("procedural") else HeliModels.build(String(k), spec)
	var b := Basis(Vector3.UP, h)
	var out := PackedVector2Array()
	var st: Array = [[m, Transform3D.IDENTITY]]
	while not st.is_empty():
		var e: Array = st.pop_back()
		for c in (e[0] as Node).get_children():
			if not (c is Node3D):
				continue
			var xf: Transform3D = (e[1] as Transform3D) * (c as Node3D).transform
			if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
				var mesh := (c as MeshInstance3D).mesh
				for si in mesh.get_surface_count():
					var vs: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
					for i in range(0, vs.size(), 3):
						var w: Vector3 = b * (xf * vs[i]) + at
						out.append(Vector2(w.x, w.z))
			st.append([c, xf])
	var r := float(spec.get("rotor_r", 0.0))
	if r > 0.0:
		for i in 24:
			var w2: Vector3 = b * Vector3(cos(TAU * i / 24.0) * r, 0.0, sin(TAU * i / 24.0) * r) + at
			out.append(Vector2(w2.x, w2.z))
	m.free()
	return out


## Closest distance between two point sets in xz (a grid would be faster: these are a few thousand points each).
func clearance(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var ra := Rect2(a[0], Vector2.ZERO)
	for q in a:
		ra = ra.expand(q)
	var best := 1.0e9
	for q2 in b:
		if not ra.grow(best).has_point(q2):
			continue
		for q in a:
			best = minf(best, q.distance_to(q2))
	return best


const LANES := [Rect2(1342.0, -759.0, 40.0, 110.0), Rect2(1342.0, -559.0, 40.0, 110.0)]


func _solve2() -> void:
	var planes: Array = []
	for pt: Dictionary in PlaneRoster.spawn_points():
		if String(pt["id"]).begins_with("pl_"):
			var k: StringName = pt["kind"]
			planes.append([k, points(k, Airport.to_local(pt["pos"]), float(PlaneRoster.PLACES[k][1]))])
	for i in HeliRoster.NEW.size():
		var k2: StringName = HeliRoster.NEW[i]
		var z := HeliRoster.LINE_Z0 + HeliRoster.LINE_STEP * float(i)
		var found := -1.0
		var why := ""
		for dx in range(0, 30):
			var x := HeliRoster.LINE_X + float(dx)
			var hp := points(k2, Vector3(x, 0.0, z), PI * 0.5)
			var worst := 1.0e9
			for e: Array in planes:
				worst = minf(worst, clearance(e[1], hp))
			var in_lane := false
			for ln: Rect2 in LANES:
				for q in hp:
					if ln.has_point(q):
						in_lane = true
						break
			if in_lane:
				why = "lane at x %.0f (clear %.1f)" % [x, worst]
				break
			if worst >= 3.5:
				found = x
				why = "clear %.1f" % worst
				break
		print("SOLVE2 %s z %.0f -> x %s  %s" % [k2, z, ("%.0f" % found) if found > 0.0 else "NONE", why])
