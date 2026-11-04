extends RefCounted
## HERO POWER by difficulty (scripts/progress/hero_power.gd) in the real scene (main.tscn): the table is complete and monotone, and switching Difficulty applies live to
## health regen, damage taken, energy cost, cooldown, teleport range and chained hops, jump and sprint speed.
## Run: tools/test.sh tests/test_hero_power.gd

var host: Node


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	var keep := Difficulty.current
	# table
	var keys := (HeroPower.ROWS[0] as Dictionary).keys()
	TestLib.check(HeroPower.ROWS.size() == Difficulty.NAMES.size(), "one row per difficulty")
	for r in HeroPower.ROWS:
		TestLib.check((r as Dictionary).keys() == keys, "every row has the same keys")
	for k in ["regen", "dmg", "energy_regen", "sprint", "jump", "tp_range", "tp_hops"]:
		TestLib.check(HeroPower.f(k, 0) > HeroPower.f(k, 1) and HeroPower.f(k, 1) >= HeroPower.f(k, 2) and HeroPower.f(k, 2) >= HeroPower.f(k, 3), "%s falls from STORY to QUANTUM" % k)
	TestLib.check(HeroPower.f("energy_cost", 0) < 0.1 and HeroPower.f("cooldown", 0) < 0.2 and HeroPower.f("taken", 0) < 1.0, "STORY: near-free energy, tiny cooldowns, low damage taken")

	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	var p := Game.player as Player
	TestLib.check(p != null and p.quantum != null, "the real scene has the player and QUANTUM")
	if p == null or p.quantum == null:
		main.queue_free()
		return
	var q: Node = p.quantum
	Game.state = &"play"
	await frames(3)
	var res := {}
	for m in [0, 1, 3]:
		Difficulty.set_mode(m)
		p.invuln = 0.0
		p.since_hurt = 99.0
		p.hp = 10.0
		p.max_hp = 100.0
		p._tick(1.0)
		var regen := p.hp - 10.0
		p.hp = 100.0
		p.since_hurt = 99.0
		p.invuln = 0.0
		p.damage(10.0)
		var taken := 100.0 - p.hp
		p.hp = 100.0
		p.energy = 100.0
		q.cd_blink = 0.0
		q.has_beacon = true
		q.beacon_pos = p.global_position + Vector3(6.0, 0.0, 0.0)
		q.chain_left = 0
		q._chain_t = 0.0
		var e0 := p.energy
		q.aiming = true
		q.aim_pos = q.beacon_pos
		q.aim_go()
		res[m] = {"regen": regen, "taken": taken, "cost": e0 - p.energy, "cd": q.cd_blink, "chain": q.chain_left}
		p.global_position.y += 0.0
	TestLib.check(res[0]["regen"] > res[1]["regen"] * 3.0 and res[1]["regen"] > res[3]["regen"], "health regen applies live per difficulty")
	TestLib.check(res[0]["taken"] < res[1]["taken"] and res[1]["taken"] < res[3]["taken"], "damage taken applies live per difficulty")
	TestLib.check(res[0]["cost"] < res[1]["cost"] * 0.2 and res[1]["cost"] <= res[3]["cost"], "QUANTUM TELEPORT energy cost scales")
	TestLib.check(res[0]["cd"] < res[1]["cd"] and res[1]["cd"] < res[3]["cd"], "cooldown scales")
	TestLib.check(res[0]["chain"] > res[1]["chain"] and res[1]["chain"] > res[3]["chain"], "chained hops scale (STORY > NORMAL > QUANTUM)")
	# chained hop: no cooldown inside the window
	Difficulty.set_mode(0)
	p.energy = 100.0
	q.cd_blink = 0.0
	q.has_beacon = true
	q.beacon_pos = p.global_position + Vector3(4.0, 0.0, 0.0)
	q.teleport()
	var left: int = q.chain_left
	q.has_beacon = true
	q.beacon_pos = p.global_position + Vector3(4.0, 0.0, 0.0)
	q.teleport()
	TestLib.check(q.chain_left == left - 1 and q.cd_blink == 0.0, "a chained hop has no cooldown and uses one hop")
	# speeds
	Difficulty.set_mode(0)
	var j0 := HeroPower.f("jump")
	Difficulty.set_mode(3)
	TestLib.check(j0 > HeroPower.f("jump") and HeroPower.can_wall_run() == false, "jump and wall-run follow the difficulty")
	Difficulty.set_mode(0)
	TestLib.check(HeroPower.can_wall_run() and HeroPower.f("glide") > 0.0 and HeroPower.f("glide", 0) < HeroPower.f("glide", 1), "STORY can wall-run and glides slower than NORMAL")
	Difficulty.set_mode(keep)
	Game.state = &"menu"
	main.queue_free()
	await frames(2)
