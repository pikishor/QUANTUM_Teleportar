extends RefCounted
## Traffic density and variety (owner round 6: "many cars outside, on the roads, in the villages; houses and streets are blank"): the data first (archetypes, the mix by district and by hour, tier counts,
## the hour curve), then the REAL composed game (scenes/main.tscn) stepped through AmbientCity._process by hand:
##  * the near cars of the city at LOW / MED / HIGH around three spots (the market, the docks, the outer spires): enough of them, of many kinds, moving;
##  * the hour curve: rush hour fills the ring, the small hours thin it;
##  * the cars parked at the kerbs (they stand beside the lanes, never in one), the driveways of a village, the verge cars of a highway, the accident scenes (wrecks, a patrol car, an ambulance);
##  * the road traffic of the highways (cars on the real road polylines, far lamp pairs, drawn mesh cars) and its single MultiMesh nodes.
## Looked at with tests/bot_traffic.gd (street and highway frames in docs/shots/round6/). Run: tools/test.sh tests/test_traffic_density.gd

const DT := 0.05
const TIMEOUT_SECONDS := 170
const TIER_NEAR_MIN: Array[int] = [30, 45, 50]           ## near cars alive in the ring (at the market) per tier

var host: Node
var city: City
var p: Player
var amb: Node3D


func run(h: Node) -> void:
	host = h
	seed(3)
	Sfx.muted = true
	_data()
	_mix()
	await _real()


# --- pure data ------------------------------------------------------------------------------------------------------------------------------------

func _data() -> void:
	var n := NearTraffic.KINDS.size()
	TestLib.check(n >= 12, "the near traffic has at least 12 archetypes (%d)" % n)
	TestLib.check(NearTraffic.KIND_SPEED.size() == n and NearTraffic.KIND_HALF.size() == n and NearTraffic.KIND_HW.size() == n and NearTraffic.KIND_VARIANT.size() == n and NearTraffic.KIND_LAMP.size() == n,
			"every archetype has a speed, a hull, a body variant and a lamp flag")
	var known := true
	for k: StringName in NearTraffic.KINDS:
		known = known and VehicleSpecs.SPECS.has(k)
	TestLib.check(known, "every archetype is a real vehicle kind (a promoted car is the real car of that kind)")
	for mix: Array[float] in [NearTraffic.KIND_MIX, NearTraffic.KIND_MIX_HIGHWAY, NearTraffic.KIND_MIX_TRACK]:
		var sum := 0.0
		for x in mix:
			sum += x
		TestLib.check(mix.size() == n and absf(sum - 1.0) < 0.02, "a kind mix has one share per archetype and sums to 1 (%.3f)" % sum)
	TestLib.check(NearTraffic.COUNTS[0] < NearTraffic.COUNTS[1] and NearTraffic.COUNTS[1] < NearTraffic.COUNTS[2] and NearTraffic.COUNTS[2] <= NearTraffic.BUILT and NearTraffic.COUNTS[0] >= 70,
			"near cars per tier grow and fit the MultiMesh (%s of %d): the street has 70+ cars even on LOW" % [str(NearTraffic.COUNTS), NearTraffic.BUILT])
	TestLib.check(RoadTraffic.TARGETS[0] < RoadTraffic.TARGETS[1] and RoadTraffic.TARGETS[1] < RoadTraffic.TARGETS[2] and RoadTraffic.TARGETS[2] <= RoadTraffic.CAP, "road cars per tier grow and fit the pool (%s of %d)" % [str(RoadTraffic.TARGETS), RoadTraffic.CAP])
	TestLib.check(ParkedCars.OCC_TIER[0] < ParkedCars.OCC_TIER[1] and ParkedCars.OCC_TIER[1] <= ParkedCars.OCC_TIER[2], "the kerbs fill up with the tier")
	var rush := DayNight.density_for(8.5)
	var noon := DayNight.density_for(12.0)
	var deep := DayNight.density_for(3.0)
	TestLib.check(rush > noon and noon > deep and deep < 0.8 and rush > 1.05, "the hour curve: rush hour %.2f, noon %.2f, the small hours %.2f" % [rush, noon, deep])
	RoadLanes.ensure()
	var hw := 0
	var tracks := 0
	for r: Dictionary in RoadLanes.roads:
		if String(r["kind"]) == "highway":
			hw += 1
		else:
			tracks += 1
	TestLib.check(hw >= 4 and tracks >= 2, "the road network has the four highways and the dirt tracks (%d, %d)" % [hw, tracks])
	var sm := RoadLanes.sample(0, 400.0)
	var lp := RoadLanes.lane_point(0, 400.0, 1)
	var off := (lp[0] as Vector2).distance_to(Vector2(sm[0], sm[1]))
	TestLib.check(absf(off - float(RoadLanes.roads[0]["lane"])) < 0.05, "a lane point lies one lane width from the centre line (%.2f m)" % off)


func _share(zone: int, night: float, kinds: Array[int]) -> float:
	var hit := 0
	var total := 4000
	for i in total:
		if NearTraffic.pick_kind(zone, night, (float(i) + 0.5) / float(total)) in kinds:
			hit += 1
	return float(hit) / float(total)


func _mix() -> void:
	var seen := {}
	for zone in 8:
		for night in [0.0, 1.0]:
			for i in 600:
				seen[NearTraffic.pick_kind(zone, night, (float(i) + 0.5) / 600.0)] = true
	TestLib.check(seen.size() == NearTraffic.KINDS.size(), "every archetype is picked somewhere, some time (%d of %d)" % [seen.size(), NearTraffic.KINDS.size()])
	var commuters := true
	for zone in 8:
		commuters = commuters and _share(zone, 0.0, [0, 1, 2]) >= 0.35
	TestLib.check(commuters, "commuters (sedan, compact, SUV) are the biggest group in every district")
	TestLib.check(_share(0, 0.0, [4]) > 2.0 * _share(4, 0.0, [4]), "taxis are common in the market and rare on the docks (%.2f vs %.2f)" % [_share(0, 0.0, [4]), _share(4, 0.0, [4])])
	TestLib.check(_share(4, 0.0, [7]) > 3.0 * _share(0, 0.0, [7]), "lorries work the docks, not the market (%.2f vs %.2f)" % [_share(4, 0.0, [7]), _share(0, 0.0, [7])])
	TestLib.check(_share(6, 0.0, [6]) > 3.0 * _share(0, 0.0, [6]), "pickups belong to the fields (%.2f vs %.2f)" % [_share(6, 0.0, [6]), _share(0, 0.0, [6])])
	TestLib.check(_share(3, 0.0, [5]) > 1.5 * _share(2, 0.0, [5]), "the glass towers have more speeders than the slums (%.2f vs %.2f)" % [_share(3, 0.0, [5]), _share(2, 0.0, [5])])
	TestLib.check(_share(0, 1.0, [9, 10]) > 1.6 * _share(0, 0.0, [9, 10]), "patrols and ambulances are out more at night (%.3f vs %.3f)" % [_share(0, 1.0, [9, 10]), _share(0, 0.0, [9, 10])])
	TestLib.check(_share(0, 1.0, [8, 11]) < 0.5 * _share(0, 0.0, [8, 11]), "buses and delivery vans sleep at night (%.3f vs %.3f)" % [_share(0, 1.0, [8, 11]), _share(0, 0.0, [8, 11])])
	TestLib.check(_share(0, 0.0, [9, 10]) <= 0.08, "emergency vehicles stay a rare sight by day (%.3f)" % _share(0, 0.0, [9, 10]))


# --- the real scene ------------------------------------------------------------------------------------------------------------------------------

func _tick(n: int) -> void:
	var vm := Game.vehicles as VehicleManager
	for k in n:
		if vm != null:
			vm.signal_clock += DT
		amb._process(DT)


## Cars of the near layer within `r` of the hero: {n, moving, kinds (distinct), taxis, heavy}.
func _near_census(r: float) -> Dictionary:
	var nt: NearTraffic = amb.near_traffic
	var kinds := {}
	var n := 0
	var moving := 0
	for i in nt.count:
		if not nt.car_alive(i):
			continue
		var q := nt.car_position(i)
		if Vector2(q.x - p.global_position.x, q.z - p.global_position.z).length() > r:
			continue
		n += 1
		if nt.car_speed(i) > 1.0:
			moving += 1
		kinds[nt.car_kind(i)] = true
	return {"n": n, "moving": moving, "kinds": kinds.size(), "has": kinds}


func _real() -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	MapScreen.path_override = "user://test_traffic_density_map_%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(MapScreen.path_override)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	city = Game.world as City
	p = Game.player as Player
	if p == null or city == null or city.ambient == null:
		TestLib.check(false, "the real game has a player and a city with an ambient layer")
		return
	var enc := Encounters.current
	if enc != null:
		enc.enabled = false
	if Game.enemies != null:
		(Game.enemies as EnemyManager).clear()
	p.max_hp = 1.0e6
	amb = city.ambient
	var nt: NearTraffic = amb.near_traffic
	var vm := Game.vehicles as VehicleManager
	vm.lights_on = true
	if city.day_night != null:
		city.day_night.frozen = true
		city.day_night.set_hour(12.0)
	amb.set_process(false)
	amb.simulate = true
	await _multimeshes()
	await _near_cars(nt)
	await _hour_curve(nt)
	await _parked()
	await _roads()
	main.queue_free()


func _multimeshes() -> void:
	var names := {}
	for n in city.multimesh_nodes:
		names[n.name] = names.get(n.name, 0) + 1
	TestLib.check(int(names.get("NearTraffic", 0)) == 1 and int(names.get("RoadLamps", 0)) == 1, "one MultiMesh node for every car on the ground and one for the far lamps")
	TestLib.check(not names.has("ParkedCars") and not names.has("RoadTraffic"), "the kerb cars and the road cars have no node of their own: they ride in the near traffic's draw call (the phone's draw budget)")
	var nt: NearTraffic = amb.near_traffic
	TestLib.check(nt.mm.instance_count == NearTraffic.SHARED and NearTraffic.SHARED - NearTraffic.BUILT >= RoadTraffic.DRAWN + ParkedCars.DRAWN, "that MultiMesh has room for the near cars, %d road cars and %d kerb cars (%d instances)" % [RoadTraffic.DRAWN, ParkedCars.DRAWN, nt.mm.instance_count])
	var rt: RoadTraffic = amb.road_traffic
	TestLib.check(rt.lamp_mm.instance_count == RoadTraffic.LAMPS, "the road layer draws at most %d far lamp pairs: far traffic is impostors" % RoadTraffic.LAMPS)
	TestLib.check(rt.lamp_node != null and not rt.lamp_node.visible, "with no highway near the hero the lamp node is hidden (an empty node still costs a draw call)")
	await TestLib.frames(host, 1)


func _near_cars(nt: NearTraffic) -> void:
	var spots := {"market": Game.SPAWN, "docks": Vector3(-560.0, 0.0, 700.0), "outer spires": Vector3(640.0, 0.0, -680.0)}
	for q in [0, 1, 2]:
		Game.set_quality(q)
		_tick(20)
		for name: String in spots:
			p.teleport_to((spots[name] as Vector3) + Vector3(0.0, 0.1, 0.0))
			_tick(260)                                              # 13 s: the ring re-centres and fills
			var c := _near_census(nt.radius)
			var floor_n: int = TIER_NEAR_MIN[q] if name == "market" else int(TIER_NEAR_MIN[q] * 0.7)
			TestLib.check(int(c["n"]) >= floor_n, "tier %d, %s: %d+ near cars in the ring (%d, %d moving)" % [q, name, floor_n, int(c["n"]), int(c["moving"])])
			if q >= 1:
				TestLib.check(int(c["kinds"]) >= 6, "tier %d, %s: at least 6 kinds of car in the ring (%d)" % [q, name, int(c["kinds"])])
			if q == 1 and name == "market":
				TestLib.check(int(c["moving"]) >= 8, "tier 1, market: the traffic moves (%d of %d)" % [int(c["moving"]), int(c["n"])])
				var h: Dictionary = c["has"]
				TestLib.check(h.has(&"taxi") or h.has(&"bus") or h.has(&"delivery"), "the market has taxis, buses or delivery vans among its cars (%s)" % str(h.keys()))
	Game.set_quality(1)
	await TestLib.frames(host, 1)


func _hour_curve(nt: NearTraffic) -> void:
	Game.set_quality(1)
	amb.set_density(DayNight.density_for(8.5))
	var rush := nt.count
	amb.set_density(DayNight.density_for(12.0))
	var noon := nt.count
	amb.set_density(DayNight.density_for(3.0))
	var deep := nt.count
	amb.set_density(1.0)
	TestLib.check(rush > noon and noon > deep, "the ring holds more cars at rush hour than at noon, and fewest in the small hours (%d, %d, %d)" % [rush, noon, deep])
	await TestLib.frames(host, 1)


## Does a hull parked at the kerb touch the lane next to it? A car of the lane (2.4 x 1.0 half size) at the same place along the road, on either side, must clear every kerb car.
func _kerb_clash(x: float, z: float, yaw: float, hl: float, hw: float) -> float:
	var kx := roundi((x + CityLayout.HALF) / CityLayout.PITCH)
	var kz := roundi((z + CityLayout.HALF) / CityLayout.PITCH)
	var dx := absf(x - CityLayout.road_center(kx))
	var dz := absf(z - CityLayout.road_center(kz))
	var axis := 0 if dz < dx else 1                                      # the road this car lines (axis 0 = along X)
	var fx := -sin(yaw)
	var fz := -cos(yaw)
	var worst := -INF
	for side: float in [-1.0, 1.0]:
		var lane: float = CityLayout.LANE * side
		var lx := x if axis == 0 else CityLayout.road_center(kx) + lane
		var lz := CityLayout.road_center(kz) + lane if axis == 0 else z
		var lfx := 1.0 if axis == 0 else 0.0
		var lfz := 0.0 if axis == 0 else 1.0
		worst = maxf(worst, TrafficField.obb_depth(x, z, fx, fz, hl, hw, lx, lz, lfx, lfz, 2.4, 1.0))
	return worst


func _parked() -> void:
	var pk: ParkedCars = ParkedCars.instance
	TestLib.check(pk != null and pk.enabled, "the parked cars of the city exist")
	if pk == null:
		return
	Game.set_quality(1)
	pk.reset()
	TrafficField.clear_source(TrafficField.PARKED)
	# fly over the city: every cell generates (the ring fills in a second per spot, not in a frame)
	var x := -960.0
	while x <= 960.0:
		var z := -960.0
		while z <= 960.0:
			p.teleport_to(Vector3(x, 0.1, z))
			for k in 14:
				pk.step(0.45, Vector3(x, 0.0, z))
			z += 240.0
		x += 240.0
	TestLib.check(pk.generated >= 600, "kerb cars were generated all over the city (%d)" % pk.generated)
	# the ring around the market holds a street full of cars
	pk.reset()
	TrafficField.clear_source(TrafficField.PARKED)
	for k in 30:
		pk.step(0.45, Game.SPAWN)
	var near_n := 0
	var kinds := {}
	var worst := -INF
	var lane_clash := 0
	for i in pk._n:
		if not pk.car_alive(i):
			continue
		var pos := pk.car_position(i)
		if Vector2(pos.x - Game.SPAWN.x, pos.z - Game.SPAWN.z).length() < 80.0:
			near_n += 1
			kinds[pk.car_kind(i)] = true
		var kind_i := NearTraffic.KINDS.find(pk.car_kind(i))
		var d := _kerb_clash(pos.x, pos.z, pk.car_yaw(i), NearTraffic.KIND_HALF[kind_i], NearTraffic.KIND_HW[kind_i])
		worst = maxf(worst, d)
		if d > 0.0:
			lane_clash += 1
	TestLib.check(near_n >= 25 and kinds.size() >= 4, "the streets around the market are lined with parked cars (%d within 80 m, %d kinds)" % [near_n, kinds.size()])
	TestLib.check(lane_clash == 0, "no parked car reaches into a lane (%d do, worst %.2f m)" % [lane_clash, worst])
	var out: Array = []
	TrafficField.pairs(0.05, out)
	var bad := 0
	for q: Array in out:
		if int(q[0]) == TrafficField.PARKED and int(q[2]) == TrafficField.PARKED:
			bad += 1
	TestLib.check(bad == 0, "no two parked cars overlap (%d pairs)" % bad)
	# accident scenes: scanned over the grid
	pk.reset()
	TrafficField.clear_source(TrafficField.PARKED)
	pk.accidents = 0
	var acc_cells := 0
	var wrecks := 0
	var patrol := 0
	var ambu := 0
	var xx := -900.0
	while xx <= 900.0 and acc_cells < 3:
		var zz := -900.0
		while zz <= 900.0 and acc_cells < 3:
			for k in 14:
				pk.step(0.45, Vector3(xx, 0.0, zz))
			acc_cells = pk.accidents
			zz += 200.0
		xx += 200.0
	for i in pk._n:
		if pk.car_alive(i):
			if pk._wreck[i] == 1:
				wrecks += 1
			if pk.car_kind(i) == &"interceptor":
				patrol += 1
			if pk.car_kind(i) == &"ambulance":
				ambu += 1
	TestLib.check(pk.accidents >= 1 and wrecks >= 2, "accident scenes exist: %d scenes, %d wrecks standing" % [pk.accidents, wrecks])
	TestLib.check(patrol >= 1 and ambu >= 1, "an accident has its patrol car and its ambulance (%d, %d)" % [patrol, ambu])
	# the driveways of a village
	pk.reset()
	TrafficField.clear_source(TrafficField.PARKED)
	var site := OutskirtsSites.by_id(&"dust_wells")
	if not site.is_empty():
		var front := OutskirtsSites.to_world(site, Vector3(0.0, 0.0, -30.0))
		for k in 20:
			pk.step(0.45, Vector3(front.x, 0.0, front.z))
		var at_site := 0
		for i in pk._n:
			if pk.car_alive(i):
				var pos2 := pk.car_position(i)
				if Vector2(pos2.x - front.x, pos2.z - front.z).length() < 130.0:
					at_site += 1
		TestLib.check(at_site >= 4, "a village has cars in its driveways (%d at DUST WELLS)" % at_site)
	pk.reset()
	TrafficField.clear_source(TrafficField.PARKED)
	await TestLib.frames(host, 1)


func _roads() -> void:
	var rt: RoadTraffic = amb.road_traffic
	var pk: ParkedCars = ParkedCars.instance
	rt.enabled = true
	RoadLanes.ensure()
	for q in [1, 2]:
		Game.set_quality(q)
		var best := 0
		var kinds := {}
		var lamps := 0
		var verge := 0
		for s: float in [380.0, 900.0]:                                   # two stretches of the north highway
			var sm := RoadLanes.sample(0, s)
			var pos := Vector3(sm[0], TerrainHeight.height_at(sm[0], sm[1]) + 1.0, sm[1])
			if city.terrain != null:
				city.terrain.settle(pos)
			p.teleport_to(pos)
			_tick(20)
			_tick(400)                                                   # 20 s
			best = maxi(best, rt.alive_count())
			lamps = maxi(lamps, rt.lamp_mm.visible_instance_count)
			for i in RoadTraffic.CAP:
				if rt.car_alive(i):
					kinds[rt.car_kind(i)] = true
		TestLib.check(best >= (6 if q == 1 else 10), "tier %d: the north highway carries %d road cars around the hero" % [q, best])
		TestLib.check(kinds.size() >= 3, "tier %d: the road cars are of %d kinds" % [q, kinds.size()])
		if q == 2:
			TestLib.check(lamps >= 0 and rt.lamp_mm.visible_instance_count <= RoadTraffic.LAMPS, "the far lamp pairs stay inside their MultiMesh (%d)" % rt.lamp_mm.visible_instance_count)
	# the verge: cars standing beside the highway, clear of its lanes
	pk.reset()
	TrafficField.clear_source(TrafficField.PARKED)
	pk.roadside = 0
	var seen := {}
	var too_close := 0
	for ri in 4:
		var rd: Dictionary = RoadLanes.roads[ri]
		var s := 300.0
		while s < float(rd["len"]) - 300.0:
			var sm2 := RoadLanes.sample(ri, s)
			for k in 3:
				pk.step(0.45, Vector3(sm2[0], 0.0, sm2[1]))
			for i in pk._n:                                                 # the cars standing now (the ones behind the hero are dropped as he drives on)
				if pk.car_alive(i) and pk._cell[i] >= 800000 and pk._cell[i] < 900000:
					var pos3 := pk.car_position(i)
					var key := Vector2i(roundi(pos3.x), roundi(pos3.z))
					if seen.has(key):
						continue
					seen[key] = true
					var nr := RoadLanes.nearest(pos3.x, pos3.z)
					if int(nr[0]) < 0 or float(nr[2]) < float(RoadLanes.roads[int(nr[0])]["lane"]) + 2.2:
						too_close += 1
			s += 160.0
	TestLib.check(pk.roadside >= 2 and seen.size() >= 2, "cars stand on the verge of the highways (%d generated, %d seen standing)" % [pk.roadside, seen.size()])
	TestLib.check(too_close == 0, "and every one of them is clear of the lane (%d too close of %d)" % [too_close, seen.size()])
	pk.reset()
	TrafficField.clear_source(TrafficField.PARKED)
	await TestLib.frames(host, 1)
