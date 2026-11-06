extends RefCounted
const FightBot := preload("res://tests/fight_bot.gd")

func run(host: Node) -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	var p: Player = Game.player
	var enc := Encounters.current
	enc.enabled = true
	Game.state = &"play"
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	var bot := FightBot.new()
	bot.setup(p)
	bot.aim_error = 0.01
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	var t := 0.0
	var last := -5.0
	while t < 60.0:
		await host.get_tree().physics_frame
		var dt := 1.0 / 60.0
		t += dt
		bot.step(dt)
		if t - last >= 5.0:
			last = t
			if t >= 35.0:
				for e in mgr.list:
					print("   ENEMY %s dist=%.1f aware=%s dead=%s los=%s active=%s reinf=%s cover=%s hp=%.0f y=%.2f" % [e.type, e.global_position.distance_to(p.global_position), e.aware, e.dead, e.los, e.active, e.reinforce, e.get(&"_cover_state"), e.hp, e.global_position.y])
				if bot.target != null:
					var tq := bot.target
					print("   T type=%s dist=%.1f hp=%.0f center=%s hero=%s yaw=%.2f col=%s" % [tq.type, tq.global_position.distance_to(p.global_position), tq.hp, tq.center(), p.global_position, p.camera_rig.yaw, p.weapon._last_collider])
				print("   BOT target=", bot.target, " ammo=", p.weapon.ammo, " reloading=", p.weapon.is_reloading(), " vehicle=", p.vehicle)
			print("t=%.0f %s alive=%d shots=%d hits=%d kills=%d heat=%.1f" % [t, enc.stats(), mgr.alive_count(), bot.shots, bot.hits, bot.kills, Game.heat])
	bot.finish()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
