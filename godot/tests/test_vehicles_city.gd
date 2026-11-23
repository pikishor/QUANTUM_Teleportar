extends RefCounted
## Vehicles on the real city (headless): streaming by distance with Game.world.road_point_near, caps per tier, parked cars on bays, no car in a building,
## level of detail (wheels beyond 50 m, mirror proxy only near), node count bounded after a 350 m jump, traffic staying in the city.
## Time runs 4x (see ARCHITECTURE.md). Run: tools/test.sh tests/test_vehicles_city.gd

const Env := preload("res://tests/player_env.gd")

const K := 4

var e := Env.new()
var p: Player
var mgr: VehicleManager


func run(host: Node) -> void:
	seed(5)
	await e.setup(host)
	p = e.p
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	mgr = (load("res://scenes/vehicle_manager.tscn") as PackedScene).instantiate() as VehicleManager
	mgr.stream_every = 0.05
	e.root.add_child(mgr)
	await e.frames(3)
	await _streaming_on_the_city(host)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	mgr.queue_free()
	await e.teardown()


func _extras() -> void:
	for v in mgr.list.duplicate():
		if v != mgr.starter:
			mgr._release(v)


func _streaming_on_the_city(host: Node) -> void:
	var world := (load("res://scenes/world.tscn") as PackedScene).instantiate()
	host.add_child(world)
	await e.frames(10)
	TestLib.check(Game.world != null and Game.world.has_method(&"road_point_near"), "the real city is up")
	await e.prep(Vector3(0.0, 0.0, 0.0), 0.0)
	var ppos := Vector3.ZERO
	for q in [0, 1, 2]:
		Game.set_quality(q)
		_extras()
		await e.secs(3.0)
		var want: int = [3, 5, 8][q]
		var fixed := 0                                      # wave 118: the helicopter of CITY HELIPAD EAST (108 m from here) waits on its pad OUTSIDE the car cap (ArmourSites): the streamed cars are counted without it
		for fv in mgr.list:
			if fv.has_meta(&"fixed"):
				fixed += 1
		TestLib.check(mgr.list.size() - fixed == want and fixed <= 1, "tier %d: streaming fills the city up to %d cars (%d, and %d on a fixed place)" % [q, want, mgr.list.size() - fixed, fixed])
		ppos = p.global_position
		var far := 0
		for v in mgr.list:
			if v != mgr.starter and Vector2(v.global_position.x - ppos.x, v.global_position.z - ppos.z).length() > VehicleSpecs.DESPAWN_RADIUS + 1.0:
				far += 1
		TestLib.check(far == 0, "tier %d: no streamed car beyond %.0f m" % [q, VehicleSpecs.DESPAWN_RADIUS])
	Game.set_quality(2)
	await e.secs(3.0)
	TestLib.check(mgr.traffic_count() >= 1 and mgr.parked_count() >= 1, "both traffic and parked cars are streamed (%d traffic, %d parked)" % [mgr.traffic_count(), mgr.parked_count()])
	var bays_ok := true
	var off_bay := ""
	for v in mgr.list:
		if v.ai or v == mgr.starter or v.has_meta(&"fixed"):          # (the helicopter on its pad is not a kerb car)
			continue
		if v.lost_lane:                                             # w119 CI: a traffic car stopped by a crash stands where it hit (an ambulance or a police car running a red), it was never parked
			print("vehicles_city: %s lost its lane in a crash at %s (not a kerb car)" % [v.kind, str(v.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
			continue
		var ox := absf(CityLayout.road_offset(v.global_position.x))
		var oz := absf(CityLayout.road_offset(v.global_position.z))
		if absf(ox - VehicleSpecs.BAY) > 0.2 and absf(oz - VehicleSpecs.BAY) > 0.2:
			bays_ok = false
			off_bay += " %s at %s (metas %s)" % [v.kind, str(v.global_position.snapped(Vector3(0.1, 0.1, 0.1))), str(v.get_meta_list())]
	TestLib.check(bays_ok, "parked cars stand on the parking bays (8.3 m from the road centre)%s" % off_bay)
	# the player moves across the city: far cars are released, new ones appear around him, the starter car stays alive
	p.teleport_to(Vector3(-250.0, 0.0, 250.0))
	await e.secs(3.0)
	ppos = p.global_position
	var all_near := true
	var lod_ok := true
	for v in mgr.list:
		var d := Vector2(v.global_position.x - ppos.x, v.global_position.z - ppos.z).length()
		if v != mgr.starter and d > VehicleSpecs.DESPAWN_RADIUS + 1.0:
			all_near = false
		if d > 56.0 and v.visual.wheels_visible():
			lod_ok = false
		if d < 44.0 and not v.visual.wheels_visible():
			lod_ok = false
		if d > 40.0 and v.has_mirror():
			lod_ok = false
	TestLib.check(all_near and mgr.list.size() == 8, "after a 350 m jump every streamed car is near the player again (%d cars)" % mgr.list.size())
	TestLib.check(lod_ok, "wheels are hidden beyond 50 m and the mirror proxy only serves cars within 25-33 m")
	TestLib.check(mgr.starter != null and mgr.list.has(mgr.starter) and not mgr.starter.visible, "the starter car still exists, hidden while far away")
	TestLib.check(mgr.total_nodes() <= VehicleSpecs.CAPS[2] + 2, "the node count stays bounded after the churn (%d car nodes)" % mgr.total_nodes())
	var inside := 0
	for v in mgr.list:
		if Game.world.call(&"is_inside_building", Vector3(v.global_position.x, 1.0, v.global_position.z)):
			inside += 1
	TestLib.check(inside == 0, "no car spawned inside a building")
	await e.secs(4.0)
	var bounds_ok := true
	for v in mgr.list:
		if absf(v.global_position.x) > CityLayout.HALF + 30.0 or absf(v.global_position.z) > CityLayout.HALF + 30.0:
			bounds_ok = false
	TestLib.check(bounds_ok and mgr.list.size() <= 8, "traffic stays inside the city after 15 s more")
	Game.set_quality(1)
	world.queue_free()
	await e.frames(3)
