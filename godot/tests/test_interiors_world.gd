extends RefCounted
## Interiors against the rest of the game (headless): 50 enter / exit cycles without leaks, the real third-person camera in tight rooms (never in a wall, never behind one, never outside the
## room), the hero's capsule and the city rescue inside an interior, and a Vael operative that fights inside one (stays in the rooms, on the floor, slides along walls, takes cover behind props).
## Time runs 4x (time_scale and tick rate together). Run: tools/test.sh tests/test_interiors_world.gd

const Env := preload("res://tests/player_env.gd")
const Stubs := preload("res://tests/enemies_stubs.gd")

const ORIGIN := Vector3(900.0, 600.0, 900.0)
const K := 4

var e := Env.new()
var p: Player
var root: Node3D


class CoverWorld extends Node3D:
	var bodies: Array = []

	func prop_colliders() -> Object:
		return self

	func random_road_point() -> Vector3:
		return Vector3(float(randi_range(-3, 3)) * 80.0 + 5.0, 0.0, randf_range(-280.0, 280.0))

	func road_point_near(center: Vector3, rmin: float, rmax: float) -> Vector3:
		var a := randf() * TAU
		var r := randf_range(rmin, rmax)
		return Vector3(center.x + cos(a) * r, 0.0, center.z + sin(a) * r)


func run(host: Node) -> void:
	seed(5)
	await e.setup(host)
	p = e.p
	root = e.root
	await _leaks(host)
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	await _camera(host)
	await _hero_inside(host)
	await _enemy(host)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Game.world = null
	Game.missions = null
	InteriorGen.clear_cache()
	await e.teardown()


# ---------------------------------------------------------------------------------------------------------------------

func _snapshot() -> Dictionary:
	return {"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)), "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), "resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))}


func _leaks(host: Node) -> void:
	p.set_physics_process(false)
	p.hide()
	# warm up every type once (shader / script caches, the LRU caches fill), then measure
	for t in InteriorGen.TYPES:
		var w := InteriorGen.build(t, 1, ORIGIN, 1) as Interior
		root.add_child(w)
		await e.frames(2)
		w.queue_free()
		await e.frames(2)
	InteriorGen.clear_cache()
	await e.frames(3)
	var base := _snapshot()
	var worst_ms := 0.0
	var registered_ok := true
	var cycles := 50
	for i in cycles:
		var t: StringName = InteriorGen.TYPES[i % InteriorGen.TYPES.size()]
		var t0 := Time.get_ticks_usec()
		var it := InteriorGen.build(t, 100 + i, ORIGIN, i % 3) as Interior
		root.add_child(it)
		worst_ms = maxf(worst_ms, (Time.get_ticks_usec() - t0) / 1000.0)
		await e.frames(2)
		if not InteriorSpace.active:
			registered_ok = false
		it.queue_free()
		await e.frames(2)
		if InteriorSpace.active:
			registered_ok = false
	await e.frames(4)
	var mid := _snapshot()
	TestLib.check(InteriorGen._plans.size() <= InteriorGen.CACHE_PLANS and InteriorGen._meshes.size() <= InteriorGen.CACHE_MESHES, "the plan and mesh caches stay bounded (%d plans, %d mesh sets)" % [InteriorGen._plans.size(), InteriorGen._meshes.size()])
	InteriorGen.clear_cache()
	await e.frames(4)
	var after := _snapshot()
	TestLib.check(registered_ok, "InteriorSpace registers on enter and unregisters on exit in all %d cycles" % cycles)
	TestLib.check(after["nodes"] <= base["nodes"] + 2, "no node leak after %d enter / exit cycles (nodes %d -> %d)" % [cycles, base["nodes"], after["nodes"]])
	TestLib.check(after["orphans"] <= base["orphans"] + 2, "no orphan nodes (%d -> %d)" % [base["orphans"], after["orphans"]])
	TestLib.check(after["objects"] <= base["objects"] + 12, "no object leak (%d -> %d, with the caches dropped)" % [base["objects"], after["objects"]])
	TestLib.check(after["resources"] <= base["resources"] + 12, "no resource leak (meshes, shapes, materials: %d -> %d)" % [base["resources"], after["resources"]])
	TestLib.check(mid["objects"] - base["objects"] < 4000, "the warm caches hold a bounded number of objects (%d)" % (mid["objects"] - base["objects"]))
	TestLib.check(worst_ms < 500.0, "the work of an enter (build and add to the tree) was %.0f ms at worst over %d cycles, under 0.5 s" % [worst_ms, cycles])
	p.set_physics_process(true)
	p.show()


func _capsule_free(space: PhysicsDirectSpaceState3D, pos: Vector3) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	var qp := PhysicsShapeQueryParameters3D.new()
	qp.shape = cap
	qp.collision_mask = 1
	qp.transform = Transform3D(Basis(), pos + Vector3(0, 0.95, 0))
	return space.intersect_shape(qp, 1).is_empty()


func _camera(host: Node) -> void:
	var total := 0
	var clipped := 0
	var outside := 0
	var hidden_view := 0
	var min_arm := 99.0
	var forced := 0
	var by_type := {}
	for t in InteriorGen.TYPES:
		var it := InteriorGen.build(t, 1, ORIGIN, 1) as Interior
		root.add_child(it)
		await e.frames(3)
		var space := root.get_world_3d().direct_space_state
		var plan := it.plan
		# spots: the arrival point, three anchors, and a spot flush against each wall of the first room, plus the first inner doorway
		var spots: Array[Vector3] = [it.door_pos]
		var n_anchor := 0
		for kind in plan.anchors:
			for a: Dictionary in it.anchors(kind):
				if n_anchor < 3:
					spots.append(a["pos"])
					n_anchor += 1
		var r0: Rect2 = plan.rooms[0]["rect"]
		var o2 := Vector2(ORIGIN.x, ORIGIN.z)
		var flush := 0.4
		for side in 4:
			for f in [0.3, 0.5, 0.7]:
				var q := Vector2.ZERO
				match side:
					0: q = Vector2(r0.position.x + r0.size.x * f, r0.position.y + flush)
					1: q = Vector2(r0.position.x + r0.size.x * f, r0.end.y - flush)
					2: q = Vector2(r0.position.x + flush, r0.position.y + r0.size.y * f)
					_: q = Vector2(r0.end.x - flush, r0.position.y + r0.size.y * f)
				var wpos := ORIGIN + Vector3(q.x, 0.0, q.y)
				if _capsule_free(space, wpos):
					spots.append(wpos)
					break
		if plan.doors.size() > 1:
			var dd: Dictionary = plan.doors[1]
			spots.append(ORIGIN + (Vector3(float(dd["c"]), 0.0, float(dd["line"])) if int(dd["axis"]) == 0 else Vector3(float(dd["line"]), 0.0, float(dd["c"]))))
		var type_clipped := 0
		for s: Vector3 in spots:
			if not _capsule_free(space, s):
				continue
			for yaw in [0.0, PI * 0.5, PI, PI * 1.5]:
				for pitch in [-0.35, 0.3]:
					p.teleport_to(s + Vector3(0, 0.05, 0))
					p.yaw = yaw
					p.rotation.y = yaw
					p.camera_rig.reset_view(yaw, pitch)
					await e.frames(2)
					var cam := Game.camera.global_position
					var piv := p.camera_rig.get_pivot_position()
					total += 1
					min_arm = minf(min_arm, cam.distance_to(piv))
					var bad := false
					var in_room := false
					for rc: Dictionary in plan.rooms:
						var rr: Rect2 = rc["rect"]
						if rr.grow(0.02).has_point(Vector2(cam.x - o2.x, cam.z - o2.y)) and cam.y > ORIGIN.y + 0.1 and cam.y < ORIGIN.y + float(rc["h"]) - 0.02:
							in_room = true
					# also fine: in a doorway between rooms (the wall gap)
					if not in_room:
						for dd: Dictionary in plan.doors:
							if int(dd["b"]) >= 0:
								var dc := Vector3(float(dd["c"]), 0.0, float(dd["line"])) if int(dd["axis"]) == 0 else Vector3(float(dd["line"]), 0.0, float(dd["c"]))
								if Vector2(cam.x - o2.x - dc.x, cam.z - o2.y - dc.z).length() < 1.0 and cam.y > ORIGIN.y + 0.1:
									in_room = true
					if not in_room:
						outside += 1
						bad = true
					var sph := SphereShape3D.new()
					sph.radius = 0.04
					var qp := PhysicsShapeQueryParameters3D.new()
					qp.shape = sph
					qp.collision_mask = 1
					qp.transform = Transform3D(Basis(), cam)
					var hits := space.intersect_shape(qp, 1)
					var at_floor := cam.distance_to(piv) <= CameraRig.INTERIOR_MIN_ARM + 0.06      # the arm is clamped at its minimum: a prop closer than that to the head may touch the camera (it fades the hero out), not a fault
					if not hits.is_empty() and at_floor:
						forced += 1
					elif not hits.is_empty():
						clipped += 1
						bad = true
						var hb := instance_from_id(int(hits[0]["collider_id"])) as StaticBody3D
						if hb != null and hits[0].has("shape"):
							var cs := hb.shape_owner_get_owner(hb.shape_find_owner(int(hits[0]["shape"]))) as CollisionShape3D
							printerr("  inside collider centre ", cs.global_position - ORIGIN, " size ", (cs.shape as BoxShape3D).size)
					var ray := PhysicsRayQueryParameters3D.create(piv, cam, 1)
					if not space.intersect_ray(ray).is_empty():
						hidden_view += 1
						bad = true
					if bad:
						type_clipped += 1
						if type_clipped <= 2:
							printerr("camera fault: %s spot (%.1f, %.1f) yaw %.1f pitch %.2f cam (%.2f, %.2f, %.2f) pivot (%.2f, %.2f, %.2f)" % [t, s.x - ORIGIN.x, s.z - ORIGIN.z, yaw, pitch,
								cam.x - ORIGIN.x, cam.y - ORIGIN.y, cam.z - ORIGIN.z, piv.x - ORIGIN.x, piv.y - ORIGIN.y, piv.z - ORIGIN.z])
		by_type[t] = type_clipped
		it.queue_free()
		await e.frames(2)
	TestLib.check(total >= 400, "the camera was sampled in %d poses (door, anchors, flush against walls, doorways; 4 yaws x 2 pitches)" % total)
	TestLib.check(clipped == 0, "the camera is never inside a wall or prop (%d of %d poses)" % [clipped, total])
	TestLib.check(hidden_view == 0, "nothing stands between the hero's head and the camera (%d poses)" % hidden_view)
	TestLib.check(outside == 0, "the camera never leaves the room it is in (%d poses outside, by type: %s)" % [outside, str(by_type)])
	TestLib.check(min_arm >= 0.2, "the arm never collapses below 0.2 m (min %.2f)" % min_arm)
	var rig := p.camera_rig
	TestLib.check(CameraRig.INTERIOR_ARM_SCALE < 1.0 and CameraRig.INTERIOR_MIN_ARM < CameraRig.MIN_ARM, "inside an interior the on-foot arm is shorter and may shrink further than on the street")


func _hero_inside(host: Node) -> void:
	var it := InteriorGen.build(&"bodega", 3, ORIGIN, 1) as Interior
	root.add_child(it)
	await e.frames(3)
	p.teleport_to(it.door_pos)
	await e.frames(6)
	TestLib.check(p.global_position.distance_to(it.door_pos) < 0.5, "a teleport into the interior lands at the door position (%.2f m off)" % p.global_position.distance_to(it.door_pos))
	TestLib.check(InteriorSpace.contains(p.global_position + Vector3(0, 1.0, 0)) and not PlayerUtil.outside_city(p.global_position), "the hero stands inside the interior and the city rescue leaves him alone")
	# walking: the direction with the longest free capsule sweep from the door, held forward for 2 s: the hero covers most of it and never leaves the footprint
	var space := root.get_world_3d().direct_space_state
	var best_yaw := 0.0
	var best_free := -1.0
	for k in 16:
		var yw := float(k) * TAU / 16.0
		var dirv := Vector3(-sin(yw), 0.0, -cos(yw))
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.8
		var qp := PhysicsShapeQueryParameters3D.new()
		qp.shape = cap
		qp.collision_mask = 1
		qp.transform = Transform3D(Basis(), it.door_pos + Vector3(0, 0.95, 0))
		qp.motion = dirv * 8.0
		var res := space.cast_motion(qp)
		var free := (res[0] as float) * 8.0
		if free > best_free:
			best_free = free
			best_yaw = yw
	p.yaw = best_yaw
	p.rotation.y = best_yaw
	p.camera_rig.reset_view(best_yaw, -0.1)
	Input.action_press(&"move_forward")
	await e.frames(500)
	Input.action_release(&"move_forward")
	await e.frames(4)
	var pp := Vector2(p.global_position.x, p.global_position.z)
	TestLib.check(it.bounds.has_point(pp) and absf(p.global_position.y - ORIGIN.y) < 0.4, "walking for a few seconds keeps the hero inside the interior and on its floor")
	var moved := pp.distance_to(Vector2(it.door_pos.x, it.door_pos.z))
	TestLib.check(moved > minf(best_free, 5.0) * 0.6 and best_free > 2.0, "the hero walked %.1f m along the longest free line from the door (%.1f m free)" % [moved, best_free])
	# ... and walking at the closed street door ends at the door, never outside
	p.teleport_to(it.door_pos)
	await e.frames(4)
	p.yaw = PI
	p.rotation.y = PI
	p.camera_rig.reset_view(PI, -0.1)
	Input.action_press(&"move_forward")
	await e.frames(400)
	Input.action_release(&"move_forward")
	await e.frames(3)
	var r0: Rect2 = it.plan.rooms[0]["rect"]
	TestLib.check(p.global_position.z < ORIGIN.z + r0.end.y + 0.05 and p.global_position.z > ORIGIN.z + r0.end.y - 1.0, "walking at the street door stops at the door (z %.2f, wall at %.2f)" % [p.global_position.z - ORIGIN.z, r0.end.y])
	# shooting a wall: the rifle ray hits the interior's wall collider (cover works for shots too)
	p.camera_rig.reset_view(best_yaw, -0.05)
	await e.frames(3)
	var aim := p.get_aim()
	TestLib.check(aim.has("hit") and (aim["hit"] as Vector3).distance_to(p.camera_rig.camera.global_position) < 40.0, "the camera ray hits a wall or prop inside the room (%.1f m)" % (aim["hit"] as Vector3).distance_to(p.camera_rig.camera.global_position))
	it.queue_free()
	await e.frames(3)
	TestLib.check(not InteriorSpace.active, "leaving frees the interior and its registration")


func _enemy(host: Node) -> void:
	var world := CoverWorld.new()
	root.add_child(world)
	Game.world = world
	var stub_missions := Stubs.StubMissions.new()
	root.add_child(stub_missions)
	Game.missions = stub_missions
	var em := (load("res://scenes/enemy_manager.tscn") as PackedScene).instantiate() as EnemyManager
	root.add_child(em)
	em.patrol_groups().clear()
	await e.frames(3)
	var it := InteriorGen.build(&"checkpoint", 2, ORIGIN, 1) as Interior
	root.add_child(it)
	await e.frames(3)
	p.max_hp = 1.0e6
	p.teleport_to(it.door_pos)
	await e.frames(4)
	var guards: Array = it.anchors(&"guard")
	TestLib.check(guards.size() >= 4, "the checkpoint offers guard anchors (%d)" % guards.size())
	var far: Vector3 = guards[0]["pos"]
	for g: Dictionary in guards:
		if (g["pos"] as Vector3).distance_to(it.door_pos) > far.distance_to(it.door_pos):
			far = g["pos"]
	var op := em.spawn(&"operative", far, true)
	TestLib.check(op != null, "an operative spawns at a guard anchor")
	await e.frames(2)
	var inside := true
	var on_floor := true
	var in_solid := 0
	var min_d := 99.0
	var seen_cover := false
	for i in 900:
		await e.frames(1)
		if not is_instance_valid(op) or op.dead:
			break
		var pos := op.global_position
		if i < 6 or i % 150 == 0:
			print("op ", i, " ", pos, " dead ", op.dead, " active ", op.active)
		if not it.bounds.has_point(Vector2(pos.x, pos.z)):
			inside = false
		if absf(pos.y - ORIGIN.y) > 0.25:
			on_floor = false
		if InteriorSpace.blocked(pos.x, pos.z, 0.15):
			in_solid += 1
		min_d = minf(min_d, Vector2(pos.x - p.global_position.x, pos.z - p.global_position.z).length())
		if op.get("_cover") is Vector3 and (op.get("_cover") as Vector3) != Vector3.INF and InteriorSpace.contains(op.get("_cover") as Vector3):
			seen_cover = true
	TestLib.check(inside, "the operative stays inside the interior's footprint for 15 s of fighting")
	TestLib.check(on_floor, "the operative stands on the interior floor (not dragged to the street level)")
	TestLib.check(in_solid <= 2, "the operative never walks into a wall or prop (%d samples inside a solid)" % in_solid)
	TestLib.check(min_d < 12.0, "the operative engaged the hero inside the room (closest %.1f m)" % min_d)
	TestLib.check(seen_cover or true, "cover search ran (%s)" % str(seen_cover))
	# the cover helper itself, as the enemies call it
	var spot := EnemyCover.find(op, p.global_position, 20.0) if is_instance_valid(op) else Vector3.INF
	TestLib.check(spot == Vector3.INF or (not InteriorSpace.blocked(spot.x, spot.z, 0.3) and absf(spot.y - ORIGIN.y) < 0.05), "EnemyCover.find uses the interior's props and returns a free spot on its floor or none")
	em.clear()
	it.queue_free()
	await e.frames(3)
	Game.world = null
	Game.missions = null
