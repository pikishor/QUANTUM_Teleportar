extends RefCounted
## Performance and texture-quality contract (headless): what the performance layer promises, checked on the REAL composed game (scenes/main.tscn), plus the render budget
## itself when a real renderer is available.
##   * PerfTiers: mesh LOD threshold, anisotropy and mip bias follow Game.quality; Compatibility pool caps.
##   * Shadow cost: the hero, the troopers and the cars cast their shadows through ShadowProxy (shadows only, coarse LOD, no lamp surfaces).
##   * Distance LOD of enemies (shadow, small parts, hidden when far, with hysteresis) and of cars (shadow within 25 m).
##   * The 4-enemy simultaneous death stays inside the tier's explosion slots and effect tokens.
##   * Pose-following reflection of the skinned hero (a skinned copy on the SAME skeleton, one draw, never a rest-pose copy).
##   * Shader pre-warm leaves nothing behind (enemies and cars back in their pools, FX idle, nodes restored).
##   * Texture quality: the baked atlases of the hero, trooper, drones, cars and pickups are 1K-2K, mipmapped, high-quality compressed (albedo / normal / emission).
##   * The render budget (draws, triangles, texture memory per tier) when the renderer reports numbers: `tools/perf_report.sh` with PERF_CHECK=1 is the real gate and runs the
##     whole staged scene per tier; `--headless` has a dummy renderer (all zeros), where only the static budgets below can be checked.
## Run: tools/test.sh tests/test_perf_budget.gd

const SPEED_UP := 4
const TICK_RATE := 60 * SPEED_UP

var host: Node
var main: Node
var p: Player


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	Engine.physics_ticks_per_second = TICK_RATE
	Engine.time_scale = float(SPEED_UP)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	p = Game.player as Player
	_budget_table()
	await _tiers()
	await _shadow_proxies()
	await _enemy_lod()
	await _car_lod()
	await _death_governor()
	await _reflection()
	await _warmup()
	_textures()
	_render_budget()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60


func _budget_table() -> void:
	var med: Dictionary = PerfProbe.BUDGETS[1]
	TestLib.check(int(med["draws"]) <= 140 and int(med["prims"]) <= 280000, "MED budget: whole frame at most 140 draws and 280k triangles (%d / %d)" % [med["draws"], med["prims"]])
	TestLib.check(int(PerfProbe.BUDGETS[0]["draws"]) < int(med["draws"]) and int(med["draws"]) < int(PerfProbe.BUDGETS[2]["draws"]), "the budgets grow with the tier")
	TestLib.check(int(med["death_draws"]) <= 150, "the 4-enemy simultaneous death stays under 150 draws")
	TestLib.check(PerfProbe.HUD_TOUCH_MAX_DRAWS <= 15, "the touch layout may add at most 15 canvas draws")
	var bad := PerfProbe.violations({"total_draws": 141, "total_prims": 100, "tex_mb": 1.0}, 1)
	TestLib.check(bad.size() == 1, "the budget check flags 141 draws on MED (%s)" % str(bad))
	TestLib.check(PerfProbe.violations({"total_draws": 100, "total_prims": 200000, "tex_mb": 100.0}, 1, {"total_draws": 149}).is_empty(), "100 draws / 200k triangles / 149 on death is inside the MED budget")
	TestLib.check(PerfTiers.cap_scale(8) == 8 or PerfTiers.compat(), "the Mobile renderer keeps the full pool caps")
	TestLib.check(int(floor(8.0 * PerfTiers.COMPAT_CAP_SCALE)) < 8, "the Compatibility fallback caps the pools lower than Mobile (8 -> %d)" % int(floor(8.0 * PerfTiers.COMPAT_CAP_SCALE)))


func _tiers() -> void:
	var vp := main.get_viewport()
	var seen := {}
	for q in [0, 2, 1]:
		Game.set_quality(q)
		await frames(2)
		seen[q] = vp.mesh_lod_threshold
		TestLib.check(is_equal_approx(vp.mesh_lod_threshold, float(PerfTiers.LOD_THRESHOLD[q])), "tier %d: mesh LOD threshold %.1f px" % [q, vp.mesh_lod_threshold])
		TestLib.check(vp.anisotropic_filtering_level == PerfTiers.ANISO[q], "tier %d: anisotropic filtering level %d" % [q, vp.anisotropic_filtering_level])
	TestLib.check(seen[0] > seen[1] and seen[1] > seen[2], "a lower tier uses a coarser mesh LOD (%.1f > %.1f > %.1f px)" % [seen[0], seen[1], seen[2]])
	TestLib.check(vp.texture_mipmap_bias == 0.0 and PerfTiers.MIP_BIAS[0] > 0.0, "LOW reads a lower mip (bias %.1f), MED none" % PerfTiers.MIP_BIAS[0])


func _shadow_proxies() -> void:
	var rig := p.body.rig
	TestLib.check(rig != null, "the hero is the skinned model")
	if rig == null:
		return
	TestLib.check(rig.shadow != null and rig.shadow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "the hero's shadow comes from a shadows-only proxy")
	TestLib.check(rig.body_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "...the visible body itself casts none (one caster, not two)")
	TestLib.check(rig.shadow != null and rig.shadow.mesh == rig.body_mesh.mesh and rig.shadow.skin == rig.body_mesh.skin and rig.shadow.get_node(rig.shadow.skeleton) == rig.skeleton, "the proxy shares the mesh, the skin and the SKELETON of the body (it follows the pose)")
	TestLib.check(rig.shadow != null and rig.shadow.lod_bias < 1.0, "...and asks the renderer for a coarse LOD (bias %.2f)" % (rig.shadow.lod_bias if rig.shadow != null else -1.0))
	rig.set_shadow(false)
	TestLib.check(rig.shadow != null and not rig.shadow.visible, "the hero's shadow can be switched off")
	rig.set_shadow(true)
	var cars := Game.vehicles as VehicleManager
	var c: Vehicle = cars.starter
	var vis: VehicleVisual = c.visual
	TestLib.check(vis._shadow != null and vis._shadow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "the car's shadow comes from a shadows-only proxy")
	if vis._shadow != null:
		TestLib.check(vis._shadow.mesh.get_surface_count() < vis.body.mesh.get_surface_count(), "...without the lamp surfaces (%d of %d surfaces cast)" % [vis._shadow.mesh.get_surface_count(), vis.body.mesh.get_surface_count()])
		TestLib.check(vis.body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "...the visible body casts none")


func _stage_enemies(types: Array, base: Vector3) -> Array[Drone]:
	var out: Array[Drone] = []
	var em := Game.enemies as EnemyManager
	em.patrol_groups().clear()
	em.clear()
	for i in types.size():
		var d := em.spawn(types[i], base + Vector3(3.0 * i, 0.0, 0.0), true)
		if d != null:
			out.append(d)
	return out


func _enemy_lod() -> void:
	Game.set_quality(1)
	p.teleport_to(Game.SPAWN)
	var ds := _stage_enemies([&"sentinel", &"operative"], Game.SPAWN + Vector3(40.0, 0.0, 0.0))
	TestLib.check(ds.size() == 2, "two enemies spawned for the LOD checks")
	if ds.size() < 2:
		return
	var s: Drone = ds[0]
	var o: Drone = ds[1]
	s.update_lod(10.0)
	o.update_lod(10.0)
	TestLib.check(s.lod_state()["shadow"] and s.lod_state()["parts"] and s.lod_state()["shown"], "near (10 m): the drone has its shadow, fins and model")
	TestLib.check(s._body_mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and s._fins.visible, "...really: body casts, fins visible")
	s.update_lod(32.0)
	o.update_lod(32.0)
	TestLib.check(not s.lod_state()["shadow"] and s._body_mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "beyond 25 m the drone casts no shadow")
	TestLib.check(not o.lod_state()["shadow"] and o.rig != null and not o.rig.shadow.visible, "beyond 25 m the trooper casts no shadow (its proxy is off)")
	TestLib.check(s.lod_state()["parts"] and s._fins.visible, "at 32 m the fins are still drawn")
	TestLib.check(not o.lod_state()["lights"] and not (o._lights[0] as Light3D).visible, "beyond %.0f m the trooper's own lights are off" % PerfTiers.light_range(1))
	s.update_lod(60.0)
	TestLib.check(not s._fins.visible and not s.lod_state()["parts"] and s.model.visible, "beyond 45 m the fins are hidden (one draw less), the body stays")
	s.update_lod(150.0)
	o.update_lod(150.0)
	TestLib.check(not s.model.visible and not o.model.visible, "beyond 130 m the whole model is hidden")
	s.update_lod(28.0)
	TestLib.check(not s.lod_state()["shadow"], "hysteresis: coming back to 28 m does not switch the shadow on yet")
	s.update_lod(12.0)
	o.update_lod(12.0)
	TestLib.check(s.lod_state()["shadow"] and s.model.visible and s._fins.visible and o.model.visible and o.rig.shadow.visible and o.lod_state()["lights"] and (o._lights[0] as Light3D).visible, "back at 12 m everything is on again (lights included)")
	# the manager's pass uses the camera distance and the active list only
	var em := Game.enemies as EnemyManager
	em.lod_pass()
	var cam_d := Game.camera.global_position.distance_to(s.global_position)
	TestLib.check(s.lod_state()["shadow"] == (cam_d < PerfTiers.shadow_range() + 4.0), "EnemyManager.lod_pass applies the camera distance (%.0f m, shadow %s)" % [cam_d, str(s.lod_state()["shadow"])])
	# a pooled enemy that is respawned starts with everything on
	em.release(s)
	var again := em.spawn(&"sentinel", Game.SPAWN + Vector3(30.0, 0.0, 0.0), true)
	TestLib.check(again != null and again.lod_state()["shown"] and again.model.visible and again._fins.visible, "a pooled enemy comes back with its full detail")
	em.clear()


func _car_lod() -> void:
	var c: Vehicle = (Game.vehicles as VehicleManager).starter
	Game.set_quality(1)
	c.update_lod(10.0)
	TestLib.check(c.visual.shadow_on and c.visual._shadow != null and c.visual._shadow.visible, "a car within 25 m casts a shadow")
	c.update_lod(40.0)
	TestLib.check(not c.visual.shadow_on and c.visual._shadow != null and not c.visual._shadow.visible, "beyond 25 m a car casts no shadow")
	TestLib.check(not c.visual.wheels_visible() or VehicleSpecs.WHEELS_NEAR > 40.0, "the wheels follow their own range (%.0f m)" % VehicleSpecs.WHEELS_NEAR)
	c.update_lod(60.0)
	TestLib.check(not c.visual.wheels_visible(), "beyond %.0f m the wheels are hidden" % VehicleSpecs.WHEELS_NEAR)
	c.update_lod(5.0)
	TestLib.check(c.visual.wheels_visible() and c.visual.shadow_on, "back near: wheels and shadow return")
	TestLib.check(c.visual.lights.size() <= 1, "a car keeps at most its underglow light (the headlight spot and the car's own fill are gone: %d)" % c.visual.lights.size())
	c.update_lod(40.0)
	TestLib.check(not c.visual.lights_on and (c.visual.lights.is_empty() or not (c.visual.lights[0] as Light3D).visible), "beyond %.0f m the car's underglow light is off" % PerfTiers.light_range(1))
	c.update_lod(5.0)
	# the whole staged scene: model lights are bounded (the moon, the shared fill, the hero's key and rim, and only the ones near the camera)
	var shown := 0
	for n in main.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if l.is_visible_in_tree() and l.light_energy > 0.0:
			shown += 1
	TestLib.check(shown <= 14, "at most 14 real lights are on in the staged scene (%d): no per-object lights beyond the budgeted model lights" % shown)


func _active_blasts() -> int:
	var n := 0
	for s in FX.explosions.slots:
		if s.active:
			n += 1
	return n


func _death_governor() -> void:
	var em := Game.enemies as EnemyManager
	for q in [1, 0]:
		Game.set_quality(q)
		FX.reset()
		await frames(10)
		em._death_ends.clear()
		em._fx_tokens = float(EnemyManager.FX_CAPACITY[q])
		var ds := _stage_enemies([&"sentinel", &"sentinel", &"striker", &"heavy"], Game.SPAWN + Vector3(14.0, 0.0, -4.0))
		TestLib.check(ds.size() >= 3 or q == 0, "enemies for the death test (tier %d: %d)" % [q, ds.size()])
		for d in ds:
			d.damage(9999.0)
		await frames(2)
		var limit: int = EnemyManager.DEATH_BLASTS[q]
		TestLib.check(_active_blasts() <= limit, "tier %d: %d enemies dying at once use at most %d explosion slots (%d)" % [q, ds.size(), limit, _active_blasts()])
		TestLib.check(_active_blasts() >= 1 or ds.size() == 0, "...but the first death still gets a real blast")
		var tokens := em._fx_tokens
		TestLib.check(tokens < float(EnemyManager.FX_CAPACITY[q]), "the decorative bursts of the deaths spent effect tokens (%.1f left of %.0f)" % [tokens, EnemyManager.FX_CAPACITY[q]])
		var granted := 0
		for i in 12:
			if em.fx_token():
				granted += 1
		TestLib.check(granted <= int(EnemyManager.FX_CAPACITY[q]), "an empty budget refuses further bursts (%d granted of 12 asked)" % granted)
		em.clear()
		FX.reset()
	Game.set_quality(1)


func _reflection() -> void:
	Game.set_quality(1)
	p.teleport_to(Game.SPAWN)
	p.camera_rig.reset_view(-PI * 0.5, -0.1)
	await frames(12)
	var rig := p.body.rig
	var r: SkinnedMirror = rig.reflection
	TestLib.check(r != null and r.has_copy(), "the skinned hero has a pose-following reflection")
	if r == null or not r.has_copy():
		return
	var cp := r.copy
	TestLib.check(cp.get_parent() == Game.world.call(&"get_mirror_root"), "it lives under the world's Mirror node")
	TestLib.check(cp.mesh == rig.body_mesh.mesh and cp.skin == rig.body_mesh.skin and cp.get_node(cp.skeleton) == rig.skeleton, "it shares mesh, skin and SKELETON with the body: the very same bone transforms pose it (never a rest-pose copy)")
	var a := rig.body_mesh.global_transform
	var want := Basis.from_scale(Vector3(1, -1, 1)) * a.basis
	TestLib.check(cp.visible and cp.global_transform.basis.is_equal_approx(want) and cp.global_transform.origin.distance_to(Vector3(a.origin.x, -a.origin.y, a.origin.z)) < 0.01, "it sits at the mirrored transform of the body")
	TestLib.check(cp.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and cp.lod_bias < 1.0, "it casts no shadow and uses a coarse LOD")
	# the pose: bend a bone, both follow, because they are the same skeleton
	var bone := rig.skeleton.find_bone("Head")
	TestLib.check(bone >= 0, "the skeleton has a Head bone")
	r.range = -10.0
	await frames(4)
	r._process(0.0)                                         # one explicit tick: the headless frame loop of this sandbox does not always tick the node in 4 frames
	TestLib.check(not cp.visible, "beyond its range the reflection is hidden (no draw call)")
	r.range = SkinnedMirror.RANGE
	await frames(4)
	r._process(0.0)                                         # the same explicit tick as above (the sandbox's headless loop can run four physics frames inside one process frame; it failed on the wave 112 tree too)
	TestLib.check(cp.visible, "...and back within range it is drawn again")
	Game.set_quality(0)
	await frames(4)
	TestLib.check(not Game.world.call(&"get_mirror_root").visible, "LOW: the mirror node is hidden, so the reflection costs nothing")
	Game.set_quality(1)
	await frames(4)
	p.body.visible = false
	for _i in 30:                                       # wait on the mirror's own process frames, not on physics ticks (time_scale makes those several per frame)
		await host.get_tree().process_frame
		if not cp.visible:
			break
	TestLib.check(not cp.visible, "a hidden body (the player in a car) hides its reflection")
	p.body.visible = true
	await frames(4)


func _warmup() -> void:
	Game.set_quality(1)
	p.teleport_to(Game.SPAWN)
	await frames(4)
	var em := Game.enemies as EnemyManager
	var list_before := em.list.size()
	var cars_before := (Game.vehicles as VehicleManager).list.size()
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var res: Dictionary = await ShaderWarmup.run(host, true)
	TestLib.check(int(res.get("items", 0)) >= 10, "the pre-warm touched %d items (enemy types, car kinds, FX, quantum visuals, UI)" % int(res.get("items", 0)))
	TestLib.check(em.list.size() == list_before and (Game.vehicles as VehicleManager).list.size() == cars_before, "enemies and cars are back in their pools (%d / %d active as before)" % [em.list.size(), (Game.vehicles as VehicleManager).list.size()])
	var idle := true
	for s in FX.explosions.slots:
		idle = idle and not s.active
	TestLib.check(idle, "the FX are reset: no explosion slot is left running")
	await frames(2)
	var nodes_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	TestLib.check(nodes_after - nodes_before < 260, "the pre-warm leaves a bounded node count (+%d: pooled enemies and cars, nothing temporary)" % (nodes_after - nodes_before))
	var q: Variant = p.get(&"quantum")
	if q != null and q.get(&"fx_root") != null:
		var hidden := 0
		for n in (q.get(&"fx_root") as Node).find_children("*", "MeshInstance3D", true, false):
			if (n as MeshInstance3D).visible:
				hidden += 1
		TestLib.check(hidden == 0, "the quantum visuals are hidden again after the pre-warm (%d shown)" % hidden)
	TestLib.check(ShaderWarmup.done, "the pre-warm flag is set (main.gd runs it once per process behind the loading overlay)")


func _textures() -> void:
	var sizes := {"player": 2048, "operative": 2048, "drone_sentinel": 2048, "drone_striker": 2048, "drone_heavy": 2048, "car_sedan": 2048, "car_sport": 2048, "car_suv": 2048,
			"pickup_health": 1024, "pickup_energy": 1024, "core_gem": 1024}
	var total_px := 0
	for m: String in sizes:
		var path := ""
		for ext in ["jpg", "png"]:
			if ResourceLoader.exists("res://assets/textures/%s_albedo.%s" % [m, ext]):
				path = "res://assets/textures/%s_albedo.%s" % [m, ext]
		if path == "":
			TestLib.check(false, "%s has a baked albedo atlas" % m)
			continue
		var t := load(path) as Texture2D
		TestLib.check(t != null and t.get_width() >= int(sizes[m]) and t.get_width() == t.get_height(), "%s atlas is %d px (>= %d)" % [m, t.get_width() if t != null else 0, int(sizes[m])])
		var imp := FileAccess.get_file_as_string(path + ".import")
		TestLib.check(imp.contains("mipmaps/generate=true") and imp.contains("compress/mode=2"), "%s albedo is VRAM-compressed with mipmaps" % m)
		TestLib.check(imp.contains("compress/high_quality=true"), "%s albedo is imported in high quality (ASTC 4x4 / BPTC)" % m)
		var nrm := FileAccess.get_file_as_string("res://assets/textures/%s_normal.png.import" % m)
		TestLib.check(nrm.contains("compress/normal_map=1") and nrm.contains("compress/high_quality=true"), "%s normal map is a high-quality compressed normal map" % m)
		total_px += t.get_width() * t.get_height()
	TestLib.check(total_px >= 8 * 2048 * 2048, "the hero-facing atlases add up to %.0f megapixels of albedo" % (total_px / 1.0e6))
	# anisotropy: the imported materials sample anisotropically
	var model := Game.load_model("player")
	var aniso := false
	if model != null:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var mat := (mi as MeshInstance3D).mesh.surface_get_material(0) as BaseMaterial3D
			if mat != null and mat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC:
				aniso = true
		model.free()
	TestLib.check(aniso, "the hero's imported material uses anisotropic mipmap filtering")


## With a real renderer the staged view must be inside the tier's budget; the dummy renderer reports zeros (then the static checks above are what a headless run can do).
func _render_budget() -> void:
	var s := PerfProbe.snapshot(main.get_viewport())
	if int(s["total_draws"]) == 0:
		print("note: the renderer reports no draw calls (headless): the render budget is gated by tools/perf_report.sh (PERF_CHECK=1)")
		TestLib.check(true, "headless: render counts unavailable, static budgets checked")
		return
	var bad := PerfProbe.violations(s, Game.quality)
	TestLib.check(bad.is_empty(), "render budget at tier %d: %s" % [Game.quality, PerfProbe.line("staged", s) if bad.is_empty() else str(bad)])
