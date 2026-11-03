extends RefCounted
## Wave 50 variety in the REAL game scene (scenes/main.tscn): pouncer / mender / wisp and the bosses SKIMMER (hover skiff, COLLAPSE crashes it) and PHASEWRIGHT (QUANTUM TELEPORT):
## each spawns through the live EnemyManager and dies once; chapter tables, colours, boss cutscene hook and the two boss mechanics. Run: tools/test.sh tests/test_new_enemies_bosses.gd

const NEW: Array[StringName] = [&"pouncer", &"mender", &"wisp", &"skimmer", &"phasewright"]


func run(host: Node) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://progress.cfg"))
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	Game.state = &"play"
	var em := Game.enemies as EnemyManager
	TestLib.check(em != null, "the live game has an EnemyManager")
	if em == null:
		return
	em.patrol_groups().clear()
	em.set_physics_process(false)                 # spawn and kill by hand, no reinforcements
	var p: Node3D = Game.player
	p.set(&"max_hp", 1.0e6)
	p.set(&"hp", 1.0e6)
	_tables()
	var at := p.global_position + Vector3(14.0, 0.0, 0.0)
	for t in NEW:
		em.clear()
		var d := em.spawn(t, at, true)
		TestLib.check(d != null and d.active and not d.dead, "%s spawns in the real scene" % t)
		if d == null:
			continue
		TestLib.check(d.type == t and d.is_in_group("enemy"), "%s is an enemy of its type" % t)
		d.damage(1.0e6)
		d.damage(1.0e6)
		TestLib.check(d.dead or d.hp <= 0.0, "%s dies from damage" % t)
		await TestLib.frames(host, 2)
	em.clear()
	await _skimmer(host, em, at)
	await _phasewright(host, em, at)
	await _mender(host, em, at)
	em.clear()
	Sfx.boss_active = false
	main.queue_free()
	await TestLib.frames(host, 2)


func _tables() -> void:
	var seen := {}
	for t in NEW:
		TestLib.check(EnemyTypes.TYPES.has(t), "%s is in the type table" % t)
		var c := EnemyLook.code_color(EnemyTypes.get_cfg(t))
		seen["%d,%d,%d" % [int(c.r * 10), int(c.g * 10), int(c.b * 10)]] = true
	TestLib.check(seen.size() == NEW.size(), "the new types have their own colours")
	for t: StringName in [&"pouncer", &"mender", &"wisp"]:
		TestLib.check(EnemyTypes.VARIETY_TYPES.has(t), "%s is in the reinforcement pool" % t)
	var found := {}
	for i in CampaignData.CAMPAIGN.size():
		for st: Dictionary in CampaignData.steps(i):
			if str(st.get("target", "")) == "boss" and st.has("enemy"):
				found[str(st["enemy"])] = i
				TestLib.check(str(CampaignData.chapter(i)["cutscenes"]["boss"]) == "boss_in", "chapter %d plays boss_in" % (i + 1))
	TestLib.check(found.has("skimmer") and found.has("phasewright"), "both bosses are in the chapter tables (%s)" % str(found))
	for verb: String in ["hover", "phase"]:
		var d: Dictionary = StoryData.VERB_BOSS_RADIO[verb]
		var ok := true
		for k: String in ["intro", "phase2", "phase3", "down"]:
			ok = ok and d.has(k)
		TestLib.check(ok, "%s has ORACLE lines" % verb)


func _skimmer(host: Node, em: EnemyManager, at: Vector3) -> void:
	em.clear()
	var b := em.spawn(&"skimmer", at, true) as VerbBoss
	TestLib.check(b != null and b.mode == &"hover", "skimmer is a hover VerbBoss")
	if b == null:
		return
	b.set_physics_process(false)
	var h0 := b.hp
	b.damage(100.0)
	TestLib.check(is_equal_approx(h0 - b.hp, 100.0 * VerbBoss.ARMOR), "the skiff armours it (x%.1f)" % VerbBoss.ARMOR)
	b.disable(1.0)                                # COLLAPSE
	TestLib.check(b.crashed_t > 0.0 and b.exposed(), "COLLAPSE crashes the skiff and exposes it")
	h0 = b.hp
	b.damage(100.0)
	TestLib.check(is_equal_approx(h0 - b.hp, 100.0), "a crashed skiff takes full damage")
	b.damage(1.0e6)
	TestLib.check(b.dead, "the skimmer can be killed")
	await TestLib.frames(host, 1)


func _phasewright(host: Node, em: EnemyManager, at: Vector3) -> void:
	em.clear()
	var b := em.spawn(&"phasewright", at, true) as VerbBoss
	TestLib.check(b != null and b.mode == &"phase", "phasewright is a phase VerbBoss")
	if b == null:
		return
	b.set_physics_process(false)
	var from := b.global_position
	b._tp_wind = VerbBoss.TP_WIND
	b.disable(1.0)                                # COLLAPSE during the windup breaks the jump
	TestLib.check(b.breaks == 1 and b.exposed() and b._tp_wind == 0.0, "COLLAPSE breaks the teleport windup and exposes it")
	b._expose_t = 0.0
	b._tgt = Game.player.global_position
	b._tgt_ok = true
	b._teleport()                                 # QUANTUM TELEPORT
	TestLib.check(b.teleports == 1 and b.global_position.distance_to(from) > 3.0, "it teleports to the player's far side")
	var h0 := b.hp
	b.damage(500.0)
	TestLib.check(b.hp == h0, "phased out: no damage")
	b._tp_out = 0.0
	b._expose_t = 1.0
	b.damage(1.0e6)
	TestLib.check(b.dead, "the phasewright can be killed")
	await TestLib.frames(host, 1)


func _mender(host: Node, em: EnemyManager, at: Vector3) -> void:
	em.clear()
	var m := em.spawn(&"mender", at, true) as Specialist
	var a := em.spawn(&"operative", at + Vector3(3.0, 0.0, 0.0), true)
	TestLib.check(m != null and a != null, "mender and an ally spawn")
	if m == null or a == null:
		return
	m.set_physics_process(false)
	a.set_physics_process(false)
	a.hp = a.max_hp * 0.5
	var h0 := a.hp
	for i in 30:
		m._move_mender(1.0 / 60.0, 1.0, 0.0, 15.0, 3.0, 20.0)
	TestLib.check(a.hp > h0 and m.healed > 0.0, "the mender heals a wounded ally")
	await TestLib.frames(host, 1)
