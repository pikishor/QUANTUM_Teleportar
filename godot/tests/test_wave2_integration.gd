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
	# quantum flow in the real city: blink, entangle, superposition, all through the real player, enemies and world
	var q := p.quantum as Quantum
	TestLib.check(q != null and q.get_parent() == p, "the player carries the real Quantum module")
	TestLib.check(UiUtil.ability_state(p, UiUtil.ABILITIES[0])["on"], "the HUD sees the quantum module (ability buttons on)")
	em.clear()
	p.energy = 100.0
	p.teleport_to(Game.SPAWN)
	p.camera_rig.reset_view(-PI * 0.5, -0.15)
	p.yaw = -PI * 0.5
	await frames(8)
	TestLib.check(q.blink() and q.has_beacon, "blink throws a beacon in the city")
	var beacon := q.beacon_pos
	TestLib.check(beacon.distance_to(p.global_position) > 5.0 and not (Game.world as City).is_inside_building(beacon + Vector3(0.0, 1.0, 0.0)), "the beacon is out in front and not inside a building")
	q.cd_blink = 0.0
	TestLib.check(q.blink() and not q.has_beacon, "the second blink teleports")
	TestLib.check(p.global_position.distance_to(beacon) < 0.3 and not (Game.world as City).is_inside_building(p.global_position + Vector3(0.0, 1.0, 0.0)), "the player stands on the beacon, outside any building")
	TestLib.check(q.last_fix == Quantum.fix_for(q.last_m0, q.last_m1) and q.bits_left > 0.0, "Alice's bits and Bob's correction are recorded for the HUD")
	await frames(10)
	p.teleport_to(Game.SPAWN)
	p.camera_rig.reset_view(-PI * 0.5, -0.1)
	await frames(4)
	var qa := em.spawn(&"sentinel", Game.SPAWN + Vector3(14.0, 0.0, 2.0), false)
	var qb := em.spawn(&"sentinel", Game.SPAWN + Vector3(19.0, 0.0, -3.0), false)
	p.camera_rig.aim_at(qa.center())
	await frames(3)
	TestLib.check(q.link_drones() and qa.linked == qb and qb.linked == qa, "link_drones links two drones in the city")
	var qhp := qb.hp
	qa.damage(12.0)
	TestLib.check(absf(qb.hp - (qhp - 12.0)) < 0.01, "damage to one linked drone reaches the other")
	# ENTANGLE is the swap ability: it trades places with a target in sight
	em.clear()
	p.energy = 100.0
	q.cd_link = 0.0
	p.teleport_to(Game.SPAWN)
	p.camera_rig.reset_view(-PI * 0.5, -0.1)
	await frames(4)
	var qs := em.spawn(&"sentinel", Game.SPAWN + Vector3(14.0, 0.0, 2.0), false)
	p.camera_rig.aim_at(qs.center())
	await frames(3)
	var from := p.global_position
	var tpos := qs.global_position
	var e0 := p.energy
	TestLib.check(q.entangle() and p.energy < e0 and q.cd_link > 0.0, "entangle swaps with a target in sight and costs coherence")
	await frames(4)
	TestLib.check(p.global_position.distance_to(tpos) < 1.0 and qs.global_position.distance_to(from) < 4.0, "the player and the drone traded places (player %.1f m from the drone's old spot, drone %.1f m from the player's)" % [p.global_position.distance_to(tpos), qs.global_position.distance_to(from)])
	q.cd_super = 0.0
	TestLib.check(q.superpose() and q.clone != null and p.speed_boost == 1.3 and em.get_clone() == q.clone, "superposition leaves a clone the enemies can see, with the speed boost")
	var cpos := q.clone.global_position
	var qc := em.spawn(&"heavy", cpos + Vector3(3.0, 0.0, 0.0), false)
	var qc_hp := qc.hp
	q.collapse()
	TestLib.check(q.clone == null and p.speed_boost == 1.0 and qc.hp < qc_hp - 40.0, "collapse blasts nearby enemies and ends the boost (%.0f damage)" % (qc_hp - qc.hp))
	em.clear()
	await frames(4)
	# vehicle flow in the real city: starter car, enter with interact, drive, ram a drone, exit; caps and streaming
	var vm := Game.vehicles as VehicleManager
	TestLib.check(vm != null and vm.starter != null and vm.starter.kind == &"sport" and vm.list.has(vm.starter), "the vehicles module is composed and the starter sport car stands near the spawn")
	if vm != null and vm.starter != null:
		var car := vm.starter
		Game.set_quality(1)
		Game.heat = 0.0
		p.invuln = 0.0
		p.teleport_to(car.global_position + Vector3(0.0, 0.0, -3.0))
		await frames(6)
		TestLib.check(vm.nearest(p.global_position, 4.2) == car, "the HUD's USE hint finds the car (nearest within 4.2 m)")
		Input.action_press(&"interact")
		await frames(3)
		Input.action_release(&"interact")
		await frames(3)
		TestLib.check(p.vehicle == car and vm.driven == car and car.driver_is_player and p.camera_rig.mode == &"vehicle", "interact enters the car: player.vehicle set, camera in vehicle mode")
		var drone := em.spawn(&"sentinel", car.global_position + Vector3(11.0, 0.0, 0.0), false)
		var drone_hp := drone.hp
		var x0 := car.global_position.x
		Input.action_press(&"move_forward")
		await frames(100)
		Input.action_release(&"move_forward")
		TestLib.check(car.global_position.x - x0 > 12.0 and car.speed > 8.0, "forward drives the car through the real city (%.0f m, %.1f m/s)" % [car.global_position.x - x0, car.speed])
		TestLib.check(p.global_position.distance_to(car.global_position) < 0.6 and absf(car.rotation.y - car.heading) < 1e-3, "the player rides with the car and the root rotates with it")
		TestLib.check(drone.hp < drone_hp or drone.dead, "running into a drone at speed hurts it (%.0f -> %.0f)" % [drone_hp, drone.hp])
		em.clear()
		await frames(60)
		Input.action_press(&"interact")
		await frames(3)
		Input.action_release(&"interact")
		await frames(3)
		TestLib.check(p.vehicle == null and vm.driven == null and p.body.visible and not (Game.world as City).is_inside_building(p.global_position + Vector3(0.0, 1.0, 0.0)), "interact again leaves the car and the player stands outside any building")
		await frames(150)
		TestLib.check(vm.list.size() <= vm.cap() and vm.list.size() >= 3 and vm.total_nodes() <= 10, "streaming keeps the live cars within the MED cap (%d of %d)" % [vm.list.size(), vm.cap()])
		for vq in [0, 2, 1]:
			Game.set_quality(vq)
			await frames(2)
			var vcap: int = [3, 5, 8][vq]
			TestLib.check(vm.cap() == vcap and vm.list.size() <= vcap, "tier %d: at most %d live cars (%d)" % [vq, vcap, vm.list.size()])
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
	TestLib.check(not q.has_beacon and q.clone == null and q.links.is_empty() and p.speed_boost == 1.0, "respawn resets the quantum module")
	main.queue_free()
	await frames(10)
	TestLib.check(Game.enemies == null and Game.missions == null, "freeing the game clears the enemies and missions registry")
	Game.state = &"menu"
	Sfx.muted = false
