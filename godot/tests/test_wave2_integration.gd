extends RefCounted
## Wave-2 integration (headless): boots scenes/main.tscn with every module; enemies, damage, drops, core collection, win, respawn, caps.
## Run: tools/test.sh tests/test_wave2_integration.gd

var host: Node


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	var p := Game.player as Player
	var em := Game.enemies as EnemyManager
	var ms := Game.missions as Missions
	TestLib.check(p != null and em != null and ms != null and Game.world != null and Game.is_playing(), "main.tscn registers player, enemies, missions, world and is playing")
	if p == null or em == null or ms == null:
		return
	TestLib.check(ms.total >= 6 and ms.cores.size() == ms.total, "the first round placed %d cores" % ms.total)
	# enemy caps by tier
	for q in [0, 1, 2]:
		Game.set_quality(q)
		await frames(2)
		var cap_expected: int = [5, 8, 12][q]
		TestLib.check(em.cap() == cap_expected, "tier %d enemy cap is %d (got %d)" % [q, cap_expected, em.cap()])
		em.clear()
		var made := 0
		for i in 20:
			if em.spawn(&"sentinel", Game.SPAWN + Vector3(30.0 + i * 2.0, 0.0, 0.0)) != null:
				made += 1
		TestLib.check(made == cap_expected, "tier %d: spawn() stops at the cap (%d)" % [q, made])
	Game.set_quality(1)
	em.clear()
	await frames(2)
	# damage and kill a drone: score, heat, drop
	p.teleport_to(Game.SPAWN)
	var d := em.spawn(&"sentinel", Game.SPAWN + Vector3(14.0, 0.0, 0.0), true)
	TestLib.check(d != null, "a drone spawns")
	await frames(10)
	var score0 := Game.score
	d.damage(d.hp * 0.5)
	TestLib.check(not d.dead and d.hp > 0.0, "damage lowers hp without killing")
	d.damage(9999.0)
	await frames(5)
	TestLib.check(d.dead and not d.is_in_group(&"enemy"), "a killed drone is dead and leaves group enemy")
	TestLib.check(Game.score > score0, "killing a drone scores (%d -> %d)" % [score0, Game.score])
	# drop pickup
	var hp0 := p.hp
	p.hp = 50.0
	ms.drop(&"health", p.global_position + Vector3(0.0, 0.0, 0.0))
	TestLib.check(ms.pickups.size() >= 1, "a drop creates a pickup")
	await frames(10)
	TestLib.check(p.hp > 50.0, "walking onto a health pickup heals (%.0f)" % p.hp)
	p.hp = hp0
	# heat flow
	Game.heat = 3.0
	await frames(2)
	TestLib.check(Game.heat >= 2.9, "heat is held while recent")
	# collect every core, then win
	var wins := [0]
	var l := func() -> void: wins[0] += 1
	Game.sector_cleared.connect(l)
	var n := ms.total
	for i in n:
		if ms.cores.is_empty():
			break
		p.teleport_to(ms.cores[0].pos + Vector3(0.0, 0.2, 0.0))
		await frames(6)
		Game.state = &"play" if i < n - 1 else Game.state
	TestLib.check(ms.got == n and ms.cores.is_empty(), "all %d cores collected (%d)" % [n, ms.got])
	TestLib.check(Game.state == &"win" and wins[0] == 1, "the last core wins exactly once (state %s, %d)" % [Game.state, wins[0]])
	Game.sector_cleared.disconnect(l)
	Game.do_next_sector()
	await frames(5)
	TestLib.check(Game.state == &"play" and ms.total == 7 and ms.cores.size() == 7, "next sector builds 7 cores (%d)" % ms.total)
	# death and respawn with enemies around
	em.spawn(&"striker", Game.SPAWN + Vector3(25.0, 0.0, 0.0), true, true)
	Game.heat = 4.0
	p.invuln = 0.0
	p.damage(999.0)
	await frames(30)
	TestLib.check(Game.state == &"dead", "the player dies")
	Game.do_respawn()
	await frames(10)
	TestLib.check(Game.state == &"play" and not p.is_dead() and Game.heat == 0.0 and ms.cores.size() == 7, "respawn: play, heat 0, cores kept")
	TestLib.check(em.alive_count() <= em.cap(), "enemies stay within the cap after respawn")
	main.queue_free()
	await frames(10)
	TestLib.check(Game.enemies == null and Game.missions == null, "freeing the game clears the enemies and missions registry")
	Game.state = &"menu"
	Sfx.muted = false
