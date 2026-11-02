extends RefCounted
## Enemy variety (D3/D4): stalker (blink, phased), carrier (all-round ward, releases swarmers), walker (mortar), swarmer (micro-drone), elites warden (phase pulse + blink) and
## hivemother (calls swarmers); chapter/heat selection, tier limits and elite caps, role colours. Run: tools/test.sh tests/test_enemy_variety.gd

const Env := preload("res://tests/player_env.gd")
const Stubs := preload("res://tests/enemies_stubs.gd")
const DT := 1.0 / 60.0
const NEW: Array[StringName] = [&"stalker", &"carrier", &"walker", &"swarmer", &"warden", &"hivemother"]

var e := Env.new()
var p: Player
var em: EnemyManager
var stub_missions := Stubs.StubMissions.new()


func run(host: Node) -> void:
	seed(7)
	await e.setup(host)
	p = e.p
	e.root.add_child(stub_missions)
	Game.missions = stub_missions
	em = (load("res://scenes/enemy_manager.tscn") as PackedScene).instantiate() as EnemyManager
	e.root.add_child(em)
	em.patrol_groups().clear()
	await e.frames(3)
	_tables()
	await _behaviours()
	Game.missions = null
	Game.heat = 0.0
	await e.teardown()


func _tables() -> void:
	var seen := {}
	for t in NEW:
		TestLib.check(EnemyTypes.TYPES.has(t), "%s in the table" % t)
		var c := EnemyLook.code_color(EnemyTypes.get_cfg(t))
		var k := "%d,%d,%d" % [int(c.r * 10), int(c.g * 10), int(c.b * 10)]
		TestLib.check(not seen.has(k), "%s has its own colour" % t)
		seen[k] = true
	for t in [&"operative", &"shield", &"flanker", &"sniper", &"brute", &"sentinel", &"striker", &"heavy"]:
		var c := EnemyLook.code_color(EnemyTypes.get_cfg(t))
		seen["%d,%d,%d" % [int(c.r * 10), int(c.g * 10), int(c.b * 10)]] = true
	TestLib.check(seen.size() == NEW.size() + 8, "no colour shared with the existing roles")
	TestLib.check(EnemyTypes.is_elite(&"warden") and EnemyTypes.is_elite(&"hivemother") and not EnemyTypes.is_elite(&"stalker"), "two elites")
	TestLib.check(EnemyTypes.is_specialist(&"stalker") and not EnemyTypes.is_specialist(&"swarmer"), "swarmer is a plain drone")
	# chapter selection
	var s0 := {}
	var s2 := {}
	var s5 := {}
	var elite_low_heat := false
	for i in 600:
		s0[EnemyTypes.variety_for(0, 4.0, randf() * 0.09 + 0.11, randf())] = true
		s2[EnemyTypes.variety_for(2, 2.0, randf() * 0.15, randf())] = true
		s5[EnemyTypes.variety_for(5, 2.0, randf() * 0.3, randf())] = true
		elite_low_heat = elite_low_heat or EnemyTypes.is_elite(EnemyTypes.variety_for(5, 2.0, 0.05, randf()))
	TestLib.check(s0.size() == 1 and s0.has(&""), "chapter 1: no variety")
	TestLib.check(s2.has(&"stalker") and s2.has(&"swarmer") and not s2.has(&"carrier") and not s2.has(&"walker"), "chapter 3: stalkers and swarmers")
	TestLib.check(s5.has(&"carrier") and s5.has(&"walker"), "later chapters add carriers and walkers")
	TestLib.check(not elite_low_heat, "no elites below heat 3")
	var el3 := {}
	var el5 := {}
	for i in 100:
		el3[EnemyTypes.variety_for(3, 3.5, 0.02, randf())] = true
		el5[EnemyTypes.variety_for(5, 3.5, 0.02, randf())] = true
	TestLib.check(el3.has(&"warden") and not el3.has(&"hivemother"), "warden from chapter 4")
	TestLib.check(el5.has(&"warden") and el5.has(&"hivemother"), "hivemother joins in chapter 6")
	TestLib.check(EnemyManager.pick_type(0.5, 0.2, 5, 0.0, 0.5) == EnemyManager.pick_type(0.5, 0.2, 5, 0.0, 0.5, 1.0), "r_var defaults to none")
	# tier limits
	TestLib.check(EnemyTypes.tier_limit(&"warden", 0) == 0 and EnemyTypes.tier_limit(&"warden", 1) == 1, "no elites on LOW, one on MED")
	TestLib.check(EnemyTypes.tier_limit(&"swarmer", 0) < EnemyTypes.tier_limit(&"swarmer", 2) and EnemyTypes.tier_limit(&"walker", 0) == 1, "variety limits scale with the tier")
	TestLib.check(EnemyTypes.tier_limit(&"flanker", 0) == 3, "old limits unchanged")


func _fresh() -> void:
	em.clear()
	Game.heat = 0.0
	Game.state = &"play"
	await e.prep(Vector3(0.0, 0.05, 0.0))
	p.max_hp = 1.0e6
	p.hp = p.max_hp


func _spawn(type: StringName, at: Vector3) -> Drone:
	var d := em.spawn(type, at, true)
	d.set_physics_process(false)
	await e.frames(2)
	return d


func _behaviours() -> void:
	Game.quality = 2
	await _fresh()
	# stalker: phased during the wind, blink moves it to the ring round the target
	var st := await _spawn(&"stalker", Vector3(20.0, 0.0, 0.0)) as Specialist
	var d0 := st.global_position.distance_to(p.global_position)
	st._tgt = p.global_position
	st._tgt_ok = true
	st._blink_wind = Specialist.BLINK_WIND
	var hp0 := st.hp
	st.damage(10.0)
	TestLib.check(is_equal_approx(st.hp, hp0), "a phasing stalker takes no damage")
	st._blink_wind = 0.0
	st.blink()
	var d1 := st.global_position.distance_to(p.global_position)
	TestLib.check(st.blink_count() == 1 and d1 >= 5.5 and d1 <= 9.5 and absf(d1 - d0) > 0.5, "blink lands 6-9 m from the target (%.1f m)" % d1)
	st.damage(10.0)
	TestLib.check(st.hp < hp0, "damage lands again after the blink")
	# carrier: all-round ward, breaks into swarmers
	var ca := await _spawn(&"carrier", Vector3(0.0, 0.0, 18.0)) as Specialist
	TestLib.check(ca.shield_up() and ca.shield_node != null, "carrier wears a ward")
	TestLib.check(ca.shield_blocks(ca.global_position + Vector3(0, 0, 10)) and ca.shield_blocks(ca.global_position + Vector3(10, 0, 0)), "the ward covers every side")
	var n0 := em.count_type(&"swarmer")
	ca.break_shield()
	TestLib.check(em.count_type(&"swarmer") == n0 + 2 and em.count_type(&"swarmer") <= EnemyTypes.tier_limit(&"swarmer", 2), "a broken ward releases two swarmers")
	TestLib.check(em.alive_count() <= em.cap(), "cap respected")
	# swarmer: a small kamikaze drone
	var sw := em.list.filter(func(x: Drone) -> bool: return x.type == &"swarmer")[0] as Drone
	TestLib.check(sw.hp <= 10.0 * Progress.enemy_hp_mult() + 0.1 and bool(sw.cfg["kamikaze"]) and float(sw.cfg["scale"]) < 0.6, "swarmer is a tiny kamikaze")
	# walker: lock then land a shell
	await _fresh()
	var w := await _spawn(&"walker", Vector3(30.0, 0.0, 0.0)) as Specialist
	w._tgt = p.global_position
	w._tgt_ok = true
	w._shell_cd = 0.0
	w._fire_walker(DT, 30.0, 60.0)
	TestLib.check(w.threat_charge() == 0.0 and w._shell_t > 1.4, "walker locks a ground point")
	for i in int(Specialist.SHELL_TIME / DT) + 4:
		w._fire_walker(DT, 30.0, 60.0)
	TestLib.check(w.shell_count() == 1, "the shell lands after the delay")
	# warden: pulse hurts nearby, then blinks
	await _fresh()
	var wa := await _spawn(&"warden", Vector3(3.0, 0.0, 0.0)) as Specialist
	wa._tgt = p.global_position
	wa._tgt_ok = true
	p.hp = 100.0
	p.max_hp = 100.0
	wa._pulse()
	TestLib.check(wa.pulse_count() == 1 and wa.blink_count() == 1, "pulse then blink")
	TestLib.check(p.hp < 100.0, "the pulse hurt the player (%.0f)" % p.hp)
	TestLib.check(wa.global_position.distance_to(p.global_position) >= 9.0, "the warden blinks 10+ m away")
	# hivemother: call
	await _fresh()
	var hm := await _spawn(&"hivemother", Vector3(10.0, 0.0, 0.0)) as Specialist
	hm._tgt = p.global_position
	hm._tgt_ok = true
	hm._summon_cd = 0.0
	for i in int((Specialist.SUMMON_WIND + 0.2) / DT) + 2:
		hm._move_hivemother(DT, 1.0, 0.0, 12.0, 3.0, 32.0)
	TestLib.check(hm.summon_count() == 1 and em.count_type(&"swarmer") == 2, "the hivemother calls two swarmers")
	# elites: tier cap
	await _fresh()
	Game.quality = 1
	var w1 := em.spawn(&"warden", Vector3(30.0, 0.0, 0.0), true)
	TestLib.check(em.elite_count() == 1 and w1 != null, "one elite on MED")
	TestLib.check(EnemyTypes.tier_limit(&"hivemother", 1) == 1 and em.elite_count() >= EnemyTypes.ELITE_CAPS[1], "the elite cap on MED is full")
	Game.quality = 2
	em.clear()
