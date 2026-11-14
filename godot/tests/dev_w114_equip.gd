extends RefCounted
## DEV PROBE of the wave 114 play critic (not a regression test): the cost of the FIRST equip of every weapon (the glb is loaded, the mesh cached, the hero's material copy made, the grips solved) and what 229
## cached weapons weigh. Prints PROBE lines. Run: tools/test.sh tests/dev_w114_equip.gd

const TIMEOUT_SECONDS := 140.0


func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	WeaponDefs.reset_unlocked()
	WeaponDefs.hero_mode = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 10)
	Game.state = &"play"
	var p := Game.player as Player
	var w := p.weapon
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	TestMode.god = true
	await TestLib.frames(host, 10)
	var mem0 := OS.get_static_memory_usage()
	var obj0 := Performance.get_monitor(Performance.OBJECT_COUNT)
	var times: Array = []
	var meshes_ms := 0.0
	for id: StringName in WeaponDefs.all_ids():
		var t0 := Time.get_ticks_usec()
		var ok := w.switch_to(id, true)
		var t1 := Time.get_ticks_usec()
		await TestLib.frames(host, 1)
		var t2 := Time.get_ticks_usec()
		times.append([id, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, ok])
	var mem1 := OS.get_static_memory_usage()
	var obj1 := Performance.get_monitor(Performance.OBJECT_COUNT)
	times.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	var sum := 0.0
	var over5 := 0
	var over15 := 0
	for t: Array in times:
		sum += float(t[1])
		over5 += 1 if float(t[1]) > 5.0 else 0
		over15 += 1 if float(t[1]) > 15.0 else 0
	print("PROBE equip n=%d total %.0f ms mean %.2f ms  over5ms %d over15ms %d  worst %s %.1f ms" % [times.size(), sum, sum / float(times.size()), over5, over15, times[0][0], float(times[0][1])])
	for k in 12:
		print("PROBE slow %-14s switch %.1f ms next frame %.1f ms" % [times[k][0], times[k][1], times[k][2]])
	print("PROBE memory static %.1f -> %.1f MB (+%.1f), objects %d -> %d" % [mem0 / 1048576.0, mem1 / 1048576.0, (mem1 - mem0) / 1048576.0, obj0, obj1])
	# second equip of the same weapons (cached)
	var sum2 := 0.0
	for id: StringName in WeaponDefs.all_ids():
		var t0 := Time.get_ticks_usec()
		w.switch_to(id, true)
		sum2 += (Time.get_ticks_usec() - t0) / 1000.0
	print("PROBE equip again total %.0f ms mean %.2f ms" % [sum2, sum2 / float(times.size())])
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
	WeaponDefs.hero_mode = false
