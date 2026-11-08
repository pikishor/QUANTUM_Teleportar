extends RefCounted
## Director review 4, gameplay half (docs/SLICE_REVIEW.md "Fix pass, review 4 gameplay half"), in the REAL game scene:
##   1  the fight: the opening countdown is never held back by a far street patrol (the first wave comes on time); the squad ahead is placed where a parked car does not hide it
##   10 cover is cover: the crosshair's point stops at a parked car (the round does), and the aim assist does not pull the look toward a trooper a car or a wall hides
##   8  a side-step at a run has a short contact (no skier stance); the camera in a small room is lifted over the hero instead of sitting in his back
##   11 a hero who stands still in the open with a goal on the map gets one "how to move" line, once, and it stops when he moves
##   12 a wrecked car crawling at 1-4 km/h against a kerb backs out within a second (a car pulling away from a light is not "wedged")
## Waits on game time, positions and counters, never on frame counts; user:// state is reset first. Frames of the same things: tests/bot_director_review.gd (DR_ACTS=fight),
## tests/bot_slice_art.gd (spots in_lob_a, in_off_a..c); the sheet is docs/shots/slice/director_round4_a_before_after.jpg.
## Run: tools/test.sh tests/test_director_round4_a.gd

var host: Node
var p: Player
var mgr: VehicleManager
var em: EnemyManager
var blockers: Array[StaticBody3D] = []


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_numbers()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	p = Game.player as Player
	mgr = Game.vehicles as VehicleManager
	em = Game.enemies as EnemyManager
	TestLib.check(p != null and mgr != null and em != null, "the real scene has a player, vehicles and enemies")
	if p == null or mgr == null or em == null:
		return
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	await _cover_and_assist()
	await _first_wave_not_held()
	await _wedge()
	await _move_hint()
	await _camera_in_rooms()
	for b in blockers:
		b.queue_free()
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)


# --- the numbers ----------------------------------------------------------------------------------------------------------------------------------------

func _numbers() -> void:
	TestLib.check(Locomotion.STRAFE_CONTACT < 0.8 and Locomotion.STRAFE_CONTACT > 0.3, "a sideways run keeps %.0f %% of the forward contact length" % (Locomotion.STRAFE_CONTACT * 100.0))
	TestLib.check(VehicleSpecs.WEDGE_SECS <= 1.0 and VehicleSpecs.WEDGE_SPEED_CRASH > VehicleSpecs.WEDGE_SPEED, "a wedged car backs out after %.1f s (crawling counts as wedged for %.0f s after a crash, below %.1f m/s)" % [VehicleSpecs.WEDGE_SECS, VehicleSpecs.WEDGE_AFTER_CRASH, VehicleSpecs.WEDGE_SPEED_CRASH])
	TestLib.check(CameraRig.INTERIOR_LIFT > 0.0 and CameraRig.INTERIOR_LIFT_SQUEEZE > 0.0 and CameraRig.INTERIOR_ARM_SCALE >= 0.75, "interior camera: lift %.2f + %.2f m, arm %.0f %%" % [CameraRig.INTERIOR_LIFT, CameraRig.INTERIOR_LIFT_SQUEEZE, CameraRig.INTERIOR_ARM_SCALE * 100.0])
	TestLib.check(Encounters.CAR_HIDDEN > 0.0 and AimAssist.LOS_CHECKS >= 2, "the squad ahead avoids a spot a car hides, the assist checks %d candidates a frame" % AimAssist.LOS_CHECKS)
	TestLib.check(MissionGuide.MOVE_HINT_AFTER <= 6.0 and MissionGuide.MOVE_HINT_MAX <= 3, "the move hint comes after %.0f s of standing, at most %d times" % [MissionGuide.MOVE_HINT_AFTER, MissionGuide.MOVE_HINT_MAX])


# --- helpers --------------------------------------------------------------------------------------------------------------------------------------------

func _block(center: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	host.add_child(b)
	b.global_position = center
	blockers.append(b)
	return b


func _clear_enemies() -> void:
	em.patrol_groups().clear()
	em.clear()
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false
	if Game.story != null:
		(Game.story as Story).skip_cards()
	Game.heat = 0.0


# --- 10: cover ------------------------------------------------------------------------------------------------------------------------------------------

func _cover_and_assist() -> void:
	_clear_enemies()
	Encounters.current.enabled = false
	var assist := p.get_node_or_null("AimAssist") as AimAssist
	if assist == null:
		for c in p.get_children():
			if c is AimAssist:
				assist = c
	TestLib.check(assist != null, "the player has the aim assist")
	if assist == null:
		return
	p.teleport_to(Vector3(-30.0, 0.0, 4.0))
	await TestLib.frames(host, 3)
	var eye := p.global_position + Vector3(0.0, 1.5, 0.0)
	var foe: Drone = null
	var foe_pos := Vector3.ZERO
	var c := Vector3.ZERO
	var dir := Vector3.ZERO
	# the street has parked cars and props: take the first spot ahead of the hero that nothing covers
	var spots: Array[Vector3] = []
	for dz: float in [-16.0, -13.0, -19.0]:
		for dx: float in [0.0, 4.0, -4.0, 8.0, -8.0]:
			spots.append(p.global_position + Vector3(dx, 0.0, dz))
	for sp in spots:
		if foe == null:
			foe = em.spawn(&"operative", sp, true, true, &"vael")
			if foe == null:
				break
		foe.global_position = sp
		foe.set_physics_process(false)
		await TestLib.frames(host, 1)
		c = foe.center()
		var rq := PhysicsRayQueryParameters3D.create(eye, c, Game.L_WORLD | Game.L_VEHICLE)
		var rr := p.get_world_3d().direct_space_state.intersect_ray(rq)
		if rr.is_empty():
			foe_pos = sp
			break
	TestLib.check(foe != null and foe_pos != Vector3.ZERO, "a trooper stands in the open ahead of the hero")
	if foe == null or foe_pos == Vector3.ZERO:
		return
	dir = (c - eye).normalized()
	var seen := assist.find(eye, dir, eye)
	TestLib.check(not seen.is_empty() and seen["node"] == foe, "in the open the assist finds the trooper")
	# a van across the lane: the world layer of vehicles
	var van := _block(Vector3(foe_pos.x, 1.2, foe_pos.z + 8.0), Vector3(4.0, 2.4, 2.0), Game.L_VEHICLE)
	await TestLib.frames(host, 2)
	var hidden := assist.find(eye, dir, eye)
	TestLib.check(hidden.is_empty(), "behind a van the assist does not lock on (it used to pull the look onto the van)")
	TestLib.check(not assist.clear_line(eye, c), "the line from the hero to the trooper is not clear through the van")
	# the crosshair's point stops at the van
	p.camera_rig.aim_at(c)
	await TestLib.frames(host, 3)
	var aim := p.get_aim()
	var d_hit := (aim["start"] as Vector3).distance_to(aim["hit"])
	var d_van := (aim["start"] as Vector3).distance_to(van.global_position)
	TestLib.check(d_hit < d_van + 1.5, "the crosshair point is on the van (%.1f m), not behind it (the trooper is %.1f m away)" % [d_hit, (aim["start"] as Vector3).distance_to(c)])
	# the van leaves: locked again
	van.queue_free()
	blockers.erase(van)
	await TestLib.frames(host, 3)
	var back := assist.find(eye, dir, eye)
	TestLib.check(not back.is_empty() and back["node"] == foe, "with the van gone the assist locks on again")
	# a wall (world layer) hides as well
	var wall := _block(Vector3(foe_pos.x, 3.0, foe_pos.z + 8.0), Vector3(8.0, 6.0, 0.5), Game.L_WORLD)
	await TestLib.frames(host, 2)
	TestLib.check(assist.find(eye, dir, eye).is_empty(), "a wall hides the trooper from the assist too")
	wall.queue_free()
	blockers.erase(wall)
	# two troopers, the nearer one hidden: the visible one is chosen
	var foe2 := em.spawn(&"operative", foe_pos + Vector3(2.5, 0.0, 6.0), true, true, &"vael")
	if foe2 != null:
		foe2.global_position = foe_pos + Vector3(2.5, 0.0, 6.0)
		foe2.set_physics_process(false)
		var shield := _block(foe2.global_position + Vector3(0.0, 1.2, 3.0), Vector3(3.0, 2.4, 1.0), Game.L_VEHICLE)
		await TestLib.frames(host, 2)
		var dir2 := ((foe2.center() - eye).normalized() + dir).normalized()
		var pick := assist.find(eye, dir2, eye)
		TestLib.check(pick.is_empty() or pick["node"] == foe, "of two troopers in the cone the one behind a car is passed over")
		shield.queue_free()
		blockers.erase(shield)
	_clear_enemies()


# --- 1: the first wave and the placement ---------------------------------------------------------------------------------------------------------------

func _first_wave_not_held() -> void:
	_clear_enemies()
	var enc := Encounters.current
	enc.enabled = true
	enc.reset()
	p.teleport_to(Game.SPAWN)
	await TestLib.frames(host, 2)
	# a car between a spawn point and the hero is seen by the line test, a world wall too, and the plain world mask ignores the car
	var q := p.global_position + Vector3(14.0, 0.0, 0.0)
	var car := _block(p.global_position + Vector3(7.0, 1.0, 0.0), Vector3(1.5, 2.0, 4.0), Game.L_VEHICLE)
	await TestLib.frames(host, 2)
	TestLib.check(enc._walled(q, p.global_position, Game.L_WORLD | Game.L_VEHICLE) and not enc._walled(q, p.global_position), "a parked car hides a spawn point from the hero (the vehicle mask sees it, the wall mask does not)")
	car.queue_free()
	blockers.erase(car)
	# a far street patrol is aware 40 m away; the opening countdown still runs out on time
	var a := em.spawn(&"operative", p.global_position + Vector3(0.0, 0.0, -42.0), true, true, &"drones")
	var b := em.spawn(&"operative", p.global_position + Vector3(4.0, 0.0, -44.0), true, true, &"drones")
	for e in [a, b]:
		if e != null:
			(e as Drone).set_meta(&"patrol", {"live": 2})
	var started := false
	var guard := 0
	while not started and guard < 400:
		enc.tick(0.25)
		guard += 1
		started = enc.waves_started >= 1
	TestLib.check(started and enc.first_wave_t <= Encounters.FIRST_DELAY + 3.0, "two aware troopers 40 m away do not hold the first wave back (it came %.1f s into the play, the countdown is %.0f s)" % [enc.first_wave_t, Encounters.FIRST_DELAY])
	enc.enabled = false
	_clear_enemies()


# --- 12: wedge ------------------------------------------------------------------------------------------------------------------------------------------

func _wedge() -> void:
	if mgr.driven != null:
		mgr.exit_vehicle()
	for v in mgr.list.duplicate():
		mgr._release(v)
	mgr.starter = null
	mgr.stream_every = 1.0e9
	mgr._stream_t = 1.0e9
	mgr.set_physics_process(false)
	var pos := Vector3(-700.0, 0.0, 400.0)
	var v := mgr.spawn_parked(&"sedan", pos, 0.0)
	v.global_position = pos
	v.heading = 0.0
	v.rotation = Vector3.ZERO
	v._heading_set = 0.0
	mgr.enter(v)
	v.active = true
	var dt := 1.0 / 60.0
	# a wreck that just hit a wall and crawls at 1 m/s with the throttle held: it backs out
	v._crash_age = 0.5
	var n0 := v.wedge_count
	var t := 0.0
	while t < 3.0 and v.wedge_count == n0:
		v.vel = v.forward() * 1.0
		v.speed = 1.0
		v.step_drive(dt, 1.0, 0.0, false)
		t += dt
	TestLib.check(v.wedge_count > n0 and t <= VehicleSpecs.WEDGE_SECS + 0.2, "a wreck crawling at 3.6 km/h with the throttle held backs out after %.2f s (was 2-4 s and often never)" % t)
	# a car pulling away from a light (no crash lately) at the same crawl is not wedged
	v._nudge_t = 0.0
	v._wedge_t = 0.0
	v._crash_age = 99.0
	var n1 := v.wedge_count
	t = 0.0
	while t < 2.0:
		v.vel = v.forward() * 1.0
		v.speed = 1.0
		v.step_drive(dt, 1.0, 0.0, false)
		t += dt
	TestLib.check(v.wedge_count == n1, "the same crawl with no crash lately is not taken for a wedge")
	mgr.exit_vehicle()
	for w in mgr.list.duplicate():
		mgr._release(w)
	mgr.set_physics_process(true)


# --- 11: the move hint ----------------------------------------------------------------------------------------------------------------------------------

func _move_hint() -> void:
	var m := Game.missions as Missions
	var camp := m.campaign
	camp.set_physics_process(false)
	camp.enabled = true
	camp.abort()
	Game.heat = 0.0
	Game.state = &"play"
	camp.start_custom({"id": "r4a", "clears_sector": false, "steps": [{"kind": "reach", "pos": [-200.0, 0.0], "obj": "Reach the beacon"}]})
	var g := camp.guide
	g.move_hints = 0
	_clear_enemies()
	p.teleport_to(Vector3(-30.0, 0.0, 4.0))
	p.velocity = Vector3.ZERO
	await TestLib.frames(host, 2)
	var said: Array[String] = []
	var on_say := func(text: String, _s: float) -> void: said.append(text)
	Game.message.connect(on_say)
	for i in int(MissionGuide.MOVE_HINT_AFTER) - 1:
		g.tick(1.0)
	var early := said.any(func(t: String) -> bool: return t.contains("TO MOVE"))
	TestLib.check(not early, "no hint in the first %d s of standing" % (int(MissionGuide.MOVE_HINT_AFTER) - 1))
	for i in 3:
		g.tick(1.0)
	var line := ""
	for t in said:
		if t.contains("TO MOVE"):
			line = t
	TestLib.check(g.move_hints == 1 and line != "", "a hero who stands still hears one line (%s)" % line)
	TestLib.check(line.contains("FOLLOW THE BEACON"), "...and it says what to follow")
	# he moves: nothing more
	p.velocity = Vector3(0.0, 0.0, -4.0)
	for i in 20:
		g.tick(1.0)
	TestLib.check(g.move_hints == 1, "a hero who moves is left alone (hints %d)" % g.move_hints)
	# standing again for long: a second line at most, never a third
	p.velocity = Vector3.ZERO
	for i in 80:
		g.tick(1.0)
	TestLib.check(g.move_hints <= MissionGuide.MOVE_HINT_MAX, "the hint never nags (%d of at most %d)" % [g.move_hints, MissionGuide.MOVE_HINT_MAX])
	Game.message.disconnect(on_say)
	camp.abort()
	camp.enabled = false


# --- 8: the camera in a small room ---------------------------------------------------------------------------------------------------------------------

func _camera_in_rooms() -> void:
	var ig := InteriorGameplay.instance
	if ig == null:
		TestLib.check(false, "the real scene has the interior director")
		return
	_clear_enemies()
	var rig := p.camera_rig
	rig.reset_view(0.0, -0.12)
	await TestLib.frames(host, 8)
	var street_h := rig.camera.global_position.y - p.global_position.y
	TestLib.check(ig.test_enter(&"lobby").begins_with("INSIDE"), "the hero goes into a lobby")
	await TestLib.frames(host, 10)
	rig.reset_view(0.0, -0.12)
	await TestLib.frames(host, 25)
	var in_h := rig.camera.global_position.y - p.global_position.y
	var dist := rig.camera.global_position.distance_to(p.global_position + Vector3(0.0, 1.5, 0.0))
	TestLib.check(InteriorSpace.active, "(inside)")
	TestLib.check(in_h > street_h - 0.2 and dist > 0.9, "in the room the lens sits %.2f m above the feet (street %.2f) and %.1f m from the head, not in his back" % [in_h, street_h, dist])
	ig.leave(true)
	await TestLib.frames(host, 4)
