extends RefCounted
## BRIDGES, HARBOUR AND BOATS (wave 105). Data checks first, then the REAL game scene:
##  * Bridges: one per road crossing of a river or lake (the road bench is not cut under it, the river runs through, the deck rides 3+ m over the water), the HARBOUR GATE suspension bridge, two
##    footbridges and the rail trestle; deck_y / drive_height_at know the deck for a vehicle on it and ignore it for one far under it;
##  * Harbour: the carved quay (apron at the quay height, the basin dredged), the berths float in deep water, docks, hooks, the layout's collision boxes;
##  * live: BridgeWorld and HarbourWorld under the city within their mesh / triangle budgets, a sedan (real physics, steering along the bridge) drives over a road bridge and never leaves the deck,
##    the hero stands on a deck (physics ray + body), scenery traffic crosses the harbour gate, the ferry sails, boats (speedboat, jet ski, patrol boat) float at the surface, drive, turn, plane and
##    run aground at a quay instead of climbing it, the hero steps out onto a pier, the BOAT RUN pays and the dock hook fires.
## Run: tools/test.sh tests/test_bridges_harbour_boats.gd   (about 90 s; waits on positions, counters and game time, never on frame counts)

const TIMEOUT_SECONDS := 140.0
const K := 3

var _host: Node
var _p: Player
var _vm: VehicleManager
var _city: City


func run(host: Node) -> void:
	_host = host
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://boat_run.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_data()
	await _scene(host)


# --- data -------------------------------------------------------------------------------------------------------------------------------

func _data() -> void:
	TerrainHeight.warm()
	Bridges.ensure()
	var roads := 0
	var span_roads := 0
	var shared_ok := true
	var shared := 0
	for r: Dictionary in TerrainRoads.roads():
		var own: Array = r.get("bridge_spans", r["spans"])
		span_roads += own.size()
		for sp: Vector2i in r["spans"]:                                  # wave 112 critic: a span of a branch that runs on its parent's bridge (SUMMIT ROAD on the PASS ROAD bridge) has no deck of its own,
			if not own.has(sp):                                          # it must lie on the parent's: the deck under its middle sample
				var mid: int = (sp.x + sp.y) / 2
				var q: Vector2 = (r["pos"] as PackedVector2Array)[mid]
				shared += 1
				shared_ok = shared_ok and Bridges.on_deck(q.x, q.y, (r["prof"] as PackedFloat32Array)[mid])
	for b in Bridges.list:
		if b["kind"] in [&"road", &"track"]:
			roads += 1
	TestLib.check(span_roads + shared >= 4 and roads == span_roads, "every place where a road crosses water is a road bridge (%d spans with their own deck, %d bridges, %d shared with the road they run on)" % [span_roads, roads, shared])
	TestLib.check(shared_ok, "and a span without a deck of its own lies on the deck of the road it runs on")
	for k in [&"suspension", &"foot", &"rail"]:
		TestLib.check(Bridges.of_kind(k).size() >= 1, "there is a %s bridge" % k)
	TestLib.check(Bridges.of_kind(&"foot").size() >= 2, "two footbridges")
	var gate := Bridges.by_id(&"harbour_gate")
	TestLib.check(not gate.is_empty() and float(gate["len"]) > 500.0 and gate["name"] == "HARBOUR GATE BRIDGE", "the HARBOUR GATE suspension bridge is a landmark over 500 m long")
	# road bridges: clearance over the water, the river is not filled, the bench is not cut
	var worst_clear := 1.0e9
	var filled := false
	var in_span := true
	for b in Bridges.of_kind(&"road") + Bridges.of_kind(&"track"):
		var pts: PackedVector3Array = b["pts"]
		var mid := pts[pts.size() / 2]
		var water := TerrainHeight.water_level_at(mid.x, mid.z)
		if water != TerrainHeight.NO_WATER:
			worst_clear = minf(worst_clear, mid.y - water)
			if TerrainHeight.height_at(mid.x, mid.z) > mid.y - 2.0:
				filled = true
		in_span = in_span and TerrainRoads.in_span(mid.x, mid.z)
	TestLib.check(worst_clear >= 3.0, "every deck stands 3 m or more over the water it crosses (worst %.1f m)" % worst_clear)
	TestLib.check(not filled and in_span, "the river bed is not filled under a deck and TerrainRoads marks the span")
	# deck queries
	var b0: Dictionary = Bridges.of_kind(&"road")[0]
	var pts0: PackedVector3Array = b0["pts"]
	var m := pts0[pts0.size() / 2]
	TestLib.check(absf(Bridges.deck_y(m.x, m.z, m.y) - m.y) < 0.8, "deck_y on the centre line is the deck height (%.2f vs %.2f)" % [Bridges.deck_y(m.x, m.z, m.y), m.y])
	TestLib.check(Bridges.deck_y(m.x, m.z, m.y - 12.0) == Bridges.NONE, "something 12 m under the deck drives under it (no deck)")
	TestLib.check(Bridges.deck_y(m.x + 90.0, m.z + 90.0, m.y) == Bridges.NONE, "away from the bridge there is no deck")
	TestLib.check(TerrainHeight.drive_height_at(m.x, m.z, m.y) > TerrainHeight.height_at(m.x, m.z) + 2.0, "vehicles ride the deck, not the river bed")
	for fb in Bridges.of_kind(&"foot"):                                  # a footbridge crosses the water, high enough to keep the feet dry
		var fp: PackedVector3Array = fb["pts"]
		var fw := TerrainHeight.water_level_at(fp[1].x, fp[1].z)
		TestLib.check(fw != TerrainHeight.NO_WATER and fp[1].y - fw >= 1.5 and fp[1].y - fw < 8.0, "%s spans open water (%.1f m over it)" % [fb["name"], fp[1].y - fw if fw != TerrainHeight.NO_WATER else -99.0])
	var nb := Bridges.nearest(m)
	TestLib.check(nb[0] == b0 and float(nb[1]) < 1.0, "nearest() finds the bridge")
	# the harbour
	var A := Harbour.APRON
	TestLib.check(absf(TerrainHeight.height_at(A.position.x + 30.0, A.position.y + 130.0) - Harbour.QUAY_Y) < 0.05, "the apron is flat at the quay height")
	var basin_c := Harbour.center()
	TestLib.check(TerrainHeight.height_at(basin_c.x, basin_c.z) < -6.0 and TerrainHeight.depth_at(basin_c.x, basin_c.z) > 4.0, "the basin is dredged (%.1f m of water)" % TerrainHeight.depth_at(basin_c.x, basin_c.z))
	TestLib.check(Harbour.carve(900.0, 900.0, 5.0) == 5.0 and Harbour.carve(0.0, 0.0, 0.0) == 0.0 and Harbour.carve(-600.0, 1450.0, 3.0) == 3.0, "the harbour carve is local (it leaves the land outside its rectangle alone)")
	var deep := true
	for br in Harbour.BERTHS:
		var pos: Vector3 = br["pos"]
		deep = deep and TerrainHeight.depth_at(pos.x, pos.z) >= 3.0
	TestLib.check(deep and Harbour.BERTHS.size() >= 5, "every boat berth lies in deep water (%d berths)" % Harbour.BERTHS.size())
	var kinds := {}
	for br in Harbour.BERTHS:
		kinds[br["kind"]] = true
	TestLib.check(kinds.has(&"boat") and kinds.has(&"jetski") and kinds.has(&"patrol"), "berths for a speedboat, a jet ski and a patrol boat")
	TestLib.check(Harbour.on_dock(Harbour.PIER_X[0], 1450.0) and not Harbour.on_dock(-20.0, 1450.0) and Harbour.on_dock(-200.0, 1500.0), "docks: the pier deck and the quay are walkable, the water between the piers is not")
	TestLib.check(Harbour.exit_point(Vector3(-53.6, -2.0, 1448.0)).is_finite() and not Harbour.exit_point(Vector3(30.0, -2.0, 1700.0)).is_finite(), "a boat beside a pier has a place to step out, one in open water has not")
	var L := Harbour.layout()
	TestLib.check((L["containers"] as Array).size() >= 150 and (L["sheds"] as Array).size() >= 4 and (L["cranes"] as Array).size() >= 2 and (L["tanks"] as Array).size() >= 4, "the port has containers, warehouses, cranes and tanks (%d containers)" % (L["containers"] as Array).size())
	var hooks := BoatRun.hooks()
	TestLib.check(hooks.size() >= 10 and BoatRun.reward_for(30.0) > BoatRun.reward_for(120.0) and BoatRun.reward_for(120.0) >= BoatRun.PAY_BASE, "boat mission hooks: docks and buoys as data, a time bonus")
	TestLib.check(VehicleSpecs.SPECS.has(&"jetski") and VehicleSpecs.SPECS.has(&"patrol") and VehicleSpecs.name_of(&"jetski") == "JET SKI" and VehicleWeapons.has_weapon(&"patrol"), "jet ski and patrol boat are in the vehicle specs, the patrol boat is armed")
	# kit meshes build and stay small
	var tri_kit := BridgeWorld._tri_count(HarbourKit.kit())
	TestLib.check(tri_kit > 3000 and tri_kit < 24000, "the harbour kit is one mesh of %d triangles" % tri_kit)
	var tri_gate := BridgeWorld._tri_count(BridgeKit.structure(gate))
	TestLib.check(tri_gate > 1500 and tri_gate < 14000, "the suspension bridge is one mesh of %d triangles" % tri_gate)


# --- the real scene ---------------------------------------------------------------------------------------------------------------------

func _until(cond: Callable, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < secs:
		if cond.call():
			return true
		await _host.get_tree().process_frame
	return cond.call()


func _hold(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < secs:
		await _host.get_tree().process_frame


func _clear() -> void:
	Input.action_release(&"move_forward")
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	Input.action_release(&"move_back")
	if _vm.driven != null:
		_vm.exit_vehicle()
	for v in _vm.list.duplicate():
		if v != _vm.starter:
			_vm._release(v)


func _scene(host: Node) -> void:
	CarRadio.auto_headless = true
	Game.quality = 1
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	_p = Game.player as Player
	_vm = Game.vehicles as VehicleManager
	_city = Game.world as City
	TestLib.check(_p != null and _vm != null and _city != null, "the real scene has a city, a player and a vehicle manager")
	if _p == null or _vm == null or _city == null:
		main.queue_free()
		CarRadio.auto_headless = false
		return
	_p.set_physics_process(true)
	_p.max_hp = 1.0e6
	_p.hp = _p.max_hp
	(Game.enemies as EnemyManager).clear()
	_vm.stream_every = 1.0e9
	_vm._stream_t = 1.0e9
	for v in _vm.list.duplicate():
		if v != _vm.starter:
			_vm._release(v)
	if NearTraffic.instance != null:
		for i in NearTraffic.instance.count:
			NearTraffic.instance._alive[i] = 0
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	_live_nodes()
	await _bridge_drive()
	await _hero_on_deck()
	await _traffic_and_ferry()
	await _boats()
	await _boat_run()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	_clear()
	CarRadio.auto_headless = false
	main.queue_free()
	await TestLib.frames(host, 2)


func _live_nodes() -> void:
	var bw := BridgeWorld.instance
	var hw := HarbourWorld.instance
	TestLib.check(bw != null and hw != null and bw.get_parent() == _city and hw.get_parent() == _city, "the city has a BridgeWorld and a HarbourWorld")
	if bw == null or hw == null:
		return
	var st := bw.stats()
	TestLib.check(int(st["bridges"]) == Bridges.list.size() and int(st["shapes"]) > 20 and int(st["tris"]) < 40000, "bridges: %d, %d collision shapes, %d triangles" % [st["bridges"], st["shapes"], st["tris"]])
	var meshes := 0
	for n in bw.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
	TestLib.check(meshes <= Bridges.list.size() * 2 + 2, "at most two draw calls per bridge (%d meshes)" % meshes)
	var hm := 0
	for n in hw.find_children("*", "MeshInstance3D", true, false):
		hm += 1
	var hs := hw.stats()
	TestLib.check(hm <= 7 and int(hs["tris"]) < 30000 and int(hs["boxes"]) > 30, "the harbour is %d meshes (four, the ferry and two beams), %d triangles, %d collision boxes" % [hm, hs["tris"], hs["boxes"]])
	TestLib.check(hw.run != null and is_instance_valid(hw.ferry), "the harbour owns the boat run and the ferry")


## A sedan drives over the DESERT ROAD bridge with real physics (a steering helper keeps it on the carriageway): it stays on the deck height the whole way and gets across.
func _bridge_drive() -> void:
	_clear()
	var b: Dictionary = {}
	for cand in Bridges.of_kind(&"road"):
		if cand["road"] == "DESERT ROAD":
			b = cand
	if b.is_empty():
		b = Bridges.of_kind(&"road")[0]
	var pts: PackedVector3Array = b["pts"]
	var d0 := Vector3(pts[1].x - pts[0].x, 0.0, pts[1].z - pts[0].z).normalized()
	var start := pts[0] - d0 * 30.0
	var total := float(b["len"])
	_p.teleport_to(Vector3(start.x, TerrainHeight.height_at(start.x, start.z) + 1.0, start.z))
	await _hold(0.6)
	var car := _vm.spawn_parked(&"sedan", Vector3(start.x, 0.0, start.z), atan2(-d0.x, -d0.z))
	TestLib.check(car != null, "a sedan is spawned in front of the %s" % b["name"])
	if car == null:
		return
	car.global_position = Vector3(start.x, TerrainHeight.height_at(start.x, start.z), start.z)
	car.update_lod(0.0)
	_p.teleport_to(car.global_position + car.right() * 2.4)
	await _hold(0.3)
	_vm.enter(car)
	var worst := 0.0
	var on_deck_frames := 0
	var crossed := false
	var max_u := 0.0
	var t0 := Time.get_ticks_msec()
	Input.action_press(&"move_forward")
	while float(Time.get_ticks_msec() - t0) / 1000.0 < 25.0 and not crossed:
		await _host.get_tree().physics_frame
		var cp := car.global_position
		# progress along the bridge and the steering target 14 m ahead on its centre line
		var best_u := 0.0
		var bd := 1.0e9
		var acc := 0.0
		for s in pts.size() - 1:
			var a := Vector2(pts[s].x, pts[s].z)
			var c := Vector2(pts[s + 1].x, pts[s + 1].z)
			var l := a.distance_to(c)
			var t := clampf((Vector2(cp.x, cp.z) - a).dot(c - a) / maxf((c - a).length_squared(), 1.0e-6), 0.0, 1.0)
			var dd := Vector2(cp.x, cp.z).distance_to(a + (c - a) * t)
			if dd < bd:
				bd = dd
				best_u = acc + t * l
			acc += l
		max_u = maxf(max_u, best_u)
		var ahead := Bridges.point_at(b, minf(best_u + 14.0, total + 30.0))
		var tp: Vector3 = ahead[0]
		var want := atan2(-(tp.x - cp.x), -(tp.z - cp.z))
		var err := wrapf(want - car.heading, -PI, PI)
		if best_u >= total - 1.0 and bd < 12.0:
			want = atan2(-d0.x, -d0.z)
		Input.action_release(&"move_left")
		Input.action_release(&"move_right")
		if err > 0.05:
			Input.action_press(&"move_left")
		elif err < -0.05:
			Input.action_press(&"move_right")
		var dy := Bridges.deck_y(cp.x, cp.z, cp.y)
		if dy != Bridges.NONE and best_u > 4.0 and best_u < total - 4.0:
			on_deck_frames += 1
			worst = maxf(worst, absf(cp.y - dy))
		if best_u >= total - 2.0 and Vector2(cp.x - pts[pts.size() - 1].x, cp.z - pts[pts.size() - 1].z).length() < 6.0:
			crossed = true
	Input.action_release(&"move_forward")
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	TestLib.check(crossed, "the sedan drives over %s to the far side (progress %.0f of %.0f m)" % [b["name"], max_u, total])
	TestLib.check(on_deck_frames > 20 and worst < 1.0, "it rode the deck the whole way (%d frames on the deck, worst height error %.2f m)" % [on_deck_frames, worst])
	TestLib.check(car.hp > car.max_hp * 0.7, "and was not wrecked by the parapets (hp %.0f of %.0f)" % [car.hp, car.max_hp])
	_clear()


## The hero stands on a deck: a physics ray from above hits the deck body at the deck height, and a hero placed on it does not fall through in a second.
func _hero_on_deck() -> void:
	_clear()
	var b := Bridges.by_id(&"harbour_gate")
	var mid: Array = Bridges.point_at(b, 40.0)
	var pos: Vector3 = mid[0]
	_p.teleport_to(pos + Vector3(0.0, 2.5, 0.0))
	await _hold(1.5)
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(2.0, 12.0, 0.0), pos + Vector3(2.0, -6.0, 0.0), Game.L_WORLD)
	var hit := _p.get_world_3d().direct_space_state.intersect_ray(q)
	TestLib.check(not hit.is_empty() and absf((hit["position"] as Vector3).y - pos.y) < 0.15, "a ray finds the deck of the harbour gate at the deck height (%s)" % [str(hit.get("position", "none"))])
	TestLib.check(_p.global_position.y > pos.y - 0.4 and _p.global_position.y < pos.y + 3.0, "the hero stands on the deck (y %.2f, deck %.2f)" % [_p.global_position.y, pos.y])


func _traffic_and_ferry() -> void:
	var bw := BridgeWorld.instance
	var hw := HarbourWorld.instance
	var b := Bridges.by_id(&"harbour_gate")
	var pos: Vector3 = (Bridges.point_at(b, 300.0))[0]
	_p.teleport_to(pos + Vector3(0.0, 2.5, 0.0))
	var woke := await _until(func() -> bool:
		for t in bw.traffic:
			if t.active and t.bridge["id"] == &"harbour_gate":
				return true
		return false, 5.0)
	TestLib.check(woke, "scenery traffic wakes up when the hero is on the harbour gate")
	var tr: BridgeTraffic = null
	for t in bw.traffic:
		if t.active and t.bridge["id"] == &"harbour_gate":
			tr = t
	if tr != null:
		var m0 := tr.moved
		await _hold(2.5)
		TestLib.check(tr.moved > m0 + 8.0 and tr.deck_error() < 0.5, "a car crosses the bridge on its deck (%.0f m in 2.5 s, deck error %.2f)" % [tr.moved - m0, tr.deck_error()])
	# the ferry leaves its landing and sails
	hw._dock_t = 0.0
	var sailing := await _until(func() -> bool: return hw.ferry_state != &"docked" and hw.ferry_u > 10.0, 12.0)
	TestLib.check(sailing and hw.ferry.visible, "the ferry leaves its landing and sails (u %.0f m, %s)" % [hw.ferry_u, hw.ferry_state])
	var wy := WaterWorld.surface_y(hw.ferry_pos.x, hw.ferry_pos.z)
	TestLib.check(wy != TerrainHeight.NO_WATER and absf(hw.ferry_pos.y - (wy - 0.5)) < 1.5, "and floats on the water (y %.2f, water %.2f)" % [hw.ferry_pos.y, wy])


func _spawn_berth(id: StringName) -> Vehicle:
	_clear()
	var pt := VehicleSpawns.point(id)
	var pos: Vector3 = pt["pos"]
	_vm._spawned.clear()
	_vm._spawn_ready.clear()
	var stand := Harbour.exit_point(pos, 12.0)
	_p.teleport_to(stand + Vector3(0.0, 0.2, 0.0) if stand.is_finite() else Vector3(Harbour.PIER_X[0], Harbour.QUAY_Y + 0.3, 1440.0))
	await _hold(0.4)
	_vm._spawn_t = 0.0
	var got := await _until(func() -> bool:
		var v: Variant = _vm._spawned.get(id)
		return is_instance_valid(v) and (v as Vehicle).active, 8.0)
	if not got:
		return null
	var car := _vm._spawned[id] as Vehicle
	car.update_lod(0.0)
	return car


func _boats() -> void:
	var boat := await _spawn_berth(&"dock_speed_a")
	TestLib.check(boat != null and boat.kind == &"boat", "the harbour berth puts a speedboat on the water when the hero comes near")
	if boat == null:
		return
	var wy := WaterWorld.surface_y(boat.global_position.x, boat.global_position.z)
	TestLib.check(boat.craft.sea and absf(boat.global_position.y - (wy - float(boat.spec["draft"]))) < 0.6, "it floats at the surface (y %.2f, water %.2f, draft %.2f)" % [boat.global_position.y, wy, float(boat.spec["draft"])])
	# the hero walks up on the pier and gets in
	_p.teleport_to(Vector3(Harbour.PIER_X[0] + 4.0, Harbour.QUAY_Y + 0.3, 1448.0))
	await _hold(0.5)
	_vm.enter(boat)
	var in_boat := _vm.driven == boat and _p.vehicle == boat
	TestLib.check(in_boat, "the hero steps from the pier into the speedboat")
	var start := boat.global_position
	Input.action_press(&"move_forward")
	var moved := await _until(func() -> bool: return Vector2(boat.global_position.x - start.x, boat.global_position.z - start.z).length() > 30.0 and boat.speed > 9.0, 16.0)
	var planed := await _until(func() -> bool: return boat.craft.planing > 0.1, 6.0)
	TestLib.check(planed, "at speed the hull planes (%.2f at %.1f m/s)" % [boat.craft.planing, boat.speed])
	var h0 := boat.heading
	Input.action_press(&"move_right")
	await _hold(0.25)
	Input.action_release(&"move_right")
	var turned := wrapf(boat.heading - h0, -PI, PI) < -0.15
	var sea := TerrainHeight.depth_at(boat.global_position.x, boat.global_position.z) > float(boat.spec["draft"]) + 0.5
	TestLib.check(moved and turned and sea and boat.craft.sea, "it drives out of the basin (%.0f m, %.1f m/s), turns right with the stick (%.2f rad) and stays in deep water (%.1f m)" % [Vector2(boat.global_position.x - start.x, boat.global_position.z - start.z).length(), boat.speed, wrapf(boat.heading - h0, -PI, PI), TerrainHeight.depth_at(boat.global_position.x, boat.global_position.z)])
	Input.action_release(&"move_forward")
	# run it into the west quay: it must not climb the wall or the land
	boat.global_position = Vector3(-70.0, boat.global_position.y, 1520.0)
	boat.heading = PI * 0.5
	boat.vel = Vector3.ZERO
	boat.craft.last_wet = boat.global_position
	Input.action_press(&"move_forward")
	await _hold(5.0)
	Input.action_release(&"move_forward")
	var bp := boat.global_position
	TestLib.check(bp.x > Harbour.BASIN.position.x - 0.5 and TerrainHeight.depth_at(bp.x, bp.z) >= float(boat.spec["draft"]) + 0.3, "driven at the quay wall the boat stops in the water (x %.1f, depth %.1f)" % [bp.x, TerrainHeight.depth_at(bp.x, bp.z)])
	# step out onto the pier
	boat.global_position = Vector3(Harbour.PIER_X[0] + Harbour.PIER_W * 0.5 + 2.4, boat.global_position.y, 1450.0)
	boat.vel = Vector3.ZERO
	boat.craft.last_wet = boat.global_position
	boat.heading = PI
	await _hold(0.4)
	_vm.exit_vehicle()
	await _hold(0.5)
	var hp := _p.global_position
	TestLib.check(_vm.driven == null and Harbour.on_dock(hp.x, hp.z, 1.0) and hp.y > Harbour.QUAY_Y - 0.5, "leaving the boat beside a pier puts the hero on the pier (%.1f, %.1f, %.1f)" % [hp.x, hp.y, hp.z])
	# jet ski and patrol boat
	for id: StringName in [&"dock_ski_a", &"dock_patrol"]:
		var v := await _spawn_berth(id)
		TestLib.check(v != null and v.craft != null and v.craft.sea, "%s: waits at its berth on the water" % id)
		if v == null:
			continue
		_p.teleport_to(v.global_position + Vector3(v.right().x, 0.0, v.right().z) * 3.0 + Vector3(0.0, 4.0, 0.0))
		await _hold(0.4)
		_vm.enter(v)
		var s0 := v.global_position
		Input.action_press(&"move_forward")
		var ok := await _until(func() -> bool: return Vector2(v.global_position.x - s0.x, v.global_position.z - s0.z).length() > 25.0, 16.0)
		Input.action_release(&"move_forward")
		TestLib.check(ok and v.craft.sea and v.hp > v.max_hp * 0.8, "%s: drives %.0f m on the water at %.1f m/s" % [id, Vector2(v.global_position.x - s0.x, v.global_position.z - s0.z).length(), v.speed])
		if id == &"dock_ski_a":
			TestLib.check(float(VehicleSpecs.SPECS[&"jetski"]["max"]) > float(VehicleSpecs.SPECS[&"boat"]["max"]) and float(VehicleSpecs.SPECS[&"patrol"]["hp"]) > float(VehicleSpecs.SPECS[&"boat"]["hp"]) * 2.0, "the jet ski is the fastest, the patrol boat the toughest")
	_clear()


func _boat_run() -> void:
	var hw := HarbourWorld.instance
	var run := hw.run
	var boat := await _spawn_berth(&"dock_speed_b")
	if boat == null or run == null:
		TestLib.check(false, "a boat for the boat run")
		return
	var prog := Game.progress as Progress
	var c0 := prog.credits if prog != null else 0
	var got := {"started": 0, "checkpoints": 0, "finished": 0, "reward": 0, "docked": 0}
	run.started.connect(func() -> void: got["started"] += 1)
	run.checkpoint.connect(func(_i: int) -> void: got["checkpoints"] += 1)
	run.finished.connect(func(_s: float, ok: bool, rw: int) -> void:
		if ok:
			got["finished"] += 1
			got["reward"] = rw)
	run.docked.connect(func(_id: StringName, _b: Vehicle) -> void: got["docked"] += 1)
	run.player_boat = boat
	boat.global_position = Vector3(Harbour.COURSE[0].x, boat.global_position.y, Harbour.COURSE[0].z)
	run.step(0.1)
	TestLib.check(run.running and got["started"] == 1, "driving through the start buoy begins the BOAT RUN")
	for i in range(1, Harbour.COURSE.size()):
		boat.global_position = Vector3(Harbour.COURSE[i].x, boat.global_position.y, Harbour.COURSE[i].z)
		run.step(2.0)
	TestLib.check(not run.running and got["finished"] == 1 and got["reward"] >= BoatRun.PAY_BASE and run.best > 0.0, "taking every buoy finishes it and pays (%d credits, %.1f s)" % [got["reward"], run.best])
	if prog != null:
		TestLib.check(prog.credits >= c0 + int(got["reward"]), "the credits arrive in the wallet (%d -> %d)" % [c0, prog.credits])
	# the dock hook: a slow boat inside a dock's radius fires `docked` once
	var dock := Harbour.dock(&"pier_b")
	var dp: Vector3 = dock["pos"]
	boat.global_position = Vector3(dp.x, boat.global_position.y, dp.z + 3.0)
	boat.speed = 0.0
	run.step(0.5)
	run.step(0.6)
	run.step(0.6)
	TestLib.check(got["docked"] == 1, "a boat held at PIER B fires the docked hook once (%d)" % got["docked"])
	# leaving the boat ends a running run quietly
	run.begin()
	run.player_boat = null
	_clear()
	run.step(0.1)
	TestLib.check(not run.running, "leaving the boat ends a run in progress")
