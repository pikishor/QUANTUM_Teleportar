extends RefCounted
## w123-critic probe (dev only): real main scene, real fingers. Prints PROBE lines on bench sitters, bus-stop waiters, kerb props vs parked cars, node growth.
const TIMEOUT_SECONDS := 300
const Lib := preload("res://tests/w120_reach_lib.gd")
var L: Lib


func _overlap_props(pc, x: float, z: float, r: float) -> Array:
	var out: Array = []
	for dx in [-3.0, 0.0, 3.0]:
		for dz in [-3.0, 0.0, 3.0]:
			for id in (pc._grid.get(pc._key(x + dx, z + dz), PackedInt32Array()) as PackedInt32Array):
				var xf: Transform3D = pc._xf[id]
				if absf(xf.origin.y) > 1.5:
					continue
				var spec: Array = pc._spec_list[pc._spec[id]]
				var sz: Vector3 = spec[1]
				var half := maxf(sz.x, sz.z) * 0.5 if int(spec[0]) == 0 else sz.x
				var d := Vector2(xf.origin.x - x, xf.origin.z - z).length()
				if d < half + r and not out.has(spec[3]):
					out.append("%s@%.2f" % [spec[3], d])
	return out


func run(h: Node) -> void:
	h.get_tree().root.size = Vector2i(844, 390)
	L = Lib.new()
	await L.start(h)
	L.fast(true)
	var nodes0 := h.get_tree().get_node_count()
	var amb = (Game.world as City).ambient
	var cr = amb.crowd
	var pc = Game.world.prop_colliders()
	print("PROBE benches=", StreetLife.benches.size(), " stops=", StreetLife.bus_stops.size())
	# bench seats: is there a bench prop (StreetDress) there, and what else stands on the seat
	var bad_b := 0
	for b in StreetLife.benches:
		var o := _overlap_props(pc, b.x, b.z, 0.3)
		var fam := ",".join(o)
		if not fam.contains("Dress") or o.size() > 1:
			bad_b += 1
			if bad_b < 8:
				print("PROBE bench ", Vector2(b.x, b.z).snapped(Vector2.ONE * 0.1), " props ", o)
	print("PROBE bench seats odd: ", bad_b)
	# wait spots
	var bad_w := 0
	for sp in StreetLife.bus_stops:
		for j in 3:
			var w := StreetLife.wait_spot(sp, j)
			var o2 := _overlap_props(pc, w[0], w[1], 0.3)
			if not o2.is_empty():
				bad_w += 1
				if bad_w < 8:
					print("PROBE wait ", Vector2(w[0], w[1]).snapped(Vector2.ONE * 0.1), " in ", o2)
	print("PROBE wait spots in props: ", bad_w)
	var pw := 0
	for sp in StreetLife.bus_stops:
		for j in 3:
			var w := StreetLife.wait_spot(sp, j)
			var s2 := StreetLife.solid_at(w[0], w[1], 0.25)
			if s2 != "":
				pw += 1
				print("PROBE precise wait ", Vector2(w[0], w[1]).snapped(Vector2.ONE * 0.1), " ", s2)
	var pb := 0
	for b in StreetLife.benches:
		var s3 := StreetLife.solid_at(b.x, b.z, 0.2)
		if s3 != "":
			pb += 1
			if pb < 10:
				print("PROBE precise bench ", Vector2(b.x, b.z).snapped(Vector2.ONE * 0.1), " ", s3)
	print("PROBE precise waits=%d of %d benches=%d of %d" % [pw, StreetLife.bus_stops.size() * 3, pb, StreetLife.benches.size()])
	# walk the spawn street by the stick with the crowd on, then sample sitters / waiters
	NearTraffic.instance.enabled = true
	NearTraffic.instance.set_tier(NearTraffic.instance.quality, 1.0)
	var streets := [[Vector3(-20, 0.3, 11), Vector3(-100, 0.3, 11)], [Vector3(-69, 0.3, 20), Vector3(-69, 0.3, 90)], [Vector3(11, 0.3, 30), Vector3(11, 0.3, 90)], [Vector3(91, 0.3, -70), Vector3(91, 0.3, 0)], [Vector3(-100, 0.3, -11), Vector3(-20, 0.3, -11)]]
	for k in streets.size():
		var a: Vector3 = streets[k][0]
		var b: Vector3 = streets[k][1]
		await L.tp(a, Lib.yaw_to(a, b))
		var r := await L.walk(b, 40.0, 2.0)
		var dup := {}
		var dups := 0
		var pins := 0
		for i in cr.count:
			if cr.is_pinned(i) and cr.is_alive(i):
				pins += 1
				var key := Vector2(cr.person_position(i).x, cr.person_position(i).z).snapped(Vector2.ONE * 0.5)
				if dup.has(key):
					dups += 1
				dup[key] = true
		var inprop := 0
		for i in cr.count:
			if cr.is_alive(i) and (cr.is_sitting(i) or cr.is_waiting(i)):
				var pp: Vector3 = cr.person_position(i)
				var o3 := _overlap_props(pc, pp.x, pp.z, 0.2)
				if not o3.is_empty() and not (cr.is_sitting(i) and o3.size() == 1 and str(o3[0]).contains("Dress")):
					inprop += 1
					print("PROBE person in prop ", pp.snapped(Vector3.ONE * 0.1), " sit=", cr.is_sitting(i), " ", o3)
		print("PROBE street %d reached=%s short=%.1f block=%s pinned=%d same_spot=%d sit=%d wait=%d boarded=%d in_prop=%d nodes=%d" % [k, r["reached"], r["dist"], (r["block"] as Array).map(func(x): return x["what"]), pins, dups, amb.life.sitting_count(), amb.life.waiting_near(L.p.global_position, 60.0), amb.life.boarded, inprop, h.get_tree().get_node_count()])
	# scare everyone with gunfire and see the sitters / waiters
	cr.scare_from(L.p.global_position, 80.0)
	await L.secs(12.0)
	print("PROBE after scare sit=%d bus_dwells=%d leaves=%d" % [amb.life.sitting_count(), StreetLife.bus_dwells, StreetLife.bus_leaves])
	# parked cars vs kit props / benches
	var pk := ParkedCars.instance
	var carhits := 0
	for i in pk._n:
		if pk._alive[i] != 1:
			continue
		var o4 := _overlap_props(pc, pk._x[i], pk._z[i], 1.0)
		if not o4.is_empty():
			carhits += 1
			if carhits < 8:
				print("PROBE parked car ", Vector2(pk._x[i], pk._z[i]).snapped(Vector2.ONE * 0.1), " on ", o4)
	print("PROBE parked cars on props: ", carhits, " of ", pk._n)
	print("PROBE nodes start=%d end=%d" % [nodes0, h.get_tree().get_node_count()])
	await L.finish()
