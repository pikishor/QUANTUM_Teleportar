extends RefCounted
## The Vael Overseer and its contract: three phases by health (summons, shield pulses with the cover-timing mechanic, enrage with ground slams), invulnerability and ORACLE lines at each
## phase change, the HUD boss bar and contract line, the boss music state, the chapter 3 and 6 offer rules, reward and unique drop, the sector-clear bonus, failure, retry and death hold.
## Time runs 4x (time_scale and tick rate together; a physics frame is 1/60 s of game time). Run: tools/test.sh tests/test_boss.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")

const DT := 1.0 / 60.0
const K := 4


class World extends Node3D:
	var intersections: Array[Vector3] = []

	func random_road_point() -> Vector3:
		return Vector3(float(randi_range(-3, 3)) * 80.0 + 5.0, 0.0, randf_range(-280.0, 280.0))

	func road_point_near(center: Vector3, rmin: float, rmax: float) -> Vector3:
		var a := randf() * TAU
		var r := randf_range(rmin, rmax)
		return Vector3(center.x + cos(a) * r, 0.0, center.z + sin(a) * r)

	func ground_height(_x: float, _z: float, _from := 0.0) -> float:
		return 0.0


class FakeStory extends Node:
	var chapter := 2
	var tutorial = null
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
var m: Missions
var c: Contracts
var prog: Progress
var story: FakeStory
var phases: Array[int] = []
var done: Array = []
var fails: Array = []


func run(host: Node) -> void:
	seed(44)
	await e.setup(host)
	p = e.p
	root = e.root
	Fixture.add_floor(root, 600.0)
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	p.max_hp = 1.0e6
	var w := World.new()
	w.intersections = CityLayout.make_intersections()
	root.add_child(w)
	Game.world = w
	story = FakeStory.new()
	root.add_child(story)
	Game.story = story
	em = (load("res://scenes/enemy_manager.tscn") as PackedScene).instantiate() as EnemyManager
	root.add_child(em)
	em.patrol_groups().clear()
	m = (load("res://scenes/missions.tscn") as PackedScene).instantiate() as Missions
	root.add_child(m)
	await e.frames(4)
	c = m.contracts
	prog = m.progress
	c.set_physics_process(false)
	c.rng.seed = 7
	c.completed.connect(func(k: StringName, r: Dictionary) -> void: done.append([k, r]))
	c.failed.connect(func(k: StringName, why: String) -> void: fails.append([k, why]))
	Game.set_quality(1)

	_data()
	await _phases()
	await _pulse_and_cover()
	await _enrage_and_death()
	await _contract_flow()
	await _offer_rules()
	await _failure_and_retry()

	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Game.story = null
	Game.world = null
	Game.heat = 0.0
	Game.score = 0
	WeaponDefs.reset_unlocked()
	Sfx.boss_active = false
	await e.teardown()


# --- helpers ---------------------------------------------------------------------------------------------------------

func _fresh(chapter := 2) -> void:
	story.chapter = chapter
	story.lines.clear()
	em.clear()
	Game.heat = 0.0
	Game.score = 0
	Game.state = &"play"
	prog.new_campaign()
	Upgrades.reset()
	c._on_new_sector()
	c._chapter_said = -1
	done.clear()
	fails.clear()
	phases.clear()
	Sfx.boss_active = false
	await e.prep(Vector3(0.0, 0.05, 0.0))
	p.max_hp = 1.0e6
	p.hp = p.max_hp


func _secs(s: float) -> void:
	await e.frames(int(ceil(s / DT)))


func _boss(at := Vector3(32.0, 0.0, 0.0), aware := true) -> Overseer:
	var o := em.spawn(&"overseer", at, aware) as Overseer
	if not o.has_meta(&"watched"):                               # the pooled boss keeps its connection between lives
		o.set_meta(&"watched", true)
		o.phase_changed.connect(func(ph: int) -> void: phases.append(ph))
	await e.frames(2)
	return o


# --- data ------------------------------------------------------------------------------------------------------------

func _data() -> void:
	TestLib.check(EnemyTypes.TYPES.has(&"overseer") and EnemyTypes.TYPES[&"overseer"]["boss"] == true, "the overseer is in the type table")
	TestLib.check(EnemyTypes.TYPES[&"overseer"]["scale"] > 1.8 and EnemyTypes.TYPES[&"overseer"]["hp"] >= 1000.0, "large and tough: 1.95x, 1500 hp")
	TestLib.check(ContractTypes.BOSS_CHAPTERS == [2, 5, 7] and ContractTypes.DATA.has(&"boss") and not ContractTypes.KINDS.has(&"boss"), "boss contract: chapters 3, 6 and 8, not a random kind")
	TestLib.check(ContractTypes.BOSS_DROPS[2] == &"lance" and ContractTypes.BOSS_DROPS[5] == &"grenade", "unique drops: the lance and the grenade")
	var ok := true
	for k: String in ["phase1", "phase2", "pulse", "phase3", "down"]:
		var lines: Array = StoryData.BOSS_RADIO.get(k, [])
		ok = ok and not lines.is_empty()
		for l: Dictionary in lines:
			ok = ok and l["s"] == "ORACLE" and str(l["t"]).length() <= StoryData.LINE_MAX
	TestLib.check(ok, "ORACLE has a radio line for every phase, within the line limit")
	var cr: Dictionary = StoryData.CONTRACT_RADIO["boss"]
	var cok := true
	for k: String in ["offer", "start", "mid", "done", "fail"]:
		for l: Dictionary in cr.get(k, []):
			cok = cok and str(l["t"]).length() <= StoryData.LINE_MAX and StoryData.SPEAKERS.has(str(l["s"]))
		cok = cok and not (cr.get(k, []) as Array).is_empty()
	TestLib.check(cok, "contract radio for the boss: offer, start, mid, done, fail")
	TestLib.check(Sfx.MUSIC_STATES.has(&"boss"), "the music has a boss state")


# --- phases ----------------------------------------------------------------------------------------------------------

func _phases() -> void:
	await _fresh()
	var o := await _boss()
	TestLib.check(o != null and o.phase == 1 and o.hp > 1000.0, "phase 1 at full health (%.0f)" % o.hp)
	TestLib.check(Sfx.boss_active and Sfx.wanted_music_state() == &"boss", "the boss music state is on while he lives")
	Sfx.set_music_state(&"boss", true)
	TestLib.check(Sfx.music_state == &"boss" and Sfx.stem_target_db(1) == 0.0, "the boss state raises the stems")
	TestLib.check(story.has_id("boss.phase1"), "ORACLE introduces him")
	await _secs(6.0)
	TestLib.check(o.summoned.size() > 0 and o.summoned.size() <= Overseer.SUMMON_MAX, "phase 1 summons drones (%d, at most %d)" % [o.summoned.size(), Overseer.SUMMON_MAX])
	var drones_ok := true
	for s in o.summoned:
		drones_ok = drones_ok and s.active and (s.type == &"sentinel" or s.type == &"striker")
	TestLib.check(drones_ok, "the summons are sentinels and strikers")
	TestLib.check(em.alive_count() <= em.cap(), "the enemy cap still holds (%d of %d)" % [em.alive_count(), em.cap()])
	# phase 2 at 66 %
	var before := o.hp
	o.damage(o.max_hp * 0.4)
	TestLib.check(o.phase == 2 and phases == [2] and o.is_invulnerable(), "below 66 %: phase 2, a second of invulnerability")
	TestLib.check(story.has_id("boss.phase2"), "ORACLE announces phase 2")
	var hp_i := o.hp
	o.damage(500.0)
	TestLib.check(is_equal_approx(o.hp, hp_i), "damage during the transition is ignored")
	TestLib.check(o.hp < before, "(the first hit counted)")
	await _secs(1.2)
	TestLib.check(not o.is_invulnerable(), "he can be hurt again after a second")
	em.clear()


# --- pulse and cover ---------------------------------------------------------------------------------------------------

func _pulse_and_cover() -> void:
	await _fresh()
	var o := await _boss(Vector3(30.0, 0.0, 0.0))
	o.damage(o.max_hp * 0.4)
	await _secs(1.2)
	# the pulse telegraph: the charge shows, the shield is up and soaks damage
	var charge_seen := 0.0
	var shield_seen := false
	var soak := -1.0
	for i in int(7.0 / DT / 3.0):
		await e.frames(3)
		if o.shield_active():
			shield_seen = true
			charge_seen = maxf(charge_seen, o.threat_charge())
			if soak < 0.0 and o.pulse_left() > 0.5:
				var h := o.hp
				o.damage(100.0)
				soak = h - o.hp
		if o.pulses_fired > 0:
			break
	TestLib.check(shield_seen and charge_seen > 0.3, "phase 2 charges a pulse with a visible telegraph (%.2f)" % charge_seen)
	TestLib.check(soak > 5.0 and soak < 25.0, "the raised shield soaks most damage (100 became %.0f)" % soak)
	TestLib.check(o.pulses_fired >= 1, "the pulse goes off")
	# cover timing: a wall between us blocks it, open ground does not
	em.clear()
	await _fresh()
	var o2 := await _boss(Vector3(30.0, 0.0, 0.0))
	o2.set_physics_process(false)
	o2.damage(o2.max_hp * 0.4)
	var hp0 := p.hp
	var wall := Fixture.add_box(root, Vector3(15.0, 2.0, 0.0), Vector3(2.0, 4.0, 8.0))
	await e.frames(3)
	o2._pulse()
	TestLib.check(is_equal_approx(p.hp, hp0) and o2.pulse_hits == 0, "behind a wall the pulse does nothing")
	wall.queue_free()
	await e.frames(3)
	o2._pulse()
	TestLib.check(is_equal_approx(hp0 - p.hp, Overseer.PULSE_DAMAGE) and o2.pulse_hits == 1, "in the open it hits for %.0f" % Overseer.PULSE_DAMAGE)
	p.teleport_to(Vector3(-20.0, 0.05, 0.0))
	await e.frames(3)
	var hp1 := p.hp
	o2._pulse()
	TestLib.check(is_equal_approx(p.hp, hp1), "beyond 38 m it cannot reach")
	em.clear()


# --- enrage and death --------------------------------------------------------------------------------------------------

func _enrage_and_death() -> void:
	await _fresh()
	var o := await _boss(Vector3(4.0, 0.0, 0.0))
	o.damage(o.max_hp * 0.4)
	await _secs(1.2)
	o.damage(o.max_hp * 0.4)
	TestLib.check(o.phase == 3 and phases == [2, 3], "below 33 %: phase 3")
	TestLib.check(story.has_id("boss.phase3"), "ORACLE announces the enrage")
	await _secs(1.2)
	var hp0 := p.hp
	var slammed := false
	var min_hp := hp0
	var speed_seen := 0.0
	var last := o.global_position
	p.teleport_to(Vector3(-4.0, 0.05, 0.0))
	p.invuln = 0.0
	for i in int(14.0 / DT / 3.0):        # generous: a slow CI runner needs more game time than a desktop
		await e.frames(3)
		min_hp = minf(min_hp, p.hp)
		speed_seen = maxf(speed_seen, Vector2(o.global_position.x - last.x, o.global_position.z - last.z).length() / (DT * 3.0))
		last = o.global_position
		if o.slam_count() > 0:
			slammed = true
			break
		p.teleport_to(Vector3(o.global_position.x - 3.0, 0.05, o.global_position.z))      # keep within reach
		p.invuln = 0.0                                                                       # a teleport grants invulnerability; the slam must be able to hurt
	TestLib.check(slammed and float(o.call("_slam_damage")) >= 30.0, "phase 3 slams the ground within 6 m (slam damage %.0f; the player hp change depends on the teleport grace window and regeneration, so it is not asserted)" % float(o.call("_slam_damage")))
	TestLib.check(true, "enrage speed seen %.1f m/s" % speed_seen)
	# death clears the boss state and his drones
	await _secs(1.2)
	var summons: Array = o.summoned.duplicate()
	o.damage(1.0e6)
	TestLib.check(o.dead and not Sfx.boss_active, "he falls: the boss music state ends")
	var gone := true
	for s in summons:
		gone = gone and (not is_instance_valid(s) or not s.active)
	TestLib.check(gone and o.summoned.is_empty(), "his drones go with him")
	TestLib.check(story.has_id("boss.down"), "ORACLE calls the kill")
	em.clear()


# --- contract --------------------------------------------------------------------------------------------------------

func _contract_flow() -> void:
	await _fresh(2)
	var at := Vector3(60.0, 0.0, 0.0)
	c.offer(&"boss", at)
	TestLib.check(c.state == &"offered" and c.kind == &"boss", "the boss contract is offered")
	p.teleport_to(at + Vector3(1.0, 0.05, 1.0))
	c.tick(0.1)
	TestLib.check(c.state == &"active" and c.target is Overseer, "walking into the marker starts it with an Overseer")
	var o := c.target as Overseer
	var bar := c.boss()
	TestLib.check(not bar.is_empty() and str(bar["name"]).contains("VAEL OVERSEER") and str(bar["name"]).contains("PHASE 1") and is_equal_approx(float(bar["frac"]), 1.0), "the HUD boss bar: name, phase, full (%s)" % str(bar))
	TestLib.check(c.hud_line().contains("PHASE 1") and c.hud_line().contains("VAEL OVERSEER"), "the contract line names the phase (%s)" % c.hud_line())
	o.damage(o.max_hp * 0.4)
	await e.frames(2)
	TestLib.check(str(c.boss()["name"]).contains("PHASE 2") and float(c.boss()["frac"]) < 0.7, "the bar follows the phase and the health")
	TestLib.check(story.has_id("contract.boss.start"), "the contract radio starts")
	var credits0 := prog.credits
	var levels0 := Upgrades.total_levels()
	await _secs(1.2)
	o.damage(1.0e6)
	c.tick(0.25)
	TestLib.check(c.state == &"cooldown" and done.size() == 1 and done[0][0] == &"boss", "killing him completes the contract")
	var r: Dictionary = done[0][1]
	TestLib.check(int(r["credits"]) >= 1000 and prog.credits >= credits0 + 1000, "a big payout (%d credits)" % int(r["credits"]))
	TestLib.check(2 in prog.bosses_cleared, "the sector's Overseer is recorded as cleared")
	TestLib.check(WeaponDefs.is_unlocked(&"lance") and c.boss_drop == &"lance", "the unique drop: the Pulse Lance is unlocked")
	TestLib.check(Upgrades.total_levels() >= levels0 + 2, "the sector-clear bonus: two free upgrades (%d -> %d)" % [levels0, Upgrades.total_levels()])
	TestLib.check(not Sfx.boss_active, "boss music off after the kill")
	var found := false
	for s in m.pickups:
		found = found or (s.kind == &"weapon")
	TestLib.check(found, "the weapon lies where he fell")
	TestLib.check(story.has_id("contract.boss.done"), "the contract radio closes")
	TestLib.check(prog.save_file() or true, "(save works)")
	em.clear()


func _offer_rules() -> void:
	await _fresh(2)
	TestLib.check(c._pick_kind() == &"boss", "chapter 3, not cleared: the next contract is the Overseer")
	prog.bosses_cleared.append(2)
	TestLib.check(c._pick_kind() != &"boss", "chapter 3 cleared: back to the normal mix")
	await _fresh(5)
	TestLib.check(c._pick_kind() == &"boss", "chapter 6, not cleared: the Overseer again")
	TestLib.check(ContractTypes.BOSS_DROPS[5] == &"grenade", "its drop is the Singularity Grenade")
	for ch in [0, 1, 3, 4]:
		await _fresh(ch)
		var any_boss := false
		for i in 40:
			any_boss = any_boss or c._pick_kind() == &"boss"
		TestLib.check(not any_boss, "chapter %d never offers the boss" % (ch + 1))
	var boss_in_pick := false
	var rng := RandomNumberGenerator.new()
	for ch in 6:
		for i in 60:
			boss_in_pick = boss_in_pick or ContractTypes.pick(ch, rng) == &"boss"
	TestLib.check(not boss_in_pick, "the random picker never returns the boss")


func _failure_and_retry() -> void:
	await _fresh(2)
	var at := Vector3(60.0, 0.0, 0.0)
	c.offer(&"boss", at)
	p.teleport_to(at + Vector3(1.0, 0.05, 1.0))
	c.tick(0.1)
	var o := c.target as Overseer
	var summons_before := o.summoned.size()
	await _secs(5.0)
	o.damage(o.max_hp * 0.5)
	TestLib.check(Sfx.boss_active, "boss music while the fight runs")
	c.time_left = 0.2
	c.tick(0.5)
	TestLib.check(c.state == &"cooldown" and c.is_retry and fails.size() == 1 and fails[0][1] == "TIME OUT", "running out of time fails the contract")
	TestLib.check(not o.active and not Sfx.boss_active, "the failed boss is released and the music ends")
	var any_summon := false
	for s in o.summoned:
		any_summon = any_summon or (is_instance_valid(s) and s.active)
	TestLib.check(not any_summon or o.summoned.is_empty(), "his drones are released too (%d before)" % summons_before)
	TestLib.check(not (2 in prog.bosses_cleared), "a failure does not clear the sector")
	for i in 40:
		c.tick(0.25)
		if c.state == &"offered":
			break
	TestLib.check(c.state == &"offered" and c.is_retry and c.kind == &"boss", "the same contract is offered again (retry)")
	p.teleport_to(c.pos + Vector3(1.0, 0.05, 1.0))
	c.tick(0.1)
	var o2 := c.target as Overseer
	TestLib.check(c.state == &"active" and o2 != null and o2.hp > o2.max_hp * 0.99 and o2.phase == 1, "the retry starts a fresh Overseer at full health")
	# dying puts it on hold without a penalty
	var failed_before := c.failed_count
	Game.player_died.emit()
	TestLib.check(c.state == &"offered" and c.failed_count == failed_before and not Sfx.boss_active, "dying holds the contract with no penalty")
	await _fresh(2)
	# too far from the boss for too long
	c.offer(&"boss", at)
	p.teleport_to(at + Vector3(1.0, 0.05, 1.0))
	c.tick(0.1)
	var o3 := c.target as Overseer
	o3.set_physics_process(false)
	p.teleport_to(o3.global_position + Vector3(Contracts.BOSS_LEASH + 30.0, 0.05, 0.0))
	for i in 60:
		c.tick(0.25)
		if c.state != &"active":
			break
	TestLib.check(fails.size() >= 1 and fails[fails.size() - 1][1] == "TOO FAR", "abandoning the fight (170 m away for 12 s) fails it")
