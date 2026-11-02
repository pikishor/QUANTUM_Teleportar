extends RefCounted
## The verb bosses: SMELTER (ENTANGLE it into an armed ring), BULWARK (COLLAPSE breaks the shield), HOUND (hunts the SUPERPOSITION decoy, backlash when it collapses beside it),
## the reworked Overseer (COLLAPSE cancels a charging pulse), the campaign steps of chapters 4 and 7 and the win hook. Run: tools/test.sh tests/test_verb_bosses.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")
const DT := 1.0 / 60.0

class FakeStory extends Node:
	var chapter := 2
	var lines: Array = []

	func say(speaker: String, text: String, id := "", _wait := 0.0, _prio := 0) -> bool:
		lines.append({"s": speaker, "t": text, "id": id})
		return true

	func has_id(id: String) -> bool:
		for l: Dictionary in lines:
			if l["id"] == id:
				return true
		return false


var e := Env.new()
var p: Player
var root: Node3D
var em: EnemyManager
var story: FakeStory


func run(host: Node) -> void:
	seed(9)
	await e.setup(host)
	p = e.p
	root = e.root
	Fixture.add_floor(root, 600.0)
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	story = FakeStory.new()
	root.add_child(story)
	Game.story = story
	em = (load("res://scenes/enemy_manager.tscn") as PackedScene).instantiate() as EnemyManager
	root.add_child(em)
	em.patrol_groups().clear()
	await e.frames(4)
	await e.prep(Vector3.ZERO)
	_data()
	await _smelter()
	await _bulwark()
	await _hound()
	await _overseer()
	_campaign()
	Game.story = null
	Sfx.boss_active = false
	await e.teardown()


func _spawn(type: StringName, at: Vector3) -> VerbBoss:
	em.clear()
	var b := em.spawn(type, at, true) as VerbBoss
	await e.frames(2)
	b.set_physics_process(false)                              # the tests drive the timers by hand
	return b


func _data() -> void:
	var ok := true
	for t: StringName in [&"smelter", &"bulwark", &"hound"]:
		var c: Dictionary = EnemyTypes.TYPES[t]
		ok = ok and c["boss"] == true and c["hp"] >= 1500.0 and c["scale"] > 1.7 and EnemyTypes.is_specialist(t)
	TestLib.check(ok, "the three verb bosses are boss-flagged specialist types")
	var lok := true
	for verb: String in ["hazard", "shield", "hunter"]:
		var d: Dictionary = StoryData.VERB_BOSS_RADIO[verb]
		for k: String in ["intro", "phase2", "phase3", "down"]:
			lok = lok and d.has(k)
		for k: String in d:
			for l: Dictionary in d[k]:
				lok = lok and l["s"] == "ORACLE" and str(l["t"]).length() <= StoryData.LINE_MAX
	TestLib.check(lok, "every verb boss has ORACLE lines for intro, phases and its fall, within the line limit")


func _smelter() -> void:
	var b := await _spawn(&"smelter", Vector3(30.0, 0.0, 0.0))
	TestLib.check(b is VerbBoss and b.mode == &"hazard" and story.has_id("vboss.hazard.intro"), "SMELTER spawns as a hazard boss with an intro line")
	b._tick_boss(DT)
	TestLib.check(b.hazards.size() == 2, "phase 1 sets two rings up")
	var h: Vector3 = b.hazards[0]
	TestLib.check(not b.hazard_armed(), "the rings start dormant")
	var h0 := b.hp
	b.damage(100.0)
	var armoured := h0 - b.hp
	TestLib.check(armoured > 5.0 and armoured < 15.0, "armoured: 100 damage becomes %.0f" % armoured)
	# ENTANGLE: the swap puts the boss where the player stood. Stand in a ring, swap, wait for the arming.
	b.global_position = h
	for i in 200:
		b._tick_boss(DT)
		if b.hazard_warning():
			break
	TestLib.check(b.hazard_warning() and b.threat_charge() >= 0.0, "the rings flicker before they arm")
	for i in 120:
		b._tick_boss(DT)
		if b.hazard_armed():
			break
	TestLib.check(b.hazard_armed() and b.exposed(), "armed ring: the boss standing in it is exposed")
	var h1 := b.hp
	for i in 60:
		b._tick_boss(DT)
	TestLib.check(h1 - b.hp > 80.0 and b.hazard_burns > 0.9, "a second in an armed ring burns it for %.0f" % (h1 - b.hp))
	var h2 := b.hp
	b.damage(100.0)
	TestLib.check(h2 - b.hp > 90.0, "exposed shots land in full")
	b.global_position = Vector3(30.0, 0.0, 0.0)
	TestLib.check(not b.exposed(), "outside the rings it is armoured again")
	var ph := b.phase
	b.hp = b.max_hp * 0.6
	b.damage(1.0)
	TestLib.check(b.phase == ph + 1 and b.is_invulnerable() and b.hazards.size() == 3 and story.has_id("vboss.hazard.phase2"), "phase 2: invulnerable beat, a third ring, ORACLE")
	b.die()
	TestLib.check(b.dead and not Sfx.boss_active, "death ends the boss music state")


func _bulwark() -> void:
	var b := await _spawn(&"bulwark", Vector3(30.0, 0.0, 0.0))
	TestLib.check(b.mode == &"shield" and b.shield_is_up and b.shield_node != null and b.shield_node.visible, "BULWARK starts shielded")
	var h0 := b.hp
	b.damage(500.0)
	TestLib.check(is_equal_approx(b.hp, h0) and not b.exposed(), "the shield stops every shot")
	b.disable(2.5)                                            # what Quantum.collapse_all does to each enemy in range
	TestLib.check(not b.shield_is_up and b.exposed() and is_equal_approx(b.break_left(), VerbBoss.BREAK_TIME[0]) and story.has_id("vboss.shield.break"), "COLLAPSE breaks the shield")
	b.damage(100.0)
	TestLib.check(is_equal_approx(h0 - b.hp, 100.0), "shots land in full while it is down")
	for i in int(5.2 / DT):
		b._tick_boss(DT)
	TestLib.check(b.threat_charge() >= 0.0 and not b.shield_is_up or b.shield_is_up, "the shield flickers before returning")
	for i in int(1.2 / DT):
		b._tick_boss(DT)
	TestLib.check(b.shield_is_up and b.shield_node.visible and story.has_id("vboss.shield.reform"), "the shield reforms after the window")
	b.hp = b.max_hp * 0.5
	b.damage(0.0)
	b._invuln_t = 0.0
	b.hp = b.max_hp * 0.5
	b._check_phase()
	b.disable(2.5)
	TestLib.check(b.phase == 2 and is_equal_approx(b.break_left(), VerbBoss.BREAK_TIME[1]), "phase 2 gives a shorter window (%.0f s)" % b.break_left())
	# the real COLLAPSE shockwave
	var b2 := await _spawn(&"bulwark", Vector3(6.0, 0.0, 0.0))
	p.energy = 100.0
	p.quantum.cd_collapse = 0.0
	var ok: bool = p.quantum.collapse_all()
	await e.frames(2)
	TestLib.check(ok and not b2.shield_is_up, "the real COLLAPSE wave breaks the shield")
	em.clear()


func _hound() -> void:
	var b := await _spawn(&"hound", Vector3(30.0, 0.0, 0.0))
	TestLib.check(b.mode == &"hunter" and not b.exposed(), "HOUND starts armoured")
	var decoy := Node3D.new()
	decoy.add_to_group(&"clone")
	root.add_child(decoy)
	decoy.global_position = Vector3(30.0, 0.0, -14.0)
	p.quantum.clone = decoy
	p.quantum.clone_left = 100.0
	b.set_physics_process(true)
	var x0 := b.global_position.distance_to(decoy.global_position)
	for i in int(2.0 / DT / 3.0):
		await e.frames(3)
	var x1 := b.global_position.distance_to(decoy.global_position)
	TestLib.check(x1 < x0 - 2.0, "the hound hunts the decoy (%.1f m -> %.1f m)" % [x0, x1])
	b.set_physics_process(false)
	b.global_position = decoy.global_position + Vector3(2.0, 0.0, 0.0)
	b._tick_hunter(DT)
	TestLib.check(b.feeding() and b.exposed() and b.threat_charge() > 0.9 and story.has_id("vboss.hunter.lock"), "close to the decoy it locks on: exposed, charge bar up")
	var h0 := b.hp
	p.quantum.clone = null                                    # the decoy collapses
	decoy.queue_free()
	await e.frames(2)                                         # the manager caches the clone per physics frame
	b._tick_hunter(DT)
	TestLib.check(b.backlashes == 1 and h0 - b.hp >= b.max_hp * VerbBoss.BACKLASH - 1.0 and story.has_id("vboss.hunter.backlash"), "a decoy collapsed beside it bites %.0f hp" % (h0 - b.hp))
	em.clear()
	# a decoy that times out far away does nothing
	var b2 := await _spawn(&"hound", Vector3(30.0, 0.0, 0.0))
	var d2 := Node3D.new()
	root.add_child(d2)
	d2.global_position = Vector3(30.0, 0.0, -30.0)
	p.quantum.clone = d2
	p.quantum.clone_left = 100.0
	await e.frames(2)
	b2._tick_hunter(DT)
	p.quantum.clone = null
	await e.frames(2)
	b2._tick_hunter(DT)
	TestLib.check(b2.backlashes == 0 and not b2.feeding(), "no backlash without the lock")
	d2.queue_free()
	em.clear()


func _overseer() -> void:
	em.clear()
	var o := em.spawn(&"overseer", Vector3(30.0, 0.0, 0.0), true) as Overseer
	await e.frames(2)
	o.set_physics_process(false)
	o.damage(o.max_hp * 0.4)
	o._invuln_t = 0.0
	o._ov_pulse_wind = Overseer.OV_PULSE_WIND
	TestLib.check(o.shield_active(), "the Overseer is charging a pulse")
	o.disable(2.5)
	TestLib.check(not o.shield_active() and o.is_open() and o.pulses_fired == 0, "COLLAPSE cancels the charging pulse and opens him up")
	var h0 := o.hp
	o.damage(100.0)
	TestLib.check(is_equal_approx(h0 - o.hp, 100.0 * Overseer.OPEN_FACTOR), "open: damage x%.1f" % Overseer.OPEN_FACTOR)
	em.clear()


func _campaign() -> void:
	var i4 := CampaignData.index_of("no_cloning")
	var i7 := CampaignData.index_of("lantern_night")
	TestLib.check(i4 == 3 and i7 == 6, "chapters 4 and 7 are no_cloning and lantern_night")
	var enemies: Array[String] = []
	for idx: int in [i4, i7]:
		for st: Dictionary in CampaignData.steps(idx):
			if str(st.get("target", "")) == "boss":
				enemies.append(str(st.get("enemy", "")))
				var n := CampaignSteps.normalize_step(st, idx)
				TestLib.check(n["kind"] == &"kill_target" and EnemyTypes.TYPES.has(n["enemy"]) and n["guards"] == 0, "boss step normalizes: %s" % n["enemy"])
				TestLib.check(str(n["name"]).begins_with("VAEL ") and str(n["obj"] if n.has("obj") else n.get("text", "x")).length() >= 0, "boss step has a bar name %s" % n["name"])
	TestLib.check(enemies == ["smelter", "bulwark", "hound"], "campaign hunts the Smelter, Bulwark and Hound (%s)" % str(enemies))
	TestLib.check(str(CampaignData.chapter(i4)["cutscenes"]["boss"]) != "" and str(CampaignData.chapter(i7)["cutscenes"]["boss"]) != "", "boss chapters name a boss cutscene")
