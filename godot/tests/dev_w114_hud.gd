extends RefCounted
## DEV PROBE of the wave 114 play critic (not a regression test): the play HUD at 844x390 and 1280x720 in a busy moment (objective line, a story banner, wanted stars, three kill lines with weapon pictures
## and a pickup line, the weapon pop plate): every pair of texts that overlap, and the plates the kill feed draws over other text. Prints PROBE lines.
## Run: tools/test.sh tests/dev_w114_hud.gd

const TIMEOUT_SECONDS := 140.0


func _redraw(hud: Hud, host: Node) -> void:
	hud.scan_log.clear()
	hud.scan_text = true
	hud.scan_hud = true
	hud._hud.queue_redraw()
	hud._screen.queue_redraw()
	for i in 60:
		await TestLib.frames(host, 1)
		if not hud.scan_log.is_empty():
			break
	await TestLib.frames(host, 1)
	hud.scan_text = false
	hud.scan_hud = false


func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	WeaponDefs.reset_unlocked()
	WeaponDefs.hero_mode = true
	var win := host.get_window()
	var win_old := win.size
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 8)
	Game.state = &"play"
	var hud := host.get_tree().get_first_node_in_group(&"hud") as Hud
	var p := Game.player as Player
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	TestMode.god = true
	if hud.touch != null:
		hud.touch.controls_on = true
	for size: Vector2i in [Vector2i(844, 390), Vector2i(1280, 720)]:
		win.size = size
		await TestLib.frames(host, 4)
		var vp := hud.get_viewport().get_visible_rect().size
		var s := UiUtil.ui_scale(vp)
		Game.heat = float(OS.get_environment("W114_HEAT")) if OS.get_environment("W114_HEAT") != "" else 2.0
		var now := PlayerUtil.now()
		hud.feed.clear()
		hud.feed.push(HudFeed.KILL, "OPERATIVE  RIFT CARBINE", now, &"a_pillar")
		hud.feed.push(HudFeed.KILL, "BRUTE  SHARD SCATTER", now, &"scatter")
		hud.feed.push(HudFeed.PICKUP, "NEW WEAPON  TWIN RIVET SMG", now, &"s_rivet")
		hud.feed.push(HudFeed.KILL, "VAEL RAIDER  ION BATTLE RIFLE", now, &"e_ioncarb")
		Game.say("HIJACK COMPACT", 3.0)
		p.weapon.switch_to(&"scatter", true)
		p.weapon.switch_to(&"a_pillar", true)
		await _redraw(hud, host)
		var log: Array[Dictionary] = hud.scan_log
		print("PROBE size %dx%d canvas %.0fx%.0f scale %.2f texts %d" % [size.x, size.y, vp.x, vp.y, s, log.size()])
		var seen := {}
		var uniq: Array[Dictionary] = []
		for e: Dictionary in log:
			var key := "%s|%s" % [e["text"], e["rect"]]
			if not seen.has(key):
				seen[key] = true
				uniq.append(e)
		for e: Dictionary in uniq:
			print("PROBE   text '%s' rect %s" % [e["text"], e["rect"]])
		for i in uniq.size():
			for j in range(i + 1, uniq.size()):
				var a: Rect2 = uniq[i]["rect"]
				var b: Rect2 = uniq[j]["rect"]
				var inter := a.intersection(b)
				if inter.has_area() and inter.get_area() > 0.05 * minf(a.get_area(), b.get_area()):
					print("PROBE OVERLAP '%s' %s  /  '%s' %s  (%.0f%% of the smaller)" % [uniq[i]["text"], a, uniq[j]["text"], b, 100.0 * inter.get_area() / minf(a.get_area(), b.get_area())])
		hud.feed.clear()
	win.size = win_old
	Game.heat = 0.0
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
	WeaponDefs.hero_mode = false
