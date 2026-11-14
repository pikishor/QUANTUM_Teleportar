extends RefCounted
## Wave 114 critic (LOOK): the scope of a long-range weapon (scripts/ui/scope_view.gd). The surround is four polygons that together cover the screen minus the lens; a scoped weapon (aimed field of view
## 36 degrees or less) shows the lens when it is aimed, a pistol or a rifle with an ordinary zoom does not; the HUD draws it without an engine error.
##   tools/test.sh tests/test_scope_view_w114.gd


class _Probe extends Control:
	var drawn := 0

	func _draw() -> void:
		ScopeView.draw_mask(self, Game.player, size, 1.0)
		ScopeView.draw_reticle(self, Game.player, size, 1.0, Color(1, 1, 1, 0.9))
		drawn += 1


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var j := (i + 1) % poly.size()
		a += poly[i].x * poly[j].y - poly[j].x * poly[i].y
	return absf(a) * 0.5


func run(host: Node) -> void:
	_geometry()
	await _live(host)


func _geometry() -> void:
	for vp: Vector2 in [Vector2(2400, 1080), Vector2(844, 390), Vector2(1280, 720), Vector2(1920, 1080)]:
		var polys := ScopeView.mask_polygons(vp)
		TestLib.check(polys.size() == 4, "%s: the surround is four pieces" % str(vp))
		var total := 0.0
		var simple := true
		for poly in polys:
			total += _area(poly)
			simple = simple and poly.size() >= 30 and Geometry2D.triangulate_polygon(poly).size() >= 3 * (poly.size() - 2) - 3
		var r := vp.y * ScopeView.LENS
		var want := vp.x * vp.y - PI * r * r
		TestLib.check(absf(total - want) / want < 0.006, "%s: the four pieces cover the screen minus the lens (%.0f of %.0f px)" % [str(vp), total, want])
		TestLib.check(simple, "%s: every piece is a simple polygon a canvas can triangulate" % str(vp))
		TestLib.check(r < vp.y * 0.5, "%s: the lens fits the screen height" % str(vp))
	TestLib.check(ScopeView.amount(null) == 0.0, "no player, no scope")


func _live(host: Node) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg.bak"))
	WeaponDefs.reset_unlocked()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	Game.state = &"play"
	var p := Game.player as Player
	TestMode.god = true
	var was_hero := WeaponDefs.hero_mode
	WeaponDefs.hero_mode = true
	if Game.enemies != null:
		(Game.enemies as EnemyManager).clear()
	var probe := _Probe.new()
	probe.size = Vector2(1280, 576)
	host.add_child(probe)
	Dev.errors.clear()
	# a scoped weapon, aimed: the lens is up; at the hip: it is not
	p.weapon.switch_to(&"rail", true)
	await TestLib.frames(host, 20)
	TestLib.check(ScopeView.amount(p) == 0.0, "the rail rifle at the hip shows no scope")
	Input.action_press(&"aim")
	var guard := 0
	while guard < 600 and p.camera_rig.get_ads_amount() < 0.97:
		await TestLib.frames(host, 4)
		guard += 4
	await TestLib.frames(host, 10)
	TestLib.check(p.camera_rig.ads_fov <= ScopeView.SCOPED_FOV, "the rail rifle zooms to %.0f degrees" % p.camera_rig.ads_fov)
	TestLib.check(ScopeView.amount(p) > 0.95, "the rail rifle aimed shows the scope (%.2f)" % ScopeView.amount(p))
	probe.queue_redraw()
	await TestLib.frames(host, 4)                                    # (the HUD redraws itself every frame: its own draw of the scope runs in these frames too)
	TestLib.check(probe.drawn >= 1, "the scope draws (%d redraws)" % probe.drawn)
	Input.action_release(&"aim")
	# weapons with an ordinary zoom never show it, aimed or not
	for id: StringName in [&"pistol", &"carbine", &"scatter", &"minigun", &"katana"]:
		p.weapon.switch_to(id, true)
		Input.action_press(&"aim")
		await TestLib.frames(host, 40)
		TestLib.check(ScopeView.amount(p) == 0.0, "%s aimed shows no scope (zoom %.0f degrees)" % [id, p.camera_rig.ads_fov])
		Input.action_release(&"aim")
		await TestLib.frames(host, 20)
	# the number of scoped weapons: the snipers, the lance, the railgun (a scope on 20 to 40 weapons, not on the whole roster)
	var scoped := 0
	for id: StringName in WeaponDefs.all_ids():
		if float(WeaponDefs.DEFS.get(id, {}).get("zoom", 60.0)) <= ScopeView.SCOPED_FOV:
			scoped += 1
	TestLib.check(scoped >= 15 and scoped <= 40, "%d weapons are scoped" % scoped)
	var mine: Array[String] = []                                       # (the headless dummy renderer says 'material is null' for every shader material that is asked for its properties: noise of every weapon test)
	for line in Dev.error_lines():
		if not line.contains("material_get_instance_shader_parameters"):
			mine.append(line)
	TestLib.check(mine.is_empty(), "drawing the scope raised no engine error (%s)" % ("; ".join(mine) if not mine.is_empty() else "none"))
	probe.queue_free()
	WeaponDefs.hero_mode = was_hero
	p.weapon.switch_to(&"carbine", true)
