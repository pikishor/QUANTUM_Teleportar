extends RefCounted
## Tier-switch memory (TextureBudget.set_tier, SurfaceTextures.prune, PerfTiers): in the real main scene cycle LOW -> HIGH -> LOW -> MED -> LOW three times. What a tier
## loaded must be released when the tier leaves: the HIGH surface sets and 2K twins are freed (checked with weak references, so it holds on the headless dummy renderer too),
## the RenderingServer texture memory returns to the LOW baseline (only measured when the renderer reports memory: it reads 0 headless), the render resolution follows the tier
## and the PerfOverlay keeps its fixed ring. Run: tools/test.sh tests/test_tier_switch_memory.gd

const MARGIN_MB := 12.0
var host: Node


func _mem() -> float:
	return float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576.0


func _switch(level: int) -> void:
	Game.set_quality(level)
	await TestLib.frames(host, 4)
	if _mem() <= 0.0:
		return
	# a real renderer frees GPU textures a few frames after the last reference goes: wait until the reading holds still (or the cap)
	var last := _mem()
	var still := 0
	for i in 240:
		await TestLib.frames(host, 1)
		var m := _mem()
		still = still + 1 if absf(m - last) < 0.5 else 0
		last = m
		if still >= 12:
			break


## Weak references to the textures held for HIGH: the surface caches of the full-size sets and the 2K twins of the hero and the sedan.
func _high_refs() -> Array[WeakRef]:
	var out: Array[WeakRef] = []
	for key: String in SurfaceTextures._cache.keys():
		var t: Variant = SurfaceTextures._cache[key]
		if t != null and key != "sign_atlas":
			out.append(weakref(t))
	for e: Array in TextureBudget._high_orig:
		var m := e[0] as BaseMaterial3D
		var t2 := m.get_texture(e[1] as BaseMaterial3D.TextureParam) if m != null else null
		if t2 != null:
			out.append(weakref(t2))
	return out


func _alive(refs: Array[WeakRef]) -> int:
	var n := 0
	for r in refs:
		if r.get_ref() != null:
			n += 1
	return n


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	var cfg := ConfigFile.new()                      # persisted options must not decide the starting tier or resolution
	RenderRes.user_mode = -1
	RenderRes.gov_mode = -1
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	TestLib.check(cfg != null and Game.world != null, "the real scene is up")
	var vp := host.get_viewport()
	var po := host.get_tree().get_first_node_in_group(&"perf_overlay") as PerfOverlay
	TestLib.check(po != null, "the PerfOverlay is composed")
	await _switch(1)
	await _switch(0)                                 # warm-up: the LOW state (half-size atlases, no surface sets) the cycles must return to
	var baseline := _mem()
	var live := baseline > 0.0
	TestLib.check(TextureBudget.low_active and not TextureBudget.high_active, "LOW: half-size models, no HIGH twins")
	TestLib.check(SurfaceTextures._cache.keys().filter(func(k: String) -> bool: return k != "sign_atlas" and not k.ends_with("|0")).is_empty(), "LOW holds no full-size surface texture cache (only the 512 px scanned albedo layers, keys ending |0)")
	var ring := po.samples.size()
	for cycle in 3:
		# HIGH visit
		await _switch(2)
		TestLib.check(TextureBudget.high_active and not TextureBudget.low_active, "cycle %d HIGH: twins loaded, models full size" % cycle)
		var refs := _high_refs()
		TestLib.check(refs.size() >= 2, "cycle %d HIGH: held textures seen (%d)" % [cycle, refs.size()])
		TestLib.check(is_equal_approx(vp.scaling_3d_scale, RenderRes.scale_for(2)), "cycle %d HIGH: render scale follows the tier (%.2f)" % [cycle, vp.scaling_3d_scale])
		var high_mem := _mem()
		await _switch(0)
		TestLib.check(not TextureBudget.high_active and TextureBudget._held.is_empty() and TextureBudget._high_orig.is_empty(), "cycle %d LOW: HIGH state dropped" % cycle)
		TestLib.check(TextureBudget.low_active, "cycle %d LOW: half-size models again" % cycle)
		TestLib.check(_alive(refs) == 0, "cycle %d LOW: every HIGH texture is freed (%d alive of %d)" % [cycle, _alive(refs), refs.size()])
		TestLib.check(is_equal_approx(vp.scaling_3d_scale, RenderRes.scale_for(0)), "cycle %d LOW: render scale back (%.2f)" % [cycle, vp.scaling_3d_scale])
		if live:
			TestLib.check(_mem() <= baseline + MARGIN_MB, "cycle %d LOW after HIGH: texture memory %.0f MB vs baseline %.0f (HIGH %.0f)" % [cycle, _mem(), baseline, high_mem])
		# MED visit
		await _switch(1)
		TestLib.check(not TextureBudget.low_active and not TextureBudget.high_active, "cycle %d MED: plain 1K imports" % cycle)
		var med_refs := _high_refs()
		await _switch(0)
		TestLib.check(_alive(med_refs) == 0, "cycle %d LOW: every MED surface texture is freed" % cycle)
		if live:
			TestLib.check(_mem() <= baseline + MARGIN_MB, "cycle %d LOW after MED: texture memory %.0f MB vs baseline %.0f" % [cycle, _mem(), baseline])
		TestLib.check(po.samples.size() == ring and po.report().contains("tier LOW"), "cycle %d: PerfOverlay ring fixed, report on LOW" % cycle)
		TestLib.check(po.summary().contains("tex="), "cycle %d: overlay summary shows the texture memory" % cycle)
	# a governor resolution step belongs to the tier it lowered and is cleared by the next tier change
	RenderRes.gov_mode = 0
	await _switch(2)
	TestLib.check(RenderRes.gov_mode == -1 and is_equal_approx(vp.scaling_3d_scale, RenderRes.scale_for(2)), "a tier change clears the governor's resolution step")
	await _switch(0)
	# LOW+ visits: the same half-size atlases and no surface sets as LOW, so it neither loads nor keeps anything extra; leaving it for HIGH / MED frees nothing twice and clears the flag
	for cycle in 2:
		Game.set_low_plus(true)
		await TestLib.frames(host, 4)
		TestLib.check(Game.low_plus and Game.quality == 0 and TextureBudget.low_active and not TextureBudget.high_active, "LOW+ cycle %d: LOW textures, no HIGH twins" % cycle)
		TestLib.check(is_equal_approx(vp.scaling_3d_scale, LowPlus.SCALE_3D), "LOW+ cycle %d: render scale %.2f" % [cycle, vp.scaling_3d_scale])
		if live:
			TestLib.check(_mem() <= baseline + MARGIN_MB, "LOW+ cycle %d: texture memory %.0f MB vs LOW baseline %.0f" % [cycle, _mem(), baseline])
		await _switch(2)
		TestLib.check(not Game.low_plus and TextureBudget.high_active, "LOW+ cycle %d -> HIGH: the flag is cleared, the twins load" % cycle)
		var hrefs := _high_refs()
		Game.set_low_plus(true)
		await _switch(0)
		TestLib.check(Game.low_plus and not TextureBudget.high_active and _alive(hrefs) == 0, "LOW+ cycle %d: HIGH -> LOW+ frees every HIGH texture (%d alive)" % [cycle, _alive(hrefs)])
		if live:
			TestLib.check(_mem() <= baseline + MARGIN_MB, "LOW+ cycle %d after HIGH: texture memory %.0f MB vs baseline %.0f" % [cycle, _mem(), baseline])
		await _switch(1)
		TestLib.check(not Game.low_plus and not TextureBudget.low_active, "LOW+ cycle %d -> MED: plain imports" % cycle)
		Game.set_tier_index(1)
		await TestLib.frames(host, 2)
		TestLib.check(not Game.low_plus and Game.quality == 0 and is_equal_approx(vp.scaling_3d_scale, RenderRes.scale(0)), "LOW+ cycle %d: back on LOW" % cycle)
	main.queue_free()
	await TestLib.frames(host, 2)
