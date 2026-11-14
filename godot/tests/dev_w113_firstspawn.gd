extends RefCounted
## DEV PROBE 7: what does the first body of every roster look cost when it spawns (unwarmed)? Run: tools/test.sh tests/dev_w113_firstspawn.gd
const TIMEOUT_SECONDS := 140.0
const IDS: Array[StringName] = [&"merc_rifle", &"merc_shotgun", &"merc_rocket", &"merc_medic", &"merc_officer", &"merc_sniper", &"auth_rifle", &"auth_riot", &"auth_heavy", &"auth_breacher",
	&"auth_ghost", &"auth_drone", &"auth_engineer", &"vael_grunt", &"vael_jackal", &"vael_brute", &"vael_hunter", &"vael_elite", &"vael_stalker", &"vael_bloater", &"grid_walker", &"grid_heavy",
	&"shield_bearer", &"jet_elite", &"beam_sniper", &"strider", &"crawler", &"wasp_drone", &"auto_turret", &"plate_brute", &"veil_stalker", &"hiveling"]

func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 40)
	Game.state = &"play"
	var p := Game.player as Player
	var city := Game.world as City
	var w := city.aliens as AlienWorld
	print("PROBE alien world ", w, " enabled ", w.enabled if w != null else false)
	w.force_active = true
	var out: Array[String] = []
	var worst := 0.0
	var total := 0.0
	for id in IDS:
		if not RosterSpecies.has(id):
			continue
		var h := p.global_position
		var t0 := Time.get_ticks_usec()
		var c := w.spawn_one(id, Vector3(h.x + 60.0, 0.0, h.z), &"", false)
		var t1 := Time.get_ticks_usec()
		var c2 := w.spawn_one(id, Vector3(h.x + 62.0, 0.0, h.z), &"", false)
		var t2 := Time.get_ticks_usec()
		var first := float(t1 - t0) / 1000.0
		var second := float(t2 - t1) / 1000.0
		worst = maxf(worst, first)
		total += first
		print("PROBE %-14s first %7.1f ms  second %6.1f ms" % [id, first, second])
		for x in [c, c2]:
			if is_instance_valid(x):
				(x as AlienCreature).die(false)
		await TestLib.frames(host, 3)
	print("PROBE worst first spawn ", snappedf(worst, 0.1), " ms; all firsts ", snappedf(total, 0.1), " ms")
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
