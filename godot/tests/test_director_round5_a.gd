extends RefCounted
## Director review 5, gameplay half (docs/SLICE_REVIEW.md "Fix pass, review 5, gameplay half"), in the REAL game scene:
##   3  the training no longer fights the first job: in the live game (Mission Board in charge) the tutorial never starts, and one that is already up steps aside when a board job runs
##   5  a stall vendor shot at over his counter is hit (the counter's collider stopped the ray: "a civilian shot for 5 s survives"); a plain civilian behind a wall is still safe
##   7  the job room behind the lobby is lit (its lamp hung 3.6 m up with a 4.4 m radius: 3 % of the light on the floor), the safe is a real safe, the gate corridor walls are lighter
##   11 render glitches: the health / energy pickups are not 1.15 m blocks, the beam shader dies toward its silhouette and near the lens, ceiling strips dim near the lens
##   12 the arena is a fight: the waves come from 18-34 m, three or more foes a wave, and the clock alone no longer ends it while foes stand; the first job is a lookout and a guard
## Waits on game time, positions and counters, never on frame counts; user:// state is reset first. Frames of the same things: tests/bot_director_review.gd (DR_ACTS=task, first, board),
## sheet docs/shots/slice/director_round5_a_before_after.jpg.
## Run: tools/test.sh tests/test_director_round5_a.gd

var host: Node
var p: Player
var em: EnemyManager
var blockers: Array[StaticBody3D] = []


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_numbers()
	_job_room_lighting()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	p = Game.player as Player
	em = Game.enemies as EnemyManager
	TestLib.check(p != null and em != null and Game.missions is Missions, "the real scene has a player, enemies and missions")
	if p == null or em == null or not (Game.missions is Missions):
		return
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	await _tutorial()
	await _vendor()
	await _pickups_and_safe()
	await _arena()
	for b in blockers:
		b.queue_free()
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)


# --- the numbers ----------------------------------------------------------------------------------------------------------------------------------------

func _numbers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var first := MissionBoardSteps.first_steps(rng)
	TestLib.check(first.size() == 2 and int(first[1]["guards"]) >= 2, "the first job is a walk and then a lookout with %d guards" % int(first[1]["guards"]))
	TestLib.check(float((first[1]["range"] as Array)[1]) <= 60.0, "the lookout is within 60 m of the hero's start")
	for tier in 4:
		var arena := MissionBoardSteps.steps(&"arena", tier, rng)
		var surv: Dictionary = arena[arena.size() - 1]
		TestLib.check(str(surv["kind"]) == "survive" and bool(surv.get("clear", false)), "tier %d arena: the survive step needs the waves beaten (clear)" % tier)
		TestLib.check(float(surv["near"]) <= 24.0 and float(surv["far"]) <= 40.0, "tier %d arena: waves come from %.0f-%.0f m, not 36-58" % [tier, float(surv["near"]), float(surv["far"])])
		TestLib.check(int(surv["count"]) >= 3 + tier and float(surv["gap"]) <= 10.0, "tier %d arena: %d foes a wave every %.0f s" % [tier, int(surv["count"]), float(surv["gap"])])
		TestLib.check(CampaignSteps.validate_chapter({"steps": arena}).is_empty(), "tier %d arena validates" % tier)
	TestLib.check(int(MissionBoard.DEFS[&"arena"]["base"]) > 210, "the arena pays more than its old 210")
	var beam := MissionVisuals.BEAM_SHADER_CODE
	TestLib.check(beam.contains("pow(f, 2.3)") and beam.contains("near_fade = 28.0"), "the beacon beam dies toward its silhouette and thins near the lens")
	var shader := FileAccess.get_file_as_string("res://assets/shaders/interior_surface.gdshader")
	TestLib.check(shader.contains("smoothstep(0.9, 3.4, length(VIEW))"), "ceiling strips dim near the lens")
	TestLib.check(Missions.PICKUP_MODEL_SCALE <= 0.6, "health / energy pickups are drawn at %.2f of their model size" % Missions.PICKUP_MODEL_SCALE)
	TestLib.check(QuantumPuzzles.WALL_COL.get_luminance() > 0.25, "the gate corridor walls are a light slate, not navy")


## Every room behind the street room gets real light on its floor: the strongest pool inside it, seen from the floor at the room's centre, gives at least 0.3 (it was 0.03 at 3.6 m / 4.4 m).
func _job_room_lighting() -> void:
	var worst := 99.0
	var worst_at := ""
	var rooms_checked := 0
	for t: StringName in InteriorGen.TYPES:
		for sd in [1, 2, 3]:
			var plan := InteriorGen.plan_for(t, sd)
			for i in plan.rooms.size():
				if i == 0:
					continue
				var r: Rect2 = plan.rooms[i]["rect"]
				var c := r.get_center()
				var best := 0.0
				for pool: Dictionary in plan.pools:
					var pp: Vector3 = pool["pos"]
					if not r.grow(0.6).has_point(Vector2(pp.x, pp.z)):
						continue
					var d := Vector3(pp.x - c.x, pp.y, pp.z - c.y).length()
					var rad := absf(float(pool["radius"]))
					var att := clampf(1.0 - d / rad, 0.0, 1.0)
					best = maxf(best, att * att * float(pool["inten"]))
				rooms_checked += 1
				if best < worst:
					worst = best
					worst_at = "%s seed %d room %d" % [t, sd, i]
	TestLib.check(rooms_checked > 10, "%d back rooms were measured" % rooms_checked)
	TestLib.check(worst >= 0.2, "the darkest back room floor (%s) gets %.2f of a pool (was 0.03)" % [worst_at, worst])


# --- 3: the training ------------------------------------------------------------------------------------------------------------------------------------

func _tutorial() -> void:
	var m := Game.missions as Missions
	var tut := (Game.story as Story).tutorial
	TestLib.check(tut != null and m.board != null, "the story has a tutorial and the board is there")
	if tut == null or m.board == null:
		return
	m.board.set_take_over(true)
	tut.stop()
	tut.force = true
	var prog := Game.progress as Progress
	if prog != null:
		prog.tutorial_done = false
	TestLib.check(Tutorial.board_owns_goals(), "in the live game the board owns the goals")
	TestLib.check(not tut.maybe_start() and not tut.active, "with the board in charge the training never starts (the first job is the training)")
	# a pill that is already up (an old save) gives way to a board job
	tut.begin()
	TestLib.check(tut.active, "a training that was started by hand is up")
	var o := m.board.build(&"patrol", p.global_position, true)
	TestLib.check(not o.is_empty(), "the board builds an offer")
	TestLib.check(not o.is_empty() and str(o.get("gift", "")) != "" and str(o["brief"]).contains(str(o["gift"])), "a card says what it hands out besides credits (%s)" % str(o.get("gift", "")))
	tut.force = false
	if not o.is_empty():
		TestLib.check(m.board.accept_offer(o), "the board takes the job")
		TestLib.check(await _wait(func() -> bool: return not tut.active, 3.0), "the training steps aside once the board job runs")
		m.board.abandon("TEST")
	tut.stop()
	await TestLib.frames(host, 2)


# --- 5: a vendor behind his counter -----------------------------------------------------------------------------------------------------------------------

func _vendor() -> void:
	var city := Game.world as City
	var amb: Node = city.ambient if city != null else null
	TestLib.check(amb != null and amb.get("crowd") != null, "the city has a crowd")
	if amb == null:
		return
	var crowd: RefCounted = amb.crowd
	Game.civilian_casualties = true
	# a plain walker 8 m ahead, and a wall (a car-sized box) 1.5 m in front of him: the wall is cover, the shot must not find him
	var i := -1
	for k in crowd.count:
		if crowd.is_alive(k) and not crowd.is_dying(k) and not crowd.is_vendor(k):
			i = k
			break
	TestLib.check(i >= 0, "a walker is alive")
	if i < 0:
		return
	var pos: Vector3 = crowd.person_position(i)
	var origin := Vector3(pos.x, pos.y + 1.2, pos.z - 8.0)
	var dir := Vector3(0.0, 0.0, 1.0)
	var open: Dictionary = amb.civilian_ray(origin, dir, 20.0)
	TestLib.check(not open.is_empty() and int(open["i"]) == i, "a walker in the open is hit by a ray at his chest")
	# a vendor: pin the same person to a stall (the crowd's own pin) and put a counter between
	crowd._pin[i] = 1
	var wall_before: Dictionary = amb.civilian_ray(origin, dir, 6.9)          # the world ray stopped 1.1 m short of him (the counter in front)
	TestLib.check(not wall_before.is_empty() and crowd.is_vendor(int(wall_before["i"])), "a vendor is found even when the world ray stopped at his counter 1.2 m in front of him")
	crowd._pin[i] = 0
	var wall_walker: Dictionary = amb.civilian_ray(origin, dir, 6.9)
	TestLib.check(wall_walker.is_empty(), "an ordinary walker behind a wall is still safe (only a vendor shows over the counter)")
	# the real shot: a counter box and a vendor, the hero's carbine, five shots at his chest
	crowd._pin[i] = 1
	p.global_position = Vector3(pos.x, 0.1, pos.z - 7.0)
	var counter := _block(Vector3(pos.x, 0.5, pos.z - 1.1), Vector3(2.0, 1.0, 0.5), Game.L_WORLD)
	await TestLib.frames(host, 3)
	var killed_before: int = crowd.killed_total
	var weapon := p.weapon
	weapon.switch_to(&"carbine", true)
	p.camera_rig.reset_view(0.0, 0.0)
	for n in 12:
		if not crowd.is_alive(i) or crowd.is_dying(i):
			break
		p.camera_rig.aim_at(crowd.person_position(i) + Vector3(0.0, 1.2, 0.0))
		await TestLib.frames(host, 2)
		weapon._trace_pellet()
		await TestLib.frames(host, 1)
	TestLib.check(crowd.killed_total > killed_before or crowd.is_dying(i) or not crowd.is_alive(i), "a vendor shot over his counter goes down (killed_total %d -> %d)" % [killed_before, crowd.killed_total])
	crowd._pin[i] = 0


# --- 11 / 7: pickups and the safe -----------------------------------------------------------------------------------------------------------------------

func _pickups_and_safe() -> void:
	var m := Game.missions as Missions
	m.drop(&"health", p.global_position + Vector3(3.0, 0.0, 0.0))
	var worst := 0.0
	for s: Dictionary in m._pickup_pool:
		if not bool(s["active"]):
			continue
		var mdl := (s["models"] as Dictionary)[&"health"] as Node3D
		var aabb := AABB()
		var first := true
		for mi in MissionVisuals.meshes_of(mdl):
			var a: AABB = (mi as MeshInstance3D).get_aabb()
			var sc := mdl.scale.x
			a.size *= sc
			aabb = a if first else aabb.merge(a)
			first = false
		worst = maxf(worst, maxf(aabb.size.x, aabb.size.y))
	TestLib.check(worst > 0.0 and worst <= 0.8, "a health pickup is %.2f m across (was 1.15 m: a giant block at the hero's side)" % worst)
	var im := InteriorMissions.new()
	host.add_child(im)
	im._make_safe(Vector3(0.0, 0.0, 200.0))
	var mesh := (im._prop as MeshInstance3D).mesh
	var box := mesh.get_aabb()
	TestLib.check(box.size.y >= 1.2 and box.size.x >= 1.0, "the safe is %.2f x %.2f m with a door, wheel and keypad (it was a 0.9 x 1.0 m cube)" % [box.size.x, box.size.y])
	TestLib.check(mesh.surface_get_array_len(0) > 150, "the safe has %d vertices of detail" % mesh.surface_get_array_len(0))
	im.queue_free()
	await TestLib.frames(host, 1)


# --- 12: the arena is a fight -----------------------------------------------------------------------------------------------------------------------------

func _arena() -> void:
	var m := Game.missions as Missions
	var k: CampaignRunner = m.campaign
	var board := m.board
	em.patrol_groups().clear()
	em.clear()
	Encounters.current.enabled = false
	Game.heat = 0.0
	if Game.story != null:
		(Game.story as Story).skip_cards()
	p.teleport_to(Vector3(-30.0, 0.0, 4.0))
	board.set_take_over(true)
	var o := board.build(&"arena", p.global_position)
	TestLib.check(not o.is_empty() and board.accept_offer(o), "the arena job starts")
	if o.is_empty():
		return
	# walk onto the ring, then the survive step runs
	var guard := 0
	Game.state = &"play"
	while guard < 200 and k.is_running() and str(k.step.get("kind", "")) != "survive":
		guard += 1
		if k.pos.is_finite():
			p.teleport_to(Vector3(k.pos.x, 0.0, k.pos.z))
		await TestLib.frames(host, 3)
	TestLib.check(k.is_running() and str(k.step.get("kind", "")) == "survive", "the survive step is running")
	if str(k.step.get("kind", "")) != "survive":
		return
	var hero := p.global_position
	var seen := await _wait(func() -> bool: return k.foes_alive() >= 3, 12.0)
	TestLib.check(seen, "a first wave of 3+ foes stands up (%d alive)" % k.foes_alive())
	var near := 0
	var far := 0.0
	for f: Variant in k.foes:
		var d := f as Drone
		if d != null and is_instance_valid(d) and d.active:
			var dist := Vector2(d.global_position.x - hero.x, d.global_position.z - hero.z).length()
			far = maxf(far, dist)
			if dist <= 45.0:
				near += 1
	TestLib.check(near >= 3 and far <= 70.0, "%d foes stand within 45 m of the hero (farthest %.0f m)" % [near, far])
	# the clock alone must not end it: run the hold to its end while the foes stand
	k._hold_t = float(k.step["hold"]) + 1.0
	await TestLib.frames(host, 6)
	TestLib.check(k.is_running() and str(k.step.get("kind", "")) == "survive", "past the clock the arena waits for the foes (%d alive)" % k.foes_alive())
	# beat them: the step ends
	for f: Variant in k.foes.duplicate():
		var d := f as Drone
		if d != null and is_instance_valid(d) and d.active and not d.dead:
			d.damage(1.0e6)
	var ended := await _wait(func() -> bool: return not k.is_running() or str(k.step.get("kind", "")) != "survive" or board.state != &"running", 6.0)
	TestLib.check(ended, "with the waves beaten the arena ends")
	if board.state == &"running":
		board.abandon("TEST")
	await TestLib.frames(host, 2)


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


## Polls `cond` on game time (physics frames) for up to `secs` seconds.
func _wait(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while t < secs:
		if cond.call():
			return true
		await TestLib.frames(host, 3)
		t += 3.0 / 60.0
	return cond.call()
