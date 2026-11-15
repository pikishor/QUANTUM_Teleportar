extends RefCounted
## WAVE 115 CRITIC (lens PLAY): regression tests for the functional defects found by playing the QUANTUM SNAKES in the real scene (main.tscn, the real hero, the real city), measured with
## the probes tests/dev_w115p_*.gd (docs/sprint/progress/w115-critic-play.md has the numbers):
##  1 a TAP of SNAKE in the air (a thumb: 0.05 to 0.2 s) fired the snake and then cancelled it before it bit (only a press of 0.3 s and more swung): the shot is committed, the swing hangs at least TAP_HANG
##  2 a snake power armed from the weapon wheel put the gun away and NOTHING brought it back (the swap button, the number keys and the wheel left FIRE casting the power with every new gun holstered and silent)
##  3 the tutorial SWING ACROSS THE CITY ends with FLY and LAND, which HARD and QUANTUM could not do without a WING POWER rank (flight is open while the tutorial runs)
##  4 the SNAKE ARENA / ROOFTOP SNAKE HUNT injection replaced a world mission of the lodge board (test_world_missions "a world mission every time")
##  5 the snake pose basis stays finite and orthonormal when its inputs are degenerate (a zip whose target is the hero's own spot)
##  6 the verbs against LIVE enemies (aware, shooting, moving: the builders' test stages dummies with their physics off): PULL, NET and GRAB-and-throw leave no hold, no snake and no enemy in a bad place
##  7 the pre-warm of the snake visuals (SnakeWarm, run by ShaderWarmup): the first swing no longer compiles the tendril, speed-line, swarm and aim pipelines (tests/bot_w115p_firstuse.gd counts them); afterwards nothing is left behind
##  8 the SNAKE HUNTER stands where it can fight (10 % of its old random spots were inside a building, 8 % behind a wall)
##  9 the swing legs of the tutorial: the next roof is one with an anchor above the roof edge and not much higher (7 of 12 legs had none: the held button turned into a flight, the step asks for a swing)
## Waits on counters and state, never on frame counts; user:// state is reset.
## Run: tools/test.sh tests/test_play_critic_w115.gd   (about 60 s)

const TIMEOUT_SECONDS := 140.0

var host: Node
var p: Player
var sn: SnakeTraversal
var war: SnakeWar
var main: Node


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func until(cond: Callable, secs: float) -> bool:
	var n := int(secs * 60.0)
	while n > 0 and not cond.call():
		await frames(1)
		n -= 1
	return cond.call()


func release_all() -> void:
	for a in [&"snake", &"fly", &"jump", &"move_forward", &"move_back", &"move_left", &"move_right", &"crouch", &"sprint", &"fire", &"swap", &"altfire", &"weapon_2"]:
		Input.action_release(a)


func prep(pos: Vector3, yaw := -PI * 0.5, pitch := 0.0) -> void:
	release_all()
	sn.cancel()
	TrafficField.bare_street()
	p.invuln = 0.0
	p.hp = p.max_hp
	sn.energy = SnakePower.max_energy()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	await frames(12)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	SnakeMissions.reset_flags()
	SnakeWarMissions.reset_flags()
	var mode0 := Difficulty.current
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	sn = p.snake
	war = SnakeWar.of(p)
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	Game.state = &"play"
	TestMode.god = true
	Difficulty.set_mode(1)
	SnakeTraversal.assist = true
	await _air_taps()
	await _gun_comes_back()
	await _tutorial_flight()
	_board_injection()
	_pose_basis()
	await _live_enemies()
	await _prewarm()
	await _hunter_spots()
	await _tutorial_roofs()
	release_all()
	TestMode.god = false
	WeaponDefs.hero_mode = false
	Difficulty.set_mode(mode0)
	SnakeMissions.reset_flags()
	SnakeWarMissions.reset_flags()
	main.queue_free()
	await frames(3)


# --- 1 a tap on SNAKE in the air -----------------------------------------------------------------------------------------------------------

func _air_taps() -> void:
	for ticks in [3, 6, 12, 20]:
		await prep(Vector3(-30.0, 40.0, 4.0), -PI * 0.5, 0.2)
		var bit0 := sn.swing.swings
		var rel0 := sn.swing.releases
		var wf0 := sn.whiffs
		Input.action_press(&"snake")
		await frames(ticks)
		Input.action_release(&"snake")
		var bit := await until(func() -> bool: return sn.swing.swings > bit0, 1.5)
		TestLib.check(bit, "a tap of %.2f s on SNAKE in the air still bites (the shot is no longer cancelled while the head travels)" % (float(ticks) / 60.0))
		var released := await until(func() -> bool: return sn.swing.releases > rel0, 2.0)
		TestLib.check(released and sn.mode != SnakeTraversal.Mode.SWING, "and the tapped swing lets go by itself (%s)" % sn.mode_name())
		var hang := 0.0
		if not sn.swing.log.is_empty():
			hang = float((sn.swing.log[sn.swing.log.size() - 1] as Dictionary).get("hang", 0.0))
		TestLib.check(hang >= SnakeSwing.TAP_HANG - 0.06, "after a hang of at least %.2f s, not at the first tick (%.2f s)" % [SnakeSwing.TAP_HANG, hang])
		TestLib.check(sn.whiffs == wf0, "a tap is never reported as a miss")
	# a long hold still hangs on to the button: the release comes when the finger lets go
	await prep(Vector3(-30.0, 40.0, 4.0), -PI * 0.5, 0.2)
	Input.action_press(&"snake")
	var hanging := await until(func() -> bool: return sn.swing.is_hanging(), 2.0)
	await frames(45)
	TestLib.check(hanging and sn.swing.active, "a held button keeps the swing hanging (the minimum hang does not shorten a hold)")
	var v0 := p.velocity.length()
	Input.action_release(&"snake")
	await frames(3)
	TestLib.check(not sn.swing.active and p.velocity.length() >= minf(v0, 10.0), "and letting go ends it with the speed kept (%.1f then %.1f m/s)" % [v0, p.velocity.length()])
	release_all()


# --- 2 a snake power armed from the wheel never took the gun's place back ----------------------------------------------------------------------

func _gun_comes_back() -> void:
	await prep(Game.SPAWN)
	var w := p.weapon
	var gun0 := w.current
	TestLib.check(war.arm(&"sv_pull") and SnakeWar.holding(), "arming SNAKE PULL puts the power in the hand")
	# 1 the WEAPON button (the swap action)
	Input.action_press(&"swap")
	await frames(4)
	Input.action_release(&"swap")
	await frames(4)
	TestLib.check(not SnakeWar.holding() and w.current == gun0, "a tap on WEAPON puts the snake power away and the gun in hand comes back (%s)" % str(w.current))
	var ammo0 := w.ammo
	Input.action_press(&"fire")
	await until(func() -> bool: return w.ammo < ammo0, 1.5)
	Input.action_release(&"fire")
	TestLib.check(w.ammo < ammo0, "and FIRE shoots it again (%d -> %d rounds)" % [ammo0, w.ammo])
	# the next tap cycles the guns as before
	var before := w.current
	Input.action_press(&"swap")
	await frames(4)
	Input.action_release(&"swap")
	await frames(4)
	TestLib.check(w.current != before or WeaponDefs.owned_ordered().size() < 2, "with no power in hand a tap on WEAPON still cycles the guns (%s -> %s)" % [str(before), str(w.current)])
	# 2 a number key
	war.arm(&"sb_coil")
	TestLib.check(SnakeWar.holding(), "a bomb armed")
	Input.action_press(&"weapon_2")
	await frames(4)
	Input.action_release(&"weapon_2")
	await frames(4)
	TestLib.check(not SnakeWar.holding(), "a number key puts it away and selects that gun (%s)" % str(w.current))
	# 3 a pick on the weapon wheel: a weapon disc, also the gun already in hand
	war.arm(&"sv_net")
	var cur := w.current
	WeaponWheel.activate({"id": cur, "type": &"weapon"}, w)
	TestLib.check(not SnakeWar.holding() and w.current == cur, "picking the gun that is already in hand on the wheel puts the power away (no equip happens then)")
	war.arm(&"sv_grab")
	var items := WeaponWheel.items()
	for it: Dictionary in items:
		if StringName(it.get("type", &"class")) == &"class" and WeaponDefs.class_of(w.current) != StringName(it["id"]) and bool(it.get("ready", true)) and not WeaponDefs.owned_in_class(StringName(it["id"])).is_empty():
			WeaponWheel.activate(it, w)
			break
	TestLib.check(not SnakeWar.holding(), "picking another gun class on the wheel puts it away too")
	# 4 the equip signal covers every other way a gun is put in the hand (a pickup, a mission, the shop)
	war.arm(&"sv_decoy")
	var other := &"pistol" if w.current != &"pistol" else &"carbine"
	w.switch_to(other, true)
	TestLib.check(not SnakeWar.holding(), "any equip (a pickup, the shop, a mission) brings the gun back")
	# 5 the power still works when it is armed and used (nothing broke the normal path)
	war.arm(&"sv_shield")
	TestLib.check(war.cast(&"sv_shield", true) and not war.verbs.shield.is_empty(), "a power in hand still casts")
	war.disarm()
	war.reset()


# --- 3 the tutorial needs flight on every difficulty ---------------------------------------------------------------------------------------

func _tutorial_flight() -> void:
	var board := (Game.missions as Missions).board
	var camp := (Game.missions as Missions).campaign
	Difficulty.set_mode(2)                                                    # HARD: flight needs a WING POWER rank
	SnakeMissions.reset_flags()
	TestLib.check(not SnakePower.flight_unlocked(), "on HARD the flight is locked without a WING POWER rank")
	await prep(Vector3(3000.0, 0.0, 200.0), 0.0, -0.1)
	var f0 := sn.flights
	Input.action_press(&"fly")
	await frames(4)
	Input.action_release(&"fly")
	await frames(20)
	TestLib.check(sn.flights == f0 and sn.mode == SnakeTraversal.Mode.NONE, "FLY does nothing there (WING POWER LOCKED)")
	await prep(Game.SPAWN)
	var tut := board.build(&"swing_city", Game.SPAWN)
	TestLib.check(not tut.is_empty(), "the board builds SWING ACROSS THE CITY")
	if tut.is_empty():
		Difficulty.set_mode(1)
		return
	TestLib.check(camp.start_custom(tut["chapter"]), "the runner starts the tutorial chapter")
	var open := await until(func() -> bool: return SnakePower.flight_unlocked(), 2.0)
	TestLib.check(open and SnakeMissions.tutorial_running, "while the tutorial runs, flight is open on HARD (its FLY and LAND steps need it)")
	sn.energy = SnakePower.max_energy()
	p.teleport_to(Vector3(3000.0, 0.0, 200.0))
	p.camera_rig.reset_view(0.0, -0.1)
	await frames(15)
	Input.action_press(&"fly")
	await frames(4)
	Input.action_release(&"fly")
	var flew := await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.FLY, 1.5)
	TestLib.check(flew, "and FLY takes off on HARD during the tutorial")
	sn.cancel()
	camp.abort()
	var shut := await until(func() -> bool: return not SnakeMissions.tutorial_running, 2.0)
	TestLib.check(shut and not SnakePower.flight_unlocked(), "when the tutorial is over the flight is locked again on HARD")
	Difficulty.set_mode(1)
	SnakeMissions.reset_flags()
	await prep(Game.SPAWN)


# --- 4 the board injection ---------------------------------------------------------------------------------------------------------------------

func _board_injection() -> void:
	SnakeWarMissions.reset_flags()
	var kept := 0
	var tried := 0
	for seed_i in 80:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + seed_i
		var picks: Array[StringName] = [&"kill_patrol", &"delivery", &"heli_extract"]
		var out := SnakeWarMissions.inject(picks, rng)
		tried += 1
		if out.has(&"heli_extract"):
			kept += 1
	TestLib.check(kept == tried, "SNAKE ARENA / SNAKE HUNT never replace a world mission of the board (%d of %d boards kept it)" % [kept, tried])
	var injected := 0
	for seed_j in 80:
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 2000 + seed_j
		var picks2: Array[StringName] = [&"kill_patrol", &"delivery", &"rescue"]
		var out2 := SnakeWarMissions.inject(picks2, rng2)
		if out2.has(&"snake_arena") or out2.has(&"snake_hunt"):
			injected += 1
	TestLib.check(injected > 5 and injected < 60, "and a board of plain missions still gets one now and then (%d of 80)" % injected)
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 5
	var all_world: Array[StringName] = [&"heli_extract", &"heli_extract", &"heli_extract"]
	var keep := SnakeWarMissions.inject(all_world, rng3)
	TestLib.check(keep == all_world, "a board of nothing but world missions is left alone")


# --- 5 the pose basis ---------------------------------------------------------------------------------------------------------------------------

func _pose_basis() -> void:
	var pose := sn.pose
	var mode0 := sn.mode
	var dest0 := sn.zip.dest
	sn.mode = SnakeTraversal.Mode.ZIP
	sn.zip.phase = &"pull"
	sn.zip.dest = p.global_position                                       # a zip whose target is his own spot: a zero direction
	pose.update(sn, 0.016)
	var b := pose.basis
	var finite := b.x.is_finite() and b.y.is_finite() and b.z.is_finite()
	TestLib.check(finite and absf(b.x.length() - 1.0) < 0.01 and absf(b.y.length() - 1.0) < 0.01 and absf(b.z.length() - 1.0) < 0.01, "the snake pose basis stays finite and orthonormal for a zero zip direction")
	var q := Quaternion(b.orthonormalized())
	TestLib.check(q.is_finite(), "and turns into a clean quaternion")
	sn.zip.dest = dest0
	sn.mode = mode0
	pose.reset()


# --- 6 the verbs against live enemies --------------------------------------------------------------------------------------------------------------

var _spot := Vector3.ZERO
var _lane_yaw := 0.0


func _lane() -> bool:
	var city := Game.world as City
	var space := p.get_world_3d().direct_space_state
	for tries in 600:
		var rp: Vector3 = city.random_core_road_point()
		if not rp.is_finite():
			continue
		for k in 8:
			var yaw := TAU * float(k) / 8.0
			var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var a := rp + Vector3(0, 1.5, 0)
			var ok := true
			for off in [-5.0, 0.0, 5.0]:
				var side := dir.cross(Vector3.UP) * float(off)
				var q := PhysicsRayQueryParameters3D.create(a + side, a + side + dir * 40.0, Game.L_WORLD | Game.L_VEHICLE)
				if not space.intersect_ray(q).is_empty():
					ok = false
					break
			if ok:
				_spot = rp
				_lane_yaw = yaw
				return true
	return false


func _live_enemies() -> void:
	WeaponDefs.hero_mode = true                                              # every verb open, no energy, no cooldown: the test is about the verbs against enemies that fight back
	TestLib.check(_lane(), "an open lane in the city was found")
	var em := Game.enemies as EnemyManager
	var dir := Vector3(-sin(_lane_yaw), 0.0, -cos(_lane_yaw))
	var right := Vector3(cos(_lane_yaw), 0.0, -sin(_lane_yaw))
	for vid in [&"sv_pull", &"sv_net", &"sv_grab"]:
		war.reset()
		war.disarm()
		em.clear()
		p.teleport_to(_spot)
		p.camera_rig.reset_view(_lane_yaw, -0.04)
		p.yaw = _lane_yaw
		p.velocity = Vector3.ZERO
		sn.cancel()
		var foes: Array[Drone] = []
		for i in 3:
			var pos := _spot + dir * (11.0 + 2.0 * float(i)) + right * (float(i - 1) * 2.4)
			pos.y = _spot.y
			var f := em.spawn(&"operative", pos, true)
			if f != null:
				foes.append(f)
		await frames(15)
		TestLib.check(foes.size() == 3, "%s: three live operatives stand on the lane" % str(vid))
		var casts0 := war.casts
		war.arm(vid)
		var first := foes[0]
		p.camera_rig.aim_at(SnakeAim.center_of(first))
		await frames(2)
		var d0 := first.global_position.distance_to(p.global_position)
		Input.action_press(&"fire")
		if vid == &"sv_grab":
			await until(func() -> bool: return war.verbs.is_grabbing(), 1.5)
			await frames(40)
		else:
			await frames(6)
		Input.action_release(&"fire")
		await frames(30)
		TestLib.check(war.casts > casts0, "%s: FIRE casts it at an enemy that moves and shoots back" % str(vid))
		if vid == &"sv_pull":
			TestLib.check(war.verbs.pulls >= 1 and (not is_instance_valid(first) or first.global_position.distance_to(p.global_position) < d0 - 2.0), "PULL drags a live enemy toward the hero (%.1f m before)" % d0)
		if vid == &"sv_grab":
			TestLib.check(war.verbs.throws >= 1 or not war.verbs.is_grabbing(), "letting go of the grab throws the body (the hold ends)")
		await until(func() -> bool: return war.holds.recs.is_empty(), 9.0)
		TestLib.check(war.holds.recs.is_empty(), "%s: no hold is left 9 s later (a stuck net or wrap would freeze an enemy for ever)" % str(vid))
		var bad := 0
		for f in foes:
			if is_instance_valid(f) and not f.dead:
				if not f.global_position.is_finite() or f.global_position.y < -2.0:
					bad += 1
		TestLib.check(bad == 0, "%s: every live enemy stands somewhere sane afterwards" % str(vid))
		var gone := await until(func() -> bool: return SnakeSwarm.current == null or SnakeSwarm.current.count() <= 1, 6.0)
		TestLib.check(gone, "%s: its snakes are gone again (%d left)" % [str(vid), SnakeSwarm.current.count() if SnakeSwarm.current != null else 0])
		war.disarm()
	em.clear()
	war.reset()
	WeaponDefs.hero_mode = false


# --- 7 the pre-warm of the snake visuals ---------------------------------------------------------------------------------------------------------

func _prewarm() -> void:
	await prep(Vector3(3000.0, 0.0, 200.0), 0.0, -0.1)                       # open ground: nothing to bite or zip to, so the marker is never wanted
	var cam := Game.camera
	var at := cam.global_position - cam.global_basis.z * 8.0
	var fx := p.get_node("SnakeFx") as SnakeFx
	sn.preview = {}                                                          # (a preview of the spot he came from would make the marker wanted again)
	fx.warm_end()                                                            # the swings of the sections above made the lazy nodes: back to the idle state
	await frames(4)
	TestLib.check(fx.get_node_or_null("SpeedLines") == null and fx.get_node_or_null("AnchorMarker") == null, "an idle hero carries no speed-line layer and no marker before the pre-warm")
	var n := SnakeWarm.begin(at)
	TestLib.check(n >= 9, "the pre-warm shows tendrils, free snakes, the speed lines, the marker and the aim previews (%d items)" % n)
	TestLib.check(SnakeTendrilPool.current != null and SnakeTendrilPool.current.count() >= 2 and SnakeSwarm.current != null and SnakeSwarm.current.count() >= 3, "tendrils and snakes are alive in front of the camera while it runs")
	TestLib.check(fx.get_node_or_null("SpeedLines") != null and fx.get_node_or_null("AnchorMarker") != null, "and so are the speed-line layer and the anchor marker")
	await frames(3)
	sn.preview = {}
	SnakeWarm.end()
	await frames(4)
	TestLib.check(SnakeTendrilPool.current.count() == 0 and SnakeSwarm.current.count() == 0, "afterwards no tendril and no snake is left")
	TestLib.check(fx.get_node_or_null("SpeedLines") == null and fx.get_node_or_null("AnchorMarker") == null, "the speed-line layer and the marker are gone again (the perf gate counted two draws for them at MED)")
	TestLib.check(war.armed == &"" and not SnakeWar.holding() and BlastPreview.radius_shown == 0.0 and war.preview_radius == 0.0, "no power is armed and no aim ring is shown")
	TestLib.check(sn.mode == SnakeTraversal.Mode.NONE and sn.energy >= SnakePower.max_energy() - 0.5, "the hero's snake state and energy are untouched")
	# the real thing: ShaderWarmup.run calls it, twice in a row without leaving anything
	var res: Dictionary = await ShaderWarmup.run(host, true)
	TestLib.check(int(res.get("items", 0)) >= 20, "ShaderWarmup.run includes the snake items (%d in all)" % int(res.get("items", 0)))
	await frames(3)
	TestLib.check(SnakeTendrilPool.current.count() == 0 and SnakeSwarm.current.count() == 0 and fx.get_node_or_null("SpeedLines") == null and fx.get_node_or_null("AnchorMarker") == null and not SnakeWar.holding(), "and puts everything back")


# --- 8 the snake hunter's spot ---------------------------------------------------------------------------------------------------------------------

func _hunter_spots() -> void:
	Difficulty.set_mode(1)                                                    # NORMAL: a hunter comes after a run of snake powers
	var em := Game.enemies as EnemyManager
	var city := Game.world as City
	city.collision_chunks().activate_all()
	await frames(4)
	var react := war.react
	var space := p.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var placed := 0
	var inside := 0
	var blocked := 0
	for i in 12:
		em.clear()
		p.teleport_to(city.random_core_road_point())
		await frames(6)
		react._casts.clear()
		for k in 10:
			react._casts.append(react._now)
		react._hunter_cd = 0.0
		var h0 := react.hunters
		for tries in 12:                                                      # a try is half a second apart in the game; here every call
			react._hunter_try_t = 0.0
			react._try_hunter()
			if react.hunters > h0:
				break
		if react.hunters == h0:
			continue
		placed += 1
		for e: Node3D in Gear.living_enemies(p.get_tree()):
			if StringName(e.get(&"type")) != &"hunter":
				continue
			var pq := PhysicsPointQueryParameters3D.new()
			pq.position = e.global_position + Vector3(0.0, 1.0, 0.0)
			pq.collision_mask = Game.L_WORLD
			if not space.intersect_point(pq, 1).is_empty():
				inside += 1
			if not SnakeAim.clear_line(p, e.global_position + Vector3(0.0, 1.4, 0.0), p.global_position + Vector3(0.0, 1.2, 0.0)):
				blocked += 1
	em.clear()
	TestLib.check(placed >= 9, "a hunter is called at %d of 12 street spots (the others had no good place in ten tries and try again half a second later)" % placed)
	TestLib.check(inside == 0 and blocked == 0, "and none stands inside a building (%d) or behind a wall from the hero (%d)" % [inside, blocked])


# --- 9 the swing legs of the tutorial ----------------------------------------------------------------------------------------------------------------

func _tutorial_roofs() -> void:
	var city := Game.world as City
	city.collision_chunks().activate_all()
	await frames(6)                                                           # the colliders of the outer districts reach the physics server one tick later
	# open ground: no roof under the first point, so the predicate says "unknown" (-1) and the picker falls back to the old random choice
	TestLib.check(SnakeMissions.swing_possible(Vector3(3000.0, 30.0, 200.0), Vector3(3100.0, 30.0, 200.0)) == -1, "no roof, no verdict (-1: the old random pick stays)")
	seed(7)
	var tried := 0
	var old_n := 0                                                            # boards whose first swing leg (a -> b) has an anchor above the roof edge: the old random pick of b
	var new_n := 0                                                            # the same with SnakeMissions._pick_swingable
	var worse := 0
	var level_cases := 0
	var rule_broken := 0
	for mi in 30:
		var o := city.random_core_road_point()
		o.y = 0.0
		var r0 := RandomNumberGenerator.new()
		r0.seed = 900 + mi
		var a := SnakeMissions._pick(SnakeMissions.roofs(o, 55.0, 120.0, 26.0, 70.0), r0)
		if a.is_empty():
			continue
		var apos: Vector3 = a["pos"]
		var list_b := SnakeMissions.roofs(apos, 95.0, 160.0, 26.0, 90.0, [apos])
		var r1 := RandomNumberGenerator.new()
		r1.seed = 5000 + mi
		var r2 := RandomNumberGenerator.new()
		r2.seed = 5000 + mi
		var b_old := SnakeMissions._pick(list_b, r1)
		var b_new := SnakeMissions._pick_swingable(list_b, apos, r2)
		if b_old.is_empty() or b_new.is_empty():
			continue
		tried += 1
		var so := SnakeMissions.swing_possible(apos, b_old["pos"] as Vector3)
		var sn2 := SnakeMissions.swing_possible(apos, b_new["pos"] as Vector3)
		old_n += 1 if so == 1 else 0
		new_n += 1 if sn2 == 1 else 0
		if so == 1 and sn2 != 1:
			worse += 1
		var level_exists := false                                             # a level or downhill roof with an anchor among the nearest ten: the pick must be one
		for i in mini(list_b.size(), 10):
			var bp: Vector3 = list_b[i]["pos"]
			if bp.y - apos.y <= SnakeMissions.SWING_RISE_MAX and SnakeMissions.swing_possible(apos, bp) == 1:
				level_exists = true
		if level_exists:
			level_cases += 1
			if (b_new["pos"] as Vector3).y - apos.y > SnakeMissions.SWING_RISE_MAX or sn2 != 1:
				rule_broken += 1
	TestLib.check(tried >= 24, "the tutorial legs were measured on %d boards" % tried)
	TestLib.check(worse == 0, "the swing-aware pick never turns a roof with an anchor into one without (%d of %d boards)" % [worse, tried])
	TestLib.check(new_n >= old_n + 3, "and finds an anchor above the roof edge for more first legs than the old random pick (%d against %d of %d boards)" % [new_n, old_n, tried])
	TestLib.check(level_cases >= 6 and rule_broken == 0, "whenever a level roof with an anchor stands in reach the pick is one (%d of %d boards)" % [level_cases - rule_broken, level_cases])
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var rec := SnakeMissions.build(&"swing_city", 1, city.random_core_road_point(), rng)
	TestLib.check(rec.is_empty() or (rec["steps"] as Array).size() == 6, "the tutorial still builds its six steps")
