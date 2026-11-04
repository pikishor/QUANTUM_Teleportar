extends RefCounted
## Visual fixes 2: no flat white rectangles (soft-dot textures hold their pixels at once; the visual QA catches big flat rects), title badges do not overlap,
## exposure stays in one band over day / dusk / night / weather, the QA overlap check works. Run: tools/test.sh tests/test_visual_fixes2.gd


func run(host: Node) -> void:
	Sfx.muted = true
	# 1. soft dots are real pixels from the first use
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1.0))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var t := SoftDot.radial(g, 32)
	var img := t.get_image()
	TestLib.check(t is ImageTexture and img.get_width() == 32, "SoftDot is an ImageTexture with pixels")
	TestLib.check(img.get_pixel(16, 16).a > 0.8 and img.get_pixel(0, 0).a < 0.05, "the dot is opaque in the middle and clear at the corners")
	for tex in [FX._soft_texture(), MissionVisuals.soft_texture(), ImpactSparks._get_dot()]:
		TestLib.check(tex is ImageTexture and (tex as Texture2D).get_image().get_pixel(0, 0).a < 0.05, "shared billboard dot texture is immediate and clear at its corners")

	# 2. the QA catches flat bright rectangles and overlapping badges
	var busy := Image.create(320, 200, false, Image.FORMAT_RGBA8)
	for y in 200:
		for x in 320:
			var l := 0.15 + 0.2 * float((x * 7 + y * 13) % 5) / 4.0
			busy.set_pixel(x, y, Color(l, l, l))
	TestLib.check(float(VisualQaLib.flat_rects(busy)["frac"]) == 0.0, "a busy frame has no flat rectangle")
	var sky := busy.duplicate() as Image
	sky.fill_rect(Rect2i(40, 30, 120, 90), Color(0.85, 0.85, 0.88))
	var fr := VisualQaLib.flat_rects(sky)
	TestLib.check(float(fr["frac"]) > VisualQaLib.MAX_FLAT_RECT and VisualQaLib.verdict(VisualQaLib.stats(sky), -1.0, -1, float(fr["frac"])).contains("rectangle"), "a flat white rectangle fails the verdict: %s" % [fr])
	var blob := busy.duplicate() as Image
	blob.fill_rect(Rect2i(40, 30, 6, 6), Color(0.9, 0.9, 0.9))
	TestLib.check(float(VisualQaLib.flat_rects(blob)["frac"]) <= VisualQaLib.MAX_FLAT_RECT, "a small bright speck is not a rectangle")
	TestLib.check(VisualQaLib.overlap({"A": Rect2(0, 0, 100, 60), "B": Rect2(90, 10, 100, 60)}) != "", "overlap is reported")
	TestLib.check(VisualQaLib.overlap({"A": Rect2(0, 0, 100, 60), "B": Rect2(100, 0, 100, 60)}) == "", "touching rects do not overlap")

	# 3. exposure band
	var lo := 9.0
	var hi := 0.0
	for h in range(0, 24):
		for w in [&"clear", &"rain", &"storm", &"fog"]:
			var e := DayNight.exposure_for(float(h), w)
			lo = minf(lo, e)
			hi = maxf(hi, e)
	TestLib.check(lo > 0.9 and hi < 1.1 and hi - lo < 0.15, "exposure stays in one band over the day and weather: %.3f..%.3f" % [lo, hi])

	# 4. real scene: title badges, exposure meta, weather flash scales from it
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	Game.state = &"menu"
	await TestLib.frames(host, 4)
	var huds := main.find_children("*", "Hud", true, false)
	var tms := main.find_children("*", "TestMenu", true, false)
	TestLib.check(not huds.is_empty() and not tms.is_empty(), "main.tscn has the Hud and the TestMenu")
	if not huds.is_empty() and not tms.is_empty():
		var hud := huds[0] as Hud
		hud._layout_key = ""
		hud._ensure_layout()
		var rects := {}
		for b: Dictionary in hud.buttons:
			if b["id"] in [&"demo", &"options"]:
				rects[String(b["id"])] = b["rect"]
		var tm := tms[0] as TestMenu
		rects["test"] = tm.entry_rect()
		var s := UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size)
		TestLib.check(tm.entry_rect().size.y >= 63.9 * s, "the TEST button is at least 64 base px")
		TestLib.check(VisualQaLib.overlap(rects) == "", "title badges do not overlap: %s %s" % [VisualQaLib.overlap(rects), rects])
	var city := Game.world as City
	if city != null and city.day_night != null:
		var dn: DayNight = city.day_night
		dn.frozen = true
		dn.set_hour(12.0)
		var env := dn.env_owner.get("env") as Environment
		TestLib.check(env.has_meta(&"base_exposure") and absf(float(env.get_meta(&"base_exposure")) - DayNight.exposure_for(12.0, Weather.current)) < 0.05, "DayNight publishes the base exposure")
		dn.set_hour(1.0)
		TestLib.check(float(env.get_meta(&"base_exposure")) > 0.9, "night exposure published")
	main.queue_free()
	await TestLib.frames(host, 5)
	Game.state = &"menu"
	Sfx.muted = false
