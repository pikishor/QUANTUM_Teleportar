extends RefCounted
## Humanoid variants on the Superhero base meshes (headless, real scene): variants are deterministic and different, triangle budgets by LOD (near enemy <= 6000, mid <= 2500, near citizen
## <= 4000), textures are shared with the hero (no new texture memory), Vael troopers spawn through the live EnemyManager with the variant model and rig, and the nearest citizens
## become real actors (<= 12, hidden in the crowd, released again). Run: tools/test.sh tests/test_humanoid_variants.gd


func run(host: Node) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://progress.cfg"))
	if not HumanoidVariants.available():
		TestLib.check(HumanoidVariants.build(&"vael", 1)["root"] == null, "without the hero files build() returns no model (the old models stay)")
		return
	_variants()
	_budgets()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	Game.state = &"play"
	await _enemies(host)
	await _citizens(host)
	main.queue_free()
	await TestLib.frames(host, 2)


func _variants() -> void:
	var seen := {}
	for s in 12:
		seen[HumanoidVariants.variant(&"vael", s)["key"]] = true
	TestLib.check(seen.size() >= 4, "Vael variants differ (%d distinct keys in 12 seeds)" % seen.size())
	TestLib.check(HumanoidVariants.variant(&"citizen", 5)["key"] == HumanoidVariants.variant(&"citizen", 5)["key"], "a variant is deterministic")
	var v := HumanoidVariants.variant(&"vael", 3)
	TestLib.check(bool(v["helmeted"]) and v["opts"]["hair"] == &"none" and bool(v["opts"]["armed"]), "a Vael trooper is helmeted, hairless and armed")
	var c := HumanoidVariants.variant(&"citizen", 3)
	TestLib.check(not bool(c["helmeted"]) and not bool(c["opts"]["armed"]), "a citizen is unarmed with hair")
	var bodies := {}
	for s in 12:
		bodies[HumanoidVariants.variant(&"citizen", s)["opts"]["body"]] = true
	TestLib.check(bodies.size() == 2, "citizens use both the male and the female mesh")


func _budgets() -> void:
	var r := HumanoidVariants.build(&"vael", 2)
	TestLib.check(r["root"] != null and bool(r["ok"]), "a Vael trooper builds")
	if r["root"] == null:
		return
	var near := HumanoidVariants.tris(r["body"].mesh)
	TestLib.check(near > 1000 and near <= HumanoidVariants.NEAR_ENEMY, "near Vael mesh within budget (%d <= %d)" % [near, HumanoidVariants.NEAR_ENEMY])
	var d: Dictionary = r["variant"]
	var mid := HumanoidVariants.tris(HumanoidVariants.mid_mesh(d))
	TestLib.check(mid > 500 and mid <= HumanoidVariants.MID, "mid mesh within budget (%d <= %d)" % [mid, HumanoidVariants.MID])
	TestLib.check(HumanoidVariants.mid_mesh(d) == HumanoidVariants.mid_mesh(d), "the mid mesh is shared per variant")
	var body := r["body"] as MeshInstance3D
	TestLib.check(HumanoidVariants.set_lod(body, d, 60.0) and body.mesh == HumanoidVariants.mid_mesh(d), "far enough shows the mid mesh")
	TestLib.check(HumanoidVariants.set_lod(body, d, 5.0) and body.mesh == body.get_meta(&"near_mesh"), "close shows the near mesh again")
	# shared textures: two variants of the same body and skin use the very same texture objects as the hero
	var a := HumanoidVariants.build(&"vael", 0)
	var b := HumanoidVariants.build(&"vael", 12)
	var hero := HeroCharacter.build({"body": a["variant"]["opts"]["body"], "skin": a["variant"]["opts"]["skin"]})
	if a["root"] != null and b["root"] != null and hero["root"] != null:
		var ta = (a["material"] as ShaderMaterial).get_shader_parameter(&"skin_albedo")
		var th = (hero["material"] as ShaderMaterial).get_shader_parameter(&"skin_albedo")
		TestLib.check(ta != null and ta == th, "the skin texture is the hero's (no new texture memory)")
		TestLib.check((a["material"] as ShaderMaterial).get_shader_parameter(&"trim_color") != null, "the visor colour is set")
	for x: Dictionary in [a, b, hero, r]:
		if x["root"] != null:
			(x["root"] as Node).free()


func _enemies(host: Node) -> void:
	var em := Game.enemies as EnemyManager
	TestLib.check(em != null, "the live game has an EnemyManager")
	if em == null:
		return
	em.patrol_groups().clear()
	em.set_physics_process(false)
	var p: Node3D = Game.player
	var at := p.global_position + Vector3(14.0, 0.0, 0.0)
	em.clear()
	var keys := {}
	var ok := true
	for k in 4:
		var d := em.spawn(&"operative", at + Vector3(2.0 * k, 0.0, 0.0), true)
		if d == null or d.humanoid.is_empty():
			ok = false
			continue
		keys[d.humanoid["key"]] = true
		var tris := HumanoidVariants.tris(d.humanoid_body.mesh)
		ok = ok and tris <= HumanoidVariants.NEAR_ENEMY and d.get("rig") != null
		d.update_lod(60.0)
		ok = ok and HumanoidVariants.tris(d.humanoid_body.mesh) <= HumanoidVariants.MID
		d.update_lod(5.0)
	TestLib.check(ok, "operatives spawn as Vael troopers with the variant model, a rig and LOD meshes")
	TestLib.check(keys.size() >= 2, "troopers look different from each other (%d variants of 4)" % keys.size())
	await TestLib.frames(host, 2)
	em.clear()


func _citizens(host: Node) -> void:
	var city := Game.world as City
	var amb: Node3D = city.ambient
	amb.set_quality(2)
	var cz = amb.citizens
	amb.reset()
	amb.simulate = true
	var tries := 0
	while cz.assigned_total == 0 and tries < 400:
		await TestLib.frames(host, 2)
		tries += 1
	TestLib.check(cz.assigned_total > 0, "citizens become real actors in the live scene (%d assigned)" % cz.assigned_total)
	var n: int = cz.active_count()
	TestLib.check(n >= 1 and n <= 12, "at most 12 citizen actors (%d)" % n)
	var hidden_ok := true
	var drawn_ok := true
	for s: Dictionary in cz.slots:
		hidden_ok = hidden_ok and amb.crowd.is_hidden(int(s["person"]))
		var root := s["root"] as Node3D
		var pp: Vector3 = amb.crowd.person_position(int(s["person"]))
		drawn_ok = drawn_ok and root.visible and root.global_position.distance_to(pp) < 3.0
		drawn_ok = drawn_ok and HumanoidVariants.tris(s["body"].mesh) <= HumanoidVariants.NEAR_CITIZEN
	TestLib.check(hidden_ok, "the crowd skips people who are real actors")
	TestLib.check(drawn_ok, "actors stand on their person within the triangle budget")
	amb.set_quality(0)
	TestLib.check(cz.active_count() == 0, "LOW draws no actors")
	var any_hidden := false
	for i in amb.crowd.count:
		any_hidden = any_hidden or amb.crowd.is_hidden(i)
	TestLib.check(not any_hidden, "released people are drawn by the crowd again")
	amb.set_quality(2)
	amb.reset()
	TestLib.check(cz.active_count() == 0, "reset releases the actors")
