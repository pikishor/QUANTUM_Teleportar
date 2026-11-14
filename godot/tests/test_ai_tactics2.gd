extends RefCounted
## COVER AI v2 and SQUAD TACTICS v2 (scripts/enemies/tactics_table.gd + enemy_cover.gd + operative.gd + enemy_manager.gd) in the REAL scene (main.tscn): the table is complete and the three
## factions differ; cover is scored (height, arc, advance) so observers take the tall wide crate and the hive the nearer bin; observers leapfrog (never more than the tier's leapers at once)
## and the hive does not; a hero who holds cover gets ONE flush grenade (observers only, squad cooldown); the mender heals the most wounded ally first and a hurt trooper falls back to it and
## regroups; allies alone regroup a retreat; a commander buffs allies in range and the buff ends with him; a scripted fight bot (hero stands in a free arena, shoots what it can see) fights
## 11 troopers of all three factions: kills vary in time-to-kill and no enemy stands stuck. Waits are on counters and state; the arena is found by scanning for building-free ground; cover in
## the fights is the test crates (EnemyCover.override_bodies). Progress writes to a throw-away file. Not run: a phone, the feel of the fights.
## Run: tools/test.sh tests/test_ai_tactics2.gd

const TIMEOUT_SECONDS := 140.0                      ## the 11-trooper fight bot needs about a minute on a slow machine (it timed out at the default 60 s on the wave 112 tree too, in the wave 113 integrator's sandbox)
const Fixture := preload("res://tests/player_fixture.gd")
const TMP := "user://test_ai_tactics2_save.cfg"
const DT := 1.0 / 60.0

var host: Node
var main: Node
var em: EnemyManager
var p: Player
var o := Vector3.ZERO                      ## arena origin (the hero stands here)
var boxes: Array[StaticBody3D] = []


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	seed(11)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	_data()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	em = Game.enemies as EnemyManager
	p = Game.player as Player
	TestLib.check(em != null and p != null, "main.tscn composes the EnemyManager and the player")
	if em == null or p == null:
		return
	var prog := Game.progress as Progress
	prog.path = TMP
	prog.autosave_enabled = false
	prog.new_campaign()
	var q0 := Game.quality
	Game.set_quality(2)                     # HIGH: the biggest cap, so the 11-trooper fight fits
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	await _arena()
	await _cover_scoring()
	await _leapfrog()
	await _flush()
	await _medic_and_regroup()
	await _factions()
	await _commander()
	await _fight_bot()
	_caps()

	_reset()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Game.set_quality(q0)
	em.force_hold = false
	Game.heat = 0.0
	Game.state = &"play"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


# --- helpers ----------------------------------------------------------------------------------------------------------

func _until(cond: Callable, max_s: float) -> bool:
	var n := int(max_s / DT / 4.0)
	for i in n:
		if cond.call():
			return true
		await TestLib.frames(host, 4)
	return cond.call()


func _secs(s: float) -> void:
	await TestLib.frames(host, int(ceil(s / DT / 4.0)) * 4)


func _reset() -> void:
	em.clear()
	em.force_hold = false
	EnemyCover.override_bodies.clear()
	for b in boxes:
		if is_instance_valid(b):
			b.queue_free()
	boxes.clear()
	Game.heat = 0.0
	Game.state = &"play"


func _fresh() -> void:
	_reset()
	em.patrol_groups().clear()
	p.max_hp = 1.0e7
	p.hp = p.max_hp
	p.invuln = 0.0
	p.global_position = o + Vector3(0.0, 0.05, 0.0)
	p.velocity = Vector3.ZERO
	await _secs(0.3)


func _crate(at: Vector3, size: Vector3) -> StaticBody3D:
	var b := Fixture.add_box(host, o + at + Vector3(0.0, size.y * 0.5, 0.0), size)
	boxes.append(b)
	EnemyCover.override_bodies.append(b)
	return b


func _spawn(type: StringName, at: Vector3, faction: StringName = &"", frozen := false, hp_frac := 1.0) -> Operative:
	var d := em.spawn(type, o + at, true)
	if d == null:                                       # the live city streamed a patrol into the cap: clear and try again
		em.clear()
		em.patrol_groups().clear()
		d = em.spawn(type, o + at, true)
	TestLib.check(d != null, "spawned %s" % type)
	var op := d as Operative
	if op == null:
		return null
	if faction != &"":
		op.faction = faction
	op.hp = op.max_hp * hp_frac
	op._called = true
	op.tactic_role = &"anchor"
	op.set_physics_process(not frozen)
	return op


## Ground free of buildings: scans a 10 m grid round the hero for a box x -6..44, z -24..24 with no building, then stands the hero there.
func _arena() -> void:
	em.clear()
	Game.heat = 0.0
	p.max_hp = 1.0e7
	p.hp = p.max_hp
	var city := Game.world as City
	var start := p.global_position
	var best := Vector3.INF
	if city != null:
		var r := 0
		while r <= 300 and not best.is_finite():
			for gx in range(-r, r + 1, 10):
				for gz in range(-r, r + 1, 10):
					if absi(gx) != r and absi(gz) != r:
						continue
					var c := Vector3(start.x + gx, 0.0, start.z + gz)
					if _free_box(city, c):
						best = c
						break
				if best.is_finite():
					break
			r += 10
	TestLib.check(best.is_finite(), "found building-free ground for the arena")
	if not best.is_finite():
		best = start
	var gy := city.ground_height(best.x, best.z, start.y + 1.0) if city != null else start.y
	o = Vector3(best.x, gy, best.z)
	p.global_position = o + Vector3(0.0, 0.05, 0.0)
	p.velocity = Vector3.ZERO
	await _secs(1.0)


func _free_box(city: City, c: Vector3) -> bool:
	for x in range(-6, 45, 6):
		for z in range(-24, 25, 6):
			if city.is_inside_building(Vector3(c.x + x, 1.0, c.z + z)):
				return false
	return true


# --- data ---------------------------------------------------------------------------------------------------------------

func _data() -> void:
	var keys := ["cover_use", "w_dist", "w_height", "w_arc", "w_adv", "hide", "peek", "leapfrog", "leap_min", "leap_step", "flush", "flush_hold", "suppress", "suppress_flank_mult",
		"flank_cd", "camp_s", "push_every", "retreat_hp", "regroup_s", "regroup_hp", "regroup_allies", "regroup_radius"]
	var ok := true
	for f: StringName in [TacticsTable.OBSERVER, TacticsTable.VAEL, TacticsTable.RAIDER]:
		for k: String in keys:
			if not TacticsTable.row(f).has(k):
				ok = false
	TestLib.check(ok, "every faction row has every key")
	TestLib.check(bool(TacticsTable.val(&"observer", "leapfrog")) and not bool(TacticsTable.val(&"vael", "leapfrog")) and bool(TacticsTable.val(&"observer", "flush")) and not bool(TacticsTable.val(&"raider", "flush")), "factions differ: observers leapfrog and flush, the others do not")
	TestLib.check(float(TacticsTable.val(&"vael", "retreat_hp")) == 0.0 and float(TacticsTable.val(&"raider", "retreat_hp")) > float(TacticsTable.val(&"observer", "retreat_hp")), "the hive never retreats, raiders retreat early")
	TestLib.check(TacticsTable.cover_quality(1.9, 1.5, 15.0) > TacticsTable.cover_quality(1.0, 0.5, 15.0) * 1.5, "a tall wide body is far better cover than a waist-high bin")
	TestLib.check(TacticsTable.faction_for(&"flanker", 0, 0.9) == TacticsTable.RAIDER and TacticsTable.faction_for(&"operative", 0, 0.0) == TacticsTable.OBSERVER and TacticsTable.faction_for(&"operative", 6, 0.1) == TacticsTable.VAEL, "faction picks by type and chapter")
	for t: StringName in [&"warden", &"hivemother", &"overseer"]:
		TestLib.check(bool(EnemyTypes.get_cfg(t).get("commander", false)), "%s is a commander" % t)
	TestLib.check(TacticsTable.LEAPERS.size() == 3 and TacticsTable.FLUSH_ACTIVE.size() == 3 and EnemyManager.THINKERS.size() == 3, "caps exist for every tier")
	TestLib.check(TacticsTable.LEAPERS[0] <= TacticsTable.LEAPERS[2] and int(EnemyManager.THINKERS[0]) <= int(EnemyManager.THINKERS[2]), "caps do not shrink up the tiers")


# --- cover scoring ------------------------------------------------------------------------------------------------------

func _cover_scoring() -> void:
	await _fresh()
	_crate(Vector3(18.0, 0.0, 0.0), Vector3(1.0, 1.0, 1.0))             # a near waist-high bin
	_crate(Vector3(12.0, 0.0, 0.0), Vector3(3.0, 1.9, 3.0))             # a farther tall wide crate
	var who := _spawn(&"operative", Vector3(26.0, 0.0, 0.0), &"observer", true)
	await _secs(0.2)
	var threat := o + Vector3(0.0, 1.0, 0.0)
	var a := EnemyCover.find(who, threat, 30.0, &"observer")
	var b := EnemyCover.find(who, threat, 30.0, &"vael")
	TestLib.check(a.is_finite() and absf(a.x - o.x - 14.25) < 1.0, "observers take the tall wide crate (spot x %.1f)" % (a.x - o.x))
	TestLib.check(b.is_finite() and absf(b.x - o.x - 19.25) < 1.0, "the hive takes the nearer bin (spot x %.1f)" % (b.x - o.x))
	var adv := EnemyCover.find(who, threat, 30.0, &"observer", 4.0)
	TestLib.check(adv.is_finite() and Vector2(adv.x - threat.x, adv.z - threat.z).length() <= 26.0 - 4.0, "an advance cover is at least 4 m closer to the threat")
	TestLib.check(not EnemyCover.find(who, threat, 30.0, &"observer", 60.0).is_finite(), "no cover that far forward: none returned")
	em.clear()


# --- leapfrog -----------------------------------------------------------------------------------------------------------

func _leapfrog() -> void:
	await _fresh()
	Game.set_quality(1)
	for zz in [-10.0, -3.0, 3.0, 10.0]:
		for xx in [24.0, 18.0, 13.0]:
			_crate(Vector3(xx, 0.0, zz), Vector3(3.0, 1.9, 3.0))
	var obs: Array[Operative] = []
	for i in 4:
		obs.append(_spawn(&"operative", Vector3(28.0 + i, 0.0, -9.0 + 6.0 * i), &"observer"))
	var hive := _spawn(&"operative", Vector3(28.0, 0.0, 0.0), &"vael")
	var cap := TacticsTable.tier_cap(TacticsTable.LEAPERS, 1)
	var worst := 0
	var seen := false
	for i in int(40.0 / DT / 4.0):
		await TestLib.frames(host, 4)
		p.global_position = o + Vector3(0.0, 0.05, 8.0 * sin(0.5 * float(i) * DT * 4.0))       # a walking hero is not "camping", so nobody is sent round the side instead
		p.velocity = Vector3.ZERO
		var n := 0
		for op in obs:
			if op.is_leaping():
				n += 1
		worst = maxi(worst, n)
		var total := 0
		for op in obs:
			total += op.leaps
		if total > 1 and i > int(8.0 / DT / 4.0):
			seen = true
			break
	var leaps := 0
	for op in obs:
		leaps += op.leaps
	TestLib.check(leaps > 0, "observers leapfrog forward between covers (%d leaps)" % leaps)
	TestLib.check(worst <= cap, "never more than the tier's leapers at once (%d of %d)" % [worst, cap])
	TestLib.check(hive.leaps == 0, "the hive does not leapfrog")
	var near := 0
	for op in obs:
		if op.global_position.distance_to(p.global_position) < 24.0:
			near += 1
	TestLib.check(near >= 1 or seen, "the squad advanced on the hero")
	em.clear()
	Game.set_quality(2)


# --- flush grenade ---------------------------------------------------------------------------------------------------

func _flush() -> void:
	await _fresh()
	Game.set_quality(2)
	em.force_hold = true
	var hive := _spawn(&"operative", Vector3(16.0, 0.0, 3.0), &"vael", true)
	await _secs(5.0)
	TestLib.check(em.flush_throws == 0 and hive.flushes == 0, "the hive never throws a flush grenade at a hero in cover")
	em.clear()
	var obs := _spawn(&"operative", Vector3(16.0, 0.0, 3.0), &"observer", true)
	obs.set_physics_process(true)
	var thrown := await _until(func() -> bool: return em.flush_throws >= 1, 14.0)
	TestLib.check(thrown and obs.flushes >= 1, "a hero who holds cover for 3 s gets a flush grenade (%d)" % em.flush_throws)
	var before := em.flush_throws
	await _secs(4.0)
	TestLib.check(em.flush_throws == before, "one grenade per squad cooldown, not a stream")
	var gone := await _until(func() -> bool: return em._flush_live == 0, 4.0)
	TestLib.check(gone, "the grenade detonated and left no state behind")
	em.force_hold = false
	em.hero_hold_t = 0.0
	em.clear()


# --- medic priority, retreat and regroup ---------------------------------------------------------------------------

func _medic_and_regroup() -> void:
	await _fresh()
	# (a) the mender heals the most wounded ally first
	var m := em.spawn(&"mender", o + Vector3(14.0, 0.0, 0.0), true)
	m.set_physics_process(true)
	var a := _spawn(&"operative", Vector3(14.0, 0.0, 3.0), &"observer", true, 0.2)
	var b := _spawn(&"operative", Vector3(14.0, 0.0, -3.0), &"observer", true, 0.7)
	var a0 := a.hp
	var b0 := b.hp
	var got := await _until(func() -> bool: return a.hp - a0 > 8.0, 5.0)
	var da := a.hp - a0
	var db := b.hp - b0
	TestLib.check(got and da > db * 1.8, "the mender heals the most wounded ally first (%.1f vs %.1f hp)" % [da, db])
	em.clear()
	await _secs(0.3)
	# (b) a hurt observer falls back to the mender and regroups once healed
	_crate(Vector3(10.0, 0.0, -10.0), Vector3(2.5, 1.8, 2.5))
	var m2 := em.spawn(&"mender", o + Vector3(12.0, 0.0, -14.0), true)
	m2.set_physics_process(true)
	var hurt := _spawn(&"operative", Vector3(26.0, 0.0, 6.0), &"observer", false, 0.2)
	var started := await _until(func() -> bool: return hurt.is_retreating(), 3.0)
	TestLib.check(started, "below a quarter hp an observer retreats")
	var reached := await _until(func() -> bool: return hurt.global_position.distance_to(m2.global_position) < 7.0, 18.0)
	TestLib.check(reached, "the retreat heads for the mender")
	var back := await _until(func() -> bool: return hurt.regroups >= 1, 14.0)
	TestLib.check(back and not hurt.is_retreating() and hurt.hp / hurt.max_hp >= 0.45, "healed, the trooper regroups and returns to the fight (hp %.0f%%)" % (100.0 * hurt.hp / hurt.max_hp))
	em.clear()
	await _secs(0.3)
	# (c) allies alone regroup a retreat too
	var friends: Array[Operative] = []
	for i in 2:
		friends.append(_spawn(&"operative", Vector3(24.0, 0.0, -4.0 + 8.0 * i), &"observer", true))
	var lone := _spawn(&"operative", Vector3(24.0, 0.0, 0.0), &"observer", false, 0.2)
	var retreated := await _until(func() -> bool: return lone.is_retreating() or lone.regroups > 0, 3.0)
	var regrouped := await _until(func() -> bool: return lone.regroups >= 1, 12.0)
	TestLib.check(retreated and regrouped, "two allies close by bring a retreating trooper back")
	em.clear()


# --- factions behave differently ------------------------------------------------------------------------------------

func _factions() -> void:
	await _fresh()
	var ob := _spawn(&"operative", Vector3(24.0, 0.0, -6.0), &"observer", false, 0.35)
	var hv := _spawn(&"operative", Vector3(24.0, 0.0, 0.0), &"vael", false, 0.2)
	var rd := _spawn(&"flanker", Vector3(24.0, 0.0, 6.0), &"", false, 0.35)
	TestLib.check(rd.faction == TacticsTable.RAIDER, "a flanker is a raider")
	var out := await _until(func() -> bool: return rd.is_retreating() or rd.regroups > 0, 3.0)
	await _secs(0.5)
	TestLib.check(not ob.is_retreating() and ob.regroups == 0, "observers hold at 35 % hp")
	TestLib.check(not hv.is_retreating() and hv.regroups == 0, "the hive fights on at 20 % hp")
	TestLib.check(out, "raiders pull out at 35 % hp")
	em.clear()


# --- commanders -------------------------------------------------------------------------------------------------------

func _commander() -> void:
	await _fresh()
	var w := em.spawn(&"warden", o + Vector3(24.0, 0.0, 0.0), true)
	w.set_physics_process(false)
	var near := _spawn(&"operative", Vector3(30.0, 0.0, 0.0), &"observer", true)
	var far := _spawn(&"operative", Vector3(24.0, 0.0, 28.0), &"observer", true)
	var buffed := await _until(func() -> bool: return near.buff_dmg > 1.0, 3.0)
	TestLib.check(buffed and is_equal_approx(near.buff_dmg, TacticsTable.BUFF_DMG) and is_equal_approx(near.buff_speed, TacticsTable.BUFF_SPEED), "an ally within range of the commander fires harder and moves faster")
	TestLib.check(far.buff_dmg == 1.0 and em.buffed_count >= 1, "an ally out of range is not buffed")
	w.damage(1.0e6)
	var gone := await _until(func() -> bool: return near.buff_dmg == 1.0, 3.0)
	TestLib.check(gone, "the buff ends with the commander")
	em.clear()


# --- the scripted fight bot ---------------------------------------------------------------------------------------------

func _fight_bot() -> void:
	await _fresh()
	Game.set_quality(2)
	_crate(Vector3(16.0, 0.0, -9.0), Vector3(3.0, 1.9, 3.0))
	_crate(Vector3(20.0, 0.0, 8.0), Vector3(1.2, 1.1, 1.2))
	_crate(Vector3(27.0, 0.0, -2.0), Vector3(3.5, 2.0, 2.0))
	_crate(Vector3(33.0, 0.0, 10.0), Vector3(2.5, 1.6, 2.5))
	_crate(Vector3(12.0, 0.0, 12.0), Vector3(2.0, 1.4, 2.0))
	var crew: Array[Operative] = []
	var spawned := {}
	var t := 0.0
	for i in 4:
		crew.append(_spawn(&"operative", Vector3(34.0 + randf() * 6.0, 0.0, -16.0 + 8.0 * i), &"observer"))
	for i in 4:
		crew.append(_spawn(&"operative", Vector3(36.0 + randf() * 6.0, 0.0, -14.0 + 8.0 * i), &"vael"))
	for i in 3:
		crew.append(_spawn(&"flanker", Vector3(38.0 + randf() * 4.0, 0.0, -10.0 + 10.0 * i)))
	for e in crew:
		e.tactic_role = &""
		e._called = false
		spawned[e] = 0.0
	var ttk := {}
	var still := {}
	var last := {}
	var stuck := 0
	var bot_t := 0.0
	var span := 70.0
	var steps := int(span / DT / 4.0)
	for i in steps:
		await TestLib.frames(host, 4)
		t += DT * 4.0
		bot_t += DT * 4.0
		for e in crew:
			if not is_instance_valid(e) or e.dead or not e.active:
				if not ttk.has(e):
					ttk[e] = t
				continue
			var pos := e.global_position
			if not last.has(e):
				last[e] = pos
				still[e] = 0.0
			elif Vector2(pos.x - last[e].x, pos.z - last[e].z).length() > 0.25 or e.cover_state() != 0 or e._aim_t > 0.0 or e._burst_left > 0 or e.is_retreating():
				last[e] = pos
				still[e] = 0.0
			else:
				still[e] += DT * 4.0
				if still[e] > 12.0 and e.aware:
					stuck += 1
					still[e] = -1.0e9                                     # count one enemy once
		if bot_t >= 0.3:                                                # the bot's rifle: a burst at the nearest enemy it can see and that is not behind cover
			bot_t = 0.0
			var tgt: Operative = null
			var bd := 45.0
			for e in crew:
				if not is_instance_valid(e) or e.dead or not e.active or e.cover_state() == 2:
					continue
				var d := e.global_position.distance_to(p.global_position)
				if e.los and d < bd:
					bd = d
					tgt = e
			if tgt != null:
				tgt.damage(22.0)
		var alive := 0
		for e in crew:
			if is_instance_valid(e) and not e.dead:
				alive += 1
		if alive == 0:
			break
	var times: Array[float] = []
	for e in ttk:
		times.append(float(ttk[e]))
	times.sort()
	var kills := times.size()
	var lo := times[0] if kills > 0 else 0.0
	var hi := times[kills - 1] if kills > 0 else 0.0
	var mean := 0.0
	for x in times:
		mean += x
	mean /= maxf(float(kills), 1.0)
	var var_sum := 0.0
	for x in times:
		var_sum += (x - mean) * (x - mean)
	var sd := sqrt(var_sum / maxf(float(kills), 1.0))
	print("fight bot: kills ", kills, " of ", crew.size(), " first ", snappedf(lo, 0.1), " last ", snappedf(hi, 0.1), " sd ", snappedf(sd, 0.1), " stuck ", stuck)
	TestLib.check(kills >= 8, "the bot beat most of the 11 troopers (%d)" % kills)
	TestLib.check(hi - lo >= 4.0 and sd >= 1.0, "kills vary in time-to-kill (spread %.1f s, sd %.1f s)" % [hi - lo, sd])
	TestLib.check(stuck == 0, "no enemy stood stuck (%d)" % stuck)
	var with_cover := 0
	var covered_any := false
	for e in crew:
		if is_instance_valid(e) and (e.leaps > 0 or e.suppress_bursts > 0 or e.regroups > 0):
			with_cover += 1
		covered_any = covered_any or (is_instance_valid(e) and e._cover_on)
	TestLib.check(covered_any, "the troopers fight with cover on")
	em.clear()


func _caps() -> void:
	var ok := true
	for tier in 3:
		Game.set_quality(tier)
		var n := 0
		for i in 12:
			if em.try_think():
				n += 1
		em._think_frame = -1
		ok = ok and n == int(EnemyManager.THINKERS[tier])
	TestLib.check(ok, "thinkers per frame stay capped on every tier")
