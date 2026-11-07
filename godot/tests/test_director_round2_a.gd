extends RefCounted
## Director round 2, builder A (docs/SLICE_REVIEW.md defects 1-5 and 15) in the REAL game scene (main.tscn, touch layout forced):
##   1  the hero has a face that reads in a dark street (skin tone lifted, skin fill in the shader) and an armoured suit: chest and belly plates, pauldrons, a rucksack with a glow seam,
##      a cape, belt, pouches, knee pads, shin guards and boots, all in the ONE hero surface (no new draw), within the triangle budget; his shader colours are not black
##   2  the rifle is on screen from the shoulder camera and clear of the crosshair (projected from the real camera)
##   3  no two touch circles touch each other, the minimap or the pause button at 844x390 and 2400x1080 (in pixels)
##   4  one banner at a time: a toast waits while the chapter banner or a story card is up; no core counter while the story owns the goal
##   5  the prologue cards stay up at most PROLOGUE_MAX seconds over a live street and end at once when the hero is not safe
##   15 no light sprite or route dash right at the lens: the glow shader fades inside a few metres, the route line is invisible close to the camera
## Waits on state and counters, never on frame counts; user:// state is reset first.
## Run: tools/test.sh tests/test_director_round2_a.gd

const VPS := [Vector2(844, 390), Vector2(2400, 1080)]
const FOOT := ["", "quantum", "weapon", "foot", "vehicle", "grab", "takedown", "skip_piece", "more", "more_gadget", "more_garage", "more_c4", "more_companion", "detonate"]
const DRIVING := ["", "vehicle", "driving", "garage_open", "radio", "skip_piece"]

var host: Node
var p: Player
var hud: Hud


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_hero_build()
	_lens_sources()
	_buttons()
	var was_touch := Game.force_touch
	Game.force_touch = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	p = Game.player as Player
	hud = host.get_tree().get_first_node_in_group(&"hud") as Hud
	TestLib.check(p != null and hud != null, "the real scene has a player and a HUD")
	if p == null or hud == null:
		Game.force_touch = was_touch
		return
	(Game.progress as Progress).autosave_enabled = false
	p.max_hp = 1000.0
	p.hp = 1000.0
	_hero_in_scene()
	await _weapon_on_screen()
	_banners()
	_prologue()
	Game.force_touch = was_touch
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


# --- 1 -------------------------------------------------------------------------------------------------------------------------

func _hero_build() -> void:
	var o := {"body": &"male", "skin": &"dark", "hair": &"parted", "beard": false, "armed": false}
	var plain := HeroCharacter.build(o)
	var og := o.duplicate()
	og["gear"] = true
	var geared := HeroCharacter.build(og)
	TestLib.check(plain["root"] != null and geared["root"] != null, "the hero builds with and without the gear")
	if plain["root"] == null or geared["root"] == null:
		return
	var pi: Dictionary = plain["info"]
	var gi: Dictionary = geared["info"]
	TestLib.check(bool(gi["ok"]) and int(gi["surfaces"]) == 1 and int(gi["tris"]) <= HeroCharacter.BUDGET, "the armoured hero is still ONE surface within the %d triangle budget (%d)" % [HeroCharacter.BUDGET, int(gi["tris"])])
	TestLib.check(int(gi["pieces"]) == int(pi["pieces"]) + 1, "the gear is one more piece of the merged mesh (%d vs %d)" % [int(gi["pieces"]), int(pi["pieces"])])
	var bp := (plain["body"] as MeshInstance3D).mesh.get_aabb()
	var bg := (geared["body"] as MeshInstance3D).mesh.get_aabb()
	# kit space faces +Z (the rig turns it): the rucksack and the cape add depth BEHIND the hero, which is the kit's -Z
	TestLib.check(bg.position.z < bp.position.z - 0.08, "the back view has a rucksack and a cape (kit z %.2f against %.2f without)" % [bg.position.z, bp.position.z])
	TestLib.check(bg.size.x > bp.size.x + 0.02, "pauldrons widen the shoulders (%.2f against %.2f m)" % [bg.size.x, bp.size.x])
	TestLib.check(HeroCharacter.SKIN_MULT[&"dark"].get_luminance() >= 0.7, "the dark skin tone keeps a face that reads in a night street (multiplier luma %.2f)" % HeroCharacter.SKIN_MULT[&"dark"].get_luminance())
	var shader := (geared["material"] as ShaderMaterial).shader
	var code := shader.code
	TestLib.check(code.contains("skin fill") and code.contains("v_kindf"), "the shader has a skin fill for the face and gear kinds for the armour")
	var rs := RenderingServer
	for u: String in ["jacket_color", "pants_color"]:
		var dv: Variant = rs.shader_get_parameter_default(shader.get_rid(), StringName(u))
		if dv is Color:
			TestLib.check((dv as Color).get_luminance() >= 0.12, "the suit's %s default is not black (luma %.2f)" % [u, (dv as Color).get_luminance()])
	for r: Dictionary in [plain, geared]:
		(r["root"] as Node).free()


func _hero_in_scene() -> void:
	var info: Dictionary = p.body.hero_info
	TestLib.check(p.body.hero_mat != null and bool(info.get("ok", false)), "the live hero is the superhero model")
	var kit: Variant = p.body.hero_mat.get_shader_parameter(&"skin_mult")
	TestLib.check(kit is Color and (kit as Color).get_luminance() >= 0.7, "the live hero's skin multiplier lifts the face")
	TestLib.check(int(info.get("pieces", 0)) >= 5, "the live hero's mesh carries his armour piece (%d pieces)" % int(info.get("pieces", 0)))
	TestLib.check(int(info.get("tris", 99999)) <= HeroCharacter.BUDGET, "the live hero stays within the triangle budget (%d)" % int(info.get("tris", 0)))


# --- 15 ------------------------------------------------------------------------------------------------------------------------

func _lens_sources() -> void:
	var glow := load("res://assets/shaders/glow.gdshader") as Shader
	TestLib.check(glow != null and glow.code.contains("float lens") and glow.code.contains("length(VERTEX)") and glow.code.contains("size = min(size"), "a light sprite fades out when it is at the lens (one coloured haze across the frame)")
	var shaft := load("res://assets/shaders/shaft.gdshader") as Shader
	TestLib.check(shaft != null and shaft.code.contains("float lens") and shaft.code.contains("length(VERTEX)"), "a lamp light cone near the lens fades out (a cyan wash with a hard ring edge across half the street)")
	var cv := ContractVisuals.new()
	cv.set_route(PackedVector3Array([Vector3.ZERO, Vector3(40.0, 0.0, 0.0)]))
	var mat := cv.route.mesh.surface_get_material(0) as StandardMaterial3D if cv.route.mesh != null else null
	TestLib.check(mat != null and mat.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED and mat.distance_fade_min_distance >= 2.0, "the route line is invisible close to the camera (it was a cream plane across the lens)")
	TestLib.check(mat != null and mat.albedo_color.a <= 0.7, "the additive route line is softer (alpha %.2f)" % (mat.albedo_color.a if mat != null else -1.0))
	cv.free()


# --- 3 -------------------------------------------------------------------------------------------------------------------------

func _centre(b: Dictionary, vp: Vector2) -> Vector2:
	var s := UiUtil.ui_scale(vp)
	return Vector2(vp.x - UiUtil.insets(vp).y - float(b["dx"]) * s, vp.y - UiUtil.insets_v(vp).y - float(b["dy"]) * s)


func _buttons() -> void:
	for vp: Vector2 in VPS:
		var s := UiUtil.ui_scale(vp)
		var mm := Rect2(Vector2(UiUtil.insets(vp).x + 16.0 * s, 14.0 * s + UiUtil.insets_v(vp).x), Vector2(Hud.MINIMAP, Hud.MINIMAP) * s)
		var pause := Vector2(vp.x - UiUtil.insets(vp).y - 52.0 * s, 112.0 * s + UiUtil.insets_v(vp).x)
		for entry: Array in [["on foot", FOOT], ["driving", DRIVING]]:
			var group: Array = []
			for b: Dictionary in TouchControls.BUTTONS:
				if (entry[1] as Array).has(String(b["need"])):
					group.append(b)
			var worst := 1.0e9
			var pair := ""
			for i in group.size():
				var bi: Dictionary = group[i]
				var ci := _centre(bi, vp)
				var ri := float(bi["r"]) * s
				# the circle stays on the screen and clear of the minimap and the pause button
				TestLib.check(ci.x - ri >= 0.0 and ci.x + ri <= vp.x and ci.y - ri >= 0.0 and ci.y + ri <= vp.y, "%dx%d %s: %s is on screen" % [int(vp.x), int(vp.y), entry[0], bi["action"]])
				var near := Vector2(clampf(ci.x, mm.position.x, mm.end.x), clampf(ci.y, mm.position.y, mm.end.y))
				TestLib.check(ci.distance_to(near) > ri, "%dx%d %s: %s clears the minimap" % [int(vp.x), int(vp.y), entry[0], bi["action"]])
				TestLib.check(ci.distance_to(pause) > ri + 30.0 * s, "%dx%d %s: %s clears the pause button" % [int(vp.x), int(vp.y), entry[0], bi["action"]])
				for j in range(i + 1, group.size()):
					var bj: Dictionary = group[j]
					var gap := ci.distance_to(_centre(bj, vp)) - ri - float(bj["r"]) * s
					if gap < worst:
						worst = gap
						pair = "%s/%s" % [bi["action"], bj["action"]]
			TestLib.check(worst >= 4.0, "%dx%d %s: no two touch circles touch (closest %s, %.1f px)" % [int(vp.x), int(vp.y), entry[0], pair, worst])


# --- 2 -------------------------------------------------------------------------------------------------------------------------

func _weapon_on_screen() -> void:
	TestLib.check(CameraRig.HIP_SHOULDER >= 1.0 and CameraRig.ADS_SHOULDER >= 0.9 and CameraRig.ADS_LIFT >= 0.25, "the shoulder camera sits out and up (hip %.2f, ads %.2f, lift %.2f)" % [CameraRig.HIP_SHOULDER, CameraRig.ADS_SHOULDER, CameraRig.ADS_LIFT])
	TestLib.check(CharacterRig.HIP_READY_YAW <= -0.25, "the shouldered rifle points a little outward at the hip (%.2f)" % CharacterRig.HIP_READY_YAW)
	var rig := p.camera_rig
	var cam := rig.camera
	for aim: bool in [false, true]:
		Input.action_release(&"aim")
		if aim:
			Input.action_press(&"aim")
		var t0 := Time.get_ticks_msec()
		var settled := 0
		while Time.get_ticks_msec() - t0 < 6000:
			await TestLib.frames(host, 2)
			settled += 1
			if settled >= 12 and (not aim or rig._ads.x > 0.97) and p.body._wp_mi != null and p.body._wp_mi.visible:
				break
		var mi: MeshInstance3D = p.body._wp_mi
		TestLib.check(mi != null and mi.visible and mi.mesh != null, "%s: the weapon mesh is drawn on the hero" % ("ADS" if aim else "hip"))
		if mi == null or mi.mesh == null:
			continue
		var vp := host.get_viewport().get_visible_rect().size
		var bb := mi.get_aabb()
		var lo := Vector2(1.0e9, 1.0e9)
		var hi := Vector2(-1.0e9, -1.0e9)
		for k in 8:
			var corner := mi.global_transform * (bb.position + bb.size * Vector3(float(k & 1), float((k >> 1) & 1), float((k >> 2) & 1)))
			if cam.is_position_behind(corner):
				continue
			var sp := cam.unproject_position(corner)
			lo = lo.min(sp)
			hi = hi.max(sp)
		var rect := Rect2(lo, hi - lo)
		var centre_px := vp * 0.5
		var tag := "ADS" if aim else "hip"
		TestLib.check(rect.size.x > 0.0 and Rect2(Vector2.ZERO, vp).intersects(rect), "%s: the weapon is on the screen (%s)" % [tag, str(rect)])
		TestLib.check(rect.size.x >= vp.y * 0.03 or rect.size.y >= vp.y * 0.03, "%s: the weapon is big enough to read (%.0f x %.0f px of %.0f)" % [tag, rect.size.x, rect.size.y, vp.y])
		var cross := Rect2(centre_px - Vector2(1.0, 1.0) * vp.y * 0.02, Vector2(1.0, 1.0) * vp.y * 0.04)
		TestLib.check(not cross.has_point(rect.get_center()), "%s: the weapon does not sit on the crosshair" % tag)
	Input.action_release(&"aim")


# --- 4 -------------------------------------------------------------------------------------------------------------------------

func _banners() -> void:
	var story := Game.story as Story
	var camp := (Game.missions as Missions).campaign
	TestLib.check(story != null and camp != null, "the story layer and the campaign exist")
	if story == null or camp == null:
		return
	camp.set_physics_process(false)
	Game.state = &"play"
	camp.enabled = true
	camp.abort()
	TestLib.check(hud.campaign_owns_goal(), "while the story is switched on the HUD draws no QUANTUM CORES line (even before the first step is up)")
	TestLib.check(not hud.pause_goal_line().contains("QUANTUM CORES"), "the pause head carries no core counter either ('%s')" % hud.pause_goal_line())
	# one banner at a time: a toast waits while the chapter banner is up and shows afterwards
	hud.toast.clear()
	hud.message_left = 0.0
	story.banner_t = 0.5
	TestLib.check(hud.banner_busy(), "the chapter banner is up: the top-centre is busy")
	hud._on_message("CHECKPOINT REACHED", 2.0)
	var before := hud.message_left
	hud._process(0.5)
	TestLib.check(before > 0.0 and absf(hud.message_left - before) < 0.001, "the toast clock is held while the banner is up (%.2f -> %.2f)" % [before, hud.message_left])
	TestLib.check(not hud.visible_controls().has(&"toast"), "a held toast is not on the screen")
	story.banner_t = -1.0
	TestLib.check(not hud.banner_busy(), "the banner is gone: the top-centre is free again")
	hud._process(0.5)
	TestLib.check(hud.message_left < before, "the toast runs again afterwards (%.2f)" % hud.message_left)
	camp.enabled = false
	hud.toast.clear()
	hud.message_left = 0.0


# --- 5 -------------------------------------------------------------------------------------------------------------------------

func _prologue() -> void:
	var story := Game.story as Story
	if story == null:
		return
	Game.state = &"play"
	Game.heat = 0.0
	p.hp = p.max_hp
	# untouched, three short cards fit the cap
	var secs := 0.0
	for c: Dictionary in StoryData.PROLOGUE:
		var n := str(c["text"]).length()
		secs += float(n) / Story.PROLOGUE_CPS + Story.PROLOGUE_HOLD_BASE + float(n) * Story.PROLOGUE_HOLD_PER_CHAR
		TestLib.check(n <= 70, "a prologue card is a short line (%d characters)" % n)
	TestLib.check(secs <= Story.PROLOGUE_MAX + 0.3, "the prologue cards take %.1f s untouched (cap %.1f)" % [secs, Story.PROLOGUE_MAX])
	# in the live scene they end by themselves inside the cap
	story.start_cards(StoryData.PROLOGUE, &"prologue")
	var t := 0.0
	while story.cards_active() and t < 10.0:
		story.advance(0.1)
		t += 0.1
	TestLib.check(not story.cards_active() and t <= Story.PROLOGUE_MAX + 0.5, "the prologue is over after %.1f s of game time (cap %.1f)" % [t, Story.PROLOGUE_MAX])
	# not safe (a wanted level): the cards end at once
	story.skip_cards()
	Game.heat = 2.0
	TestLib.check(not story.player_safe(), "a wanted level makes the street unsafe")
	story.start_cards(StoryData.PROLOGUE, &"prologue")
	story.advance(0.1)
	TestLib.check(not story.cards_active(), "the cards end at once when the hero is not safe")
	Game.heat = 0.0
	# safe: they run
	TestLib.check(story.player_safe(), "a quiet street is safe")
	story.start_cards(StoryData.PROLOGUE, &"prologue")
	story.advance(0.1)
	TestLib.check(story.cards_active(), "the cards run while the hero is safe")
	story.skip_cards()
	p.invuln = 0.0
