extends RefCounted
## Stealth and alert states (A6): levels, noise, search, takedown bonus, decoy, contract bonus constants.
## Run: tools/test.sh tests/test_stealth.gd


func run(host: Node) -> void:
	TestLib.check(Stealth.level_of(false, 0.0, 0.0) == Stealth.Level.UNAWARE, "level unaware")
	TestLib.check(Stealth.level_of(false, 0.0, 0.5) == Stealth.Level.SUSPICIOUS, "level suspicious")
	TestLib.check(Stealth.level_of(false, 3.0, 1.0) == Stealth.Level.SEARCHING, "level searching")
	TestLib.check(Stealth.level_of(true, 3.0, 1.0) == Stealth.Level.ALERTED, "level alerted")
	TestLib.check(Stealth.noise_amount(5.0, 40.0) > Stealth.noise_amount(30.0, 40.0), "closer noise is stronger")
	TestLib.check(Stealth.noise_amount(50.0, 40.0) == 0.0, "no effect out of range")
	TestLib.check(Stealth.noise_range(&"vehicle", 2.0) == 0.0 and Stealth.noise_range(&"vehicle", 25.0) > Stealth.noise_range(&"sprint"), "slow vehicles are quiet, fast ones loud")
	TestLib.check(Stealth.sight_rate(4.0, 32.0) > Stealth.sight_rate(30.0, 32.0), "sight fills faster up close")
	TestLib.check(Stealth.takedown_bonus() > 0 and Stealth.TUNING.has("contract_bonus"), "bonuses tuned")
	Stealth.reset_run()
	TestLib.check(Stealth.contract_bonus_due(), "stealth bonus due with no alerts")

	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 3)
	var em := Game.enemies as EnemyManager
	var p: Node3D = Game.player
	if em == null or p == null:
		TestLib.check(false, "enemy manager and player present")
		return
	var base := p.global_position
	var a := em.spawn(&"sentinel", base + Vector3(30, 0, 0), false)
	a.aware_dist = 1.0                                  # sight off: only noise can reach it
	a.set_physics_process(false)
	Game.heat = 0.0
	Stealth.noise(em.list, base, &"sprint")
	TestLib.check(a.suspicion == 0.0 and not a.aware, "a sprint 30 m away is not heard")
	Stealth.noise(em.list, base, &"gun")
	TestLib.check(a.suspicion > 0.0 and not a.aware and a.alert_level() >= Stealth.Level.SUSPICIOUS, "gunfire in hearing range raises suspicion")
	a.hear(base + Vector3(10, 0, 0), 1.0)
	TestLib.check(a.alert_level() == Stealth.Level.SEARCHING and a.last_known.distance_to(Vector3(base.x + 10, 0, base.z)) < 0.1, "loud noise starts a search at that spot")
	TestLib.check(a.alert_pip() == 2, "searching shows a pip")
	Stealth.noise(em.list, a.global_position + Vector3(2, 0, 0), &"gun")
	TestLib.check(a.aware and a.alert_level() == Stealth.Level.ALERTED, "gunfire at close range alerts")

	var b := em.spawn(&"sentinel", base + Vector3(-30, 0, 0), false)
	b.aware_dist = 1.0
	b.set_physics_process(false)
	var s0 := Game.score
	var t0 := Stealth.takedowns
	b.damage(9999.0)
	TestLib.check(b.dead and Stealth.takedowns == t0 + 1 and Game.score >= s0 + Stealth.takedown_bonus(), "silent takedown pays a bonus")
	var c := em.spawn(&"sentinel", base + Vector3(0, 0, -30), true)
	c.set_physics_process(false)
	var t1 := Stealth.takedowns
	c.damage(9999.0)
	TestLib.check(c.dead and Stealth.takedowns == t1, "killing an alerted enemy is no takedown")

	var d := em.spawn(&"sentinel", base + Vector3(0, 0, 40), false)
	d.aware_dist = 1.0
	d.set_physics_process(false)
	Stealth.noise(em.list, base + Vector3(0, 0, 40 - 10), &"decoy")
	TestLib.check(d.alert_level() >= Stealth.Level.SUSPICIOUS, "decoy distracts nearby unaware enemies")
	TestLib.check(d.last_known.distance_to(Vector3(base.x, 0, base.z + 30)) < 0.1, "decoy sets the investigate spot")
