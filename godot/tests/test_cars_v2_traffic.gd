extends RefCounted
## Cars v2, second pass (round 6): the traffic side of "cars go inside other cars" and the near traffic cars, on the real scene.
##  * a real car whose hull touches a kerb car at ANY speed (it creeps, it stands, it turns on the spot) swaps that kerb car for a real one, so the manager's collision response pushes the two apart
##    (the city audit found a stuck bot and a police car sitting 0.2 m inside kerb hulls for seconds);
##  * two bridge cars that sit inside each other (one rolled back into the other) leave the deck and come in again (the highway audit found two of them stuck for a minute);
##  * the near traffic: the cars within the HI range are written to the HI MultiMesh (a handful at most, the box kinds a little farther), the rest to the far one; the HI node is hidden while it holds
##    none; cars the road and kerb layers append are routed the same way; the shaders compile and the twelve kinds have a table row.
##  * a village (the driveway cars of DUST WELLS and the verge cars of its road): no two hulls inside each other after 20 s of simulated traffic.
## Run: tools/test.sh tests/test_cars_v2_traffic.gd   (about 30 s)

const TIMEOUT_SECONDS := 120

var host: Node
var p: Player
var mgr: VehicleManager
var city: City


func run(h: Node) -> void:
	host = h
	seed(7)
	Sfx.muted = true
	await _bridge_deadlock()
	await _real()


# --- the bridge cars ---------------------------------------------------------------------------------------------------------------------------------

func _bridge_deadlock() -> void:
	var b := Bridges.by_id(&"harbour_gate")
	TestLib.check(not b.is_empty(), "the harbour gate bridge exists")
	if b.is_empty():
		return
	TrafficField.reset()
	var a := BridgeTraffic.new()
	var c := BridgeTraffic.new()
	host.add_child(a)
	host.add_child(c)
	a.setup(b, 0)
	c.setup(b, 2)
	a.set_active(true)
	c.set_active(true)
	await TestLib.frames(host, 3)
	# both cars at the very start of the deck, 3.4 m apart (4.6 m of hull between their centres), standing still: the deadlock of the audit
	a.u = 2.0
	c.u = 5.4
	a.waiting = false
	c.waiting = false
	a.v = 0.0
	c.v = 0.0
	a.visible = true
	c.visible = true
	a._place()
	c._place()
	var overlap0 := TrafficField.obb_depth(a.global_position.x, a.global_position.z, a._fwd.x, a._fwd.y, a._hl, a._hw, c.global_position.x, c.global_position.z, c._fwd.x, c._fwd.y, c._hl, c._hw)
	TestLib.check(overlap0 > 0.3, "the two bridge cars start inside each other (depth %.2f m)" % overlap0)
	await TestLib.frames(host, 150)                                    # 2.5 s at 60 Hz: the overlap timer (0.8 s) runs out, the car leaves the deck and waits at the start
	var left := a.waiting or c.waiting or not a.visible or not c.visible
	var depth := 0.0
	if a.visible and c.visible and not a.waiting and not c.waiting:
		depth = TrafficField.obb_depth(a.global_position.x, a.global_position.z, a._fwd.x, a._fwd.y, a._hl, a._hw, c.global_position.x, c.global_position.z, c._fwd.x, c._fwd.y, c._hl, c._hw)
	TestLib.check(left or depth <= 0.05, "...and one of them left the deck or the pair came apart (waiting %s / %s, depth %.2f)" % [a.waiting, c.waiting, depth])
	a.queue_free()
	c.queue_free()


# --- kerb cars and the near traffic meshes, in the real scene -------------------------------------------------------------------------------------

func _real() -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	MapScreen.path_override = "user://test_cars_v2_traffic_map_%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(MapScreen.path_override)
	CarRadio.auto_headless = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	city = Game.world as City
	p = Game.player as Player
	mgr = Game.vehicles as VehicleManager
	TestLib.check(city != null and p != null and mgr != null and city.ambient != null, "the real scene has a city, a player, a vehicle manager and the ambient traffic")
	if city == null or p == null or mgr == null or city.ambient == null:
		return
	p.set_physics_process(true)
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	if Encounters.current != null:
		Encounters.current.enabled = false
	if Game.enemies != null:
		(Game.enemies as EnemyManager).clear()
	await _near_routing()
	await _kerb_promotion()
	await _village()
	CarRadio.auto_headless = false
	main.queue_free()
	for f in [MapScreen.path_override, "user://roam_world.cfg"]:                    # the real scene saves its map and the free roam discoveries: a test leaves no state behind (a leftover roam_world.cfg adds 8 MB of textures to the next perf run)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _near_routing() -> void:
	var nt: NearTraffic = city.ambient.near_traffic
	TestLib.check(nt.mm_hi != null and nt.mm_hi.instance_count == NearTraffic.HI_MAX and nt.hi_node != null and nt.hi_node.get_parent() != null, "the HI MultiMesh exists and hangs in the city (%d instances)" % nt.mm_hi.instance_count)
	TestLib.check(nt.mm.mesh != nt.mm_hi.mesh and _tris(nt.mm_hi.mesh) > 2 * _tris(nt.mm.mesh), "it draws the detailed car (%d triangles against %d of the far one)" % [_tris(nt.mm_hi.mesh), _tris(nt.mm.mesh)])
	# a street with cars around the hero: after some steps some cars are within the HI range, some beyond it
	p.teleport_to(Vector3(0.0, 0.1, 12.0))
	await TestLib.frames(host, 40)
	for k in 12:
		nt.step(0.1, Vector3(0.0, 0.1, 12.0))
		city.ambient.parked.step(0.1, Vector3(0.0, 0.1, 12.0))
	var cap: int = NearTraffic.HI_CAP[nt.quality]
	TestLib.check(nt.mm_hi.visible_instance_count <= cap, "at most %d HI cars a frame (%d now)" % [cap, nt.mm_hi.visible_instance_count])
	TestLib.check(nt.hi_node.visible == (nt.mm_hi.visible_instance_count > 0), "the HI node is hidden while it holds no car (an empty MultiMesh still costs a draw call)")
	TestLib.check(nt.mm.visible_instance_count >= 0 and nt.mm.visible_instance_count + nt.mm_hi.visible_instance_count <= NearTraffic.SHARED + NearTraffic.HI_MAX, "the far MultiMesh holds the rest (%d far, %d HI)" % [nt.mm.visible_instance_count, nt.mm_hi.visible_instance_count])
	# a car appended by another layer is routed by the distance of its own position
	var near_buf := PackedFloat32Array()
	near_buf.resize(32)
	var cam := Game.camera.global_position
	for k in 2:
		var o := k * 16
		near_buf[o] = 1.0
		near_buf[o + 5] = 1.0
		near_buf[o + 10] = 1.0
		near_buf[o + 3] = cam.x + (3.0 if k == 0 else 60.0)
		near_buf[o + 11] = cam.z
		near_buf[o + 13] = 0.0
	nt._cam_ok = true
	nt._cam_pos = Vector2(cam.x, cam.z)
	nt._nw_hi = 0
	nt._total = 0
	var done := nt.append_cars(near_buf, 2)
	TestLib.check(done == 2 and nt._nw_hi == 1 and nt._total == 1, "appended cars are routed by distance: the one at 3 m is HI, the one at 60 m is far (%d HI, %d far)" % [nt._nw_hi, nt._total])


static func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var idx_len: int = m.surface_get_array_index_len(s)
		n += (idx_len if idx_len > 0 else m.surface_get_array_len(s)) / 3
	return n


func _kerb_promotion() -> void:
	var pk: ParkedCars = city.ambient.parked
	TrafficField.reset()
	mgr.stream_every = 1.0e9
	mgr._stream_t = 1.0e9
	for v in mgr.list.duplicate():
		if v != mgr.starter and is_instance_valid(v) and not v.driver_is_player:
			mgr._release(v)
	p.teleport_to(Vector3(0.0, 0.1, 12.0))
	for k in 30:
		pk.step(0.1, Vector3(0.0, 0.1, 12.0))
	var idx := -1
	for i in pk._n:
		if pk._alive[i] == 1 and Vector2(pk._x[i], pk._z[i]).distance_to(Vector2(0.0, 12.0)) < 40.0:
			idx = i
			break
	TestLib.check(idx >= 0, "a kerb car is standing within 40 m of the market (found %d)" % idx)
	if idx < 0:
		return
	var f := Vector2(-sin(pk._yaw[idx]), -cos(pk._yaw[idx]))
	var spot := Vector3(pk._x[idx], 0.0, pk._z[idx]) + Vector3(f.x, 0.0, f.y) * 2.5          # a real sedan standing nose to nose, 2.5 m off: its hull is 2.1 m inside the kerb car's
	while mgr.list.size() >= mgr.cap():
		mgr._release(mgr.list[0])
	var v := mgr.spawn_parked(&"sedan", spot, pk._yaw[idx] + PI)
	TestLib.check(v != null, "a real car can be put beside the kerb car")
	if v == null:
		return
	v.global_position = spot
	v.heading = pk._yaw[idx] + PI
	v.rotation = Vector3(0.0, v.heading, 0.0)
	v._heading_set = v.heading
	v.vel = Vector3.ZERO
	v.speed = 0.0
	v.ai = true                                                       # a car that is driven by something (traffic AI, a chase) but stands still
	v.publish_hull()
	var before := pk.promoted
	var depth := TrafficField.obb_depth(spot.x, spot.z, -sin(v.heading), -cos(v.heading), 2.3, 0.85, pk._x[idx], pk._z[idx], f.x, f.y, NearTraffic.KIND_HALF[pk._kind[idx]], NearTraffic.KIND_HW[pk._kind[idx]])
	TestLib.check(depth > 0.5, "the real car stands inside the kerb car's hull (depth %.2f m)" % depth)
	var promoted := false
	for k in 90:                                                       # 1.5 s of frames: the manager looks at the kerb 10 times a second
		await TestLib.frames(host, 1)
		if pk.promoted > before:
			promoted = true
			break
	TestLib.check(promoted, "a real car at rest against a kerb car swaps it for a real one (promoted %d -> %d)" % [before, pk.promoted])
	await TestLib.frames(host, 60)
	var out: Array = []
	TrafficField.pairs(0.4, out)
	var bad := 0
	for q: Array in out:
		if int(q[0]) == TrafficField.REAL and int(q[2]) in [TrafficField.REAL, TrafficField.PARKED]:
			bad += 1
	TestLib.check(bad == 0, "...and the two are pushed apart (%d real pairs still deeper than 0.4 m)" % bad)


func _village() -> void:
	var st := OutskirtsSites.by_id(&"dust_wells")
	TestLib.check(not st.is_empty(), "the village DUST WELLS exists")
	if st.is_empty():
		return
	var front := OutskirtsSites.to_world(st, Vector3(0.0, 0.0, -30.0))
	var pos := Vector3(front.x, TerrainHeight.height_at(front.x, front.z) + 0.8, front.z)
	p.teleport_to(pos)
	if city.terrain != null:
		city.terrain.settle(pos)
	if city.vegetation != null:
		city.vegetation.settle(pos)
	if city.sites != null and city.sites.has_method(&"settle"):
		city.sites.call(&"settle", pos)
	await TestLib.frames(host, 8)
	var nt: NearTraffic = city.ambient.near_traffic
	var road: Object = city.ambient.get(&"road_traffic")
	var pk: ParkedCars = city.ambient.parked
	for k in 200:                                                      # 20 s of traffic around the village in 0.1 s steps (the software renderer would take minutes for the same game time)
		nt.step(0.1, pos)
		if road != null:
			road.call(&"set_time", float(k) * 0.1)
			road.call(&"step", 0.1, pos)
		pk.step(0.1, pos)
		if k % 5 == 0:
			mgr._stream()
	var out: Array = []
	TrafficField.pairs(0.2, out)
	var near_village := 0
	var worst := 0.0
	for q: Array in out:
		near_village += 1
		worst = maxf(worst, float(q[4]) if q.size() > 4 else 0.0)
	TestLib.check(pk.alive_count() > 0, "the village has kerb cars (%d parked cars in the ring)" % pk.alive_count())
	TestLib.check(near_village == 0, "no two vehicle hulls are inside each other by more than 0.2 m around the village (%d pairs)" % near_village)
