extends RefCounted
## Render resolution: tier defaults, saved choice, live apply, governor step before a tier drop, options wiring, perf report. Run: tools/test.sh tests/test_render_resolution.gd


func run(host: Node) -> void:
	var vp := host.get_viewport()
	var old_scale := vp.scaling_3d_scale
	var old_mode := vp.scaling_3d_mode
	var old_q := Game.quality
	RenderRes.user_mode = -1
	RenderRes.gov_mode = -1
	TestLib.check(is_equal_approx(RenderRes.scale_for(0), 0.67) and is_equal_approx(RenderRes.scale_for(1), 0.85) and RenderRes.scale_for(2) == 1.0, "scales 0.67 / 0.85 / 1.0")
	for t in 3:
		TestLib.check(RenderRes.mode(t) == t, "tier %d default mode" % t)
	RenderRes.apply(vp, 0)
	TestLib.check(is_equal_approx(vp.scaling_3d_scale, 0.67), "LOW applies 0.67")
	TestLib.check(vp.scaling_3d_mode == (Viewport.SCALING_3D_MODE_FSR if RenderRes.fsr_supported() else Viewport.SCALING_3D_MODE_BILINEAR), "upscaler matches the renderer")
	RenderRes.apply(vp, 2)
	TestLib.check(vp.scaling_3d_scale == 1.0 and vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "HIGH is native, no upscale pass")

	# persistence
	var path := "user://test_render_res.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var st := UiSettings.new(path)
	TestLib.check(st.res_mode == -1, "default follows the tier")
	st.res_mode = 2
	TestLib.check(st.save() and UiSettings.new(path).res_mode == 2, "choice persists")
	st.res_mode = 9
	st.save()
	TestLib.check(UiSettings.new(path).res_mode == 2, "out-of-range clamps")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# options button cycles and applies live
	Game.quality = 1
	var o := UiSettings.new("user://test_render_res_o.cfg")
	TestLib.check(OptionsScreen.PAGE2.has(&"opt_res") and OptionsScreen.is_option(&"opt_res"), "option is on the options page")
	TestLib.check(OptionsScreen.label(o, &"opt_res").contains("HIGH"), "label shows the tier default (HIGH on MED)")
	OptionsScreen.press(o, &"opt_res")
	TestLib.check(o.res_mode == 2 and RenderRes.mode() == 2 and RenderRes.user_mode == 2, "press: HIGH -> NATIVE")
	OptionsScreen.press(o, &"opt_res")
	TestLib.check(o.res_mode == 0 and RenderRes.mode() == 0 and OptionsScreen.label(o, &"opt_res").contains("BALANCED"), "press wraps to BALANCED")
	TestLib.check(is_equal_approx(host.get_viewport().scaling_3d_scale, 0.67), "applied live to the running viewport")

	# governor: resolution first, then the tier
	RenderRes.set_user(-1)
	Game.quality = 2
	var aq := AutoQuality.new()
	host.add_child(aq)
	aq.enabled = true
	var steps := 0
	while RenderRes.mode() > 0 and steps < 5:
		TestLib.check(aq.tick(10.0, AutoQuality.LOW_FOR) == false, "slow frames lower the resolution, not the tier")
		TestLib.check(Game.quality == 2, "tier kept while resolution can still drop")
		aq._since_drop = AutoQuality.MIN_GAP
		steps += 1
	TestLib.check(steps == 2 and aq.res_steps == 2 and aq.drops == 0 and is_equal_approx(RenderRes.scale(), 0.67), "HIGH went Native -> High -> Balanced")
	TestLib.check(aq.tick(10.0, AutoQuality.LOW_FOR) and Game.quality == 1 and aq.drops == 1, "then the tier drops")
	TestLib.check(RenderRes.gov_mode == -1 and RenderRes.mode() == 1, "a tier change clears the governor override (MED default HIGH)")
	aq.queue_free()

	# perf report
	var po := PerfOverlay.new()
	po.log_path = "user://perf_log_res_test.txt"
	host.add_child(po)
	TestLib.check(po.report().contains("Render ") and po.report().contains("scale"), "perf report shows render scale")
	TestLib.check(po.summary().contains("res="), "perf summary shows render scale")
	po.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://perf_log_res_test.txt"))
	# wiring
	TestLib.check(FileAccess.get_file_as_string("res://scripts/world/city_env.gd").contains("RenderRes.apply"), "world applies the render scale through RenderRes")

	RenderRes.user_mode = -1
	RenderRes.gov_mode = -1
	Game.quality = old_q
	vp.scaling_3d_scale = old_scale
	vp.scaling_3d_mode = old_mode
