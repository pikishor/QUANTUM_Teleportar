extends RefCounted
## w122-critic: walk-in doors of the wave 122 buildings are reachable by the stick. The real main scene at 844x390, phone HUD, REAL FINGERS (left thumb on the stick, right thumb
## turns the view), reward cards on. For the 12 walk-in buildings nearest the spawn (every kind: office, apartment, hotel, house) the hero stands on the sidewalk 2.4 m in
## front of the door and walks in by the stick; he must end up inside the building. Before the fix a room separator wall of the 2-room HOUSE
## stood across the inside of its street door (du = iu / 2 = a room boundary) and he could not get in.  Run: tools/test.sh tests/test_doors_w122c.gd   (W122C_OLD=1: the builders' code)
const TIMEOUT_SECONDS := 280
const Lib := preload("res://tests/w120_reach_lib.gd")
var L: Lib


func run(h: Node) -> void:
	TowerFloors.crit_on = OS.get_environment("W122C_OLD") != "1"
	h.get_tree().root.size = Vector2i(844, 390)
	L = Lib.new()
	await L.start(h)
	L.fast(true)
	var tf := TowerFloors.instance
	var list := tf.towers.duplicate()
	list.sort_custom(func(a, b): return TowerFloors.door_pos(a).distance_to(Game.SPAWN) < TowerFloors.door_pos(b).distance_to(Game.SPAWN))
	var n := 0
	var kinds := {}
	for tw: Dictionary in list:
		if n >= 12:
			break
		n += 1
		kinds[tw["kind"]] = true
		var into := TowerFloors.door_pos(tw, -3.0)
		var outside := TowerFloors.door_pos(tw, 2.4)                # on the sidewalk in front of the door (a parked car may stand at the kerb beyond)
		await L.tp(outside, Lib.yaw_to(outside, into))
		await L.secs(0.5)
		var r := await L.walk(into, 8.0, 0.8, 0.7)
		var gp := L.p.global_position
		# nothing solid in the door path: a 0.45 m ball (the hero's half width) along the door axis from 2 m outside to 3 m inside, at knee and chest height
		var hits := []
		var ball := SphereShape3D.new()
		ball.radius = 0.45
		var ss := L.p.get_world_3d().direct_space_state
		for o in [2.0, 1.0, 0.0, -0.6, -1.2, -1.8, -2.4, -3.0]:
			for y in [0.6, 1.4]:
				var pq := PhysicsShapeQueryParameters3D.new()
				pq.shape = ball
				pq.collision_mask = Game.L_WORLD
				pq.transform = Transform3D(Basis(), TowerFloors.door_pos(tw, o) + Vector3(0.0, y, 0.0))
				for hit in ss.intersect_shape(pq, 4):
					hits.append("%.1f:%s" % [o, (hit["collider"] as Node).name if hit["collider"] is Node else "?"])
		TestLib.check(hits.is_empty(), "%s lot %d: the door path is clear of walls and furniture from 2 m out to 3 m in (%s)" % [tw["kind"], (tw["lot"] as CityLayout.Lot).index, hits])
		var inside := TowerFloors.inside(gp) and gp.y < 1.5
		TestLib.check(inside, "%s lot %d: by the stick from 7 m out on the sidewalk through the street door into the building (hero %s, %.1f m from the goal, blocked by %s; door %s)" % [tw["kind"], (tw["lot"] as CityLayout.Lot).index, gp.snapped(Vector3.ONE * 0.1), r["dist"], (r["block"] as Array).map(func(b): return b["what"]), TowerFloors.door_pos(tw, 0.0)])
	TestLib.check(kinds.size() >= 3, "the walk covered several kinds (%s)" % [kinds.keys()])
	TowerFloors.crit_on = true
	await L.finish()

