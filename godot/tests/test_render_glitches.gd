extends RefCounted
## RENDER GLITCHES (owner round 2/3 screenshots: translucent pink / white rectangles floating in the street and in interiors, a purple slab on the crosswalk,
## white sheets in rooms, blocky cyan blobs). The causes found by hiding every translucent layer in turn (tests/bot_glitch_scan.gd, GLITCH_LAYERS=1) and fixed here:
##   * the hero's hit / death burst: 1 m untextured additive quads (their size came from a particle scale that a billboard without billboard_keep_scale ignores): metre-wide flat squares at the lens, now explicitly sized 6 cm soft motes in world space;
##   * portal / shock rings (fx_qring): a filled disc that covered the screen when the hero teleported, now a rim with a swirl band and a clear middle;
##   * puzzle barriers and pads: a flat additive 4 x 3 m box, now an energy field (frame + scan band) that fades near the lens; verb icons: 32 px hard-edged billboards, now 64 px soft;
##   * door markers: a filled lit sheet on every facade, now a frame; interior neon halos: a square falloff, now round; activity columns: flat 35 % cylinders, now soft hollow beams;
##   * enemy threat rings and muzzle flares: grew with the enemy's size however close the lens was (screen-wide arcs and flashes), now capped by the distance.
## Part 1 is the QA check itself (VisualQaLib.translucent_slabs) on synthetic frames; part 2 runs in the real scene (main.tscn, an interior) and checks the nodes that caused each glitch
## and walks every particle emitter and translucent mesh for flat unsized / untextured sprites. Rendered frames are the bot's job (tools/glitch_scan.sh); a headless run has no pixels.
## Run: tools/test.sh tests/test_render_glitches.gd

var host: Node


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _scene() -> Image:
	var img := Image.create(240, 120, false, Image.FORMAT_RGBA8)
	for y in 120:
		for x in 240:
			var v := 0.15 + 0.25 * float((x / 6 + y / 6) % 3) / 2.0         # a busy, textured "street"
			img.set_pixel(x, y, Color(v, v * 0.9, v * 1.1))
	return img


func _part1() -> void:
	var base := _scene()
	var none := VisualQaLib.translucent_slabs(base, base)
	TestLib.check(none["kind"] == "" and float(none["frac"]) == 0.0, "identical frames: no slab")
	var sheet := base.duplicate() as Image
	for y in range(20, 90):
		for x in range(40, 180):
			var c := sheet.get_pixel(x, y)
			sheet.set_pixel(x, y, c.lerp(Color(0.8, 0.95, 1.0), 0.6))
	var s := VisualQaLib.translucent_slabs(sheet, base)
	TestLib.check(s["kind"] == "slab" and float(s["frac"]) > 0.25, "a pale translucent sheet over the frame is a slab: %s" % [s])
	var r: Rect2i = s["rect"]
	TestLib.check(absi(r.position.x - 40) <= 8 and absi(r.position.y - 20) <= 8 and absi(r.size.x - 140) <= 16, "the slab rect is where the sheet is: %s" % [r])
	var beam := base.duplicate() as Image                                    # a thin bright beam (a tracer, a light shaft) is not a sheet
	for y in 120:
		for x in range(100, 112):
			beam.set_pixel(x, y, Color(1, 1, 1))
	TestLib.check(VisualQaLib.translucent_slabs(beam, base)["kind"] == "", "a thin beam is not a slab")
	var glow := base.duplicate() as Image                                    # a small soft glow (a lamp halo) is not a sheet either
	for y in range(40, 64):
		for x in range(100, 124):
			glow.set_pixel(x, y, Color(1.0, 0.9, 0.7))
	TestLib.check(VisualQaLib.translucent_slabs(glow, base)["kind"] == "", "a small glow is not a slab")
	var white := Image.create(240, 120, false, Image.FORMAT_RGBA8)           # no base frame: a big flat pale rectangle is judged on its own
	white.fill(Color(0.1, 0.1, 0.12))
	white.fill_rect(Rect2i(30, 10, 120, 80), Color(0.85, 0.95, 0.97))
	TestLib.check(VisualQaLib.translucent_slabs(white)["kind"] == "flat", "a flat pale rectangle is caught without a base frame")
	TestLib.check(VisualQaLib.translucent_slabs(base)["kind"] == "", "a busy frame is clean")
	TestLib.check(VisualQaLib.translucent_slabs(null)["kind"] == "", "no image, no verdict")


## Effective scale of a node from its global transform (a scaled ancestor shows up here).
func _gscale(n: Node3D) -> float:
	return maxf(n.global_transform.basis.x.length(), maxf(n.global_transform.basis.y.length(), n.global_transform.basis.z.length()))


func _mat_of(g: GeometryInstance3D) -> Material:
	if g.material_override != null:
		return g.material_override
	if g is CPUParticles3D and (g as CPUParticles3D).mesh != null:
		return (g as CPUParticles3D).mesh.surface_get_material(0)
	if g is MeshInstance3D and (g as MeshInstance3D).mesh != null and (g as MeshInstance3D).mesh.get_surface_count() > 0:
		return (g as MeshInstance3D).get_active_material(0)
	return null


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	_part1()
	# ---- the real scene ----
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	var p := Game.player as Player
	TestLib.check(p != null, "the player exists")
	if p == null:
		return
	Game.state = &"play"
	# 1. the hero's burst: world-space soft motes, never metre-wide flat squares
	var body := p.body as PlayerBody
	body.call(&"_fire_burst", p.global_position + Vector3(0.0, 1.3, 0.0), 10)
	var burst := body.find_child("QuantumBurst", true, false) as CPUParticles3D
	TestLib.check(burst != null, "the hit burst emitter exists")
	if burst != null:
		var q := burst.mesh as QuadMesh
		TestLib.check(q != null and q.size.x <= 0.1 and q.size.y <= 0.1, "a mote is a few centimetres, not a metre: %s" % [q.size if q != null else Vector2.ZERO])
		TestLib.check(burst.top_level, "the burst lives in world space (nothing inherited from the body)")
		TestLib.check(_gscale(burst) <= 1.05, "no scaled ancestor: effective scale %.2f" % _gscale(burst))
		var bm := q.material as BaseMaterial3D if q != null else null
		TestLib.check(bm != null and bm.albedo_texture != null, "a mote has a soft texture (an untextured additive quad is a flat square)")
		TestLib.check(burst.scale_amount_max <= 2.0, "particle scale range stays small")
	# 2. every emitter and translucent mesh: no flat untextured sprite, no inherited scale
	FX.burst(p.global_position + Vector3(0.0, 1.0, 2.0), Color(0.4, 0.9, 1.0), 14, 2.0, 0.9, 0.0, 9.0)
	FX.blast(p.global_position + Vector3(6.0, 1.0, 0.0), 3.0)
	FX.qvfx.teleport(p.global_position, p.global_position + Vector3(0.0, 0.0, -8.0))
	await frames(6)
	var bad: Array[String] = []
	var checked := 0
	for n in main.get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		var m := _mat_of(g)
		if not (g is CPUParticles3D or g is GPUParticles3D):
			continue
		var tm := m as BaseMaterial3D
		if tm == null:
			continue
		checked += 1
		var is_sprite := tm.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED and tm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		if is_sprite and tm.albedo_texture == null:
			bad.append("%s: billboard particles without a texture" % g.get_path())
		if is_sprite and g is CPUParticles3D and not tm.billboard_keep_scale:     # a billboard drops the particle scale: the quad shows at the mesh size, whatever scale_amount says
			var cp := g as CPUParticles3D
			if cp.scale_amount_curve != null or absf(cp.scale_amount_max - 1.0) > 0.01 or absf(cp.scale_amount_min - 1.0) > 0.01:
				var qs := (cp.mesh as QuadMesh).size if cp.mesh is QuadMesh else Vector2.ONE
				if maxf(qs.x, qs.y) > 0.2:
					bad.append("%s: scaled billboard particles of %.2f m without billboard_keep_scale" % [g.get_path(), maxf(qs.x, qs.y)])
		if _gscale(g) > 1.5:
			bad.append("%s: emitter under a scaled parent (%.1f)" % [g.get_path(), _gscale(g)])
	TestLib.check(checked >= 5, "the audit saw the particle emitters (%d)" % checked)
	TestLib.check(bad.is_empty(), "no flat untextured sprites, no scaled emitters: %s" % [bad])
	# 3. enemy rings and flares never grow past a third of their distance to the lens
	var em := Game.enemies as EnemyManager
	var cam := p.get_viewport().get_camera_3d()
	if em != null and cam != null:
		var fwd := -cam.global_basis.z
		var d := em.spawn(&"operative", cam.global_position + fwd * 2.2 + Vector3(0.0, -1.4, 0.0), true)
		await frames(3)
		if d != null:
			em.marks.refresh(em.list)
			var too_big := 0
			for i in em.marks.ring_count:
				var xf := em.marks.halos.get_instance_transform(i)
				var dist := cam.global_position.distance_to(xf.origin)
				if xf.basis.x.length() > maxf(0.12, dist * EnemyMarks.MARK_NEAR_K) + 0.4:
					too_big += 1
			TestLib.check(too_big == 0, "no threat ring or flare is screen-sized next to the lens (%d too big)" % too_big)
			TestLib.check(EnemyMarks.MARK_NEAR_K <= 0.4 and EnemyMarks.MARK_MIN_DIST >= 3.0, "ring cap constants are sane")
		em.clear()
	# 4. puzzle barriers, pads and icons
	var root := Node3D.new()
	main.add_child(root)
	var pz := QuantumPuzzles.build(root, 4, p.global_position + Vector3(0.0, 0.0, -30.0), Vector3(0, 0, 1))
	await frames(2)
	var barrier := (pz.gates[0]["barrier"] as StaticBody3D).get_child(1) as MeshInstance3D
	var bmat := barrier.material_override
	TestLib.check(bmat is ShaderMaterial, "the barrier is an energy-field shader, not a flat additive box")
	if bmat is ShaderMaterial:
		var code := (bmat as ShaderMaterial).shader.code
		TestLib.check(code.contains("smoothstep(1.4, 4.2, length(VERTEX))"), "the barrier fades out near the lens")
	var tex := QuantumPuzzles.icon_texture(&"entangle")
	TestLib.check(tex.get_width() >= 64, "verb icons are 64 px or more (were 32 px blobs)")
	var img := tex.get_image()
	var soft := 0
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			if a > 0.05 and a < 0.95:
				soft += 1
	TestLib.check(soft > 40, "icon edges are anti-aliased (%d soft pixels)" % soft)
	root.queue_free()
	# 5. shaders: no filled sheets
	var door := load("res://scripts/interiors_gameplay/door_glow.gdshader") as Shader
	TestLib.check(door != null and not door.code.contains("sin(uv.y * 20.0 - TIME * 3.0)") and not door.code.contains("step(0.1, edge)"), "door markers are frames, not lit sheets")
	var glow := load("res://assets/shaders/interior_glow.gdshader") as Shader
	TestLib.check(glow != null and glow.code.contains("length(q)") and not glow.code.contains("fx * fx * fy * fy"), "interior halos fall off round, not square")
	var ring := load("res://assets/shaders/fx_qring.gdshader") as Shader
	TestLib.check(ring != null and ring.code.contains("cfill"), "portal and shock rings keep their middle clear near the lens")
	# 6. inside a room: no flat translucent mesh sheet bigger than 2 x 2 m that is not an energy field
	var ig := InteriorGameplay.instance
	if ig != null:
		var doors := ig.doors_of(&"apartment", Game.SPAWN)
		if not doors.is_empty():
			ig.enter(doors[0], true)
			await frames(20)
			var sheets: Array[String] = []
			for n in main.get_tree().root.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				if not mi.is_visible_in_tree() or mi.mesh == null or mi.mesh is TorusMesh:      # a ring is hollow, not a sheet
					continue
				var sm := mi.material_override as BaseMaterial3D
				if sm == null or sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED or sm.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
					continue
				if sm.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
					continue
				var s := mi.mesh.get_aabb().size * mi.global_transform.basis.get_scale()
				var dims := [absf(s.x), absf(s.y), absf(s.z)]
				dims.sort()
				if float(dims[1]) > 2.0 and float(dims[2]) > 2.0:
					sheets.append("%s %s" % [mi.get_path(), s])
			TestLib.check(sheets.is_empty(), "no flat unshaded translucent sheet bigger than 2 x 2 m inside a room: %s" % [sheets])
			ig.leave(true)
	main.queue_free()
