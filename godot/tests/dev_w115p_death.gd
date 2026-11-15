extends RefCounted
## Dev probe (wave 115 PLAY critic): the hero dies in every snake state (swing, climb, flight, shield + armed power, zip) and respawns: is anything left behind (snake state, energy, snakes, armed power,
## held enemies, tendrils) and can he use the snakes again at once?
const TIMEOUT_SECONDS := 140.0
var host: Node
var p: Player
var sn: SnakeTraversal
var war: SnakeWar

func frames(n: int) -> void:
	await TestLib.frames(host, n)

func release_all() -> void:
	for a in [&"snake", &"fly", &"jump", &"move_forward", &"move_back", &"move_left", &"move_right", &"crouch", &"sprint", &"fire"]:
		Input.action_release(a)

func prep(pos: Vector3, yaw := -PI * 0.5, pitch := 0.0) -> void:
	release_all()
	sn.cancel()
	p.invuln = 0.0
	p.hp = p.max_hp
	sn.energy = SnakePower.max_energy()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	await frames(12)

func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	sn = p.snake
	war = SnakeWar.of(p)
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TrafficField.bare_street()
	Game.state = &"play"
	Difficulty.set_mode(1)
	for state in ["swing", "climb", "fly", "shield", "grab"]:
		TestMode.god = true
		await prep(Vector3(-30.0, 40.0, 4.0) if state == "swing" else (Vector3(-13.2, 0.0, 15.0) if state == "climb" else Vector3(-30.0, 0.0, 4.0)), -PI * 0.5 if state != "climb" else PI, 0.2 if state == "swing" else 0.1)
		match state:
			"swing":
				Input.action_press(&"snake")
				var t := 0
				while sn.mode != SnakeTraversal.Mode.SWING and t < 120:
					await frames(1)
					t += 1
			"climb":
				Input.action_press(&"snake")
				await frames(5)
				Input.action_release(&"snake")
				Input.action_press(&"move_forward")
				await frames(40)
			"fly":
				Input.action_press(&"fly")
				await frames(5)
				Input.action_release(&"fly")
				await frames(40)
			"shield":
				war.cast(&"sv_shield", true)
				war.arm(&"sv_net")
				await frames(30)
			"grab":
				var f := (Game.enemies as EnemyManager).spawn(&"operative", p.global_position + Vector3(0, 0, -8.0), false)
				f.set_physics_process(false)
				f.max_hp = 1e6
				f.hp = 1e6
				await frames(10)
				p.camera_rig.aim_at(SnakeAim.center_of(f))
				war.arm(&"sv_grab")
				Input.action_press(&"fire")
				await frames(30)
		var mode_before := sn.mode_name()
		var armed_before := war.armed
		var shield_before := not war.verbs.shield.is_empty()
		var grab_before := war.verbs.is_grabbing()
		TestMode.god = false
		p.damage(1.0e6)
		release_all()
		await frames(90)
		var dead_mode := sn.mode_name()
		var dead_state := Game.state
		Game.do_respawn()
		await frames(90)
		var ok: Array[String] = []
		if sn.mode != SnakeTraversal.Mode.NONE:
			ok.append("snake mode %s after respawn" % sn.mode_name())
		if war.armed != &"":
			ok.append("power %s still armed" % str(war.armed))
		if not war.verbs.shield.is_empty():
			ok.append("shield still up")
		if war.verbs.is_grabbing():
			ok.append("still grabbing")
		if sn.energy < SnakePower.max_energy() - 1.0:
			ok.append("energy %.0f" % sn.energy)
		var pool := SnakeTendrilPool.current
		if pool != null and pool.count() > 0:
			ok.append("%d tendrils left" % pool.count())
		var sw := SnakeSwarm.current
		if sw != null and sw.count() > 0:
			ok.append("%d snakes left" % sw.count())
		if p.is_dead():
			ok.append("still dead")
		if sn.jam_t > 0.0:
			ok.append("jammed")
		# a fresh swing works
		TestMode.god = true
		await prep(Vector3(-30.0, 40.0, 4.0), -PI * 0.5, 0.2)
		var s0 := sn.swings
		Input.action_press(&"snake")
		var tt := 0
		while sn.swings == s0 and tt < 180:
			await frames(1)
			tt += 1
		Input.action_release(&"snake")
		if sn.swings == s0:
			ok.append("no swing after respawn")
		print("DT %-6s: before mode %s armed %s shield %s grab %s | dead: mode %s state %s | after respawn: %s" % [state, mode_before, str(armed_before), str(shield_before), str(grab_before), dead_mode, str(dead_state), "OK" if ok.is_empty() else "; ".join(ok)])
		await frames(30)
	release_all()
	main.queue_free()
	await frames(3)
