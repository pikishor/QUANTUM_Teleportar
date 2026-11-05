extends RefCounted
## RUN BENCHMARK and the phone profiling tooling: the fixed route and the statistics (pure), the options button, a real run in the main scene (LOW / MED / HIGH slices, result text and
## file, restore of tier / state / hero / god mode / governor, cancel by tap, SEND REPORT), the FPS readout hidden by default and shown by a long press, and the safe low-end render defaults.
## Waits on counters and state, never on frame counts. Run: tools/test.sh tests/test_benchmark_mode.gd

var host: Node


func _until(cond: Callable, max_ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > max_ms:
			return false
		await TestLib.frames(host, 2)
	return true


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	_pure()
	_settings()
	await _in_game()
	await _readout()


func _pure() -> void:
	# route: 400 m of road, heading unit vectors, clamped ends
	TestLib.check(absf(BenchmarkRun.route_length() - 400.0) < 0.01, "the route is 400 m")
	var ok := true
	var d := 0.0
	while d <= BenchmarkRun.route_length():
		var p: Dictionary = BenchmarkRun.route_point(d)
		var v: Vector3 = p["pos"]
		ok = ok and CityLayout.on_road(v.x, v.z) and absf((p["dir"] as Vector3).length() - 1.0) < 0.001
		d += 5.0
	TestLib.check(ok, "every 5 m of the route is on a road with a unit heading")
	var end: Dictionary = BenchmarkRun.route_point(99999.0)
	TestLib.check((end["pos"] as Vector3).is_equal_approx(Vector3(80.0, 0.0, 120.0)), "the route clamps at its end")
	# statistics: 100 frames of 10 ms and one 50 ms hitch
	var f := PackedFloat32Array()
	for i in 99:
		f.append(10.0)
	f.append(50.0)
	var st := BenchmarkRun.stats(f)
	TestLib.check(st["frames"] == 100 and absf(st["min"] - 20.0) < 0.01, "min FPS is 1000 / the worst frame (20)")
	TestLib.check(absf(st["avg"] - 1000.0 * 100.0 / 1040.0) < 0.1, "avg FPS is frames per second")
	TestLib.check(absf(st["p95"] - 100.0) < 0.01, "p95 FPS ignores the single hitch (100)")
	TestLib.check(BenchmarkRun.stats(PackedFloat32Array())["frames"] == 0, "no frames: zero stats")
	TestLib.check(st["min"] <= st["p95"] and st["min"] <= st["avg"], "min is the lowest of the three")
	# the button is an option, 64 px or taller, inside the design height, and localised
	TestLib.check(OptionsScreen.ORDER.has(&"opt_bench") and OptionsScreen.is_option(&"opt_bench"), "RUN BENCHMARK is on the options page")
	var s := UiSettings.new("user://test_bench_opts.cfg")
	TestLib.check(OptionsScreen.label(s, &"opt_bench") == "RUN BENCHMARK", "the label")
	for i in OptionsScreen.PAGE_CELL + 1:
		var r := OptionsScreen.cell_rect(i, 640.0, 1.0)
		TestLib.check(r.size.y >= 64.0 and r.end.y <= OptionsScreen.BACK_Y, "options cell %d is >= 64 px and clears BACK" % i)
	TestLib.check(OptionsScreen.BACK_Y + OptionsScreen.ROW_H <= 720.0, "BACK fits the 720 px design height")
	TestLib.check(OptionsScreen.PAGE2.size() <= OptionsScreen.PAGE_CELL and OptionsScreen.ORDER.size() <= OptionsScreen.PAGE_CELL, "both pages fit before the MORE cell")
	TestLib.check(Tr.table("es").has("RUN BENCHMARK") and Tr.table("hi").has("RUN BENCHMARK"), "Spanish and Hindi have the label")


## Safe low-end render defaults (project settings) and what PerfTiers applies to the viewport.
func _settings() -> void:
	TestLib.check(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d")) == 0, "MSAA is off by default")
	TestLib.check(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa")) == 0 and not bool(ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa")), "no FXAA / TAA")
	TestLib.check(int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")) <= 1024, "sun shadow map starts at 1024 or less")
	TestLib.check(int(ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/atlas_size")) <= 1024, "positional atlas starts at 1024 or less")
	TestLib.check(bool(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits")), "16-bit shadow depth")
	TestLib.check(int(ProjectSettings.get_setting("rendering/textures/default_filters/anisotropic_filtering_level")) <= 1, "default anisotropy is 2x at most")
	TestLib.check(str(ProjectSettings.get_setting("rendering/renderer/rendering_method")) == "mobile" and bool(ProjectSettings.get_setting("rendering/rendering_device/fallback_to_opengl3")), "Vulkan mobile with the OpenGL fallback")
	var pt := PerfTiers.new()
	host.add_child(pt)
	pt.apply(0)
	var vp := host.get_viewport()
	TestLib.check(vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED and not vp.use_taa and not vp.use_debanding, "LOW: no AA pass, no debanding")
	TestLib.check(vp.anisotropic_filtering_level == Viewport.ANISOTROPY_2X, "LOW: 2x anisotropy")
	pt.apply(2)
	TestLib.check(vp.use_debanding and vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "HIGH: debanding on, still no screen-space AA")
	pt.free()


func _in_game() -> void:
	var q0 := Game.quality
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	var up := await _until(func() -> bool: return Game.state == &"play" and is_instance_valid(Game.player), 60000)
	TestLib.check(up, "the game is up")
	await TestLib.frames(host, 10)
	var bn := main.get_tree().get_first_node_in_group(&"benchmark") as BenchmarkRun
	TestLib.check(bn != null, "main.gd composes the BenchmarkRun")
	if bn == null:
		main.queue_free()
		return
	bn.result_path = "user://test_benchmark.txt"
	var po := main.get_tree().get_first_node_in_group(&"perf_overlay") as PerfOverlay
	po.report_path = "user://test_perf_report.txt"
	DirAccess.remove_absolute(bn.result_path)
	DirAccess.remove_absolute(po.report_path)
	bn.seconds_per_tier = 0.8
	bn.settle = 0.2
	var player := Game.player as Player
	var home := player.global_position
	var aq: AutoQuality = null
	for c in main.get_children():
		if c is AutoQuality:
			aq = c
	var aq_on := aq.enabled if aq != null else false
	TestMode.god = false
	Game.set_quality(1)
	Game.set_low_plus(false)
	await TestLib.frames(host, 4)

	# the options button starts it; the run walks the three tiers on the route
	var st := UiSettings.new("user://test_bench_opts.cfg")
	TestLib.check(OptionsScreen.press(st, &"opt_bench"), "pressing RUN BENCHMARK starts a run")
	TestLib.check(bn.running and BenchmarkRun.active and TestMode.god and Game.state == &"play", "running: active, hero protected, play state")
	TestLib.check(aq == null or not aq.enabled, "the governor is off during the run")
	TestLib.check(not bn.start(), "a second start is refused while running")
	var seen := {}
	var on_route := true
	var t0 := Time.get_ticks_msec()
	while bn.running and Time.get_ticks_msec() - t0 < 60000:
		seen[Game.tier_index()] = true
		var hp := player.global_position
		on_route = on_route and CityLayout.on_road(hp.x, hp.z, -2.0)
		await TestLib.frames(host, 2)
	TestLib.check(not bn.running and bn.panel_open, "the run finished and shows its result panel")
	TestLib.check(seen.has(0) and seen.has(1) and seen.has(2) and seen.has(3), "LOW+, LOW, MED and HIGH were all rendered during the run (%s)" % str(seen.keys()))
	TestLib.check(on_route, "the hero stayed on the road route")
	for t in 4:
		var ok := bn.results.has(t)
		TestLib.check(ok, "result for tier %d" % t)
		if ok:
			var r: Dictionary = bn.results[t]
			TestLib.check(r["frames"] > 0 and r["min"] > 0.0 and r["min"] <= r["p95"] + 0.01 and r["min"] <= r["avg"] + 0.01, "tier %d: min is the lowest of min / p95 / avg (%d frames)" % [t, r["frames"]])
	TestLib.check(bn.last_text.contains("LOW+") and bn.last_text.contains("LOW ") and bn.last_text.contains("MED") and bn.last_text.contains("HIGH") and bn.last_text.contains("min") and bn.last_text.contains("p95") and bn.last_text.contains("GPU"), "result text names the tiers, min / avg / p95 and the GPU")
	TestLib.check(FileAccess.file_exists(bn.result_path) and FileAccess.get_file_as_string(bn.result_path) == BenchmarkRun.last_text, "result written to the benchmark file")
	# restore
	TestLib.check(Game.quality == 1, "the player's tier is back")
	TestLib.check(Game.state == &"play" and not TestMode.god and not BenchmarkRun.active, "state and god mode restored")
	TestLib.check(player.global_position.distance_to(home) < 0.5, "the hero is back where he was")
	TestLib.check(aq == null or aq.enabled == aq_on, "the governor is back")
	TestLib.check(not player.camera_rig.is_cinematic(), "the camera is handed back")
	# the panel: SEND REPORT copies and writes the file, CLOSE closes
	TestLib.check(bn.send_rect().size.y >= 64.0 and bn.close_rect().size.y >= 64.0, "panel buttons are >= 64 px")
	TestLib.check(bn.press_at(bn.send_rect().get_center()) and bn.copied == 1, "SEND REPORT is taken")
	TestLib.check(FileAccess.file_exists(po.report_path) and FileAccess.get_file_as_string(po.report_path).contains("benchmark"), "the report file holds the benchmark block")
	TestLib.check(not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD) or DisplayServer.clipboard_get().contains("benchmark"), "the clipboard holds it (or the platform has none)")
	TestLib.check(bn.press_at(bn.close_rect().get_center()) and not bn.panel_open, "CLOSE closes the panel")
	TestLib.check(not bn.press_at(Vector2(5, 5)), "an idle benchmark takes no touch")

	# a tap cancels a run and restores everything
	Game.set_quality(2)
	TestLib.check(bn.start(), "start again")
	await TestLib.frames(host, 6)
	var before := bn.results.size()
	TestLib.check(bn.press_at(Vector2(10, 10)), "a tap is taken during the run")
	TestLib.check(not bn.running and not bn.panel_open and Game.quality == 2 and Game.state == &"play" and not TestMode.god, "cancel restores the tier, state and god mode")
	TestLib.check(before <= 1, "a cancelled run keeps no result")
	# a player on LOW+ is back on LOW+ afterwards
	Game.set_tier_index(0)
	TestLib.check(bn.start(), "start on LOW+")
	await TestLib.frames(host, 4)
	bn.cancel()
	TestLib.check(Game.tier_index() == 0 and Game.low_plus, "LOW+ is restored")
	Game.set_tier_index(3)
	# from the pause menu the run returns to the pause menu
	Game.state = &"paused"
	await TestLib.frames(host, 2)
	TestLib.check(bn.start(), "start from the pause state")
	TestLib.check(Game.state == &"play", "play while running")
	bn.cancel()
	TestLib.check(Game.state == &"paused", "back to the pause state")
	Game.state = &"play"
	# the report carries the system line and settings
	var rep := po.report()
	TestLib.check(rep.contains("Systems:") and rep.contains("Settings:") and rep.contains("Thermal:") and rep.contains("Battery:"), "report has systems, settings, battery and thermal")
	TestLib.check(po.summary().contains("sys[") and po.summary().contains("temp="), "the rolling log sample carries the per-system times and temperature")
	DirAccess.remove_absolute(bn.result_path)
	DirAccess.remove_absolute(po.report_path)
	main.queue_free()
	await TestLib.frames(host, 2)
	Game.set_quality(q0)


## The FPS readout: hidden until a long press on its corner, never steals a short press, the report panel and SEND REPORT.
func _readout() -> void:
	Game.state = &"play"
	var was := Game.force_touch
	Game.force_touch = true
	var tc := (load("res://scenes/touch_controls.tscn") as PackedScene).instantiate() as TouchControls
	host.add_child(tc)
	await TestLib.frames(host, 3)
	var box := tc._perf_box()
	TestLib.check(tc.perf_on and not tc.perf_shown and not tc.perf_visible(), "the FPS readout is hidden by default on a phone")
	# a short press and a drag from the corner do nothing
	tc.touch_down(5, box.get_center())
	tc.touch_up(5)
	TestLib.check(not tc.perf_visible(), "a short press does not show it")
	tc.touch_down(5, box.get_center())
	tc.touch_move(5, box.get_center() + Vector2(200.0, 0.0), Vector2(200.0, 0.0))
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1000:
		await TestLib.frames(host, 2)
	tc.touch_up(5)
	TestLib.check(not tc.perf_visible(), "a drag from the corner never counts as a long press")
	# a hold shows it; the finger keeps playing (the press was not taken)
	tc.touch_down(6, box.get_center())
	t0 = Time.get_ticks_msec()
	while not tc.perf_shown and Time.get_ticks_msec() - t0 < 5000:
		await TestLib.frames(host, 2)
	tc.touch_up(6)
	TestLib.check(tc.perf_visible() and not tc.errors_on, "a long press shows the readout")
	var q0 := Game.quality
	tc.touch_down(7, box.get_center())
	tc.touch_up(7)
	TestLib.check(Game.quality == (q0 + 1) % 3, "while shown a short tap cycles the tier")
	Game.set_quality(q0)
	# long press again: the report panel with SEND REPORT (64 px); once more hides everything
	tc.touch_down(8, box.get_center())
	t0 = Time.get_ticks_msec()
	while not tc.errors_on and Time.get_ticks_msec() - t0 < 5000:
		await TestLib.frames(host, 2)
	tc.touch_up(8)
	TestLib.check(tc.errors_on and tc._copy_rect().size.y >= 64.0, "second long press opens the report panel with a 64 px SEND REPORT")
	var po := PerfOverlay.new()
	host.add_child(po)
	var path := "user://test_readout_report.txt"
	if po != null:
		po.report_path = path
		var copies := po.copies
		tc.touch_down(9, tc._copy_rect().get_center())
		tc.touch_up(9)
		TestLib.check(po.copies == copies + 1 and FileAccess.file_exists(path), "SEND REPORT writes the report file")
		DirAccess.remove_absolute(path)
	tc.touch_down(8, box.get_center())
	t0 = Time.get_ticks_msec()
	while tc.perf_shown and Time.get_ticks_msec() - t0 < 5000:
		await TestLib.frames(host, 2)
	tc.touch_up(8)
	TestLib.check(not tc.perf_shown and not tc.errors_on, "third long press hides the panel and the readout")
	tc.queue_free()
	po.queue_free()
	Game.force_touch = was
