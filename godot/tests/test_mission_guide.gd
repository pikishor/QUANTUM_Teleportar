extends RefCounted
## The mission guide and the difficulty mercy (owner round 3: "the game does not seem obvious", "gets stuck in a task", "sometimes too hard") in the REAL game scene: the objective line between
## two steps and inside a building, the waypoint for it, the wander reminder, the stuck offer (SKIP STEP after 90 s without progress) and the game's own recovery, the compass bearing, the
## retry that starts at the fight, the bar a failed hold keeps, enemy aim error that grows with the player's wounds, and the mercy health pack.
## Run: tools/test.sh tests/test_mission_guide.gd

var host: Node
var camp: CampaignRunner
var p: Player
var done_steps := []


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_pure()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	p = Game.player as Player
	var m := Game.missions as Missions
	TestLib.check(p != null and m != null and m.campaign != null and m.campaign.guide != null, "the real scene has a player, missions and a campaign guide")
	if p == null or m == null:
		return
	camp = m.campaign
	camp.set_physics_process(false)
	camp.enabled = false
	(Game.progress as Progress).autosave_enabled = false
	camp.step_completed.connect(func(c: int, i: int, k: StringName) -> void: done_steps.append([c, i, k]))
	await _between_steps_and_indoors()
	await _wander_and_stuck()
	_retry_and_kept(m)
	_mercy(m)
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)


func _chapter(steps: Array) -> void:
	camp.abort()
	done_steps.clear()
	Game.heat = 0.0
	Game.state = &"play"
	camp.start_custom({"id": "guide_test", "clears_sector": false, "steps": steps})


func _pure() -> void:
	TestLib.check(MissionGuide.phrase("Hack the vault", 420.4) == "NEXT: HACK THE VAULT, 420 M", "the reminder reads 'NEXT: HACK THE VAULT, 420 M' (%s)" % MissionGuide.phrase("Hack the vault", 420.4))
	TestLib.check(MissionGuide.phrase("Go", 0.2) == "NEXT: GO", "no distance when it is under a metre")
	var ahead := MissionGuide.compass_bearing(Vector3.ZERO, Vector3(0, 0, -50), 0.0)
	var right := MissionGuide.compass_bearing(Vector3.ZERO, Vector3(50, 0, 0), 0.0)
	var left := MissionGuide.compass_bearing(Vector3.ZERO, Vector3(-50, 0, 0), 0.0)
	var behind := MissionGuide.compass_bearing(Vector3.ZERO, Vector3(0, 0, 50), 0.0)
	TestLib.check(absf(ahead) < 0.01 and right > 1.4 and left < -1.4 and absf(absf(behind) - PI) < 0.01, "compass: ahead 0, right +90, left -90, behind 180 degrees (%.2f %.2f %.2f %.2f)" % [ahead, right, left, behind])
	TestLib.check(MissionGuide.compass_bearing(Vector3.ZERO, Vector3(0, 0, -50), PI * 0.5) > 1.4, "turning left (positive yaw) puts a goal that was ahead on the right of the compass")
	TestLib.check(is_equal_approx(Difficulty.hurt_aim(1.0, 1), 1.0) and Difficulty.hurt_aim(0.0, 0) > Difficulty.hurt_aim(0.0, 1) and Difficulty.hurt_aim(0.0, 1) > Difficulty.hurt_aim(0.0, 3), "enemy aim error grows as health drops, most on STORY, least on QUANTUM")
	TestLib.check(Difficulty.hurt_aim(0.33, 1) > 1.5 and Difficulty.hurt_aim(0.33, 1) < 1.7, "NORMAL at a third of the health: about 1.6x the error (%.2f)" % Difficulty.hurt_aim(0.33, 1))
	TestLib.check(Difficulty.mercy_below(0) > Difficulty.mercy_below(1) and Difficulty.mercy_below(1) > Difficulty.mercy_below(2) and Difficulty.mercy_below(3) == 0.0, "the mercy threshold is highest on STORY and off on QUANTUM")


func _between_steps_and_indoors() -> void:
	var ig := InteriorGameplay.instance
	_chapter([{"kind": "reach", "pos": [-100.0, 0.0], "obj": "Reach the first beacon"}, {"kind": "reach", "pos": [-200.0, 0.0], "obj": "Cross to the vault"}])
	var g := camp.guide
	TestLib.check(camp.state == &"armed" and g.line() == "NEXT  REACH THE FIRST BEACON", "armed: the line says what comes next (%s)" % g.line())
	TestLib.check(g.waypoint().has("pos") and (g.waypoint()["pos"] as Vector3).distance_to(Vector3(-100, 0, 0)) < 1.0, "armed: the waypoint is the next goal")
	camp.tick(0.1)
	await TestLib.frames(host, 2)
	TestLib.check(camp.state == &"active" and g.line() == "", "active: the step's own line takes over (%s)" % camp.hud_line())
	# done: the next step is armed after the breath; inside a building it asks the player out
	camp.skip_step()
	TestLib.check(camp.state == &"armed" and g.line() == "NEXT  CROSS TO THE VAULT", "between steps: NEXT line again (%s)" % g.line())
	if ig != null:
		TestLib.check(ig.test_enter(&"lobby").begins_with("INSIDE"), "(the player goes into a lobby)")
		await TestLib.frames(host, 2)
		TestLib.check(InteriorGameplay.active and g.line() == "LEAVE THE BUILDING TO CONTINUE", "armed inside a building the line says LEAVE THE BUILDING TO CONTINUE (%s)" % g.line())
		var w := g.waypoint()
		TestLib.check(w.has("pos") and (w["pos"] as Vector3).distance_to(InteriorGameplay.exit_point(ig.interior)) < 0.1, "...and the waypoint is the way out")
		for i in 50:
			g.tick(1.0)
		TestLib.check(not InteriorGameplay.active and g.recoveries == 1, "a player who stays inside is put back on the street after %d s (%s)" % [int(MissionGuide.ARMED_STUCK), g.last_reason])
	camp.abort()


func _wander_and_stuck() -> void:
	var g := camp.guide
	# a step that never gets closer: reminder, then the SKIP STEP offer, then the game's own recovery
	_chapter([{"kind": "hack", "pos": [-300.0, 0.0], "obj": "Hack the ledger node", "radius": 10.0}, {"kind": "reach", "pos": [-100.0, 0.0], "obj": "Go on"}])
	camp.tick(0.1)
	camp.tick(2.0)
	await TestLib.frames(host, 2)
	camp.tick(0.1)
	TestLib.check(camp.state == &"active" and camp.kind == &"hack", "the hack step runs (%s)" % str(camp.state))
	p.global_position = Vector3(-30.0, 0.0, 4.0)
	g.reminders = 0
	var said: Array[String] = []
	var on_say := func(text: String, _s: float) -> void: said.append(text)
	Game.message.connect(on_say)
	for i in int(MissionGuide.WANDER_AFTER) + 6:
		g.tick(1.0)
	TestLib.check(g.reminders >= 1 and said.any(func(t: String) -> bool: return t.begins_with("NEXT: HACK THE LEDGER NODE, ")), "a player who is not getting closer hears 'NEXT: HACK THE LEDGER NODE, n M' (%s)" % str(said.slice(-3)))
	TestLib.check(not g.offering, "...and no skip is offered yet")
	for i in int(MissionGuide.STUCK_OFFER):
		g.tick(1.0)
	TestLib.check(g.offering and g.offers == 1, "after %d s without progress SKIP STEP is offered" % int(MissionGuide.STUCK_OFFER))
	var hud := host.get_tree().root.find_child("Hud", true, false) as Hud
	if hud != null:
		TestLib.check(hud.skip_available() and hud.step_skip_offered(), "the HUD shows the SKIP STEP button")
		TestLib.check(hud.skip_set_piece() and done_steps.size() == 1 and not g.offering, "tapping it finishes the step (%s)" % str(done_steps))
	else:
		g.skip_step()
	TestLib.check(g.skips == 1 and camp.state == &"armed", "the step is done and the next one is armed")
	# the same stuck step again: nobody taps, the game recovers by itself
	camp.abort()
	_chapter([{"kind": "reach", "pos": [-300.0, 0.0], "obj": "Cross the river"}])
	camp.tick(0.1)
	camp.tick(2.0)
	await TestLib.frames(host, 2)
	TestLib.check(camp.state == &"active", "(another step)")
	p.global_position = Vector3(-30.0, 0.0, 4.0)
	g.recoveries = 0
	for i in int(MissionGuide.STUCK_OFFER + MissionGuide.STUCK_RECOVER) + 2:
		g.tick(1.0)
	var now := p.global_position
	TestLib.check(g.recoveries == 1 and camp.state == &"active" and Vector2(camp.pos.x - now.x, camp.pos.z - now.z).length() < 40.0, "no progress for %d s: the goal is moved beside the player (%.0f m)" % [int(MissionGuide.STUCK_OFFER + MissionGuide.STUCK_RECOVER), Vector2(camp.pos.x - now.x, camp.pos.z - now.z).length()])
	for i in int(MissionGuide.STUCK_OFFER + MissionGuide.STUCK_RECOVER) + 2:
		g.tick(1.0)
		if camp.state != &"active":
			break
	TestLib.check(g.recoveries >= 2 and (camp.state == &"done" or done_steps.size() >= 1), "still stuck: the step is completed by the game (%s)" % g.last_reason)
	Game.message.disconnect(on_say)
	camp.abort()


func _retry_and_kept(_m: Missions) -> void:
	_chapter([{"kind": "hack", "pos": [-160.0, 0.0], "obj": "Hack it", "hold": 40.0, "radius": 10.0}])
	camp.tick(0.1)
	camp.tick(2.0)
	if camp.state != &"active":
		camp.tick(2.0)
	TestLib.check(camp.state == &"active" and camp.kind == &"hack", "(a hack step to fail)")
	camp.progress = 0.8
	var spot := camp._retry_spot()
	TestLib.check(spot.is_finite() and Vector2(spot.x - camp.pos.x, spot.z - camp.pos.z).length() < CampaignRunner.RETRY_DIST + 45.0, "a hack retry starts near the node, not at the old checkpoint (%.0f m from it)" % Vector2(spot.x - camp.pos.x, spot.z - camp.pos.z).length())
	camp._fail("TEST")
	TestLib.check(is_equal_approx(float(camp._kept.get(0, 0.0)), 0.4), "half of the bar the player had reached is kept for the retry (%s)" % str(camp._kept))
	camp._restart_step(true)
	camp.tick(2.0)
	camp.tick(0.1)
	TestLib.check(camp.state == &"active" and camp.progress >= 0.39, "the retried hack starts at 40 %% (%.2f)" % camp.progress)
	camp.abort()


func _mercy(m: Missions) -> void:
	var saved := Difficulty.current
	Difficulty.set_mode(1)
	Game.state = &"play"
	camp.abort()
	var em := Game.enemies as EnemyManager
	em.clear()
	m.clear_pickups()
	p.global_position = Vector3(-30.0, 0.0, 4.0)
	p.hp = p.max_hp * 0.15
	var foe := em.spawn(&"operative", Vector3(-10.0, 0.0, 4.0), true)
	TestLib.check(foe != null, "(a hostile near the wounded player)")
	var before := m.mercy_drops
	m._mercy_cd = 0.0
	m._tick_mercy(0.1, p, p.global_position)
	TestLib.check(m.mercy_drops == before + 1 and m.pickups.any(func(s: Dictionary) -> bool: return s.kind == &"health"), "NORMAL, 15 %% health, an enemy in sight: a health pack drops nearby (%d)" % m.mercy_drops)
	m._tick_mercy(0.1, p, p.global_position)
	TestLib.check(m.mercy_drops == before + 1, "only one per cooldown")
	p.hp = p.max_hp
	m._mercy_cd = 0.0
	var n := m.mercy_drops
	m._tick_mercy(0.1, p, p.global_position)
	TestLib.check(m.mercy_drops == n, "none for a healthy player")
	Difficulty.set_mode(3)
	p.hp = p.max_hp * 0.05
	m._mercy_cd = 0.0
	m._tick_mercy(0.1, p, p.global_position)
	TestLib.check(m.mercy_drops == n, "none on QUANTUM")
	Difficulty.set_mode(saved)
	em.clear()
	p.hp = p.max_hp
