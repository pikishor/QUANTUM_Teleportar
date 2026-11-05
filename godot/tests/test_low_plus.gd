extends RefCounted
## LOW+ (Game.low_plus with quality 0, scripts/common/low_plus.gd): the tier below LOW for phones that cannot hold 30 FPS, and the per-system CPU timers (PerfTimers).
## Runs in the real main scene: what LOW+ switches off in the world (render scale, bloom, adjustments, building and ground shaders, material v2, quantum surface layer), the smaller
## populations (enemies, cars, crowd, traffic, particles), the slower HUD / touch / minimap redraw, the governor step LOW -> LOW+ after 5 s under 30 FPS, the weak-GPU default,
## the saved choice, and that the timers count the HUD's redraws. Run: tools/test.sh tests/test_low_plus.gd

const ExplosionPool := preload("res://scripts/fx/explosion_pool.gd")

var host: Node


func _frames(n: int) -> void:
	for i in n:
		await host.get_tree().process_frame


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	RenderRes.user_mode = -1
	RenderRes.gov_mode = -1
	LowPlus.throttle = true
	# --- pure helpers
	TestLib.check(LowPlus.weak_gpu("Mali-G52 MC2") and LowPlus.weak_gpu("Adreno (TM) 610") and LowPlus.weak_gpu("PowerVR GE8320"), "weak GPUs are recognised")
	TestLib.check(not LowPlus.weak_gpu("Adreno (TM) 740") and not LowPlus.weak_gpu("Mali-G710") and not LowPlus.weak_gpu("Apple A17 GPU"), "strong GPUs are not")
	TestLib.check(LowPlus.device_default("Mali-G52") == 0 and LowPlus.device_default("Adreno (TM) 740") == 1, "a weak GPU defaults to LOW+ (tier index 0), another touchscreen to LOW (1)")
	TestLib.check(Game.TIER_LABELS == ["LOW+", "LOW", "MED", "HIGH"], "the player sees four tiers")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _frames(30)
	var vp := host.get_viewport()
	var em := Game.enemies as EnemyManager
	var city := Game.world as Node
	TestLib.check(Game.world != null and em != null and Game.vehicles != null, "the real scene is up")
	# --- LOW as the reference
	Game.set_tier_index(1)
	await _frames(6)
	TestLib.check(Game.tier_index() == 1 and Game.tier_label() == "LOW" and not Game.low_plus and not LowPlus.on(), "LOW: index 1, no LOW+")
	var low_cap := em.cap()
	var low_cars := VehicleSpecs.cap_for(0)
	var low_crowd: int = city.ambient.crowd.count
	var low_traffic: int = city.ambient.traffic.count
	var low_fauna: int = city.ambient.fauna.count
	var low_fx := ExplosionPool.tier_scale(0)
	var low_slots := ExplosionPool.slot_limit(0)
	var low_scale := vp.scaling_3d_scale
	var env: Environment = city._env.env
	TestLib.check(env.glow_enabled and env.adjustment_enabled, "LOW keeps its short bloom and colour adjustment")
	TestLib.check(MaterialsV2.effective() > 0.0, "LOW keeps the cheap half of material v2")
	TestLib.check(city._building_mat.shader == city.Buildings.BUILDING_SHADER, "LOW: the full building shader")
	TestLib.check(is_equal_approx(float(city._ground.material.get_shader_parameter(&"qs_amount")), 1.0), "LOW: the quantum surface layer is on")
	TestLib.check(LowPlus.hud_interval() > 0.0 and LowPlus.hud_interval() < 0.1, "LOW redraws the HUD about 20 times a second")
	# --- LOW+
	var seen := {"plus": 0, "quality": 0}
	Game.low_plus_changed.connect(func(_on: bool) -> void: seen["plus"] += 1)
	Game.quality_changed.connect(func(_l: int) -> void: seen["quality"] += 1)
	Game.set_tier_index(0)
	await _frames(6)
	TestLib.check(Game.low_plus and Game.quality == 0 and Game.tier_index() == 0 and Game.tier_label() == "LOW+" and LowPlus.on(), "LOW+: quality 0 with the flag, label LOW+")
	TestLib.check(seen["plus"] == 1 and seen["quality"] >= 1, "switching tells low_plus_changed and quality_changed")
	TestLib.check(is_equal_approx(vp.scaling_3d_scale, LowPlus.SCALE_3D) and LowPlus.SCALE_3D >= 0.5 and LowPlus.SCALE_3D <= 0.6, "render scale %.2f (0.5 to 0.6)" % vp.scaling_3d_scale)
	TestLib.check(vp.scaling_3d_scale < low_scale, "smaller than LOW (%.2f)" % low_scale)
	TestLib.check(vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "plain bilinear upscale, no FSR pass")
	TestLib.check(vp.msaa_3d == Viewport.MSAA_DISABLED, "no MSAA")
	TestLib.check(not env.glow_enabled and not env.adjustment_enabled, "no bloom, no colour adjustment pass")
	TestLib.check(env.fog_height_density == 0.0 and env.fog_aerial_perspective == 0.0, "no height fog layer, no aerial perspective")
	TestLib.check(not (city._env.sun as DirectionalLight3D).shadow_enabled, "no shadows")
	TestLib.check(not city._mirror_root.visible, "no reflection (the mirrored city is hidden)")
	TestLib.check(MaterialsV2.effective() == 0.0, "material v2 is off")
	TestLib.check(city._building_mat.shader == city.Buildings.LEAN_SHADER, "the lean building shader on every facade")
	TestLib.check(is_equal_approx(float(city._ground.material.get_shader_parameter(&"qs_amount")), 0.0) and is_equal_approx(float(city._building_mat.get_shader_parameter(&"qs_amount")), 0.0), "the quantum surface layer is off")
	TestLib.check(em.cap() < low_cap and em.cap() >= 2, "fewer enemies (%d vs %d)" % [em.cap(), low_cap])
	TestLib.check(VehicleSpecs.cap_for(0) < low_cars and VehicleSpecs.cap_for(0) >= 2, "fewer cars (%d vs %d)" % [VehicleSpecs.cap_for(0), low_cars])
	TestLib.check(city.ambient.crowd.count < low_crowd, "a smaller crowd (%d vs %d)" % [city.ambient.crowd.count, low_crowd])
	TestLib.check(city.ambient.traffic.count < low_traffic, "less traffic (%d vs %d)" % [city.ambient.traffic.count, low_traffic])
	TestLib.check(city.ambient.fauna.count < low_fauna, "fewer flocks (%d vs %d)" % [city.ambient.fauna.count, low_fauna])
	TestLib.check(ExplosionPool.tier_scale(0) < low_fx and ExplosionPool.slot_limit(0) < low_slots, "fewer particles and explosion slots")
	TestLib.check(LowPlus.hud_interval() > 1.0 / 20.0 - 0.001, "LOW+ redraws the HUD slower than LOW (%.0f Hz)" % (1.0 / LowPlus.hud_interval()))
	TestLib.check(LowPlus.minimap_interval() > 1.0 / 10.0 - 0.001, "and the minimap")
	TestLib.check(TextureBudget.low_active and not TextureBudget.high_active, "LOW+ shares LOW's half-size textures (no extra texture memory)")
	TestLib.check(RenderRes.governor_lower() == false, "the governor has no resolution step below LOW+")
	TestLib.check(Engine.physics_ticks_per_second == LowPlus.PHYSICS_HZ and Engine.max_physics_steps_per_frame == LowPlus.PHYSICS_STEPS, "half-rate physics with at most two catch-up ticks")
	# the enemy cap holds for real spawns
	em.patrol_groups().clear()
	em.clear()
	var spawned := 0
	for i in 8:
		if em.spawn(&"sentinel", Game.SPAWN + Vector3(12.0 + 3.0 * i, 0.0, 6.0), true) != null:
			spawned += 1
	TestLib.check(spawned == em.cap(), "spawn stops at the LOW+ cap (%d of %d)" % [spawned, em.cap()])
	em.clear()
	# --- the HUD, the touch layer and the minimap redraw less often, and PerfTimers count it
	Game.state = &"play"
	await _frames(20)
	PerfTimers.reset()
	var t0 := Time.get_ticks_msec()
	await _frames(90)
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	var hud_per_frame := float(PerfTimers.calls(PerfTimers.HUD)) / 90.0
	TestLib.check(PerfTimers.calls(PerfTimers.HUD) > 0 and secs > 0.0, "the HUD draws and the timers count it (%d redraws in %d frames)" % [PerfTimers.calls(PerfTimers.HUD), 90])
	TestLib.check(hud_per_frame < 0.75, "LOW+ redraws the HUD on fewer than 3 of 4 frames (%.2f per frame)" % hud_per_frame)
	TestLib.check(PerfTimers.calls(PerfTimers.TOUCH) <= PerfTimers.calls(PerfTimers.HUD) + 4 or not (Game.force_touch or DisplayServer.is_touchscreen_available()), "the touch layer follows the same limit")
	LowPlus.throttle = false
	PerfTimers.reset()
	await _frames(60)
	TestLib.check(PerfTimers.calls(PerfTimers.HUD) >= 40, "without the limit the HUD redraws every frame (%d of 60)" % PerfTimers.calls(PerfTimers.HUD))
	LowPlus.throttle = true
	# --- the timers: every named system, the table and the engine monitors
	PerfTimers.reset()
	await _frames(30)
	var table := PerfTimers.table()
	TestLib.check(PerfTimers.NAMES.size() == PerfTimers.COUNT and PerfTimers.KEYS.size() == PerfTimers.COUNT, "every timer has a name and a monitor key")
	TestLib.check(table.contains("HUD") and table.contains("ms per frame"), "the table lists the HUD and the unit")
	TestLib.check(PerfTimers.total_ms() > 0.0 and PerfTimers.avg_ms(PerfTimers.HUD) > 0.0, "the timers measured something (%.2f ms in all)" % PerfTimers.total_ms())
	TestLib.check(PerfTimers.ranked()[0] != PerfTimers.ranked()[1] and PerfTimers.avg_ms(PerfTimers.ranked()[0]) >= PerfTimers.avg_ms(PerfTimers.ranked()[1]), "systems are ranked worst first")
	TestLib.check(Performance.has_custom_monitor("quantum/hud_ms") and Performance.has_custom_monitor("quantum/enemy_ai_ms"), "custom Performance monitors exist")
	var po := host.get_tree().get_first_node_in_group(&"perf_overlay") as PerfOverlay
	TestLib.check(po != null and po.report().contains("CPU ms per frame") and po.report().contains("tier LOW+"), "the PerfOverlay report carries the CPU table and says LOW+")
	TestLib.check(PerfOverlay.tier_label() == "LOW+", "the overlay names the tier LOW+")
	# --- the governor: LOW -> LOW+ after 5 s under 30 FPS, never writing the saved choice
	Game.set_tier_index(1)
	await _frames(6)
	var aq := AutoQuality.new()
	host.add_child(aq)
	await _frames(2)
	aq.enabled = true
	aq._warm = 0.0
	aq._since_drop = 99.0
	RenderRes.user_mode = 0
	var lowered: Array[int] = []
	aq.lowered.connect(func(l: int) -> void: lowered.append(l))
	var dropped := false
	for i in 9:                                                          # 4.5 s of slow frames at LOW: not yet
		dropped = aq.tick(20.0, 0.5) or dropped
	TestLib.check(not dropped and not Game.low_plus, "4.5 s under 30 FPS on LOW does not step down")
	TestLib.check(aq.tick(20.0, 0.5) and Game.low_plus and Game.quality == 0 and lowered == [0], "5 s under 30 FPS steps LOW -> LOW+")
	TestLib.check(aq.notice_left > 0.0 and aq._label.text.contains("LOW+"), "the notice names LOW+")
	aq._since_drop = 99.0
	for i in 40:
		aq.tick(5.0, 0.5)
	TestLib.check(Game.low_plus and aq.drops == 1, "nothing below LOW+")
	TestLib.check(not UiSettings.new("user://settings_low_plus_none.cfg").low_plus, "the governor never writes the saved choice")
	aq.queue_free()
	# --- leaving LOW+ restores everything
	Game.set_tier_index(1)
	await _frames(6)
	TestLib.check(not Game.low_plus and Game.quality == 0 and is_equal_approx(vp.scaling_3d_scale, low_scale), "LOW again: scale %.2f" % vp.scaling_3d_scale)
	TestLib.check(Engine.physics_ticks_per_second == 60 and Engine.max_physics_steps_per_frame == 8, "LOW again: 60 Hz physics")
	TestLib.check(env.glow_enabled and env.adjustment_enabled and env.fog_height_density > 0.0, "bloom, adjustments and the height fog are back")
	TestLib.check(city._building_mat.shader == city.Buildings.BUILDING_SHADER and MaterialsV2.effective() > 0.0, "the full building shader and material v2 are back")
	TestLib.check(is_equal_approx(float(city._building_mat.get_shader_parameter(&"qs_amount")), 1.0), "the quantum surface layer is back")
	TestLib.check(em.cap() == low_cap and city.ambient.crowd.count == low_crowd and city.ambient.traffic.count == low_traffic, "the LOW populations are back")
	Game.set_low_plus(true)
	await _frames(4)
	Game.set_quality(1)
	await _frames(4)
	TestLib.check(not Game.low_plus and Game.tier_index() == 2, "any tier above LOW clears LOW+")
	Game.set_tier_index(3)
	await _frames(4)
	TestLib.check(Game.quality == 2 and Game.tier_label() == "HIGH" and is_equal_approx(vp.scaling_3d_scale, RenderRes.scale(2)), "HIGH is untouched by LOW+")
	Game.set_tier_index(0)
	await _frames(4)
	TestLib.check(Game.low_plus and Game.quality == 0, "HIGH -> LOW+ in one step")
	main.queue_free()
	await _frames(2)
	Game.set_tier_index(1)
	# --- the saved choice and the weak-GPU default (no scene needed)
	var tmp := "user://settings_low_plus_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	var st := UiSettings.new(tmp)
	st.quality = 0
	st.low_plus = true
	st.save()
	var st2 := UiSettings.new(tmp)
	TestLib.check(st2.quality == 0 and st2.low_plus, "LOW+ is saved and loaded")
	st2.quality = 2
	st2.low_plus = true
	st2.save()
	TestLib.check(not UiSettings.new(tmp).low_plus, "a tier above LOW never saves the LOW+ flag")
	var was_auto := Game.autostart
	var was_touch := Game.force_touch
	Game.autostart = false
	Game.force_touch = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	TestLib.check(AutoQuality.wants_low_default(tmp), "a touchscreen without a saved choice starts on LOW or LOW+")
	TestLib.check(AutoQuality.wants_low_plus_default(tmp) == (LowPlus.device_default(RenderingServer.get_video_adapter_name()) == 0), "LOW+ only on a weak GPU")
	var keep := UiSettings.new(tmp)
	keep.quality = 1
	keep.save()
	TestLib.check(not AutoQuality.wants_low_plus_default(tmp), "a saved choice always wins")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	Game.autostart = was_auto
	Game.force_touch = was_touch
