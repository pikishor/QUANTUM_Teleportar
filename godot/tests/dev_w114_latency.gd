extends RefCounted
## DEV PROBE of the wave 114 play critic (not a regression test): TRIGGER LATENCY of every weapon: the game seconds from the trigger going down (full magazine, nothing in the way) to the first shot (to the
## first swing for a melee weapon; a charge weapon is held until it releases). Prints PROBE lines for the slowest. Run: tools/test.sh tests/dev_w114_latency.gd

const TIMEOUT_SECONDS := 140.0
const DT := 1.0 / 60.0


func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	WeaponDefs.reset_unlocked()
	WeaponDefs.hero_mode = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 8)
	Game.state = &"play"
	var p := Game.player as Player
	var w := p.weapon
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	TestMode.god = true
	var rows: Array = []
	for id: StringName in WeaponDefs.all_ids():
		var d := WeaponDefs.def(id)
		var kind := String(d["kind"])
		w.switch_to(id, true)
		w.ammo = w.mag
		w.fire_t = 0.0
		w.swap_t = 0.0
		w.reload_t = 0.0
		w.charge = 0.0
		w._clear_gun_state()
		w._burst_left = 0
		var s0 := w.shots_fired
		var c0 := w.combo_hits
		var t := 0.0
		var first := -1.0
		for i in int(4.0 / DT):
			w.tick(DT, true, false, false, false)
			w.mech.tick(DT)
			t += DT
			var shot := w.combo_hits > c0 if kind == "melee" else w.shots_fired > s0
			if kind == "charge":
				shot = w.shots_fired > s0 or (w.charge >= 1.0)
			if shot:
				first = t
				break
		w.tick(6.0, false, false, false, false)
		w._clear_grenades()
		rows.append([id, first, kind])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	var slow := 0
	var none := 0
	for r: Array in rows:
		if float(r[1]) < 0.0:
			none += 1
		elif float(r[1]) > 0.5:
			slow += 1
	print("PROBE trigger latency: %d weapons never shot in 4 s, %d need more than 0.5 s" % [none, slow])
	for k in mini(22, rows.size()):
		print("PROBE   %-14s %-7s %.2f s" % [rows[k][0], rows[k][2], float(rows[k][1])])
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
	WeaponDefs.hero_mode = false
